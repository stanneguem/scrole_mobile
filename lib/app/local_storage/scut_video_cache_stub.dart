import 'package:video_player/video_player.dart';

Future<List<dynamic>> readScutFeedManifest() async => const [];

Future<void> writeScutFeedManifest(List<Map<String, dynamic>> items) async {}

Future<String?> findScutCachedVideo(String url) async => null;

Future<String?> cacheScutVideo(String url, {required bool downloadIfOnline}) async => null;

Future<void> pruneScutVideos(Iterable<String> urlsToKeep) async {}

VideoPlayerController createScutVideoController(String? localPath, String url) =>
    VideoPlayerController.networkUrl(Uri.parse(localPath ?? url));

Future<void> clearScutVideoCache() async {}

Future<void> queueScutWatchSignal(Map<String, dynamic> signal) async {}

Future<List<Map<String, dynamic>>> readPendingScutWatchSignals() async => const [];

Future<void> removePendingScutWatchSignal(String signalId) async {}
