import 'package:flutter/widgets.dart';

Widget buildChatWallpaperImage(String path, {required Key key}) {
  if (path.startsWith('blob:') || path.startsWith('http://') ||
      path.startsWith('https://') || path.startsWith('data:')) {
    return Image.network(
      path,
      key: key,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
  return const SizedBox.shrink();
}
