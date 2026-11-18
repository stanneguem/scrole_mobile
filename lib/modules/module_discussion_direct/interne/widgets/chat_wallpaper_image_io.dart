import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';

Widget buildChatWallpaperImage(String path, {required Key key}) {
  if (path.startsWith('data:')) {
    try {
      final comma = path.indexOf(',');
      if (comma < 0 || !path.substring(0, comma).endsWith(';base64')) return const SizedBox.shrink();
      return Image.memory(base64Decode(path.substring(comma + 1)), key: key, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink());
    } catch (_) { return const SizedBox.shrink(); }
  }
  final file = File(path);
  if (!file.existsSync()) return const SizedBox.shrink();
  return Image.file(
    file,
    key: ValueKey('${file.path}_${file.lastModifiedSync().millisecondsSinceEpoch}'),
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
}
