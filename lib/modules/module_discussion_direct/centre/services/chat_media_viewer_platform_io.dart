import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../../app/media/media_asset.dart';

import 'chat_media_cache.dart';

Future<String?> _localFile(String url) async {
  if (url.startsWith('data:')) {
    try {
      final data = Uri.parse(url).data;
      if (data == null) return null;
      final mime = data.mimeType.toLowerCase();
      final extension = mime == 'video/webm'
          ? 'webm'
          : mime == 'video/quicktime'
              ? 'mov'
              : mime == 'video/3gpp'
                  ? '3gp'
                  : 'mp4';
      final directory = await getTemporaryDirectory();
      final file = File(p.join(
        directory.path,
        'scrole_chat_preview_' + url.hashCode.abs().toString() + '.$extension',
      ));
      if (!await file.exists() || await file.length() == 0) {
        await file.writeAsBytes(data.contentAsBytes(), flush: true);
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }
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

final Map<VideoPlayerController, File> _pendingVideoFiles = {};

Future<VideoPlayerController> createChatMediaVideoControllerFromAsset(
  MediaAsset asset,
) async {
  final directory = await getTemporaryDirectory();
  final extension = p.extension(asset.name).isNotEmpty
      ? p.extension(asset.name)
      : (asset.mimeType == 'video/webm' ? '.webm' : '.mp4');
  final file = File(p.join(
    directory.path,
    'scrole_pending_video_${DateTime.now().microsecondsSinceEpoch}$extension',
  ));
  final sink = file.openWrite();
  try {
    await sink.addStream(asset.openRead());
    await sink.flush();
  } catch (_) {
    await sink.close();
    if (await file.exists()) await file.delete();
    rethrow;
  }
  await sink.close();
  final controller = VideoPlayerController.file(file);
  _pendingVideoFiles[controller] = file;
  return controller;
}

Future<File> _materializePendingAsset(MediaAsset asset) async {
  final directory = await getTemporaryDirectory();
  final extension = p.extension(asset.name).isNotEmpty
      ? p.extension(asset.name)
      : (asset.mimeType == 'video/webm' ? '.webm' : '.bin');
  final file = File(p.join(
    directory.path,
    'scrole_pending_share_${DateTime.now().microsecondsSinceEpoch}$extension',
  ));
  final sink = file.openWrite();
  try {
    await sink.addStream(asset.openRead());
    await sink.flush();
    await sink.close();
    return file;
  } catch (_) {
    await sink.close();
    if (await file.exists()) await file.delete();
    rethrow;
  }
}

Future<bool> savePendingChatMediaAsset(MediaAsset asset, String fileName) async {
  File? file;
  try {
    file = await _materializePendingAsset(asset);
    return await ChatMediaCache.instance.saveToGallery(
      sourcePath: file.path,
      fileName: fileName,
    );
  } catch (_) {
    return false;
  } finally {
    if (file != null) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}

Future<bool> sharePendingChatMediaAsset(MediaAsset asset, String fileName) async {
  File? file;
  try {
    file = await _materializePendingAsset(asset);
    await Share.shareXFiles(
      [XFile(file.path, name: fileName)],
      text: 'Média partagé depuis Scrole',
    );
    return true;
  } catch (_) {
    return false;
  } finally {
    if (file != null) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}

Future<void> disposeChatMediaVideoController(
  VideoPlayerController controller,
) async {
  await controller.dispose();
  final file = _pendingVideoFiles.remove(controller);
  if (file != null) {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
