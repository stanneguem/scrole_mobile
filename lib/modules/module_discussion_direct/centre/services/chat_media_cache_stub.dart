import 'dart:html' as html;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// IndexedDB-backed browser media cache. Hive's Web backend persists this box
/// in IndexedDB; object URLs are recreated from stored bytes after reload.
class ChatMediaCachePlatform {
  ChatMediaCachePlatform();

  static const int _maxBytes = 120 * 1024 * 1024;
  static const int _maxEntryBytes = 30 * 1024 * 1024;
  static const Duration _maxAge = Duration(days: 14);
  static const String _boxName = 'scrole_media_blobs_v1';
  static const String _prefix = 'blob:';
  static final Map<String, String> _objectUrls = <String, String>{};
  static Box? _box;
  static bool _hiveInitialized = false;

  static bool _isHttpUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');
  static bool _isR2ObjectKey(String value) =>
      value.startsWith('messages/') || value.startsWith('stories/') ||
      value.startsWith('private/') || value.startsWith('bug-reports/') ||
      value.startsWith('salon-messages/');

  Future<Box> _openBox() async {
    if (!_hiveInitialized) {
      await Hive.initFlutter();
      _hiveInitialized = true;
    }
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    _box = await Hive.openBox(_boxName);
    return _box!;
  }

  String _cacheKey(String remoteUrl) {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    return sha256.convert('$uid|$remoteUrl'.codeUnits).toString();
  }

  Future<String?> localPathFor(String remoteUrl) async {
    if (remoteUrl.isEmpty) return null;
    try {
      final box = await _openBox();
      final key = _cacheKey(remoteUrl);
      final raw = box.get('$_prefix$key');
      final meta = box.get('meta:$key');
      if (raw is! Uint8List || meta is! Map) return null;
      final savedAt = DateTime.tryParse(meta['saved_at']?.toString() ?? '');
      if (savedAt == null || DateTime.now().difference(savedAt) > _maxAge) {
        await _deleteEntry(box, key);
        return null;
      }
      await box.put('meta:$key', <String, dynamic>{
        ...Map<String, dynamic>.from(meta),
        'last_access': DateTime.now().millisecondsSinceEpoch,
      });
      return _objectUrl(key, raw);
    } catch (error) {
      debugPrint('[WebMediaCache] IndexedDB read failed: $error');
      return null;
    }
  }

