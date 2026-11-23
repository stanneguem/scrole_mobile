import 'dart:async';
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

  // Start playback immediately through the network data source. In parallel,
  // download the complete object into a temporary file; only a verified,
  // finished download is promoted to the durable cache for the next opening.
  unawaited(_downloadStoryVideoToCache(
    url: url,
    storyId: storyId,
    partialFile: partialFile,
    videoFile: videoFile,
    sizeFile: sizeFile,
    expiryFile: expiryFile,
    expiresAt: expiry,
  ));
  debugPrint(
    '[STORY][ANDROID][STREAM_START] story=$storyId '
    'cacheDownload=background',
  );
  return VideoPlayerController.networkUrl(Uri.parse(url));
}

Future<int> _downloadStoryVideoToCache({
  required String url,
  required String storyId,
  required File partialFile,
  required File videoFile,
  required File sizeFile,
  required File expiryFile,
  required DateTime expiresAt,
}) async {
  const maxAttempts = 3;
  Object? lastError;
  final client = http.Client();
  try {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      var receivedBytes = 0;
      IOSink? sink;
      try {
        // Always request the complete object, never a byte range. Identity
        // encoding keeps Content-Length comparable to bytes written to disk.
        final request = http.Request('GET', Uri.parse(url))
          ..headers['accept-encoding'] = 'identity';
        final streamed = await client.send(request).timeout(
          const Duration(minutes: 4),
        );

        if (streamed.statusCode != HttpStatus.ok) {
          throw HttpException(
            'Téléchargement complet requis : HTTP ${streamed.statusCode}.',
          );
        }
        final contentRange = streamed.headers['content-range'];
        if (contentRange != null && contentRange.trim().isNotEmpty) {
          throw HttpException(
            'Réponse partielle inattendue pendant le téléchargement : $contentRange',
          );
        }

        final expectedLength = streamed.contentLength;
        if (expectedLength != null && expectedLength <= 0) {
          throw StateError('La vidéo de la story est vide.');
        }

        if (await partialFile.exists()) await partialFile.delete();
        sink = partialFile.openWrite();
        await for (final chunk in streamed.stream.timeout(
          const Duration(seconds: 60),
        )) {
          receivedBytes += chunk.length;
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
        sink = null;

        // A clean end-of-stream validates chunked responses even when the
        // server omits Content-Length. When supplied, the exact byte count
        // is mandatory before promoting the temporary file to the cache.
        if (receivedBytes <= 0 ||
            (expectedLength != null && receivedBytes != expectedLength)) {
          throw StateError(
            'Story incomplète : reçu=$receivedBytes, attendu=$expectedLength octets.',
          );
        }

        if (await videoFile.exists()) await videoFile.delete();
        await partialFile.rename(videoFile.path);
        await sizeFile.writeAsString('$receivedBytes', flush: true);
        await expiryFile.writeAsString(expiresAt.toIso8601String(), flush: true);
        debugPrint(
          '[STORY][ANDROID][CACHE_COMPLETE] story=$storyId '
          'bytes=$receivedBytes contentLength=$expectedLength attempt=$attempt',
        );
        return receivedBytes;
      } catch (error) {
        lastError = error;
        try {
          await sink?.close();
        } catch (_) {}
        try {
          if (await partialFile.exists()) await partialFile.delete();
        } catch (_) {}
        debugPrint(
          '[STORY][ANDROID][DOWNLOAD_RETRY] story=$storyId '
          'attempt=$attempt/$maxAttempts bytes=$receivedBytes error=$error',
        );
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
  } finally {
    client.close();
  }

  throw StateError(
    'Impossible de télécharger intégralement la story après $maxAttempts tentatives : $lastError',
  );
}
