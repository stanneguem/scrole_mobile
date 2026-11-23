import 'dart:convert';

import 'package:flutter/widgets.dart';

Widget buildChatWallpaperImage(String path, {required Key key}) {
  // Les fonds personnalisés sont enregistrés sous forme de Data URI.
  // Image.network ne sait pas afficher une Data URI sur Flutter Web :
  // il faut décoder les octets et utiliser Image.memory.
  if (path.startsWith('data:')) {
    try {
      final comma = path.indexOf(',');
      if (comma < 0) return const SizedBox.shrink();

      final metadata = path.substring(0, comma);
      if (!metadata.endsWith(';base64')) {
        return const SizedBox.shrink();
      }

      final bytes = base64Decode(path.substring(comma + 1));
      if (bytes.isEmpty) return const SizedBox.shrink();

      return Image.memory(
        bytes,
        key: key,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  // Compatibilité avec les anciens liens distants et les URL blob du Web.
  if (path.startsWith('blob:') ||
      path.startsWith('http://') ||
      path.startsWith('https://')) {
    return Image.network(
      path,
      key: key,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  // Un chemin de fichier local n'est pas exploitable directement dans le Web.
  return const SizedBox.shrink();
}
