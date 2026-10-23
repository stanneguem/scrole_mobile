import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class R2UploadedMedia {
  const R2UploadedMedia({
    required this.objectKey,
    required this.publicUrl,
    required this.contentType,
    required this.sizeBytes,
  });

  final String objectKey;
  final String publicUrl;
  final String contentType;
  final int sizeBytes;
}

/// Obtient une URL présignée via Supabase Edge Function puis envoie les octets
/// directement vers R2. Aucune clé R2 n'est embarquée dans l'application.
class R2MediaRepository {
  R2MediaRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const Map<String, String> _imageTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'avif': 'image/avif',
  };

  static const Map<String, String> _videoTypes = {
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
  };

  Future<R2UploadedMedia> uploadFile({
    required File file,
    required String category,
    required String mediaType,
    String? entityId,
    String? communityId,
    Duration? videoDuration,
  }) async {
    final traceId = DateTime.now().millisecondsSinceEpoch.toString();
    debugPrint('[R2_UPLOAD][$traceId] START category=$category mediaType=$mediaType entityId=$entityId communityId=$communityId');
    final authUser = _client.auth.currentUser;
    debugPrint('[R2_UPLOAD][$traceId] authUserId=${authUser?.id ?? 'null'} sessionPresent=${_client.auth.currentSession != null}');
    if (authUser == null) {
      debugPrint('[R2_UPLOAD][$traceId] ABORT: utilisateur non connecté');
      throw const AuthException('Vous devez être connecté pour envoyer un média.');
    }

    final extension = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    final isVideo = mediaType == 'video';
    final contentType = (isVideo ? _videoTypes : _imageTypes)[extension];
    if (contentType == null) {
      debugPrint('[R2_UPLOAD][$traceId] ABORT: extension non prise en charge .$extension');
      throw ArgumentError('Format de média non pris en charge : .$extension');
    }

    final bytes = await file.readAsBytes();
    debugPrint('[R2_UPLOAD][$traceId] fileRead bytes=${bytes.length} extension=$extension contentType=$contentType');
    if (bytes.isEmpty) {
      debugPrint('[R2_UPLOAD][$traceId] ABORT: fichier vide');
      throw StateError('Le fichier sélectionné est vide.');
    }

    debugPrint('[R2_UPLOAD][$traceId] STEP 1: appel Edge Function r2-media-upload');
    final response = await _client.functions.invoke(
      'r2-media-upload',
      body: <String, dynamic>{
        'action': 'create-upload-url',
        'category': category,
        'media_type': mediaType,
        'content_type': contentType,
        'extension': extension,
        'size_bytes': bytes.length,
        if (entityId != null) 'entity_id': entityId,
        if (communityId != null) 'community_id': communityId,
        if (videoDuration != null)
          'duration_seconds': videoDuration.inMilliseconds / 1000,
      },
    );

    debugPrint('[R2_UPLOAD][$traceId] Edge Function status=${response.status} dataType=${response.data.runtimeType}');
    if (response.status < 200 || response.status >= 300 || response.data is! Map) {
      final details = response.data is Map
          ? (response.data as Map)['error']?.toString()
          : null;
      debugPrint('[R2_UPLOAD][$traceId] EDGE_FUNCTION_FAILURE status=${response.status} details=${details ?? response.data}');
      throw StateError('Autorisation R2 refusée${details == null ? '' : ' : $details'}');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    debugPrint('[R2_UPLOAD][$traceId] Edge response fields=${data.keys.toList()} objectKey=${data['object_key']} expiresIn=${data['expires_in']}');
    final uploadUrl = data['upload_url'] as String?;
    final objectKey = data['object_key'] as String?;
    final publicUrl = data['public_url'] as String?;
    if (uploadUrl == null || objectKey == null || publicUrl == null) {
      debugPrint('[R2_UPLOAD][$traceId] ABORT: réponse incomplète uploadUrl=${uploadUrl != null} objectKey=${objectKey != null} publicUrl=${publicUrl != null}');
      throw StateError('Réponse R2 incomplète : URL ou clé manquante.');
    }

    // Ne jamais journaliser uploadUrl : cette URL contient une signature temporaire.
    final request = http.Request('PUT', Uri.parse(uploadUrl))
      ..headers['Content-Type'] = contentType
      ..bodyBytes = Uint8List.fromList(bytes);

    final client = http.Client();
    try {
      debugPrint('[R2_UPLOAD][$traceId] STEP 2: PUT vers R2 objectKey=$objectKey bytes=${bytes.length} contentType=$contentType');
      final streamed = await client.send(request);
      final uploadResponse = await http.Response.fromStream(streamed);
      debugPrint('[R2_UPLOAD][$traceId] R2 PUT status=${uploadResponse.statusCode} responseBytes=${uploadResponse.bodyBytes.length}');
      if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
        final bodyPreview = uploadResponse.body.length > 500
            ? uploadResponse.body.substring(0, 500)
            : uploadResponse.body;
        // Extract only the provider error code for a useful diagnostic. Never
        // print uploadUrl: it contains a temporary signature credential.
        final codeMatch = RegExp(r'<Code>([^<]+)</Code>').firstMatch(bodyPreview);
        final providerCode = codeMatch?.group(1);
        debugPrint('[R2_UPLOAD][$traceId] R2_PUT_FAILURE status=${uploadResponse.statusCode} providerCode=${providerCode ?? 'unknown'} body=$bodyPreview');
        throw HttpException(
          'Échec du téléversement R2 (HTTP ${uploadResponse.statusCode}'
          '${providerCode == null ? '' : ', $providerCode'}).',
        );
      }
    } catch (e, stack) {
      debugPrint('[R2_UPLOAD][$traceId] PUT_EXCEPTION type=${e.runtimeType} error=$e');
      debugPrint('[R2_UPLOAD][$traceId] PUT_STACK_TRACE\\n$stack');
      rethrow;
    } finally {
      client.close();
      debugPrint('[R2_UPLOAD][$traceId] HTTP client closed');
    }

    debugPrint('[R2_UPLOAD][$traceId] SUCCESS objectKey=$objectKey bytes=${bytes.length}');
    return R2UploadedMedia(
      objectKey: objectKey,
      publicUrl: publicUrl,
      contentType: contentType,
      sizeBytes: bytes.length,
    );
  }
}