  String _objectUrl(String key, Uint8List bytes) {
    final existing = _objectUrls[key];
    if (existing != null) return existing;
    final blob = html.Blob(<Object>[bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    _objectUrls[key] = url;
    return url;
  }

  Future<String?> cacheBytes(String remoteUrl, Uint8List bytes) async {
    if (remoteUrl.isEmpty || bytes.isEmpty || bytes.lengthInBytes > _maxEntryBytes) {
      return null;
    }
    try {
      final box = await _openBox();
      final key = _cacheKey(remoteUrl);
      await box.put('$_prefix$key', bytes);
      await box.put('meta:$key', <String, dynamic>{
        'size': bytes.lengthInBytes,
        'owner_id': Supabase.instance.client.auth.currentUser?.id ?? 'anonymous',
        'saved_at': DateTime.now().toIso8601String(),
        'last_access': DateTime.now().millisecondsSinceEpoch,
      });
      await _enforceLimit(box);
      return _objectUrl(key, bytes);
    } catch (error) {
      debugPrint('[WebMediaCache] IndexedDB write failed: $error');
      return null;
    }
  }

  Future<String?> saveLocalToSandbox(String storagePath, String localSourcePath) async => null;
  Future<bool> saveToGallery({required String sourcePath, required String fileName}) async => false;

  Future<String?> resolveLocalPath(String ref) async {
    if (ref.isEmpty) return null;
    if (_isHttpUrl(ref)) {
      final cached = await localPathFor(ref);
      if (cached != null) return cached;
    }
    return cacheRemote(ref);
  }

  Future<String?> cacheRemote(String remoteUrl) async {
    if (remoteUrl.isEmpty) return null;
    final cached = await localPathFor(remoteUrl);
    if (cached != null) return cached;
    try {
      final downloadUrl = await _resolveDownloadUrl(remoteUrl);
      if (downloadUrl == null) return null;
      final client = http.Client();
      try {
        final request = await client.send(http.Request('GET', Uri.parse(downloadUrl)));
        if (request.statusCode < 200 || request.statusCode >= 300) return null;
        final declaredLength = request.contentLength;
        if (declaredLength != null && declaredLength > _maxEntryBytes) return null;
        final builder = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk in request.stream) {
          received += chunk.length;
          if (received > _maxEntryBytes) return null;
          builder.add(chunk);
        }
        return cacheBytes(remoteUrl, builder.takeBytes());
      } finally {
        client.close();
      }
    } catch (error) {
      debugPrint('[WebMediaCache] Download failed: $error');
      return null;
    }
  }

  Future<String?> _resolveDownloadUrl(String remoteUrl) async {
    if (_isHttpUrl(remoteUrl) && !remoteUrl.contains('/storage/v1/object/')) {
      return remoteUrl;
    }
    final client = Supabase.instance.client;
    if (_isR2ObjectKey(remoteUrl)) {
      final response = await client.functions.invoke(
        'r2-media-upload',
        body: {'action': 'create-download-url', 'object_key': remoteUrl},
      );
      if (response.status < 200 || response.status >= 300 || response.data is! Map) {
        return null;
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      final url = data['url'] as String?;
      return url == null || url.isEmpty ? null : url;
    }
    return client.storage.from('chat-media').createSignedUrl(remoteUrl, 300);
  }

  Future<void> _deleteEntry(Box box, String key) async {
    await box.delete('$_prefix$key');
    await box.delete('meta:$key');
    final objectUrl = _objectUrls.remove(key);
    if (objectUrl != null) html.Url.revokeObjectUrl(objectUrl);
  }

  Future<void> _enforceLimit(Box box) async {
    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    var total = 0;
    for (final key in box.keys.whereType<String>()) {
      if (!key.startsWith('meta:')) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      final meta = Map<String, dynamic>.from(raw);
      final id = key.substring(5);
      total += (meta['size'] as num?)?.toInt() ?? 0;
      entries.add(MapEntry(id, meta));
    }
    entries.sort((a, b) =>
        ((a.value['last_access'] as num?)?.toInt() ?? 0)
            .compareTo((b.value['last_access'] as num?)?.toInt() ?? 0));
    for (final entry in entries) {
      if (total <= _maxBytes) break;
      total -= (entry.value['size'] as num?)?.toInt() ?? 0;
      await _deleteEntry(box, entry.key);
    }
  }

  Future<void> clearForUser(String userId) async {
    if (userId.isEmpty) return;
    final box = await _openBox();
    for (final key in box.keys.whereType<String>().toList()) {
      if (!key.startsWith('meta:')) continue;
      final raw = box.get(key);
      if (raw is Map && raw['owner_id']?.toString() == userId) {
        await _deleteEntry(box, key.substring(5));
      }
    }
  }

  Future<void> removeLocal(String remoteUrl) async {
    if (remoteUrl.isEmpty) return;
    final box = await _openBox();
    await _deleteEntry(box, _cacheKey(remoteUrl));
  }

  Future<void> purgeOldFiles({int days = 14}) async {
    try {
      final box = await _openBox();
      final threshold = DateTime.now().subtract(Duration(days: days));
      for (final key in box.keys.whereType<String>().toList()) {
        if (!key.startsWith('meta:')) continue;
        final raw = box.get(key);
        if (raw is! Map) continue;
        final savedAt = DateTime.tryParse(raw['saved_at']?.toString() ?? '');
        if (savedAt == null || savedAt.isBefore(threshold)) {
          await _deleteEntry(box, key.substring(5));
        }
      }
    } catch (error) {
      debugPrint('[WebMediaCache] Purge failed: $error');
    }
  }
}
