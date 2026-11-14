import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Future<void> clearScutOfflineCache() async {
  try {
    final directory = await getApplicationSupportDirectory();
    final videoCache = Directory('${directory.path}/scut_video_cache');
    if (await videoCache.exists()) await videoCache.delete(recursive: true);
    final manifest = File('${directory.path}/scut_feed_cache.json');
    if (await manifest.exists()) await manifest.delete();
  } catch (error) {
    if (kDebugMode) debugPrint('[Auth] Unable to clear Scut offline cache: $error');
  }
}
