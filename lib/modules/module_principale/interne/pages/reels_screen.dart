import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../../shared/models/post_media.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../module_communautes/interne/controllers/community/community_feed_controller.dart';
import '../controllers/home_feed_controller.dart';
import '../controllers/main_layout_controller.dart';
import '../widgets/community_comments_sheet.dart';
import '../../centre/models/community_post.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  void _goHome() {
    if (Get.isRegistered<MainLayoutController>()) {
      Get.find<MainLayoutController>().changeTab(0);
    }
  }

  List<_ReelItem> _buildItems(HomeFeedController controller) {
    final result = <_ReelItem>[];
    final seen = <String>{};
    for (final post in [...controller.posts, ...controller.sponsoredPosts]) {
      if (post.isPublishing || !seen.add(post.id)) continue;
      for (final media in post.media) {
        if (media.isVideo && media.url.trim().isNotEmpty) {
          result.add(_ReelItem(post: post, media: media));
        }
      }
    }
    return result;
  }

  Future<void> _openComments(_ReelItem item) async {
    final communityController = Get.isRegistered<CommunityFeedController>()
        ? Get.find<CommunityFeedController>()
        : Get.put(CommunityFeedController(null, item.post.eventId));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunityCommentsSheet(
        post: item.post,
        controller: communityController,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = Get.find<HomeFeedController>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        final items = _buildItems(feed);
        if (items.isEmpty) {
          return Stack(
            children: [
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.video_library_outlined, color: Colors.white70, size: 58),
                    SizedBox(height: 16),
                    Text('Aucun réel disponible pour le moment', style: TextStyle(color: Colors.white, fontSize: 15)),
                    SizedBox(height: 8),
                    Text('Les publications contenant une vidéo apparaîtront ici.', style: TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
                  ],
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    onPressed: _goHome,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: TextButton.icon(
                    onPressed: () => feed.fetchFeed(refresh: true),
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    label: const Text('Actualiser', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ],
          );
        }
        final index = _currentIndex.clamp(0, items.length - 1);
        return PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: items.length,
          onPageChanged: (value) => setState(() => _currentIndex = value),
          itemBuilder: (context, pageIndex) => _ReelVideoPage(
            key: ValueKey('${items[pageIndex].post.id}_${items[pageIndex].media.url}'),
            item: items[pageIndex],
            active: pageIndex == index,
            onBack: _goHome,
            onLike: () => feed.handleReaction(items[pageIndex].post.id, PostReaction.like),
            onComments: () => _openComments(items[pageIndex]),
            onShare: () => Share.share(items[pageIndex].post.content.isEmpty
                ? 'Découvre ce réel sur Scrole'
                : items[pageIndex].post.content),
            onQualifiedView: () => feed.queueQualifiedVideoPostView(
              items[pageIndex].post.id,
              items[pageIndex].post,
            ),
          ),
        );
      }),
    );
  }
}

class _ReelItem {
  final CommunityPost post;
  final PostMedia media;
  const _ReelItem({required this.post, required this.media});
}

class _ReelVideoPage extends StatefulWidget {
  final _ReelItem item;
  final bool active;
  final VoidCallback onBack;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onShare;
  final VoidCallback onQualifiedView;

  const _ReelVideoPage({
    super.key,
    required this.item,
    required this.active,
    required this.onBack,
    required this.onLike,
    required this.onComments,
    required this.onShare,
    required this.onQualifiedView,
  });

  @override
  State<_ReelVideoPage> createState() => _ReelVideoPageState();
}

