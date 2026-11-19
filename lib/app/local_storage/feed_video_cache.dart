import 'feed_video_cache_stub.dart'
    if (dart.library.io) 'feed_video_cache_io.dart' as platform;

/// Native platforms may persist small progressive videos on disk.
/// Web deliberately skips this filesystem cache and streams the source URL.
Future<String?> findOrCacheFeedVideo(String url) =>
    platform.findOrCacheFeedVideo(url);

Future<void> clearFeedVideoCache() => platform.clearFeedVideoCache();

VideoPlayerController createFeedVideoController(String? localPath, String url) =>
    platform.createFeedVideoController(localPath, url);
