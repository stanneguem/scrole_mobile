import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/module_discussion_direct/centre/services/chat_media_cache.dart';
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
  });

  static Future<void> clearPrivateMediaCache(String objectKey) async {
    await ChatMediaCache.instance.removeLocal(objectKey);
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return _error();
    if (_isRemote(imageUrl)) return _networkImage(imageUrl);

    if (_isR2Key(imageUrl)) {
      return FutureBuilder<String?>(
        future: _resolveR2Url(imageUrl),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _error();
          if (!snapshot.hasData) return _placeholder();
          return _networkImage(snapshot.data!);
        },
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
        return Image(image: provider, width: width, height: height, fit: fit);
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
