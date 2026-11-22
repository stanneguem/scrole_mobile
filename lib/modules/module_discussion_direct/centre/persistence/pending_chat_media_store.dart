import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../../../../app/media/media_asset.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Persists outgoing attachment bytes outside SQLite. The existing Hive cache
/// backend uses browser storage on Web; SQLite/outbox rows keep only a URI.
class PendingChatMediaStore {
  PendingChatMediaStore();

  Future<LazyBox>? _boxFuture;
  Future<LazyBox> get _box => _boxFuture ??= Hive.openLazyBox('pending_chat_media');
  static const _prefix = 'pending_chat_media:';
  static const _scheme = 'pending-media';

  String _key(String userId, String messageId, int index) =>
      '$_prefix$userId:$messageId:$index';

  static const int chunkSize = 256 * 1024;

  Future<PendingChatMediaWriter> beginWavRecording({
    required String userId,
    required String messageId,
    required int index,
  }) async {
    final box = await _box;
    final key = _key(userId, messageId, index);
    final old = await box.get(key);
    if (old is Map && old['chunks'] is int) {
      for (var i = 0; i < (old['chunks'] as int); i++) {
        await box.delete('$key:chunk:$i');
      }
    }
    await box.delete(key);
    return PendingChatMediaWriter._(box, key);
  }

  Future<String> put({
    required String userId,
    required String messageId,
    required int index,
    required Uint8List bytes,
    required String name,
    required String mimeType,
  }) => putStream(
    userId: userId,
    messageId: messageId,
    index: index,
    stream: Stream<List<int>>.value(bytes),
    length: bytes.length,
    name: name,
    mimeType: mimeType,
  );

  Future<String> putXFile({
    required String userId,
    required String messageId,
    required int index,
    required XFile file,
    required String mimeType,
    int maxBytes = 30 * 1024 * 1024,
  }) async {
    final length = await file.length();
    if (length <= 0) throw StateError('Le fichier sélectionné est vide.');
    if (length > maxBytes) throw StateError('Chaque pièce jointe doit faire au maximum 30 Mo.');
    return putStream(
      userId: userId,
      messageId: messageId,
      index: index,
      stream: file.openRead(),
      length: length,
      name: file.name.isNotEmpty ? file.name : 'attachment.bin',
      mimeType: mimeType,
    );
  }

