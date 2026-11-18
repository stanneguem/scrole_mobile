import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _storyVideoExtension(String objectKey) {
  final path = Uri.tryParse(objectKey)?.path ?? objectKey;
  return p.extension(path).toLowerCase() == '.mov' ? '.mov' : '.mp4';
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
    if (await media.exists()) await media.delete();
    if (await expiry.exists()) await expiry.delete();
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
        for (final extension in ['.mp4', '.mov']) {
          final cachedMedia = File('$basePath$extension');
          if (await cachedMedia.exists()) await cachedMedia.delete();
        }
        await entity.delete();
      }
    } catch (_) {}
  }

  final safeId = storyId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final expiry = expiresAt.toUtc();
  final videoFile = File(p.join(cacheDirectory.path, safeId + _storyVideoExtension(objectKey)));
  final expiryFile = File(p.join(cacheDirectory.path, '$safeId.expiry'));
  if (await videoFile.exists() && await expiryFile.exists()) {
    final cachedExpiry = DateTime.tryParse(await expiryFile.readAsString());
    if (cachedExpiry != null && cachedExpiry.isAfter(DateTime.now().toUtc()) &&
        cachedExpiry.isAtSameMomentAs(expiry) && await videoFile.length() > 0) {
      return VideoPlayerController.file(videoFile);
    }
  }
  if (await videoFile.exists()) await videoFile.delete();
  if (await expiryFile.exists()) await expiryFile.delete();

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
    final streamed = await client.get(Uri.parse(url)).timeout(const Duration(minutes: 3));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw HttpException('Téléchargement de la story impossible (HTTP ${streamed.statusCode}).');
    }
    if (streamed.bodyBytes.isEmpty) throw StateError('Le fichier vidéo téléchargé est vide.');
    await videoFile.writeAsBytes(streamed.bodyBytes, flush: true);
    await expiryFile.writeAsString(expiry.toIso8601String(), flush: true);
    return VideoPlayerController.file(videoFile);
  } finally {
    client.close();
  }
}
