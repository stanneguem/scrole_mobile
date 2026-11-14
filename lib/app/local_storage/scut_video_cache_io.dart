import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

Future<Directory> _cacheDirectory() async {
  final root = await getApplicationSupportDirectory();
  final directory = Directory(p.join(root.path, 'scut_video_cache'));
  await directory.create(recursive: true);
  return directory;
}

String _fileName(String url) =>
    '${sha256.convert(utf8.encode(url)).toString()}.video';

Future<List<dynamic>> readScutFeedManifest() async {
  final root = await getApplicationSupportDirectory();
  final file = File(p.join(root.path, 'scut_feed_cache.json'));
  if (!await file.exists()) return const [];
  final decoded = jsonDecode(await file.readAsString());
  return decoded is List ? decoded : const [];
}

Future<void> writeScutFeedManifest(List<Map<String, dynamic>> items) async {
  final root = await getApplicationSupportDirectory();
  final file = File(p.join(root.path, 'scut_feed_cache.json'));
  await file.writeAsString(jsonEncode(items), flush: true);
}

Future<String?> findScutCachedVideo(String url) async {
  final directory = await _cacheDirectory();
  final file = File(p.join(directory.path, _fileName(url)));
  return await file.exists() ? file.path : null;
}

Future<String?> cacheScutVideo(String url, {required bool downloadIfOnline}) async {
  final directory = await _cacheDirectory();
  final file = File(p.join(directory.path, _fileName(url)));
  if (!await file.exists() && downloadIfOnline) {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
      }
    } catch (_) {
      // Keep streaming playback available when a cache download fails.
    }
  }
  return await file.exists() ? file.path : null;
}

Future<void> pruneScutVideos(Iterable<String> urlsToKeep) async {
  final directory = await _cacheDirectory();
  final keep = urlsToKeep.map(_fileName).toSet();
  for (final entity in directory.listSync()) {
    if (entity is File && !keep.contains(p.basename(entity.path))) {
      try { await entity.delete(); } catch (_) {}
    }
  }
}

VideoPlayerController createScutVideoController(String? localPath, String url) {
  if (localPath != null) {
    final file = File(localPath);
    if (file.existsSync()) return VideoPlayerController.file(file);
  }
  return VideoPlayerController.networkUrl(Uri.parse(url));
}

Future<void> clearScutVideoCache() async {
  final root = await getApplicationSupportDirectory();
  final directory = Directory(p.join(root.path, 'scut_video_cache'));
  if (await directory.exists()) await directory.delete(recursive: true);
  final manifest = File(p.join(root.path, 'scut_feed_cache.json'));
  if (await manifest.exists()) await manifest.delete();
}
