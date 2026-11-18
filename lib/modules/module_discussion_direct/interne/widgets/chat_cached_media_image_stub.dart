import 'package:flutter/material.dart';

Widget buildChatCachedMediaImage({
  required String path,
  required double? width,
  required double? height,
  required BoxFit fit,
  required BorderRadius? borderRadius,
  required Widget Function() unavailable,
}) {
  if (!path.startsWith('https://') && !path.startsWith('http://') &&
      !path.startsWith('blob:') && !path.startsWith('data:')) {
    return unavailable();
  }
  return ClipRRect(
    borderRadius: borderRadius ?? BorderRadius.zero,
    child: Image.network(
      path,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) =>
          Container(alignment: Alignment.center, child: const Icon(Icons.broken_image_outlined)),
    ),
  );
}
