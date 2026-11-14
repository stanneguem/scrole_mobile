import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../shared/models/post_media.dart';
import '../../../../shared/widgets/app_cached_image.dart';
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
  }

  void _onCommentDraftChanged() {
    if (mounted) setState(() {});
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
    _commentController.dispose();
    _commentFocusNode.dispose();
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadRelationship(activeItem.post.authorId);
        });
        final safeBottom = MediaQuery.of(context).viewPadding.bottom;
        final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
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
                setState(() => _currentIndex = value);
                _loadRelationship(items[value].post.authorId);
              },
              itemBuilder: (context, pageIndex) => _ReelVideoPage(
                key: ValueKey('${items[pageIndex].post.id}_${items[pageIndex].media.url}'),
                item: items[pageIndex],
                active: pageIndex == index,
                muted: _muted,
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
              bottom: safeBottom + 181,
              child: _ReelActionRail(
                post: activeItem.post,
                onLike: () => feed.handleReaction(activeItem.post.id, PostReaction.like),
                onComments: () => _openComments(activeItem),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: safeBottom + 24 + keyboardInset,
              child: _ReelPostInfo(
                key: ValueKey('info_${activeItem.post.id}_${activeItem.media.url}'),
                post: activeItem.post,
                onComments: () => _openComments(activeItem),
                followStatus: _followStates[activeItem.post.authorId] ?? 'loading',
                isFollowBusy: _followRequestsInFlight.contains(activeItem.post.authorId),
                onFollow: () => _followAuthor(activeItem.post.authorId),
                commentController: _commentController,
                commentFocusNode: _commentFocusNode,
                isSendingComment: _isSendingComment,
                onSendComment: () => _sendReelComment(activeItem),
                onOpenEmojiPicker: () => _showReelEmojis(activeItem),
                onQuickEmoji: (emoji) => _sendReelComment(activeItem, quickEmoji: emoji),
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

  const _ReelVideoPage({
    super.key,
    required this.item,
    required this.active,
    required this.muted,
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
      await controller.setVolume(widget.muted ? 0 : 1);
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
            onPressed: () => Get.back(),
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

  const _ReelActionRail({
    required this.post,
    required this.onLike,
    required this.onComments,
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
    ],
  );
}

class _ReelPostInfo extends StatelessWidget {
  final CommunityPost post;
  final VoidCallback onComments;
  final String followStatus;
  final bool isFollowBusy;
  final VoidCallback onFollow;
  final TextEditingController commentController;
  final FocusNode commentFocusNode;
  final bool isSendingComment;
  final VoidCallback onSendComment;
  final ValueChanged<String> onQuickEmoji;
  final VoidCallback onOpenEmojiPicker;

  const _ReelPostInfo({
    super.key,
    required this.post,
    required this.onComments,
    required this.followStatus,
    required this.isFollowBusy,
    required this.onFollow,
    required this.commentController,
    required this.commentFocusNode,
    required this.isSendingComment,
    required this.onSendComment,
    required this.onQuickEmoji,
    required this.onOpenEmojiPicker,
  });

  @override
  Widget build(BuildContext context) {
    final author = post.authorObj;
    final username = author?.username.isNotEmpty == true ? author!.username : post.authorName;
    final displayName = author?.fullName.trim().isNotEmpty == true
        ? author!.fullName.trim()
        : post.authorName;
    final avatar = author?.photoUrl;
    final isCertified = author?.isCertified == true;
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
    final hasText = commentController.text.trim().isNotEmpty;
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isCertified) ...[
              const SizedBox(width: 5),
              const Icon(Icons.verified_rounded, color: Color(0xFF35A7FF), size: 17),
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
          Text(post.content, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.25)),
        ],
        const SizedBox(height: 10),
        // Copie exacte du compositeur _buildQuickStoryReply() de StoryViewerScreen.
        Row(
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
                  (emoji) => PopupMenuItem<String>(
                    value: emoji,
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: '__more__',
                  child: Center(
                    child: Icon(Icons.add_circle_outline, color: Colors.white, size: 22),
                  ),
                ),
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
                        controller: commentController,
                        focusNode: commentFocusNode,
                        onChanged: (_) {},
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSendComment(),
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
                        onPressed: isSendingComment ? null : onSendComment,
                        icon: isSendingComment
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                      ),
                  ],
                ),
              ),
            ),
          ],
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
