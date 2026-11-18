import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<File> _legacyFile(String userId) async {
  final directory = await getApplicationSupportDirectory();
  return File(p.join(directory.path, 'stories_tray_cache_$userId.json'));
}

Future<Map<String, dynamic>?> readLegacyStoryTray(String userId) async {
  final file = await _legacyFile(userId);
  if (!await file.exists()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } finally {
    await file.delete();
  }
}

Future<void> clearLegacyStoryTray(String userId) async {
  final file = await _legacyFile(userId);
  if (await file.exists()) await file.delete();
}
