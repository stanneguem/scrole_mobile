import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const int _maxScutVideoBytes = 24 * 1024 * 1024;
const int _maxScutCacheBytes = 120 * 1024 * 1024;
const Duration _scutCacheTtl = Duration(days: 7);

String? _activeCacheUserId() =>
    Supabase.instance.client.auth.currentUser?.id;

String _safeUserSegment(String userId) =>
    sha256.convert(utf8.encode(userId)).toString();

Future<Directory> _cacheDirectory({String? userId}) async {
  final uid = userId ?? _activeCacheUserId();
  if (uid == null || uid.isEmpty) {
    throw StateError('Scut video cache requires an authenticated user');
  }
  final root = await getApplicationSupportDirectory();
  final directory = Directory(
    p.join(root.path, 'scut_video_cache', _safeUserSegment(uid)),
  );
  await directory.create(recursive: true);
  return directory;
}

Future<File> _manifestFile({String? userId}) async {
  final uid = userId ?? _activeCacheUserId();
  if (uid == null || uid.isEmpty) {
    throw StateError('Scut feed manifest requires an authenticated user');
  }
  final root = await getApplicationSupportDirectory();
  return File(p.join(root.path, 'scut_feed_cache_${_safeUserSegment(uid)}.json'));
}

Future<File> _pendingWatchFile({String? userId}) async {
  final uid = userId ?? _activeCacheUserId();
  if (uid == null || uid.isEmpty) {
    throw StateError('Scut watch queue requires an authenticated user');
  }
  final root = await getApplicationSupportDirectory();
  return File(p.join(root.path, 'scut_pending_watch_signals_${_safeUserSegment(uid)}.json'));
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
  if (_activeCacheUserId() == null) return const [];
  final file = await _manifestFile();
  if (!await file.exists()) return const [];
  final decoded = jsonDecode(await file.readAsString());
  return decoded is List ? decoded : const [];
}

Future<void> writeScutFeedManifest(List<Map<String, dynamic>> items) async {
  if (_activeCacheUserId() == null) return;
  final file = await _manifestFile();
  await file.writeAsString(jsonEncode(items), flush: true);
}

Future<String?> findScutCachedVideo(String url) async {
  if (_activeCacheUserId() == null) return null;
  final directory = await _cacheDirectory();
  await _pruneScutCache(directory);
  final file = File(p.join(directory.path, _fileName(url)));
  if (!await file.exists()) return null;
  final stat = await file.stat();
  if (stat.size <= 0 || stat.size > _maxScutVideoBytes ||
      DateTime.now().difference(stat.modified) > _scutCacheTtl) {
    try { await file.delete(); } catch (_) {}
    return null;
  }
  try { await file.setLastModified(DateTime.now()); } catch (_) {}
  return file.path;
}

Future<String?> cacheScutVideo(
  String url, {
  required bool downloadIfOnline,
}) async {
  final uri = Uri.tryParse(url);
  if (_activeCacheUserId() == null || uri == null ||
      !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.path.toLowerCase().endsWith('.m3u8') ||
      uri.path.toLowerCase().endsWith('.mpd')) return null;
  final cached = await findScutCachedVideo(url);
  if (cached != null || !downloadIfOnline) return cached;

  final directory = await _cacheDirectory();
  final file = File(p.join(directory.path, _fileName(url)));
  final partial = File('${file.path}.part');
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength == null ||
        response.contentLength! <= 0 ||
        response.contentLength! > _maxScutVideoBytes) {
      await response.stream.drain<void>();
      return null;
    }

    final sink = partial.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(const Duration(seconds: 45))) {
        received += chunk.length;
        if (received > _maxScutVideoBytes) {
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
    await partial.rename(file.path);
    await _pruneScutCache(directory, exceptPath: file.path);
    return file.path;
  } catch (_) {
    try { if (await partial.exists()) await partial.delete(); } catch (_) {}
    return null;
  } finally {
    client.close();
  }
}

Future<void> _pruneScutCache(
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
        if (now.difference(stat.modified) > const Duration(hours: 1)) {
          await entity.delete();
        }
        continue;
      }
      if (stat.size <= 0 || stat.size > _maxScutVideoBytes ||
          now.difference(stat.modified) > _scutCacheTtl) {
        await entity.delete();
        continue;
      }
      files.add((file: entity, modified: stat.modified, size: stat.size));
    } catch (_) {}
  }
  files.sort((a, b) => a.modified.compareTo(b.modified));
  var total = files.fold<int>(0, (sum, entry) => sum + entry.size);
  for (final entry in files) {
    if (total <= _maxScutCacheBytes) break;
    if (entry.file.path == exceptPath) continue;
    try {
      await entry.file.delete();
      total -= entry.size;
    } catch (_) {}
  }
}

Future<void> pruneScutVideos(Iterable<String> urlsToKeep) async {
  if (_activeCacheUserId() == null) return;
  final directory = await _cacheDirectory();
  final keep = urlsToKeep.map(_fileName).toSet();
  await _pruneScutCache(directory);
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

Future<void> clearScutVideoCache({String? userId}) async {
  final uid = userId ?? _activeCacheUserId();
  if (uid == null || uid.isEmpty) return;
  try {
    final directory = await _cacheDirectory(userId: uid);
    if (await directory.exists()) await directory.delete(recursive: true);
    final manifest = await _manifestFile(userId: uid);
    if (await manifest.exists()) await manifest.delete();
    // La file de signaux est un outbox : elle n'est pas supprimée ici.
  } catch (_) {
    // Logout must complete even if the OS temporarily denies cache deletion.
  }
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
