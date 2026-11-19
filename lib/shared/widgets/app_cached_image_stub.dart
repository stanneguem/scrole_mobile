import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/module_discussion_direct/centre/services/chat_media_cache.dart';
import '../../app/local_storage/fast/fast_cache_service.dart';
import 'shimmer.dart';

class AppCachedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool progressive;
  final int? lowResolutionWidth;
  final int? highResolutionWidth;
  final int imageQuality;
  final VoidCallback? onImageLoaded;
  final DateTime? cacheUntil;
  /// Persist this image across widget disposal and app navigation (avatars).
  final bool cacheInPersistentStore;

  const AppCachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.progressive = false,
    this.lowResolutionWidth,
    this.highResolutionWidth,
    this.imageQuality = 80,
    this.onImageLoaded,
    this.cacheUntil,
    this.cacheInPersistentStore = false,
  });

  static Future<void> clearPrivateMediaCache(String objectKey) async {
    await ChatMediaCache.instance.removeLocal(objectKey);
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return _error();
    // Match the native CachedNetworkImage contract on Web: every remote
    // image (feed media, thumbnails, avatars, suggestions and logos) is
    // persisted independently from the lifetime of its widget/card.
    if (_isRemote(imageUrl) || _isR2Key(imageUrl) || cacheInPersistentStore) {
      return _PersistentCachedImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        borderRadius: borderRadius,
        placeholder: placeholder,
        errorWidget: errorWidget,
        onImageLoaded: onImageLoaded,
      );
    }

    // Browser cannot read native filesystem paths. Such paths are not valid
    // Web media references; callers must provide an XFile/blob/remote URL.
    return errorWidget ?? _error();
  }

  bool _isRemote(String value) =>
      value.startsWith('https://') || value.startsWith('http://');

  bool _isR2Key(String value) => const [
    'private/', 'messages/', 'stories/', 'bug-reports/', 'comments/',
    'communities/', 'posts/', 'profiles/', 'events/',
  ].any(value.startsWith);

  Future<String?> _resolveR2Url(String key) async {
    final response = await Supabase.instance.client.functions.invoke(
      'r2-media-upload',
      body: {'action': 'create-download-url', 'object_key': key},
    );
    if (response.status < 200 || response.status >= 300 || response.data is! Map) {
      return null;
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final url = data['url']?.toString();
    return url == null || url.isEmpty ? null : url;
  }

  Widget _networkImage(String url) => ClipRRect(
    borderRadius: borderRadius ?? BorderRadius.zero,
    child: CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: highResolutionWidth,
      placeholder: (_, __) => _placeholder(),
      imageBuilder: (context, provider) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onImageLoaded?.call());
        return Image(
          image: provider,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => errorWidget ?? _error(),
        );
      },
      errorWidget: (_, __, ___) => errorWidget ?? _error(),
    ),
  );

  Widget _placeholder() => placeholder ?? SkeletonShimmer(
    width: width ?? double.infinity,
    height: height ?? double.infinity,
    borderRadius: borderRadius?.topLeft.x ?? 0,
  );

  Widget _error() => errorWidget ?? Container(
    width: width,
    height: height,
    color: Colors.grey[200],
    child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
  );
}


