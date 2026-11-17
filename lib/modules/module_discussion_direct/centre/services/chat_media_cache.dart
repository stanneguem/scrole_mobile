import 'dart:typed_data';

import 'chat_media_cache_stub.dart'
    if (dart.library.io) 'chat_media_cache_io.dart' as platform;

/// Stable API shared by mobile and browser implementations.
class ChatMediaCache {
  ChatMediaCache._() : _platform = platform.ChatMediaCachePlatform();
  static final ChatMediaCache instance = ChatMediaCache._();
  final platform.ChatMediaCachePlatform _platform;

  static bool isHttpUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');
  static bool isFilesystemPath(String value) =>
      value.startsWith('file://') || value.startsWith('/');
  static bool isStorageKey(String value) =>
      value.isNotEmpty && !isHttpUrl(value) && !isFilesystemPath(value);

  Future<String?> localPathFor(String remoteUrl) =>
      _platform.localPathFor(remoteUrl);
  Future<String?> cacheBytes(String remoteUrl, Uint8List bytes) =>
      _platform.cacheBytes(remoteUrl, bytes);
  Future<String?> saveLocalToSandbox(String storagePath, String localSourcePath) =>
      _platform.saveLocalToSandbox(storagePath, localSourcePath);
  Future<bool> saveToGallery({required String sourcePath, required String fileName}) =>
      _platform.saveToGallery(sourcePath: sourcePath, fileName: fileName);
  Future<String?> resolveLocalPath(String ref) =>
      _platform.resolveLocalPath(ref);
  Future<String?> cacheRemote(String remoteUrl) =>
      _platform.cacheRemote(remoteUrl);
  Future<void> removeLocal(String remoteUrl) =>
      _platform.removeLocal(remoteUrl);
  Future<void> purgeOldFiles({int days = 30}) =>
      _platform.purgeOldFiles(days: days);
}
