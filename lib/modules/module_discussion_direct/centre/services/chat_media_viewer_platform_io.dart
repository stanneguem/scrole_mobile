import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'chat_media_cache.dart';

Future<String?> _localFile(String url) async {
  if (url.startsWith('data:')) return null;
  if (ChatMediaCache.isFilesystemPath(url)) {
    final path = url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
    if (await File(path).exists()) return path;
  }

  final cached = await ChatMediaCache.instance.resolveLocalPath(url);
  if (cached != null && ChatMediaCache.isFilesystemPath(cached) &&
      await File(cached).exists()) {
    return cached;
  }

  if (ChatMediaCache.isHttpUrl(url)) {
    try {
      return (await DefaultCacheManager().getSingleFile(url)).path;
    } catch (_) {
      return null;
    }
  }
  return null;
}

Future<VideoPlayerController> createChatMediaVideoController(String url) async {
  final path = await _localFile(url);
  if (path != null) return VideoPlayerController.file(File(path));
  return VideoPlayerController.networkUrl(Uri.parse(url));
}

Future<bool> saveChatMediaToGallery(String url, String fileName) async {
  final path = await _localFile(url);
  if (path == null) return false;
  return ChatMediaCache.instance.saveToGallery(
    sourcePath: path,
    fileName: fileName,
  );
}

Future<bool> shareChatMedia(String url) async {
  final path = await _localFile(url);
  if (path == null) return false;
  await Share.shareXFiles([XFile(path)], text: 'Média partagé depuis Scrole');
  return true;
}
