import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

const int _maxFeedVideoBytes = 24 * 1024 * 1024;
const int _maxFeedVideoCacheBytes = 120 * 1024 * 1024;
const Duration _feedVideoCacheTtl = Duration(days: 7);

Future<Directory> _feedVideoDirectory() async {
  final root = await getApplicationSupportDirectory();
  final directory = Directory(p.join(root.path, 'feed_video_cache'));
  await directory.create(recursive: true);
  return directory;
}

String _feedVideoCacheName(String url) {
  final uri = Uri.tryParse(url);
  final extension = uri == null ? null : p.extension(uri.path).toLowerCase();
  const supported = {'.mp4', '.m4v', '.mov', '.webm', '.3gp'};
  final safeExtension = supported.contains(extension) ? extension : '.video';
  return '${sha256.convert(utf8.encode(url))}$safeExtension';
}

/// Returns a persistent local copy only for small, ordinary progressive files.
/// HLS/DASH and unknown/large responses keep using native network streaming.
Future<String?> findOrCacheFeedVideo(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.path.toLowerCase().endsWith('.m3u8') ||
      uri.path.toLowerCase().endsWith('.mpd')) {
    return null;
  }

  final directory = await _feedVideoDirectory();
  // Maintenance also runs on cache hits, so abandoned/expired files do not
  // survive indefinitely when the user stops downloading new videos.
  await _pruneFeedVideoCache(directory);
  final target = File(p.join(directory.path, _feedVideoCacheName(url)));
  if (await target.exists()) {
    final stat = await target.stat();
    if (DateTime.now().difference(stat.modified) <= _feedVideoCacheTtl &&
        stat.size > 0 && stat.size <= _maxFeedVideoBytes) {
      try { await target.setLastModified(DateTime.now()); } catch (_) {}
      return target.path;
    }
    try { await target.delete(); } catch (_) {}
  }

  final client = http.Client();
  final partial = File('${target.path}.part');
  try {
    final request = http.Request('GET', uri);
    final response = await client.send(request).timeout(const Duration(seconds: 35));
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength == null ||
        response.contentLength! <= 0 ||
        response.contentLength! > _maxFeedVideoBytes) {
      response.stream.listen((_) {}).cancel();
      return null;
    }

    final sink = partial.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(const Duration(seconds: 35))) {
        received += chunk.length;
        if (received > _maxFeedVideoBytes) {
          await sink.close();
          try { await partial.delete(); } catch (_) {}
          return null;
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      rethrow;
    }
    if (received == 0 || received != response.contentLength) {
      try { await partial.delete(); } catch (_) {}
      return null;
    }
    await partial.rename(target.path);
    await _pruneFeedVideoCache(directory, exceptPath: target.path);
    return target.path;
  } catch (_) {
    try { if (await partial.exists()) await partial.delete(); } catch (_) {}
    return null;
  } finally {
    client.close();
  }
}

Future<void> _pruneFeedVideoCache(
  Directory directory, {
  String? exceptPath,
}) async {
  final now = DateTime.now();
  final files = <({File file, DateTime modified, int size})>[];

  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    try {
      final stat = await entity.stat();
      if (entity.path.endsWith('.part')) {
        // A killed/failed download must not leave an unbounded temp file.
        if (now.difference(stat.modified) > const Duration(hours: 1)) {
          await entity.delete();
        }
        continue;
      }
      if (now.difference(stat.modified) > _feedVideoCacheTtl ||
          stat.size <= 0 ||
          stat.size > _maxFeedVideoBytes) {
        await entity.delete();
        continue;
      }
      files.add((file: entity, modified: stat.modified, size: stat.size));
    } catch (_) {
      // Ignore files concurrently removed by another cache operation.
    }
  }

  files.sort((a, b) => a.modified.compareTo(b.modified));
  var total = files.fold<int>(0, (sum, entry) => sum + entry.size);
  for (final entry in files) {
    if (total <= _maxFeedVideoCacheBytes) break;
    if (entry.file.path == exceptPath) continue;
    try {
      await entry.file.delete();
      total -= entry.size;
    } catch (_) {}
  }
}

Future<void> clearFeedVideoCache() async {
  try {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'feed_video_cache'));
    if (await directory.exists()) await directory.delete(recursive: true);
  } catch (_) {}
}


VideoPlayerController createFeedVideoController(String? localPath, String url) {
  if (localPath != null) {
    final file = File(localPath);
    if (file.existsSync()) return VideoPlayerController.file(file);
  }
  return VideoPlayerController.networkUrl(Uri.parse(url));
}
