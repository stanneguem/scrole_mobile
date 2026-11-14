import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../shared/models/post_media.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../../shared/widgets/linkified_text.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../widgets/feed_post_card.dart';
import '../../../module_communautes/interne/controllers/community/community_feed_controller.dart';
import '../controllers/home_feed_controller.dart';
import '../widgets/community_comments_sheet.dart';
import '../../centre/models/community_post.dart';
import '../../../module_discussion_direct/externe/repositories/social_repository.dart';
import '../../externe/repositories/home_feed_repository.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _muted = false;
  bool _descriptionExpanded = false;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final SocialRepository _socialRepository = SocialRepository();
  final HomeFeedRepository _feedRepository = HomeFeedRepository();
  final Map<String, String> _followStates = {};
  final Set<String> _followRequestsInFlight = {};
  bool _isSendingComment = false;

  @override
  void initState() {
    super.initState();
    _commentController.addListener(_onCommentDraftChanged);
    _commentFocusNode.addListener(_onCommentFocusChanged);
  }

  void _onCommentDraftChanged() {
    if (mounted) setState(() {});
  }

  void _onCommentFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onDescriptionExpandedChanged(bool expanded) {
    if (_descriptionExpanded == expanded) return;
    setState(() => _descriptionExpanded = expanded);
  }

  void _goHome() => Get.back();

  String _relationStatus(Map<String, dynamic> relation) {
    final state = (relation['state'] ?? '').toString().toLowerCase();
    if (state == 'following' || state == 'friends' || relation['is_following'] == true) {
      return 'following';
    }
    if (state == 'requested' || relation['request_sent'] == true) return 'requested';
    return 'none';
  }

  Future<void> _loadRelationship(String userId) async {
    if (userId.isEmpty || userId == _socialRepository.currentUserId ||
        _followStates.containsKey(userId)) return;
    try {
      final relation = await _socialRepository.getRelationship(userId);
      if (mounted) setState(() => _followStates[userId] = _relationStatus(relation));
    } catch (error) {
      debugPrint('[REELS] relationship lookup failed: $error');
      if (mounted) setState(() => _followStates.putIfAbsent(userId, () => 'none'));
    }
  }

  Future<void> _followAuthor(String userId) async {
    if (userId.isEmpty || !_followRequestsInFlight.add(userId)) return;
    setState(() {});
    try {
      final relation = await _socialRepository.followUser(userId);
      final status = _relationStatus(relation);
      if (mounted) {
        setState(() => _followStates[userId] = status == 'none' ? 'following' : status);
      }
    } catch (error) {
      debugPrint('[REELS] follow action failed: $error');
      if (mounted) {
        Get.snackbar('Suivi impossible', 'Réessaie dans un instant.',
            snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      _followRequestsInFlight.remove(userId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _sendReelComment(_ReelItem item, {String? quickEmoji}) async {
    final text = (quickEmoji ?? _commentController.text).trim();
    if (text.isEmpty || _isSendingComment) return;
    setState(() => _isSendingComment = true);
    try {
      await _feedRepository.commentCommunityPost(
        p_id: const Uuid().v4(),
        postId: item.post.id,
        content: text,
        mentions: const [],
      );
      if (!mounted) return;
      _commentController.clear();
      _commentFocusNode.unfocus();
      Get.snackbar('Commentaire envoyé', 'Ton commentaire a été publié.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2));
    } catch (error) {
      debugPrint('[REELS] comment submission failed: $error');
      if (mounted) {
        Get.snackbar('Envoi impossible', 'Vérifie ta connexion puis réessaie.',
            snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      if (mounted) setState(() => _isSendingComment = false);
    }
  }

  Future<void> _showReelEmojis(_ReelItem item) async {
    const emojis = [
      '😀','😃','😄','😁','😆','😅','😂','🤣','🥲','😊','😇','🙂',
      '🙃','😉','😍','🥰','😘','😗','😙','😚','😋','😛','😜','🤪',
      '🤗','🤭','🤫','🤔','🫡','🤐','🤨','😐','😏','😒','🙄','😬',
      '😴','🤤','🥳','😎','🤩','😭','😢','🥺','😤','😡','🤯','😱',
      '❤️','🧡','💛','💚','💙','💜','🖤','🤍','💔','💕','💞','💖',
      '🔥','✨','⭐','🌟','💯','👏','🙌','👍','👎','🙏','💪','🎉',
      '🥂','🍾','🌹','🌸','🌈','☀️','💐','🎂','😍','🤝','🫶','💋',
    ];
    final selectedEmoji = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          height: MediaQuery.of(sheetContext).size.height * 0.52,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFF202020),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'story_choose_emoji'.tr,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  itemCount: emojis.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemBuilder: (_, index) => InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(sheetContext).pop(emojis[index]),
                    child: Center(
                      child: Text(emojis[index], style: const TextStyle(fontSize: 27)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (selectedEmoji != null) {
      await _sendReelComment(item, quickEmoji: selectedEmoji);
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
    _commentController.removeListener(_onCommentDraftChanged);
    _commentFocusNode.removeListener(_onCommentFocusChanged);
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = Get.find<HomeFeedController>();
    return Scaffold(
      backgroundColor: Colors.black,
      // Le clavier ne doit jamais redimensionner le lecteur : seule la zone
      // de commentaire se repositionne au-dessus du clavier.
      resizeToAvoidBottomInset: false,
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadRelationship(activeItem.post.authorId);
        });
        final safeBottom = MediaQuery.of(context).viewPadding.bottom;
        return Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: items.length,
              onPageChanged: (value) {
                _commentController.clear();
                _commentFocusNode.unfocus();
                setState(() {
                  _currentIndex = value;
                  _descriptionExpanded = false;
                });
                _loadRelationship(items[value].post.authorId);
              },
              itemBuilder: (context, pageIndex) {
                final item = items[pageIndex];
                final isActive = pageIndex == index;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _ReelVideoPage(
                      key: ValueKey('${item.post.id}_${item.media.url}'),
                      item: item,
                      active: isActive,
                      muted: _muted,
                      paused: isActive &&
                          (_descriptionExpanded || _commentFocusNode.hasFocus),
                    ),
                    // Les interactions et les informations auteur font partie
                    // de cette page : elles glissent avec la vidéo au swipe.
                    Positioned(
                        right: 12,
                        bottom: safeBottom + 181 + keyboardInset,
                        child: _ReelActionRail(
                          key: ValueKey('actions_${item.post.id}'),
                          post: item.post,
                          onReaction: (reaction) => feed.handleReaction(item.post.id, reaction),
                          onComments: () => _openComments(item),
                          onShare: () => showFeedPostShareSheet(context, item.post),
                        ),
                      ),
                    Positioned(
                        left: 16,
                        right: 82,
                        bottom: safeBottom + 82 + keyboardInset,
                        child: _ReelAuthorInfo(
                          key: ValueKey('author_${item.post.id}_${item.media.url}'),
                          post: item.post,
                          followStatus: _followStates[item.post.authorId] ?? 'loading',
                          isFollowBusy: _followRequestsInFlight.contains(item.post.authorId),
                          onFollow: () => _followAuthor(item.post.authorId),
                          onDescriptionExpandedChanged: _onDescriptionExpandedChanged,
                        ),
                      ),
                  ],
                );
              },
            ),
            // Barre supérieure persistante : elle ne fait pas partie du PageView.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _ReelsTopBar(
                onReport: () => showFeedPostReportSheet(context, activeItem.post),
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
  final bool muted;
  // Nullable backing field keeps existing PageView children safe during hot reload.
  final bool? paused;
  bool get isPaused => paused ?? false;

  const _ReelVideoPage({
    super.key,
    required this.item,
    required this.active,
    required this.muted,
    this.paused = false,
  });

  @override
  State<_ReelVideoPage> createState() => _ReelVideoPageState();
}

class _ReelVideoPageState extends State<_ReelVideoPage> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  bool _loading = true;
  bool _failed = false;
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
    if (oldWidget.muted != widget.muted && _video?.value.isInitialized == true) {
      unawaited(_video!.setVolume(widget.muted ? 0 : 1));
    }
    if (oldWidget.isPaused != widget.isPaused && widget.active) {
      final controller = _video;
      if (controller != null && controller.value.isInitialized) {
        if (widget.isPaused) {
          unawaited(controller.pause());
        } else {
          unawaited(controller.play());
        }
      }
    }
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        unawaited(_initialize());
      } else {
        unawaited(_release());
      }
    }
  }

  Future<void> _initialize() async {
    if (!widget.active || widget.isPaused || _video != null || !_loading) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.item.media.url));
    try {
      await controller.initialize();
      if (!mounted || !widget.active) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(widget.muted ? 0 : 1);
      _video = controller;
      controller.addListener(_onVideoChanged);
      setState(() => _loading = false);
      if (!widget.isPaused) await controller.play();
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
    if (mounted) setState(() => _loading = true);
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
          // Fond « liquid glass » : la même image vidéo est agrandie,
          // floutée et assombrie derrière la vidéo originale.
          if (controller != null && controller.value.isInitialized) ...[
            Positioned.fill(
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                  child: Transform.scale(
                    scale: 1.28,
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
            ),
            // La vidéo originale reste entière : aucune coupe ni aucun zoom.
            Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
          ] else if (widget.item.media.thumbnailUrl?.isNotEmpty == true) ...[
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                child: Transform.scale(
                  scale: 1.28,
                  child: AppCachedImage(
                    imageUrl: widget.item.media.thumbnailUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
            ),
            Center(
              child: AppCachedImage(
                imageUrl: widget.item.media.thumbnailUrl!,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ] else
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
  final VoidCallback onReport;

  const _ReelsTopBar({required this.onReport});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const SizedBox(width: 4),
          const Text('Scut', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Options',
            icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 27),
            color: const Color(0xFF252525),
            onSelected: (value) {
              if (value == 'report') onReport();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'report',
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, color: Colors.white70, size: 20),
                    const SizedBox(width: 12),
                    Text('home_feed_report_post'.tr,
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ReelActionRail extends StatefulWidget {
  final CommunityPost post;
  final ValueChanged<PostReaction> onReaction;
  final VoidCallback onComments;
  final VoidCallback onShare;

  const _ReelActionRail({
    super.key,
    required this.post,
    required this.onReaction,
    required this.onComments,
    required this.onShare,
  });

  @override
  State<_ReelActionRail> createState() => _ReelActionRailState();
}

class _ReelActionRailState extends State<_ReelActionRail> {
  late PostReaction _reaction;
  late int _likes;
  late int _dislikes;

  @override
  void initState() {
    super.initState();
    _syncFromPost();
  }

  @override
  void didUpdateWidget(covariant _ReelActionRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.userReaction != widget.post.userReaction ||
        oldWidget.post.likeCount != widget.post.likeCount ||
        oldWidget.post.dislikeCount != widget.post.dislikeCount) {
      _syncFromPost();
    }
  }

  void _syncFromPost() {
    _reaction = widget.post.userReaction;
    _likes = widget.post.likeCount;
    _dislikes = widget.post.dislikeCount;
  }

  void _handleReaction(PostReaction next) {
    setState(() {
      if (_reaction == next) {
        if (next == PostReaction.like) {
          if (_likes > 0) _likes--;
        } else if (next == PostReaction.dislike) {
          if (_dislikes > 0) _dislikes--;
        }
        _reaction = PostReaction.none;
      } else {
        if (_reaction == PostReaction.like) {
          if (_likes > 0) _likes--;
        } else if (_reaction == PostReaction.dislike) {
          if (_dislikes > 0) _dislikes--;
        }
        if (next == PostReaction.like) _likes++;
        if (next == PostReaction.dislike) _dislikes++;
        _reaction = next;
      }
    });
    widget.onReaction(next);
  }

  @override
  Widget build(BuildContext context) {
    final inactive = Colors.white.withValues(alpha: 0.92);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ReelActionButton(
          icon: Icons.north_rounded,
          label: NumberFormatter.formatCount(_likes),
          color: _reaction == PostReaction.like ? AppColors.primary : inactive,
          onTap: () => _handleReaction(PostReaction.like),
        ),
        const SizedBox(height: 17),
        _ReelActionButton(
          icon: Icons.south_rounded,
          label: NumberFormatter.formatCount(_dislikes),
          color: _reaction == PostReaction.dislike ? Colors.orangeAccent : inactive,
          onTap: () => _handleReaction(PostReaction.dislike),
        ),
        const SizedBox(height: 17),
        _ReelActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          label: NumberFormatter.formatCount(widget.post.commentCount),
          onTap: widget.onComments,
        ),
        const SizedBox(height: 17),
        _ReelActionButton(
          icon: Icons.ios_share_rounded,
          label: NumberFormatter.formatCount(widget.post.shareCount),
          onTap: widget.onShare,
        ),
      ],
    );
  }
}

class _ReelAuthorInfo extends StatelessWidget {
  final CommunityPost post;
  final String followStatus;
  final bool isFollowBusy;
  final VoidCallback onFollow;
  final ValueChanged<bool> onDescriptionExpandedChanged;

  const _ReelAuthorInfo({
    super.key,
    required this.post,
    required this.followStatus,
    required this.isFollowBusy,
    required this.onFollow,
    required this.onDescriptionExpandedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final author = post.authorObj;
    final username = author?.username.isNotEmpty == true ? author!.username : post.authorName;
    final displayName = author?.displayName.trim().isNotEmpty == true
        ? author!.displayName.trim()
        : post.authorName;
    final avatar = author?.photoUrl;
    final colorScheme = Theme.of(context).colorScheme;
    final isOwnPost = post.authorId == Supabase.instance.client.auth.currentUser?.id;
    final languageCode = Localizations.localeOf(context).languageCode.toLowerCase();
    String followLabel;
    if (followStatus == 'following') {
      followLabel = switch (languageCode) {
        'fr' => 'Suivi',
        'es' => 'Siguiendo',
        'pt' => 'Seguindo',
        'de' => 'Gefolgt',
        'ar' => 'تتابعه',
        _ => 'Following',
      };
    } else if (followStatus == 'requested') {
      followLabel = switch (languageCode) {
        'fr' => 'Demandé',
        'es' => 'Solicitado',
        'pt' => 'Solicitado',
        'de' => 'Angefragt',
        'ar' => 'تم الطلب',
        _ => 'Requested',
      };
    } else {
      followLabel = switch (languageCode) {
        'fr' => 'Suivre',
        'es' => 'Seguir',
        'pt' => 'Seguir',
        'de' => 'Folgen',
        'ar' => 'متابعة',
        _ => 'Follow',
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: colorScheme.surfaceContainerHighest,
              backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar == null || avatar.isEmpty ? const Icon(Icons.person, size: 20) : null,
            ),
            const SizedBox(width: 9),
            Flexible(
              fit: FlexFit.loose,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('@$username', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            if (author?.isCertified == true) ...[
              const SizedBox(width: 5),
              UserCertifiedBadge(
                size: 17,
                showTooltip: false,
                type: CertificationBadgeType.basic,
                userId: author?.userId.isNotEmpty == true ? author!.userId : post.authorId,
              ),
            ],
            if (!isOwnPost) ...[
              const SizedBox(width: 9),
              OutlinedButton(
                onPressed: isFollowBusy || followStatus == 'loading' ||
                    followStatus == 'following' || followStatus == 'requested' ? null : onFollow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white70),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: isFollowBusy || followStatus == 'loading'
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                    : Text(followLabel, style: const TextStyle(fontSize: 11)),
              ),
            ],
          ],
        ),
        if (post.content.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _ExpandableReelDescription(
            text: post.content,
            onExpandedChanged: onDescriptionExpandedChanged,
          ),
        ],
      ],
    );
  }
}

class _ReelCommentComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onOpenEmojiPicker;
  final ValueChanged<String> onQuickEmoji;

  const _ReelCommentComposer({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
    required this.onOpenEmojiPicker,
    required this.onQuickEmoji,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;
    return Row(
      children: [
        PopupMenuButton<String>(
          tooltip: 'story_emoji_tooltip'.tr,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white, size: 26),
          color: const Color(0xFF292929),
          onSelected: (emoji) {
            if (emoji == '__more__') {
              onOpenEmojiPicker();
              return;
            }
            onQuickEmoji(emoji);
          },
          itemBuilder: (_) => [
            ...['❤️', '😂', '😍', '🔥', '👏', '👍'].map(
              (emoji) => PopupMenuItem<String>(value: emoji,
                child: Text(emoji, style: const TextStyle(fontSize: 22))),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(value: '__more__',
              child: Center(child: Icon(Icons.add_circle_outline, color: Colors.white, size: 22))),
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 5, 6, 5),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (_) {},
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'story_reply_hint'.tr,
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13),
                      filled: true,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      isCollapsed: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                    ),
                  ),
                ),
                if (hasText)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'story_send'.tr,
                    onPressed: isSending ? null : onSend,
                    icon: isSending
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ),
              ],
            ),
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


/// Description compacte des Réels : une seule ligne par défaut,
/// avec le même comportement « Voir plus / Voir moins » que le fil.
class _ExpandableReelDescription extends StatefulWidget {
  final String text;
  final ValueChanged<bool> onExpandedChanged;

  const _ExpandableReelDescription({
    required this.text,
    required this.onExpandedChanged,
  });

  @override
  State<_ExpandableReelDescription> createState() =>
      _ExpandableReelDescriptionState();
}

class _ExpandableReelDescriptionState
    extends State<_ExpandableReelDescription> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 13,
      height: 1.25,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: const TextSpan(text: ''),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        painter.text = TextSpan(text: widget.text, style: style);
        painter.layout(maxWidth: constraints.maxWidth);
        final isOverflowing = painter.didExceedMaxLines;
        painter.dispose();

        if (!isOverflowing) {
          return LinkifiedText(text: widget.text, style: style);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LinkifiedText(
              text: widget.text,
              maxLines: _isExpanded ? null : 1,
              overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: style,
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                final next = !_isExpanded;
                setState(() => _isExpanded = next);
                widget.onExpandedChanged(next);
              },
              child: Text(
                _isExpanded ? 'post_see_less'.tr : 'post_see_more'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white70,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
