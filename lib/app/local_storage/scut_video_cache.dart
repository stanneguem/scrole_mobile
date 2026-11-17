import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../modules/module_discussion_direct/centre/services/chat_media_cache.dart';

import 'fast/fast_cache_service.dart';

import 'scut_video_cache_stub.dart'
    if (dart.library.io) 'scut_video_cache_io.dart' as platform;

const _webManifestKey = 'scut.feed.manifest.v1';
String _webWatchQueueKey() =>
    'scut.watch.pending.v1.user.${Supabase.instance.client.auth.currentUser?.id ?? 'anonymous'}';

FastCacheService? get _webCache =>
    Get.isRegistered<FastCacheService>() ? Get.find<FastCacheService>() : null;

Future<List<dynamic>> readScutFeedManifest() async {
  if (!kIsWeb) return platform.readScutFeedManifest();
  final value = _webCache?.get<List<dynamic>>(_webManifestKey);
  return value ?? const [];
}

Future<void> writeScutFeedManifest(List<Map<String, dynamic>> items) async {
  if (!kIsWeb) return platform.writeScutFeedManifest(items);
  await _webCache?.set(_webManifestKey, items);
}

Future<String?> findScutCachedVideo(String url) async {
  if (!kIsWeb) return platform.findScutCachedVideo(url);
  return ChatMediaCache.instance.localPathFor(url);
}

Future<String?> cacheScutVideo(String url, {required bool downloadIfOnline}) async {
  if (!kIsWeb) {
    return platform.cacheScutVideo(url, downloadIfOnline: downloadIfOnline);
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.path.toLowerCase().endsWith('.m3u8') ||
      uri.path.toLowerCase().endsWith('.mpd')) return null;
  if (!downloadIfOnline) return url;
  // IndexedDB cache accepts bounded media files only; large videos fall back
  // to network streaming without buffering the entire file in memory.
  return await ChatMediaCache.instance.cacheRemote(url) ?? url;
}

Future<void> pruneScutVideos(Iterable<String> urlsToKeep) async {
  if (!kIsWeb) await platform.pruneScutVideos(urlsToKeep);
}

VideoPlayerController createScutVideoController(String? localPath, String url) =>
    platform.createScutVideoController(localPath, url);

Future<void> clearScutVideoCache() async {
  if (!kIsWeb) return platform.clearScutVideoCache();
  await _webCache?.remove(_webManifestKey);
  // Pending watch signals are an outbox, not a disposable media cache.
}

Future<void> queueScutWatchSignal(Map<String, dynamic> signal) async {
  if (!kIsWeb) return platform.queueScutWatchSignal(signal);
  final cache = _webCache;
  if (cache == null) return;
  final key = _webWatchQueueKey();
  final pending = cache.get<List<dynamic>>(key)?.toList() ?? <dynamic>[];
  pending.add({
    ...signal,
    'signal_id': DateTime.now().microsecondsSinceEpoch.toString(),
  });
  final bounded = pending.length > 1000
      ? pending.sublist(pending.length - 1000)
      : pending;
  await cache.set(key, bounded);
}

Future<List<Map<String, dynamic>>> readPendingScutWatchSignals() async {
  if (!kIsWeb) return platform.readPendingScutWatchSignals();
  final value = _webCache?.get<List<dynamic>>(_webWatchQueueKey()) ?? const [];
  return value.whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: true);
}

Future<void> removePendingScutWatchSignal(String signalId) async {
  if (!kIsWeb) return platform.removePendingScutWatchSignal(signalId);
  final cache = _webCache;
  if (cache == null) return;
  final key = _webWatchQueueKey();
  final pending = cache.get<List<dynamic>>(key)?.toList() ?? <dynamic>[];
  pending.removeWhere((entry) =>
      entry is Map && entry['signal_id']?.toString() == signalId);
  await cache.set(key, pending);
}
