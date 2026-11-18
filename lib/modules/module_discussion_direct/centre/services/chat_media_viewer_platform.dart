import 'package:video_player/video_player.dart';
import 'chat_media_viewer_platform_stub.dart'
    if (dart.library.io) 'chat_media_viewer_platform_io.dart' as platform;

/// Platform boundary for full-screen chat media actions.
Future<VideoPlayerController> createChatMediaVideoController(String url) =>
    platform.createChatMediaVideoController(url);

Future<bool> saveChatMediaToGallery(String url, String fileName) =>
    platform.saveChatMediaToGallery(url, fileName);

Future<bool> shareChatMedia(String url) => platform.shareChatMedia(url);