  Future<String> putStream({
    required String userId,
    required String messageId,
    required int index,
    required Stream<List<int>> stream,
    required int length,
    required String name,
    required String mimeType,
  }) async {
    if (length <= 0) throw StateError('Le fichier sélectionné est vide.');
    final normalizedMime = mimeType.toLowerCase();
    final maxBytes = normalizedMime.startsWith('image/')
        ? 15 * 1024 * 1024
        : normalizedMime.startsWith('audio/')
            ? 25 * 1024 * 1024
            : 30 * 1024 * 1024;
    if (length > maxBytes) {
      final maxMb = maxBytes ~/ (1024 * 1024);
      throw StateError('Cette pièce jointe dépasse la limite de $maxMb Mo.');
    }
    final key = _key(userId, messageId, index);
    final box = await _box;
    final old = await box.get(key);
    if (old is Map && old['chunks'] is int) {
      final count = old['chunks'] as int;
      for (var i = 0; i < count; i++) {
        await box.delete('$key:chunk:$i');
      }
    }
    var chunkCount = 0;
    var totalBytes = 0;
    try {
      await for (final incoming in stream) {
        var offset = 0;
        while (offset < incoming.length) {
          final end = (offset + chunkSize).clamp(0, incoming.length).toInt();
          final chunk = Uint8List.fromList(incoming.sublist(offset, end));
          await box.put('$key:chunk:$chunkCount', chunk);
          totalBytes += chunk.length;
          chunkCount++;
          offset = end;
        }
      }
      if (totalBytes != length || chunkCount == 0) {
        throw StateError('Le fichier local est incomplet ($totalBytes/$length octets).');
      }
      await box.put(key, <String, dynamic>{
        'chunks': chunkCount,
        'length': length,
        'name': name,
        'mime': mimeType,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      for (var i = 0; i < chunkCount; i++) {
        await box.delete('$key:chunk:$i');
      }
      rethrow;
    }
    return Uri(
      scheme: _scheme,
      host: userId,
      pathSegments: <String>[messageId, index.toString()],
    ).toString();
  }

  bool owns(String value) => isReference(value);

  static bool isReference(String value) => Uri.tryParse(value)?.scheme == _scheme;

  Future<MediaAsset?> resolve(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != _scheme ||
        uri.host.isEmpty || uri.pathSegments.length != 2) return null;
    final index = int.tryParse(uri.pathSegments[1]);
    if (index == null) return null;
    final box = await _box;
    final key = _key(uri.host, uri.pathSegments[0], index);
    final record = await box.get(key);
    if (record is! Map || record['chunks'] is! int || record['length'] is! int) {
      // Backward compatibility with an early single-blob representation.
      if (record is Map && record['bytes'] is Uint8List) {
        return MediaAsset.fromXFile(XFile.fromData(
          record['bytes'] as Uint8List,
          name: record['name']?.toString() ?? 'attachment.bin',
          mimeType: record['mime']?.toString() ?? 'application/octet-stream',
        ));
      }
      return null;
    }
    final count = record['chunks'] as int;
    final length = record['length'] as int;
    final name = record['name']?.toString() ?? 'attachment.bin';
    final mime = record['mime']?.toString() ?? 'application/octet-stream';
    return MediaAsset.fromStream(
      name: name,
      mimeType: mime,
      length: length,
      openRead: () async* {
        if (record['format'] == 'wav') yield _wavHeader(length - 44);
        yield* _readChunks(box, key, count);
      },
    );
  }

  Uint8List _wavHeader(int dataLength) {
    final header = ByteData(44);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }
    ascii(0, 'RIFF');
    header.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 44100, Endian.little);
    header.setUint32(28, 88200, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);
    return header.buffer.asUint8List();
  }

  Stream<List<int>> _readChunks(LazyBox box, String key, int count) async* {
    for (var i = 0; i < count; i++) {
      final chunk = await box.get('$key:chunk:$i');
      if (chunk is! Uint8List) throw StateError('Pièce jointe locale incomplète.');
      yield chunk;
    }
  }

  Future<void> remove(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != _scheme ||
        uri.host.isEmpty || uri.pathSegments.length != 2) return;
    final index = int.tryParse(uri.pathSegments[1]);
    if (index == null) return;
    final box = await _box;
    final key = _key(uri.host, uri.pathSegments[0], index);
    final record = await box.get(key);
    if (record is Map && record['chunks'] is int) {
      final count = record['chunks'] as int;
      for (var i = 0; i < count; i++) {
        await box.delete('$key:chunk:$i');
      }
    }
    await box.delete(key);
  }

  Future<void> removeAll(Iterable<String> values) async {
    for (final value in values) {
      if (owns(value)) await remove(value);
    }
  }

  static List<String> referencesForMessage({
    List<String>? mediaUrls,
    String? audioUrl,
  }) => <String>[
    ...?mediaUrls,
    if (audioUrl != null) audioUrl,
  ].where((value) => Uri.tryParse(value)?.scheme == _scheme).toList();
}


/// Incremental PCM writer: chunks are persisted immediately and never held as
/// one growing in-memory recording buffer.
class PendingChatMediaWriter {
  PendingChatMediaWriter._(this._box, this._key);
  final LazyBox _box;
  final String _key;
  int _chunkCount = 0;
  int _bytesWritten = 0;
  bool _closed = false;

  int get bytesWritten => _bytesWritten;
  static const int maxRecordingBytes = 25 * 1024 * 1024;

  Future<void> add(List<int> bytes) async {
    if (_closed) throw StateError('Enregistrement déjà clôturé.');
    if (_bytesWritten + bytes.length > maxRecordingBytes) {
      throw StateError('L’enregistrement vocal dépasse la limite de 25 Mo.');
    }
    var offset = 0;
    while (offset < bytes.length) {
      final end = (offset + PendingChatMediaStore.chunkSize)
          .clamp(0, bytes.length).toInt();
      final chunk = Uint8List.fromList(bytes.sublist(offset, end));
      await _box.put('$_key:chunk:$_chunkCount', chunk);
      _bytesWritten += chunk.length;
      _chunkCount++;
      offset = end;
    }
  }

  Future<String> finish({
    required String userId,
    required String messageId,
    required int index,
  }) async {
    if (_closed) throw StateError('Enregistrement déjà clôturé.');
    _closed = true;
    if (_bytesWritten <= 0 || _chunkCount == 0) {
      await discard();
      throw StateError('Aucun son n’a été capturé.');
    }
    await _box.put(_key, <String, dynamic>{
      'chunks': _chunkCount,
      'length': _bytesWritten + 44,
      'name': 'scrole_voice.wav',
      'mime': 'audio/wav',
      'format': 'wav',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return Uri(
      scheme: 'pending-media',
      host: userId,
      pathSegments: <String>[messageId, index.toString()],
    ).toString();
  }

  Future<void> discard() async {
    _closed = true;
    for (var i = 0; i < _chunkCount; i++) {
      await _box.delete('$_key:chunk:$i');
    }
    await _box.delete(_key);
  }
}
