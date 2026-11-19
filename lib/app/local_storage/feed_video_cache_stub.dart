/// Web fallback: browser playback uses the remote URL directly.
/// No path_provider, dart:io, or filesystem access is allowed here.
Future<String?> findOrCacheFeedVideo(String url) async => null;

Future<void> clearFeedVideoCache() async {}
