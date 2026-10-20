import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../modules/module_discussion_direct/interne/widgets/chat_cached_media.dart';
import '../../modules/module_discussion_direct/centre/services/chat_media_cache.dart';
import '../models/post_media.dart';
import '../utils/number_formatter.dart';
import 'app_cached_image.dart';

class MediaFullScreenPage extends StatefulWidget {
  final List<PostMedia>? media;
  final List<String>? mediaUrls;
  final String? heroTagPrefix;
  final int initialIndex;
  final int likesCount;
  final int dislikesCount;
  final int viewsCount;
  final int commentsCount;
  final int sharesCount;

  const MediaFullScreenPage({
    super.key,
    this.media,
    this.mediaUrls,
    this.heroTagPrefix,
    this.initialIndex = 0,
    this.likesCount = 0,
    this.dislikesCount = 0,
    this.viewsCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
  });

  @override
  State<MediaFullScreenPage> createState() => _MediaFullScreenPageState();
}

class _MediaFullScreenPageState extends State<MediaFullScreenPage> with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late int _currentPage;
  late final List<PostMedia> _items;

  double _dragOffsetY = 0.0;
  double _bgOpacity = 1.0;
  bool _isDragging = false;

  late int _likesCount;
  late int _dislikesCount;
  late int _sharesCount;
  late int _viewsCount;
  late int _commentsCount;

  @override
  void initState() {
    super.initState();
    if (widget.media != null && widget.media!.isNotEmpty) {
      _items = widget.media!;
    } else if (widget.mediaUrls != null && widget.mediaUrls!.isNotEmpty) {
      _items = widget.mediaUrls!.map((url) => PostMedia(type: 'photo', url: url)).toList();
    } else {
      _items = [];
    }
    _currentPage = widget.initialIndex.clamp(0, _items.isNotEmpty ? _items.length - 1 : 0);
    _pageController = PageController(initialPage: _currentPage);

    _likesCount = widget.likesCount;
    _dislikesCount = widget.dislikesCount;
    _sharesCount = widget.sharesCount > 0 ? widget.sharesCount : 0;
    _viewsCount = widget.viewsCount;
    _commentsCount = widget.commentsCount;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  final Set<int> _likedIndices = {};
  final Set<int> _dislikedIndices = {};

  Future<void> _onShare() async {
    if (_items.isEmpty) return;
    final url = _items[_currentPage].url;
    if (url.isEmpty) return;

    setState(() => _sharesCount++);

    try {
      final isNetwork = url.startsWith('http://') || url.startsWith('https://');
      if (isNetwork) {
        final file = await DefaultCacheManager().getSingleFile(url);
        await Share.shareXFiles([XFile(file.path)], text: 'Média Scrole');
      } else {
        await Share.shareXFiles([XFile(url)], text: 'Média Scrole');
      }
    } catch (e) {
      Share.share('Regardez ce contenu sur Scrole : $url');
    }
  }

  void _onReport() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.red),
              title: const Text('Signaler cette image', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.of(context).pop();
                Get.snackbar('Signalement', 'Merci, ce média a été signalé.', snackPosition: SnackPosition.BOTTOM);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Annuler'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _items.length;
    final isLiked = _likedIndices.contains(_currentPage);
    final isDisliked = _dislikedIndices.contains(_currentPage);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: _bgOpacity),
      body: GestureDetector(
        onVerticalDragStart: (_) => setState(() => _isDragging = true),
        onVerticalDragUpdate: (details) {
          setState(() {
            _dragOffsetY += details.delta.dy;
            if (_dragOffsetY < 0) _dragOffsetY = 0;
            final progress = (_dragOffsetY / 300).clamp(0.0, 1.0);
            _bgOpacity = (1.0 - progress * 0.7).clamp(0.3, 1.0);
          });
        },
        onVerticalDragEnd: (details) {
          if (_dragOffsetY > 120 || details.velocity.pixelsPerSecond.dy > 500) {
            Navigator.of(context).pop();
          } else {
            setState(() {
              _dragOffsetY = 0.0;
              _bgOpacity = 1.0;
              _isDragging = false;
            });
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragOffsetY),
          child: Stack(
            children: [
              // --- Slider plein écran avec Hero ---
              PageView.builder(
                controller: _pageController,
                itemCount: count,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final url = item.url;
                  if (url.isEmpty) return const SizedBox.shrink();

                  if (item.type == 'video') {
                    return _FullScreenVideoPlayer(url: url);
                  }

                  final isNetwork = url.startsWith('http://') || url.startsWith('https://');
                  final isLocalFile = ChatMediaCache.isFilesystemPath(url) && File(url).existsSync();

                  Widget mediaWidget = isLocalFile
                      ? Image.file(
                          File(url),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(Icons.broken_image_rounded, color: Colors.white24, size: 64),
                            );
                          },
                        )
                      : isNetwork
                          ? AppCachedImage(imageUrl: url, fit: BoxFit.contain)
                          : ChatCachedMedia(remoteUrl: url, fit: BoxFit.contain);

                  return Center(
                    child: Hero(
                      tag: '${widget.heroTagPrefix ?? 'media'}_${url}_$index',
                      flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: Tween<double>(begin: 0.9, end: 1.0).evaluate(animation),
                              child: child,
                            );
                          },
                          child: toHeroContext.widget,
                        );
                      },
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: SizedBox(
                          width: double.infinity,
                          height: double.infinity,
                          child: mediaWidget,
                        ),
                      ),
                    ),
                  );
                },
              ),

              // --- Barre supérieure (Fermer à gauche, Menu signaler à droite) ---
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 10,
                right: 10,
                child: AnimatedOpacity(
                  opacity: _isDragging ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Get.back(),
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      ),
                      IconButton(
                        onPressed: _onReport,
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 26),
                      ),
                    ],
                  ),
                ),
              ),

              // --- Barre inférieure (Compteur à gauche, Statistiques & Interactions à droite) ---
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 16,
                right: 16,
                child: AnimatedOpacity(
                  opacity: _isDragging ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Compteur 1 / 4
                      if (count > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_currentPage + 1} / $count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),

                      // Statistiques & Interactions (Like, Dislike, Vues, Commentaires, Partage)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Like
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (_likedIndices.contains(_currentPage)) {
                                  _likedIndices.remove(_currentPage);
                                  _likesCount = (_likesCount > 0) ? _likesCount - 1 : 0;
                                } else {
                                  _likedIndices.add(_currentPage);
                                  _likesCount++;
                                  if (_dislikedIndices.remove(_currentPage)) {
                                    _dislikesCount = (_dislikesCount > 0) ? _dislikesCount - 1 : 0;
                                  }
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.north_rounded,
                                    size: 18,
                                    color: _likedIndices.contains(_currentPage) ? Colors.blueAccent : Colors.white,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$_likesCount',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _likedIndices.contains(_currentPage) ? Colors.blueAccent : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Dislike
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (_dislikedIndices.contains(_currentPage)) {
                                  _dislikedIndices.remove(_currentPage);
                                  _dislikesCount = (_dislikesCount > 0) ? _dislikesCount - 1 : 0;
                                } else {
                                  _dislikedIndices.add(_currentPage);
                                  _dislikesCount++;
                                  if (_likedIndices.remove(_currentPage)) {
                                    _likesCount = (_likesCount > 0) ? _likesCount - 1 : 0;
                                  }
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.south_rounded,
                                    size: 18,
                                    color: _dislikedIndices.contains(_currentPage) ? Colors.orangeAccent : Colors.white,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$_dislikesCount',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _dislikedIndices.contains(_currentPage) ? Colors.orangeAccent : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Vues
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bar_chart_outlined, size: 18, color: Colors.white),
                                const SizedBox(width: 3),
                                Text(NumberFormatter.formatCount(_viewsCount), style: const TextStyle(fontSize: 12, color: Colors.white)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Commentaires
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.chat_bubble_outline_rounded, size: 17, color: Colors.white),
                                const SizedBox(width: 3),
                                Text('$_commentsCount', style: const TextStyle(fontSize: 12, color: Colors.white)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Partage
                          InkWell(
                            onTap: _onShare,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.ios_share_rounded, size: 18, color: Colors.white),
                                  const SizedBox(width: 3),
                                  Text('$_sharesCount', style: const TextStyle(fontSize: 12, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullScreenVideoPlayer extends StatefulWidget {
  final String url;
  const _FullScreenVideoPlayer({required this.url});

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() => _isInitialized = true);
        _controller.play();
        _controller.setLooping(true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _isInitialized
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            )
          : const CircularProgressIndicator(color: Colors.white),
    );
  }
}