class _ReelVideoPageState extends State<_ReelVideoPage> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  bool _loading = true;
  bool _failed = false;
  bool _muted = false;
  bool _qualified = false;
  Duration _lastPosition = Duration.zero;
  Duration _watched = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant _ReelVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        unawaited(_initialize());
      } else {
        unawaited(_release());
      }
    }
  }

  Future<void> _initialize() async {
    if (!widget.active || _video != null || !_loading) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.item.media.url));
    try {
      await controller.initialize();
      if (!mounted || !widget.active) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      _video = controller;
      controller.addListener(_onVideoChanged);
      setState(() => _loading = false);
      await controller.play();
    } catch (error) {
      debugPrint('[REELS] video initialization failed: $error');
      await controller.dispose();
      if (mounted) setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _onVideoChanged() {
    final controller = _video;
    if (!mounted || controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    final delta = value.position - _lastPosition;
    if (value.isPlaying && !value.isBuffering && delta > Duration.zero &&
        delta <= const Duration(milliseconds: 900)) {
      _watched += delta;
    }
    _lastPosition = value.position;
    if (!_qualified && value.duration > Duration.zero &&
        _watched >= Duration(microseconds: (value.duration.inMicroseconds * 0.5).round())) {
      _qualified = true;
      widget.onQualifiedView();
    }
  }

  Future<void> _release() async {
    final controller = _video;
    _video = null;
    controller?.removeListener(_onVideoChanged);
    if (controller != null) {
      try { await controller.pause(); } catch (_) {}
      await controller.dispose();
    }
    if (mounted && !widget.active) setState(() => _loading = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_release());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _video;
    _video = null;
    controller?.removeListener(_onVideoChanged);
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _video;
    final post = widget.item.post;
    final author = post.authorObj;
    final username = author?.username.isNotEmpty == true ? author!.username : post.authorName;
    final avatar = author?.photoUrl;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        final current = _video;
        if (current == null || !current.value.isInitialized) return;
        if (current.value.isPlaying) {
          current.pause();
        } else {
          current.play();
        }
        setState(() {});
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
          else if (widget.item.media.thumbnailUrl?.isNotEmpty == true)
            AppCachedImage(
              imageUrl: widget.item.media.thumbnailUrl!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            )
          else
            const ColoredBox(color: Colors.black),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Colors.transparent, Color(0xB9000000)],
                stops: [0, 0.38, 1],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Text('Réels', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_failed)
            const Center(child: Icon(Icons.error_outline_rounded, color: Colors.white, size: 46)),
          if (controller != null && controller.value.isInitialized && !controller.value.isPlaying)
            const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 68)),
          Positioned(
            right: 12,
            bottom: 112,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReelActionButton(
                  icon: post.userReaction == PostReaction.like ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  label: post.likeCount.toString(),
                  color: post.userReaction == PostReaction.like ? Colors.pinkAccent : Colors.white,
                  onTap: widget.onLike,
                ),
                const SizedBox(height: 22),
                _ReelActionButton(
                  icon: Icons.mode_comment_outlined,
                  label: post.commentCount.toString(),
                  onTap: widget.onComments,
                ),
                const SizedBox(height: 22),
                _ReelActionButton(
                  icon: Icons.send_rounded,
                  label: post.shareCount.toString(),
                  onTap: widget.onShare,
                ),
                const SizedBox(height: 22),
                IconButton(
                  tooltip: _muted ? 'Activer le son' : 'Couper le son',
                  onPressed: () async {
                    final current = _video;
                    if (current == null || !current.value.isInitialized) return;
                    final nextMuted = !_muted;
                    await current.setVolume(nextMuted ? 0 : 1);
                    if (mounted) setState(() => _muted = nextMuted);
                  },
                  icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 82,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
                      child: avatar == null || avatar.isEmpty ? const Icon(Icons.person, size: 18) : null,
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text('@$username', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () {
                        final id = post.authorId;
                        if (id.isNotEmpty) Get.toNamed('/user-profile/$id');
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        minimumSize: const Size(0, 30),
                      ),
                      child: const Text('Voir le profil', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                if (post.content.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(post.content, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.25)),
                ],
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: widget.onComments,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                    alignment: Alignment.centerLeft,
                    child: const Text('Ajouter un commentaire...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ReelActionButton({
    required this.icon,
    required this.label,
    this.color = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(30),
    child: Column(
      children: [
        Icon(icon, color: color, size: 31),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
