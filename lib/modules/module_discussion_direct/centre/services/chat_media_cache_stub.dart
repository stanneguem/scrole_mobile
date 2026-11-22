import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:js_util' as js_util;

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
  static const String _boxName = 'scrole_media_blobs_v1';
  static const String _prefix = 'blob:';
  static final Map<String, String> _objectUrls = <String, String>{};
  static Box? _box;
  static bool _hiveInitialized = false;
  static Future<Box>? _openingBox;
  static Future<void>? _persistenceRequest;

  static bool _isHttpUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');
  static bool _isR2ObjectKey(String value) =>
      value.startsWith('messages/') || value.startsWith('stories/') ||
      value.startsWith('private/') || value.startsWith('bug-reports/') ||
      value.startsWith('salon-messages/');

  Future<void> _requestPersistentStorage() async {
    // Browser storage is best-effort by default. Ask the browser to protect
    // IndexedDB from automatic eviction: delivered chat objects are deleted
    // from R2 after this client has durably cached them.
    _persistenceRequest ??= () async {
      try {
        final storage = js_util.getProperty(html.window.navigator, 'storage');
        if (storage == null) return;
        final persisted = await js_util.promiseToFuture<bool>(
          js_util.callMethod(storage, 'persisted', <Object>[]),
        );
        if (!persisted) {
          await js_util.promiseToFuture<bool>(
            js_util.callMethod(storage, 'persist', <Object>[]),
          );
        }
      } catch (error) {
        debugPrint('[WebMediaCache] Persistent storage request unavailable: $error');
      }
    }();
    await _persistenceRequest;
  }

  Future<Box> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final opening = _openingBox;
    if (opening != null) return opening;
    final future = () async {
      if (!_hiveInitialized) {
        await Hive.initFlutter();
        _hiveInitialized = true;
      }
      await _requestPersistentStorage();
      _box = await Hive.openBox(_boxName);
      return _box!;
    }();
    _openingBox = future;
    try {
      return await future;
    } finally {
      _openingBox = null;
    }
  }

  String _stableMediaRef(String remoteUrl) {
    final parsed = Uri.tryParse(remoteUrl);
    if (parsed != null &&
        _isHttpUrl(remoteUrl) &&
        parsed.host.contains('.r2.cloudflarestorage.com')) {
      final objectKey = Uri.decodeComponent(
        parsed.path.replaceFirst(RegExp(r'^/+'), ''),
      );
      if (_isR2ObjectKey(objectKey)) return objectKey;
    }
    if (parsed != null && _isHttpUrl(remoteUrl)) {
      return parsed.replace(query: '', fragment: '').toString();
    }
    return remoteUrl;
  }

  String? _messageObjectKey(String remoteUrl) {
    final stableRef = _stableMediaRef(remoteUrl);
    return stableRef.startsWith('messages/') ? stableRef : null;
  }

  String _cacheKey(String remoteUrl) {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    // Use the R2 object key as the identity, not its temporary signed URL.
    // This also lets old messages resolve the same IndexedDB entry when the
    // message payload stores a key but an earlier render used a signed URL.
    final stableRef = _stableMediaRef(remoteUrl);
    return sha256.convert('$uid|$stableRef'.codeUnits).toString();
  }

  Future<String?> localPathFor(String remoteUrl) async {
    if (remoteUrl.isEmpty) return null;
    try {
      final box = await _openBox();
      final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
      final canonicalKey = _cacheKey(remoteUrl);
      final candidates = <String>[canonicalKey];

      // Read entries written by earlier versions, which keyed media by the
      // signed URL (with or without its expiring query parameters).
      final parsed = Uri.tryParse(remoteUrl);
      if (parsed != null && _isHttpUrl(remoteUrl)) {
        final stableUrl = parsed.replace(query: '', fragment: '').toString();
        final legacyStable = sha256.convert('$uid|$stableUrl'.codeUnits).toString();
        final legacyRaw = sha256.convert('$uid|$remoteUrl'.codeUnits).toString();
        if (!candidates.contains(legacyStable)) candidates.add(legacyStable);
        if (!candidates.contains(legacyRaw)) candidates.add(legacyRaw);
      }

      for (final key in candidates) {
        final raw = box.get('$_prefix$key');
        final meta = box.get('meta:$key');
        if (raw is! Uint8List || meta is! Map) continue;
        final updatedMeta = <String, dynamic>{
          ...Map<String, dynamic>.from(meta),
          'last_access': DateTime.now().millisecondsSinceEpoch,
        };
        await box.put('meta:$key', updatedMeta);
        if (key != canonicalKey) {
          await box.put('$_prefix$canonicalKey', raw);
          await box.put('meta:$canonicalKey', updatedMeta);
          await _deleteEntry(box, key);
        }
        return _objectUrl(canonicalKey, raw);
      }
      return null;
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

    // Display fallback for private direct-message media: if the durable
    // IndexedDB download fails (for example a transient proxy/CORS failure),
    // still render through a short-lived authenticated R2 URL. This URL is
    // display-only; the delivery pipeline uses cacheRemote() and never treats
    // this fallback as a durable local copy.
    final messageKey = _messageObjectKey(ref);
    if (messageKey != null) {
      final cached = await localPathFor(ref);
      if (cached != null) return cached;
      final downloaded = await cacheRemote(ref);
      if (downloaded != null) return downloaded;
      try {
        final fallbackUrl = await _createR2DownloadUrl(messageKey);
        if (fallbackUrl != null) {
          debugPrint('[WebMediaCache] Using temporary display URL after local cache failure');
        }
        return fallbackUrl;
      } catch (error) {
        debugPrint('[WebMediaCache] Temporary display URL fallback failed: $error');
        return null;
      }
    }

    if (_isHttpUrl(ref)) {
      final cached = await localPathFor(ref);
      if (cached != null) return cached;
    }
    return cacheRemote(ref);
  }

  Future<Uint8List?> _downloadPrivateMessageMedia(String objectKey) async {
    try {
      final client = Supabase.instance.client;
      final token = client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) return null;

      // Use the authenticated Supabase Edge Function as a same-origin-style
      // proxy: browsers may block direct reads from private R2 due to CORS.
      final endpoint = client.rest.url.replaceFirst(
        '/rest/v1',
        '/functions/v1/r2-media-upload',
      );
      final apiKey = client.rest.headers['apikey'];
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('[WebMediaCache] Supabase anon key unavailable for media proxy');
        return null;
      }
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $token',
          'apikey': apiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'action': 'download-message-media',
          'object_key': objectKey,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = utf8.decode(
          response.bodyBytes.take(500).toList(),
          allowMalformed: true,
        );
        debugPrint(
          '[WebMediaCache] Private media proxy returned ${response.statusCode}: $errorBody',
        );
        return null;
      }
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.lengthInBytes > _maxEntryBytes) {
        return null;
      }
      return response.bodyBytes;
    } catch (error) {
      debugPrint('[WebMediaCache] Private media proxy failed: $error');
      return null;
    }
  }

  Future<String?> cacheRemote(String remoteUrl) async {
    if (remoteUrl.isEmpty) return null;
    final cached = await localPathFor(remoteUrl);
    if (cached != null) return cached;
    try {
      final messageObjectKey = _messageObjectKey(remoteUrl);
      if (messageObjectKey != null) {
        final bytes = await _downloadPrivateMessageMedia(messageObjectKey);
        if (bytes == null) return null;
        return cacheBytes(remoteUrl, bytes);
      }

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

  Future<String?> _createR2DownloadUrl(String objectKey) async {
    final response = await Supabase.instance.client.functions.invoke(
      'r2-media-upload',
      body: {'action': 'create-download-url', 'object_key': objectKey},
    );
    if (response.status < 200 || response.status >= 300 || response.data is! Map) {
      return null;
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final url = data['url'] as String?;
    return url == null || url.isEmpty ? null : url;
  }

  Future<String?> _resolveDownloadUrl(String remoteUrl) async {
    final parsed = Uri.tryParse(remoteUrl);
    if (parsed != null && parsed.scheme == 'pending-media') {
      // This reference is private to the sender's local IndexedDB store; it
      // must never be signed as a Supabase Storage object for a recipient.
      return null;
    }
    if (parsed != null &&
        _isHttpUrl(remoteUrl) &&
        parsed.host.contains('.r2.cloudflarestorage.com')) {
      final objectKey = Uri.decodeComponent(parsed.path.replaceFirst(RegExp(r'^/+'), ''));
      if (_isR2ObjectKey(objectKey)) {
        // Never reuse an expired presigned R2 URL. Ask our Edge Function for
        // a fresh URL using the stable object key.
        return _createR2DownloadUrl(objectKey);
      }
    }
    if (_isHttpUrl(remoteUrl) && !remoteUrl.contains('/storage/v1/object/')) {
      return remoteUrl;
    }
    if (_isR2ObjectKey(remoteUrl)) {
      return _createR2DownloadUrl(remoteUrl);
    }
    return Supabase.instance.client.storage.from('chat-media').createSignedUrl(remoteUrl, 300);
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
    // Message attachments can remain part of a conversation for years.
    // Age-based deletion made old messages lose their local preview. Keep
    // them until the bounded LRU policy needs space; after delivery cleanup,
    // the browser's persistent copy may be the only remaining media copy.
    try {
      final box = await _openBox();
      await _enforceLimit(box);
    } catch (error) {
      debugPrint('[WebMediaCache] Cache maintenance failed: $error');
    }
  }
}
