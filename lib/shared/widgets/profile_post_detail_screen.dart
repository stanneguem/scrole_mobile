import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/interne/widgets/feed_post_card.dart';
import 'package:scrole/modules/module_communautes/interne/controllers/community/community_feed_controller.dart';
import 'package:scrole/modules/module_principale/interne/widgets/community_comments_sheet.dart';

/// Shows a profile post using the same card and interaction rules as the main feed.
class ProfilePostDetailScreen extends StatefulWidget {
  const ProfilePostDetailScreen({super.key, required this.post});
  final CommunityPost post;

  @override
  State<ProfilePostDetailScreen> createState() => _ProfilePostDetailScreenState();
}

class _ProfilePostDetailScreenState extends State<ProfilePostDetailScreen> {
  late CommunityPost _post;
  bool _reactionBusy = false;

  bool get _isOwnPost {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return currentUserId != null && currentUserId.isNotEmpty && _post.authorId == currentUserId;
  }

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    // Profile grids can pass a lightweight post object without the complete
    // author relation. Reload the canonical post so the card receives the
    // author's real username, avatar and certification state.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCompletePost());
  }

  Future<void> _loadCompletePost() async {
    try {
      final freshPost = await HomeFeedRepository().getPost(_post.id);
      if (!mounted) return;
      setState(() => _post = freshPost);
    } catch (error) {
      // Keep the profile-provided post visible if the detail endpoint is
      // unavailable (for example, when a private post is no longer accessible).
      debugPrint('[PROFILE_POST_DETAIL] Unable to refresh post author data: $error');
    }
  }

  Future<void> _handleReaction(PostReaction reaction) async {
    if (_reactionBusy || !_post.reactionsEnabled || _post.isPublishing) return;
    final oldReaction = _post.userReaction;
    final newReaction = oldReaction == reaction ? PostReaction.none : reaction;
    setState(() {
      _reactionBusy = true;
      _post = _post.copyWith(userReaction: newReaction);
    });
    try {
      await HomeFeedRepository().setCommunityPostReaction(
        _post.id,
        newReaction == PostReaction.none ? null : newReaction == PostReaction.like ? 'like' : 'dislike',
      );
    } catch (error) {
      if (mounted) {
        setState(() => _post = _post.copyWith(userReaction: oldReaction));
        Get.snackbar('error'.tr, error.toString().replaceFirst('Exception: ', ''),
            snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      if (mounted) setState(() => _reactionBusy = false);
    }
  }

  void _openComments() {
    if (!_post.commentsEnabled || _post.isPublishing) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunityCommentsSheet(
        post: _post,
        controller: Get.isRegistered<CommunityFeedController>()
            ? Get.find<CommunityFeedController>()
            : Get.put(CommunityFeedController(null, _post.eventId)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text('post_detail_title'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        leading: IconButton(
          tooltip: 'back'.tr,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Get.back(),
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: const [],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
        children: [
          FeedPostCard(
            post: _post,
            onReactionTap: _handleReaction,
            onCommentTap: _openComments,
          ),
          if (!_post.reactionsEnabled || !_post.commentsEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Text(
                'post_interactions_restricted'.tr,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
