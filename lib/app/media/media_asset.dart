import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Platform-independent reference to a selected or locally persisted media file.
/// Stream-backed assets avoid loading large videos into a single byte array.
class MediaAsset {
  const MediaAsset(this.file)
      : _streamReader = null,
        _knownLength = null,
        _name = null,
        _mimeType = null;

  MediaAsset._stream({
    required this.file,
    required String name,
    required String? mimeType,
    required int length,
    required Stream<List<int>> Function() openRead,
  }) : _streamReader = openRead,
       _knownLength = length,
       _name = name,
       _mimeType = mimeType;

  final XFile file;
  final Stream<List<int>> Function()? _streamReader;
  final int? _knownLength;
  final String? _name;
  final String? _mimeType;

  factory MediaAsset.fromStream({
    required String name,
    required String? mimeType,
    required int length,
    required Stream<List<int>> Function() openRead,
  }) => MediaAsset._stream(
    file: XFile.fromData(Uint8List(0), name: name, mimeType: mimeType),
    name: name,
    mimeType: mimeType,
    length: length,
    openRead: openRead,
  );

  String get name => _name ?? file.name;
  String? get mimeType => _mimeType ?? file.mimeType;

  String get extension {
    final filename = name;
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  Future<Uint8List> readAsBytes() async {
    if (_streamReader == null) return file.readAsBytes();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in _streamReader()) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Stream<List<int>> openRead([int? start, int? end]) {
    final reader = _streamReader;
    if (reader == null) return file.openRead(start, end);
    if (start == null && end == null) return reader();
    return _sliceStream(reader(), start ?? 0, end);
  }

  Stream<List<int>> _sliceStream(
    Stream<List<int>> source,
    int start,
    int? end,
  ) async* {
    var offset = 0;
    await for (final chunk in source) {
      final chunkEnd = offset + chunk.length;
      final from = start > offset ? start - offset : 0;
      final to = end != null && end < chunkEnd ? end - offset : chunk.length;
      if (to > from) yield chunk.sublist(from, to);
      offset = chunkEnd;
      if (end != null && offset >= end) break;
    }
  }

  Future<int> length() async => _knownLength ?? file.length();

  factory MediaAsset.fromXFile(XFile file) => MediaAsset(file);
}
