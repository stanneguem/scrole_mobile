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
      openRead: () => _readChunks(box, key, count),
    );
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
