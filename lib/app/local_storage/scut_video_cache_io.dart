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

String _fileName(String url) {
  final uri = Uri.tryParse(url);
  final lastSegment = uri == null || uri.pathSegments.isEmpty
      ? ''
      : uri.pathSegments.last;
  final extension = RegExp(r'\.([a-zA-Z0-9]{2,5})$')
      .firstMatch(lastSegment)
      ?.group(1)
      ?.toLowerCase();
  const supported = {'mp4', 'mov', 'm4v', 'webm', 'mkv', '3gp'};
  final safeExtension = supported.contains(extension) ? extension! : 'mp4';
  return '${sha256.convert(utf8.encode(url)).toString()}.$safeExtension';
}

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

Future<String?> cacheScutVideo(
  String url, {
  required bool downloadIfOnline,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.path.toLowerCase().endsWith('.m3u8')) return null;
  final directory = await _cacheDirectory();
  final file = File(p.join(directory.path, _fileName(url)));
  if (!await file.exists() && downloadIfOnline) {
    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
      }
    } catch (_) {
      // Streaming playback remains available when a cache download fails.
    }
  }
  return await file.exists() ? file.path : null;
}

Future<void> pruneScutVideos(Iterable<String> urlsToKeep) async {
  final directory = await _cacheDirectory();
  final keep = urlsToKeep.map(_fileName).toSet();
  await for (final entity in directory.list()) {
    if (entity is File && !keep.contains(p.basename(entity.path))) {
      try {
        await entity.delete();
      } catch (_) {}
    }
  }
}

VideoPlayerController createScutVideoController(
  String? localPath,
  String url,
) {
  if (localPath != null) {
    final file = File(localPath);
    if (file.existsSync()) return VideoPlayerController.file(file);
  }
  return VideoPlayerController.networkUrl(Uri.parse(url));
}

Future<void> clearScutVideoCache() async {
  try {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'scut_video_cache'));
    if (await directory.exists()) await directory.delete(recursive: true);
    final manifest = File(p.join(root.path, 'scut_feed_cache.json'));
    if (await manifest.exists()) await manifest.delete();
    final pending = File(p.join(root.path, 'scut_pending_watch_signals.json'));
    if (await pending.exists()) await pending.delete();
  } catch (_) {
    // Logout must complete even if the OS temporarily denies cache deletion.
  }
}

Future<File> _pendingWatchFile() async {
  final root = await getApplicationSupportDirectory();
  return File(p.join(root.path, 'scut_pending_watch_signals.json'));
}

Future<List<Map<String, dynamic>>> readPendingScutWatchSignals() async {
  try {
    final file = await _pendingWatchFile();
    if (!await file.exists()) return const [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: true);
  } catch (_) {
    return const [];
  }
}

Future<void> queueScutWatchSignal(Map<String, dynamic> signal) async {
  try {
    final pending = await readPendingScutWatchSignals();
    pending.add({
      ...signal,
      'signal_id': DateTime.now().microsecondsSinceEpoch.toString(),
    });
    final file = await _pendingWatchFile();
    final bounded = pending.length > 1000
        ? pending.sublist(pending.length - 1000)
        : pending;
    await file.writeAsString(jsonEncode(bounded), flush: true);
  } catch (_) {}
}

Future<void> removePendingScutWatchSignal(String signalId) async {
  try {
    final pending = await readPendingScutWatchSignals();
    pending.removeWhere(
      (entry) => entry['signal_id']?.toString() == signalId,
    );
    final file = await _pendingWatchFile();
    await file.writeAsString(jsonEncode(pending), flush: true);
  } catch (_) {}
}
