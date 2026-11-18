import 'dart:io';
import 'package:flutter/widgets.dart';

Widget buildChatWallpaperImage(String path, {required Key key}) {
  final file = File(path);
  if (!file.existsSync()) return const SizedBox.shrink();
  return Image.file(
    file,
    key: ValueKey('${file.path}_${file.lastModifiedSync().millisecondsSinceEpoch}'),
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
}
