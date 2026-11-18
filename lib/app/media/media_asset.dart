import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Platform-independent reference to a user-selected media file.
///
/// [XFile] is the boundary type shared by image_picker on mobile and Web.
/// Keep [XFile] here instead of converting it to dart:io File in shared code.
/// Platform-specific crop/compression adapters can be applied before upload.
class MediaAsset {
  const MediaAsset(this.file);

  final XFile file;

  /// Original filename supplied by the picker.
  String get name => file.name;

  /// MIME type when the platform/picker can provide it.
  String? get mimeType => file.mimeType;

  /// File extension without the leading dot, normalized to lowercase.
  String get extension {
    final filename = name;
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  /// Reads the asset into memory. Prefer [openRead] for large uploads.
  Future<Uint8List> readAsBytes() => file.readAsBytes();

  /// Streams the asset without requiring a dart:io File.
  Stream<List<int>> openRead([int? start, int? end]) =>
      file.openRead(start, end);

  /// Returns the asset size in bytes.
  Future<int> length() => file.length();

  /// Creates an asset from the cross-platform picker representation.
  factory MediaAsset.fromXFile(XFile file) => MediaAsset(file);
}
