import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../centre/services/chat_media_cache.dart';

Widget buildChatCachedMediaImage({
  required String path,
  required Uint8List? bytes,
  required double? width,
  required double? height,
  required BoxFit fit,
  required BorderRadius? borderRadius,
  required Widget Function() unavailable,
}) {
  if (bytes != null) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Image.memory(bytes, width: width, height: height, fit: fit,
          errorBuilder: (_, __, ___) => unavailable()),
    );
  }
  if (path.startsWith('data:')) {
    final comma = path.indexOf(',');
    if (comma < 0) return unavailable();
    try {
      final decoded = base64Decode(path.substring(comma + 1));
      return ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: Image.memory(decoded, width: width, height: height, fit: fit,
            errorBuilder: (_, __, ___) => unavailable()),
      );
    } catch (_) {
      return unavailable();
    }
  }
  if (path.startsWith('https://') || path.startsWith('http://')) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Image.network(path, width: width, height: height, fit: fit,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
    );
  }
  if (!ChatMediaCache.isFilesystemPath(path)) return unavailable();
  final absolute =
      path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;
  final file = File(absolute);
  if (!file.existsSync()) return unavailable();
  return ClipRRect(
    borderRadius: borderRadius ?? BorderRadius.zero,
    child: Image.file(file, width: width, height: height, fit: fit,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
  );
}
