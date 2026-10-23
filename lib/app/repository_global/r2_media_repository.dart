import 'dart:io';
import 'dart:typed_data';

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
    if (_client.auth.currentUser == null) {
      throw const AuthException('Vous devez être connecté pour envoyer un média.');
    }

    final extension = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    final isVideo = mediaType == 'video';
    final contentType = (isVideo ? _videoTypes : _imageTypes)[extension];
    if (contentType == null) {
      throw ArgumentError('Format de média non pris en charge : .$extension');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw StateError('Le fichier sélectionné est vide.');

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

    if (response.status < 200 || response.status >= 300 || response.data is! Map) {
      final details = response.data is Map
          ? (response.data as Map)['error']?.toString()
          : null;
      throw StateError('Autorisation R2 refusée${details == null ? '' : ' : $details'}');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    final uploadUrl = data['upload_url'] as String?;
    final objectKey = data['object_key'] as String?;
    final publicUrl = data['public_url'] as String?;
    if (uploadUrl == null || objectKey == null || publicUrl == null) {
      throw StateError('Réponse R2 incomplète : URL ou clé manquante.');
    }

    final request = http.Request('PUT', Uri.parse(uploadUrl))
      ..headers['Content-Type'] = contentType
      ..headers['Content-Length'] = bytes.length.toString()
      ..bodyBytes = Uint8List.fromList(bytes);

    final client = http.Client();
    try {
      final streamed = await client.send(request);
      final uploadResponse = await http.Response.fromStream(streamed);
      if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
        throw HttpException(
          'Échec du téléversement R2 (HTTP ${uploadResponse.statusCode}).',
        );
      }
    } finally {
      client.close();
    }

    return R2UploadedMedia(
      objectKey: objectKey,
      publicUrl: publicUrl,
      contentType: contentType,
      sizeBytes: bytes.length,
    );
  }
}
