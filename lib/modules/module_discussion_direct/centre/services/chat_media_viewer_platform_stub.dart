import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import '../../../../app/media/media_asset.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'chat_media_cache.dart';

Future<VideoPlayerController> createChatMediaVideoController(String url) async {
  if (url.startsWith('data:')) {
    return VideoPlayerController.networkUrl(Uri.parse(url));
  }
  final resolved = await ChatMediaCache.instance.resolveLocalPath(url);
  final source = resolved != null && resolved.isNotEmpty ? resolved : url;
  return VideoPlayerController.networkUrl(Uri.parse(source));
}

/// On Web, save the already-cached attachment through the browser download
/// mechanism. The durable copy remains in IndexedDB; this only exports a file.
Future<bool> saveChatMediaToGallery(String url, String fileName) async {
  try {
    final resolved = await ChatMediaCache.instance.resolveLocalPath(url);
    if (resolved == null || resolved.isEmpty) return false;
    final anchor = html.AnchorElement(href: resolved)
      ..download = fileName
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  }
}

/// Uses the browser share sheet when supported by share_plus.
Future<bool> shareChatMedia(String url) async {
  try {
    final resolved = await ChatMediaCache.instance.resolveLocalPath(url) ?? url;
    final uri = Uri.parse(resolved);
    late final Uint8List bytes;
    late final String segment;
    late final String mimeType;
    if (url.startsWith('data:')) {
      final data = uri.data;
      if (data == null) return false;
      bytes = data.contentAsBytes();
      mimeType = data.mimeType;
      final extension = mimeType.split('/').last.split('+').first;
      segment = 'scrole-media.${extension == 'quicktime' ? 'mov' : extension}';
    } else {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      bytes = response.bodyBytes;
      segment = uri.pathSegments.isEmpty ? 'scrole-media' : uri.pathSegments.last;
      final extension = segment.contains('.') ? segment.split('.').last : 'bin';
      mimeType = extension.toLowerCase() == 'mp4'
          ? 'video/mp4'
          : extension.toLowerCase() == 'webm'
              ? 'video/webm'
              : 'image/jpeg';
    }
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: segment, mimeType: mimeType)],
      text: 'Média partagé depuis Scrole',
    );
    return true;
  } catch (_) {
    return false;
  }
}

final Map<VideoPlayerController, String> _pendingVideoObjectUrls = {};

Future<List<Uint8List>> _readPendingAssetChunks(MediaAsset asset) async {
  final chunks = <Uint8List>[];
  await for (final chunk in asset.openRead()) {
    chunks.add(Uint8List.fromList(chunk));
  }
  return chunks;
}

Future<html.Blob> _pendingAssetBlob(MediaAsset asset) async {
  final chunks = await _readPendingAssetChunks(asset);
  return html.Blob(chunks, asset.mimeType ?? 'application/octet-stream');
}

Future<VideoPlayerController> createChatMediaVideoControllerFromAsset(
  MediaAsset asset,
) async {
  final blob = await _pendingAssetBlob(asset);
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  final controller = VideoPlayerController.networkUrl(Uri.parse(objectUrl));
  _pendingVideoObjectUrls[controller] = objectUrl;
  return controller;
}

Future<void> disposeChatMediaVideoController(
  VideoPlayerController controller,
) async {
  await controller.dispose();
  final objectUrl = _pendingVideoObjectUrls.remove(controller);
  if (objectUrl != null) html.Url.revokeObjectUrl(objectUrl);
}

Future<bool> savePendingChatMediaAsset(MediaAsset asset, String fileName) async {
  String? objectUrl;
  try {
    final blob = await _pendingAssetBlob(asset);
    objectUrl = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: objectUrl)
      ..download = fileName
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  } finally {
    if (objectUrl != null) {
      Future<void>.delayed(const Duration(seconds: 1), () {
        html.Url.revokeObjectUrl(objectUrl!);
      });
    }
  }
}

Future<bool> sharePendingChatMediaAsset(MediaAsset asset, String fileName) async {
  try {
    final chunks = await _readPendingAssetChunks(asset);
    final bytes = Uint8List.fromList(chunks.expand((chunk) => chunk).toList());
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: fileName, mimeType: asset.mimeType)],
      text: 'Média partagé depuis Scrole',
    );
    return true;
  } catch (_) {
    return false;
  }
}
