import 'package:video_player/video_player.dart';

import 'scut_video_cache_stub.dart'
    if (dart.library.io) 'scut_video_cache_io.dart' as platform;

Future<List<dynamic>> readScutFeedManifest() => platform.readScutFeedManifest();

Future<void> writeScutFeedManifest(List<Map<String, dynamic>> items) =>
    platform.writeScutFeedManifest(items);

Future<String?> findScutCachedVideo(String url) =>
    platform.findScutCachedVideo(url);

Future<String?> cacheScutVideo(String url, {required bool downloadIfOnline}) =>
    platform.cacheScutVideo(url, downloadIfOnline: downloadIfOnline);

Future<void> pruneScutVideos(Iterable<String> urlsToKeep) =>
    platform.pruneScutVideos(urlsToKeep);

VideoPlayerController createScutVideoController(String? localPath, String url) =>
    platform.createScutVideoController(localPath, url);

Future<void> clearScutVideoCache() => platform.clearScutVideoCache();

Future<void> queueScutWatchSignal(Map<String, dynamic> signal) =>
    platform.queueScutWatchSignal(signal);

Future<List<Map<String, dynamic>>> readPendingScutWatchSignals() =>
    platform.readPendingScutWatchSignals();

Future<void> removePendingScutWatchSignal(String signalId) =>
    platform.removePendingScutWatchSignal(signalId);
