import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../../shared/models/post_media.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../module_communautes/interne/controllers/community/community_feed_controller.dart';
import '../controllers/home_feed_controller.dart';
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

  void _goHome() => Get.back();

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
        final activeItem = items[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: items.length,
              onPageChanged: (value) => setState(() => _currentIndex = value),
              itemBuilder: (context, pageIndex) => _ReelVideoPage(
                key: ValueKey('${items[pageIndex].post.id}_${items[pageIndex].media.url}'),
                item: items[pageIndex],
                active: pageIndex == index,
              ),
            ),
            // Barre supérieure persistante : elle ne fait pas partie du PageView.
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _ReelsTopBar(),
            ),
            // Les commandes restent ancrées à l'écran, mais leurs données
            // proviennent toujours de la publication actuellement affichée.
            Positioned(
              right: 12,
              bottom: 112,
              child: _ReelActionRail(
                post: activeItem.post,
                onLike: () => feed.handleReaction(activeItem.post.id, PostReaction.like),
                onComments: () => _openComments(activeItem),
                onShare: () => Share.share(activeItem.post.content.isEmpty
                    ? 'Découvre ce réel sur Scrole'
                    : activeItem.post.content),
              ),
            ),
            Positioned(
              left: 16,
              right: 82,
              bottom: 24,
              child: _ReelPostInfo(
                key: ValueKey('info_${activeItem.post.id}_${activeItem.media.url}'),
                post: activeItem.post,
                onComments: () => _openComments(activeItem),
              ),
            ),
          ],
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

  const _ReelVideoPage({
    super.key,
    required this.item,
    required this.active,
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
      final feed = Get.find<HomeFeedController>();
      feed.queueQualifiedVideoPostView(widget.item.post.id, widget.item.post);
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
    else if (widget.active && !_failed) unawaited(_initialize());
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final current = _video;
        if (current == null || !current.value.isInitialized) {
          if (widget.active && !_failed) {
            setState(() => _loading = true);
            unawaited(_initialize());
          }
          return;
        }
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
          if (_loading && widget.active)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_failed)
            const Center(child: Icon(Icons.error_outline_rounded, color: Colors.white, size: 46)),
          if (controller != null && controller.value.isInitialized && !controller.value.isPlaying)
            const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 68)),
        ],
      ),
    );
  }
}

class _ReelsTopBar extends StatelessWidget {
  const _ReelsTopBar();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topLeft,
      child: Row(
        children: [
          IconButton(
            onPressed: Get.back,
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const SizedBox(width: 4),
          const Text('Réels', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
}

class _ReelActionRail extends StatelessWidget {
  final CommunityPost post;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onShare;

  const _ReelActionRail({
    required this.post,
    required this.onLike,
    required this.onComments,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _ReelActionButton(
        icon: post.userReaction == PostReaction.like ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        label: post.likeCount.toString(),
        color: post.userReaction == PostReaction.like ? Colors.pinkAccent : Colors.white,
        onTap: onLike,
      ),
      const SizedBox(height: 22),
      _ReelActionButton(icon: Icons.mode_comment_outlined, label: post.commentCount.toString(), onTap: onComments),
      const SizedBox(height: 22),
      _ReelActionButton(icon: Icons.send_rounded, label: post.shareCount.toString(), onTap: onShare),
    ],
  );
}

class _ReelPostInfo extends StatelessWidget {
  final CommunityPost post;
  final VoidCallback onComments;

  const _ReelPostInfo({super.key, required this.post, required this.onComments});

  @override
  Widget build(BuildContext context) {
    final author = post.authorObj;
    final username = author?.username.isNotEmpty == true ? author!.username : post.authorName;
    final avatar = author?.photoUrl;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
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
          onTap: onComments,
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
