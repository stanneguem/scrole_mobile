import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _storyVideoExtension(String objectKey) {
  final path = Uri.tryParse(objectKey)?.path ?? objectKey;
  final extension = p.extension(path).toLowerCase();
  if (extension == '.mov') return '.mov';
  if (extension == '.webm') return '.webm';
  return '.mp4';
}

Future<void> deleteCachedStoryVideo({
  required String storyId,
  required String objectKey,
}) async {
  try {
    final directory = await getApplicationSupportDirectory();
    final safeId = storyId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final media = File(p.join(directory.path, 'stories_cache', safeId + _storyVideoExtension(objectKey)));
    final expiry = File(p.join(directory.path, 'stories_cache', '$safeId.expiry'));
    final size = File(p.join(directory.path, 'stories_cache', '$safeId.size'));
    final partial = File(p.join(directory.path, 'stories_cache', '$safeId.part'));
    if (await media.exists()) await media.delete();
    if (await expiry.exists()) await expiry.delete();
    if (await size.exists()) await size.delete();
    if (await partial.exists()) await partial.delete();
  } catch (_) {}
}

Future<VideoPlayerController> createStoryPlaybackController({
  required String objectKey,
  required String storyId,
  required DateTime expiresAt,
}) async {
  if (!expiresAt.isAfter(DateTime.now())) {
    throw StateError('Cette story a expiré.');
  }
  final directory = await getApplicationSupportDirectory();
  final cacheDirectory = Directory(p.join(directory.path, 'stories_cache'));
  if (!await cacheDirectory.exists()) {
    await cacheDirectory.create(recursive: true);
  }

  final now = DateTime.now().toUtc();
  await for (final entity in cacheDirectory.list()) {
    if (entity is! File || !entity.path.endsWith('.expiry')) continue;
    try {
      final cachedExpiry = DateTime.tryParse(await entity.readAsString());
      if (cachedExpiry == null || !cachedExpiry.isAfter(now)) {
        final basePath = entity.path.substring(0, entity.path.length - '.expiry'.length);
        for (final extension in ['.mp4', '.mov', '.webm']) {
          final cachedMedia = File('$basePath$extension');
          if (await cachedMedia.exists()) await cachedMedia.delete();
        }
        for (final suffix in ['.size', '.part']) {
          final sidecar = File('$basePath$suffix');
          if (await sidecar.exists()) await sidecar.delete();
        }
        await entity.delete();
      }
    } catch (_) {}
  }

  final safeId = storyId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final expiry = expiresAt.toUtc();
  final videoFile = File(p.join(cacheDirectory.path, safeId + _storyVideoExtension(objectKey)));
  final expiryFile = File(p.join(cacheDirectory.path, '$safeId.expiry'));
  final sizeFile = File(p.join(cacheDirectory.path, '$safeId.size'));
  final partialFile = File(p.join(cacheDirectory.path, '$safeId.part'));
  if (await videoFile.exists() && await expiryFile.exists() && await sizeFile.exists()) {
    final cachedExpiry = DateTime.tryParse(await expiryFile.readAsString());
    final expectedSize = int.tryParse((await sizeFile.readAsString()).trim());
    final actualSize = await videoFile.length();
    if (cachedExpiry != null && cachedExpiry.isAfter(DateTime.now().toUtc()) &&
        cachedExpiry.isAtSameMomentAs(expiry) && expectedSize != null &&
        expectedSize > 0 && actualSize == expectedSize) {
      debugPrint('[STORY][ANDROID] Using complete cached video story=$storyId bytes=$actualSize');
      return VideoPlayerController.file(videoFile);
    }
    debugPrint('[STORY][ANDROID] Invalidating incomplete/stale video cache story=$storyId expected=$expectedSize actual=$actualSize');
  }
  if (await videoFile.exists()) await videoFile.delete();
  if (await expiryFile.exists()) await expiryFile.delete();
  if (await sizeFile.exists()) await sizeFile.delete();
  if (await partialFile.exists()) await partialFile.delete();

  var url = objectKey;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    final response = await Supabase.instance.client.functions.invoke(
      'r2-media-upload',
      body: {'action': 'create-download-url', 'object_key': objectKey},
    );
    if (response.status < 200 || response.status >= 300 || response.data is! Map) {
      throw StateError('Impossible de résoudre la vidéo privée de la story.');
    }
    url = (response.data as Map)['url']?.toString() ?? '';
    if (url.isEmpty) throw StateError('URL de lecture de la vidéo absente.');
  }

  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(url));
    final streamed = await client.send(request).timeout(const Duration(minutes: 3));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw HttpException('Téléchargement de la story impossible (HTTP ${streamed.statusCode}).');
    }

    final expectedLength = streamed.contentLength;
    if (expectedLength != null && expectedLength <= 0) {
      throw StateError('La vidéo de la story est vide (Content-Length invalide).');
    }

    // Never expose a partially downloaded MP4 to ExoPlayer. A temporary file
    // is promoted to the cache only after the complete HTTP body is received
    // and its byte count matches the server's Content-Length.
    var receivedBytes = 0;
    final sink = partialFile.openWrite();
    try {
      await for (final chunk in streamed.stream) {
        receivedBytes += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await partialFile.exists()) await partialFile.delete();
      rethrow;
    }

    if (receivedBytes <= 0 ||
        (expectedLength != null && receivedBytes != expectedLength)) {
      if (await partialFile.exists()) await partialFile.delete();
      throw StateError(
        'Téléchargement incomplet de la story : reçu=$receivedBytes, attendu=$expectedLength octets.',
      );
    }

    if (await videoFile.exists()) await videoFile.delete();
    await partialFile.rename(videoFile.path);
    await sizeFile.writeAsString('$receivedBytes', flush: true);
    await expiryFile.writeAsString(expiry.toIso8601String(), flush: true);
    debugPrint(
      '[STORY][ANDROID] Video story downloaded completely story=$storyId bytes=$receivedBytes contentLength=$expectedLength',
    );
    return VideoPlayerController.file(videoFile);
  } finally {
    client.close();
  }
}
