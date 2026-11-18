import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'chat_media_cache.dart';

Future<VideoPlayerController> createChatMediaVideoController(String url) async {
  final resolved = await ChatMediaCache.instance.resolveLocalPath(url);
  final source = resolved != null && resolved.isNotEmpty ? resolved : url;
  return VideoPlayerController.networkUrl(Uri.parse(source));
}

/// Browser downloads cannot be written into a device gallery.
Future<bool> saveChatMediaToGallery(String url, String fileName) async => false;

/// Uses the browser share sheet when supported by share_plus.
Future<bool> shareChatMedia(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    final uri = Uri.parse(url);
    final segment = uri.pathSegments.isEmpty ? 'scrole-media' : uri.pathSegments.last;
    final extension = segment.contains('.') ? segment.split('.').last : 'bin';
    final mimeType = extension.toLowerCase() == 'mp4'
        ? 'video/mp4'
        : extension.toLowerCase() == 'webm'
            ? 'video/webm'
            : 'image/jpeg';
    await Share.shareXFiles(
      [XFile.fromData(response.bodyBytes, name: segment, mimeType: mimeType)],
      text: 'Média partagé depuis Scrole',
    );
    return true;
  } catch (_) {
    return false;
  }
}
