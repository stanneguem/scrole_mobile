import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Browser implementation: use HTTPS URLs directly and never touch dart:io.
class ChatMediaCachePlatform {
  ChatMediaCachePlatform();

  static bool _isHttpUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');
  static bool _isR2ObjectKey(String value) =>
      value.startsWith('messages/') || value.startsWith('stories/') ||
      value.startsWith('private/') || value.startsWith('bug-reports/') ||
      value.startsWith('salon-messages/');

  Future<String?> localPathFor(String remoteUrl) async => null;
  Future<String?> cacheBytes(String remoteUrl, Uint8List bytes) async => null;
  Future<String?> saveLocalToSandbox(String storagePath, String localSourcePath) async => null;
  Future<bool> saveToGallery({required String sourcePath, required String fileName}) async => false;

  Future<String?> resolveLocalPath(String ref) async {
    if (ref.isEmpty) return null;
    if (_isHttpUrl(ref)) return ref;
    return cacheRemote(ref);
  }

  Future<String?> cacheRemote(String remoteUrl) async {
    if (remoteUrl.isEmpty) return null;
    if (_isHttpUrl(remoteUrl) && !remoteUrl.contains('/storage/v1/object/')) {
      return remoteUrl;
    }
    try {
      final client = Supabase.instance.client;
      if (_isR2ObjectKey(remoteUrl)) {
        final response = await client.functions.invoke(
          'r2-media-upload',
          body: {'action': 'create-download-url', 'object_key': remoteUrl},
        );
        if (response.status < 200 || response.status >= 300 || response.data is! Map) return null;
        final data = Map<String, dynamic>.from(response.data as Map);
        final url = data['url'] as String?;
        return url == null || url.isEmpty ? null : url;
      }
      return await client.storage.from('chat-media').createSignedUrl(remoteUrl, 120);
    } catch (_) {
      return null;
    }
  }

  Future<void> removeLocal(String remoteUrl) async {}
  Future<void> purgeOldFiles({int days = 30}) async {}
}
