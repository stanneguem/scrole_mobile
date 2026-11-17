import '../../../../app/local_storage/structured/app_cache_database.dart';

import 'media_local_cache_stub.dart'
    if (dart.library.io) 'media_local_cache_io.dart' as platform;

/// Cross-platform facade. Web deliberately streams remote attachments rather
/// than trying to create dart:io files; native platforms keep disk caching.
class MediaLocalCache {
  MediaLocalCache(this._database)
      : _platform = platform.MediaLocalCachePlatform(_database);

  final AppDatabase _database;
  final platform.MediaLocalCachePlatform _platform;

  Future<String?> resolve({
    required String userId,
    required String messageId,
    required String remoteUrl,
  }) => _platform.resolve(
        userId: userId,
        messageId: messageId,
        remoteUrl: remoteUrl,
      );

  Future<String?> download({
    required String userId,
    required String messageId,
    required String remoteUrl,
  }) => _platform.download(
        userId: userId,
        messageId: messageId,
        remoteUrl: remoteUrl,
      );

  Future<void> deleteMessageMedia(String userId, String messageId) =>
      _platform.deleteMessageMedia(userId, messageId);
}
