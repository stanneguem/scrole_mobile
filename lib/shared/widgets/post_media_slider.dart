import 'package:flutter/material.dart';
import '../../shared/models/post_media.dart';
import '../../shared/widgets/app_cached_image.dart';
import 'media_full_screen_page.dart';

class PostMediaSlider extends StatefulWidget {
  final List<PostMedia> media;
  final String? heroTagPrefix;
  final int likesCount;
  final int dislikesCount;
  final int viewsCount;
  final int commentsCount;
  final int sharesCount;

  const PostMediaSlider({
    super.key,
    required this.media,
    this.heroTagPrefix,
    this.likesCount = 0,
    this.dislikesCount = 0,
    this.viewsCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
  });

  @override
  State<PostMediaSlider> createState() => _PostMediaSliderState();
}

class _PostMediaSliderState extends State<PostMediaSlider> {
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _computedPrefix => widget.heroTagPrefix ?? 'media_${identityHashCode(widget)}';

  String _getHeroTag(int index) {
    final url = (index < widget.media.length) ? (widget.media[index].url ?? '') : '';
    return '${_computedPrefix}_${url}_$index';
  }

  void _openFullScreen(BuildContext context, int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.95),
        pageBuilder: (context, animation, secondaryAnimation) => MediaFullScreenPage(
          media: widget.media,
          heroTagPrefix: _computedPrefix,
          initialIndex: index,
          likesCount: widget.likesCount,
          dislikesCount: widget.dislikesCount,
          viewsCount: widget.viewsCount,
          commentsCount: widget.commentsCount,
          sharesCount: widget.sharesCount,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.isEmpty) return const SizedBox.shrink();

    final len = widget.media.length;

    // Mixed-media posts use one consistent horizontal viewer so video items
    // render as playable tiles instead of being passed to the image cache.
    if (widget.media.any((item) => item.isVideo)) {
      return SizedBox(
        height: 280,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: len,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                final item = widget.media[index];
                return GestureDetector(
                  onTap: () => _openFullScreen(context, index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: item.isVideo
                        ? Container(
                            width: double.infinity,
                            color: Colors.black,
                            child: const Center(
                              child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 72),
                            ),
                          )
                        : AppCachedImage(
                            imageUrl: item.url,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 280,
                          ),
                  ),
                );
              },
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '${_currentIndex + 1}/$len',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // --- Cas 1 : Une seule image ---
    if (len == 1) {
      return GestureDetector(
        onTap: () => _openFullScreen(context, 0),
        child: Hero(
          tag: _getHeroTag(0),
          child: Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.black12,
            ),
            clipBehavior: Clip.antiAlias,
            child: AppCachedImage(
              imageUrl: widget.media[0].url ?? '',
              fit: BoxFit.cover,
              progressive: true,
              lowResolutionWidth: 400,
              highResolutionWidth: 1080,
            ),
          ),
        ),
      );
    }

    // --- Cas 2 : Deux images (50% / 50% côte à côte, ratio 1:1) ---
    if (len == 2) {
      return SizedBox(
        height: 220,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _openFullScreen(context, 0),
                child: Hero(
                  tag: _getHeroTag(0),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                    child: AppCachedImage(
                      imageUrl: widget.media[0].url ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 220,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: GestureDetector(
                onTap: () => _openFullScreen(context, 1),
                child: Hero(
                  tag: _getHeroTag(1),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
                    child: AppCachedImage(
                      imageUrl: widget.media[1].url ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 220,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // --- Cas 3 : Trois images (asymétrique : 50% gauche, 2x 25% empilées droite) ---
    if (len == 3) {
      return SizedBox(
        height: 260,
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () => _openFullScreen(context, 0),
                child: Hero(
                  tag: _getHeroTag(0),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                    child: AppCachedImage(
                      imageUrl: widget.media[0].url ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openFullScreen(context, 1),
                      child: Hero(
                        tag: _getHeroTag(1),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(topRight: Radius.circular(14)),
                          child: AppCachedImage(
                            imageUrl: widget.media[1].url ?? '',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openFullScreen(context, 2),
                      child: Hero(
                        tag: _getHeroTag(2),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(bottomRight: Radius.circular(14)),
                          child: AppCachedImage(
                            imageUrl: widget.media[2].url ?? '',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // --- Cas 4 : Plus de trois images (> 3) -> Slider horizontal avec indicateur 1/N ---
    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: len,
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _openFullScreen(context, index),
                child: Hero(
                  tag: _getHeroTag(index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AppCachedImage(
                      imageUrl: widget.media[index].url ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_currentIndex + 1} / $len',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
