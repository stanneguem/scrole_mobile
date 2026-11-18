import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../../../../app/media/media_asset.dart';
import '../../../../app/storage/contracts/cache_store.dart';

/// Persists outgoing attachment bytes outside SQLite. The existing Hive cache
/// backend uses browser storage on Web; SQLite/outbox rows keep only a URI.
class PendingChatMediaStore {
  PendingChatMediaStore(this._cache);

  final CacheStore _cache;
  static const _prefix = 'pending_chat_media:';
  static const _scheme = 'pending-media';

  String _key(String userId, String messageId, int index) =>
      '$_prefix$userId:$messageId:$index';

  Future<String> put({
    required String userId,
    required String messageId,
    required int index,
    required Uint8List bytes,
    required String name,
    required String mimeType,
  }) async {
    if (bytes.isEmpty) throw StateError('Le fichier sélectionné est vide.');
    final key = _key(userId, messageId, index);
    await _cache.set(key, <String, dynamic>{
      'bytes': bytes,
      'name': name,
      'mime': mimeType,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final saved = _cache.get<Map>(key);
    if (saved == null || saved['bytes'] is! Uint8List) {
      throw StateError('Impossible de conserver la pièce jointe localement.');
    }
    return Uri(
      scheme: _scheme,
      host: userId,
      pathSegments: <String>[messageId, index.toString()],
    ).toString();
  }

  bool owns(String value) => Uri.tryParse(value)?.scheme == _scheme;

  Future<MediaAsset?> resolve(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != _scheme ||
        uri.host.isEmpty || uri.pathSegments.length != 2) return null;
    final index = int.tryParse(uri.pathSegments[1]);
    if (index == null) return null;
    final record = _cache.get<Map>(_key(uri.host, uri.pathSegments[0], index));
    if (record == null || record['bytes'] is! Uint8List) return null;
    return MediaAsset.fromXFile(XFile.fromData(
      record['bytes'] as Uint8List,
      name: record['name']?.toString() ?? 'attachment.bin',
      mimeType: record['mime']?.toString() ?? 'application/octet-stream',
    ));
  }

  Future<void> remove(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != _scheme ||
        uri.host.isEmpty || uri.pathSegments.length != 2) return;
    final index = int.tryParse(uri.pathSegments[1]);
    if (index == null) return;
    await _cache.remove(_key(uri.host, uri.pathSegments[0], index));
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