/// Session-wide memory + Hive cache for profile avatars. The cache key is
/// derived from the stable source reference, so signed URL rotation does not
/// force another download for private R2 object keys.
class _PersistentCachedImage extends StatefulWidget {
  const _PersistentCachedImage({
    required this.imageUrl,
    this.width,
    this.height,
    required this.fit,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.onImageLoaded,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final VoidCallback? onImageLoaded;

  @override
  State<_PersistentCachedImage> createState() => _PersistentCachedImageState();
}

class _PersistentCachedImageState extends State<_PersistentCachedImage> {
  static final Map<String, Uint8List> _memory = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _inFlight = {};
  static const Duration _refreshAfter = Duration(days: 30);
  // A normal feed page can contain hundreds of distinct image variants.
  // Keep a larger persistent working set than the old avatar-only cache.
  static const int _maxPersistentEntries = 500;
  static const int _maxPersistentBytes = 128 * 1024 * 1024;
  static const int _maxSingleImageBytes = 12 * 1024 * 1024;

  Uint8List? _bytes;
  bool _failed = false;

  String get _cacheKey {
    final uri = Uri.tryParse(widget.imageUrl);
    // Signed CDN URLs rotate their query token. Cache the stable object path,
    // not the expiring authorization query string.
    final identity = uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
        ? uri.replace(
            queryParameters: Map<String, String>.from(uri.queryParameters)
              ..removeWhere((key, _) => const {
                'token', 'signature', 'sig', 'expires', 'expiration',
                'x-amz-signature', 'x-amz-credential', 'x-amz-date',
                'x-amz-security-token',
              }.contains(key.toLowerCase())),
            fragment: '',
          ).toString()
        : widget.imageUrl;
    return 'web_image_bytes_${sha256.convert(utf8.encode(identity))}';
  }

  @override
  void initState() {
    super.initState();
    _restoreAndLoad();
  }

  @override
  void didUpdateWidget(covariant _PersistentCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _bytes = null;
      _failed = false;
      _restoreAndLoad();
    }
  }

  Future<void> _restoreAndLoad() async {
    final key = _cacheKey;
    final inMemory = _memory[key];
    if (inMemory != null && mounted) {
      // A memory hit is still a cache access: refresh its persistent LRU
      // timestamp, otherwise frequently reused avatars can be evicted as old.
      final cache = Get.isRegistered<FastCacheService>()
          ? Get.find<FastCacheService>()
          : null;
      if (cache != null && cache.isReady) {
        final stored = cache.get<dynamic>(key);
        if (stored is Map && stored['bytes'] is Uint8List) {
          unawaited(cache.set(key, {
            'bytes': stored['bytes'],
            'saved_at': stored['saved_at'] ?? DateTime.now().toIso8601String(),
            'last_accessed': DateTime.now().millisecondsSinceEpoch,
          }));
        }
      }
      setState(() => _bytes = inMemory);
      return;
    }

    final cache = Get.isRegistered<FastCacheService>()
        ? Get.find<FastCacheService>()
        : null;
    final stored = cache != null && cache.isReady
        ? cache.get<dynamic>(key)
        : null;
    if (stored is Map && stored['bytes'] is Uint8List) {
      final bytes = stored['bytes'] as Uint8List;
      _memory[key] = bytes;
      if (mounted) setState(() => _bytes = bytes);
      final savedAt = DateTime.tryParse(stored['saved_at']?.toString() ?? '');
      if (savedAt != null && DateTime.now().difference(savedAt) < _refreshAfter) {
        await cache?.set(key, {
          'bytes': bytes,
          'saved_at': savedAt.toIso8601String(),
          'last_accessed': DateTime.now().millisecondsSinceEpoch,
        });
        return;
      }
    }

    final bytes = await _download();
    if (bytes != null && bytes.isNotEmpty) {
      _memory[key] = bytes;
      if (cache != null && cache.isReady) {
        await cache.set(key, {
          'bytes': bytes,
          'saved_at': DateTime.now().toIso8601String(),
          'last_accessed': DateTime.now().millisecondsSinceEpoch,
        });
        await _trimPersistentCache(cache);
      }
      if (mounted) setState(() {
        _bytes = bytes;
        _failed = false;
      });
    } else if (_bytes == null && mounted) {
      setState(() => _failed = true);
    }
  }

  Future<void> _trimPersistentCache(FastCacheService cache) async {
    try {
      final entries = <({String key, int bytes, int accessed})>[];
      var totalBytes = 0;
      for (final rawKey in cache.box.keys) {
        if (rawKey is! String || !rawKey.startsWith('web_image_bytes_')) continue;
        final value = cache.get<dynamic>(rawKey);
        if (value is! Map || value['bytes'] is! Uint8List) continue;
        final data = value['bytes'] as Uint8List;
        final accessed = (value['last_accessed'] as num?)?.toInt() ??
            DateTime.tryParse(value['saved_at']?.toString() ?? '')
                ?.millisecondsSinceEpoch ?? 0;
        entries.add((key: rawKey, bytes: data.lengthInBytes, accessed: accessed));
        totalBytes += data.lengthInBytes;
      }
      entries.sort((a, b) => a.accessed.compareTo(b.accessed));
      while (entries.length > _maxPersistentEntries || totalBytes > _maxPersistentBytes) {
        if (entries.isEmpty) break;
        final oldest = entries.removeAt(0);
        await cache.remove(oldest.key);
        totalBytes -= oldest.bytes;
        _memory.remove(oldest.key);
      }
    } catch (e) {
      debugPrint('[IMAGE_CACHE] eviction failed: $e');
    }
  }

  Future<Uint8List?> _download() {
    final key = _cacheKey;
    return _inFlight.putIfAbsent(key, () async {
      try {
        String url = widget.imageUrl;
        if (!_isHttpUrl(url)) {
          if (!const ['private/', 'messages/', 'stories/', 'bug-reports/',
              'comments/', 'communities/', 'posts/', 'profiles/', 'events/']
              .any(url.startsWith)) return null;
          final response = await Supabase.instance.client.functions.invoke(
            'r2-media-upload',
            body: {'action': 'create-download-url', 'object_key': url},
          );
          if (response.status < 200 || response.status >= 300 || response.data is! Map) return null;
          url = Map<String, dynamic>.from(response.data as Map)['url']?.toString() ?? '';
        }
        if (!_isHttpUrl(url)) return null;
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
        if (response.statusCode < 200 || response.statusCode >= 300 ||
            response.bodyBytes.isEmpty || response.bodyBytes.length > _maxSingleImageBytes) return null;
        final contentType = (response.headers['content-type'] ?? '').toLowerCase();
        if (contentType.startsWith('video/') || contentType.startsWith('audio/')) {
          debugPrint('[IMAGE_CACHE] Refusing non-image response contentType=$contentType url=$url');
          return null;
        }
        if (!_looksLikeImage(response.bodyBytes)) {
          debugPrint('[IMAGE_CACHE] Refusing payload that is not a recognized image url=$url');
          return null;
        }
        return Uint8List.fromList(response.bodyBytes);
      } catch (e) {
        debugPrint('[AVATAR_CACHE] download failed: $e');
        return null;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  bool _isHttpUrl(String value) => value.startsWith('https://') || value.startsWith('http://');

  bool _looksLikeImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final png = bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4e && bytes[3] == 0x47;
    final gif = bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
    final webp = bytes[0] == 0x52 && bytes[1] == 0x49 &&
        bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 &&
        bytes[10] == 0x42 && bytes[11] == 0x50;
    final avif = bytes.length >= 12 && bytes[4] == 0x66 &&
        bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 &&
        String.fromCharCodes(bytes.sublist(8, 12)).startsWith('avif');
    return jpeg || png || gif || webp || avif;
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (_bytes != null) {
      child = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => widget.errorWidget ?? _fallback(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onImageLoaded?.call());
    } else if (_failed) {
      child = widget.errorWidget ?? _fallback();
    } else {
      child = widget.placeholder ?? SkeletonShimmer(
        width: widget.width ?? double.infinity,
        height: widget.height ?? double.infinity,
        borderRadius: widget.borderRadius?.topLeft.x ?? 0,
      );
    }
    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: child,
    );
  }

  Widget _fallback() => Container(
    width: widget.width,
    height: widget.height,
    color: Colors.grey[200],
    child: const Icon(Icons.person_rounded, color: Colors.grey),
  );
}

Future<void> showProfileImageViewer(BuildContext context, String imageUrl) {
  if (imageUrl.trim().isEmpty) return Future<void>.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close profile photo',
    barrierColor: Colors.black.withValues(alpha: 0.96),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) => Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: AppCachedImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    errorWidget: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.5),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}
