import 'scut_cache_cleanup_stub.dart'
    if (dart.library.io) 'scut_cache_cleanup_io.dart' as platform;

/// Clears the persistent Scut video cache on platforms with a local filesystem.
Future<void> clearScutOfflineCache() => platform.clearScutOfflineCache();
