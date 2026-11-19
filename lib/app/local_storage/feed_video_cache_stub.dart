import 'package:video_player/video_player.dart';

/// Web fallback: browser playback uses the remote URL directly.
/// No path_provider, dart:io, or filesystem access is allowed here.
Future<String?> findOrCacheFeedVideo(String url) async => null;

Future<void> clearFeedVideoCache() async {}


VideoPlayerController createFeedVideoController(String? localPath, String url) =>
    VideoPlayerController.networkUrl(Uri.parse(url));
