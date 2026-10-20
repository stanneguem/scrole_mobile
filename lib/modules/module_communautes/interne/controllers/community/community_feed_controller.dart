import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/centre/models/post_comment.dart';
import 'package:scrole/modules/module_principale/interne/enums/community_role_enum.dart';
import 'package:scrole/shared/models/post_media.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';

enum CommunityFeedState { initialLoading, loaded, empty, error, refreshing }

class CommunityFeedController extends GetxController {
  final dynamic service;
  final String? communityId;
  final HomeFeedRepository _feedRepo = HomeFeedRepository();

  String? get currentUserId {
    try {
      if (Get.isRegistered<AuthService>()) {
        return Get.find<AuthService>().userId;
      }
    } catch (_) {}
    return null;
  }

  static final Set<String> _globalSentViewIds = {};
  final List<String> _pendingViewIds = [];
  Timer? _viewBatchTimer;

  CommunityFeedController([this.service, this.communityId]);

  final RxString communityName = 'evenement'.obs;
  final RxList<CommunityPost> posts = <CommunityPost>[].obs;
  final Rx<CommunityFeedState> feedState = CommunityFeedState.initialLoading.obs;
  final RxString errorMessage = ''.obs;
  String? nextCursor;
  bool hasMore = false;
  bool isLoadingMore = false;

  final RxMap<String, bool> commentsLoading = <String, bool>{}.obs;
  final RxMap<String, List<PostComment>> commentsByPostId = <String, List<PostComment>>{}.obs;
  final RxMap<String, List<PostComment>> repliesByCommentId = <String, List<PostComment>>{}.obs;
  final RxMap<String, bool> loadingRepliesByCommentId = <String, bool>{}.obs;

  @override
  void onInit() {
    super.onInit();
    fetchCommunityFeed();
  }

  @override
  void onClose() {
    _viewBatchTimer?.cancel();
    super.onClose();
  }

  void queuePostView(CommunityPost post) {
    if (post.isPublishing) return;
    final myId = currentUserId;
    if (myId != null && post.authorId == myId) return;
    if (_globalSentViewIds.contains(post.id)) return;
    if (_pendingViewIds.contains(post.id)) return;

    _pendingViewIds.add(post.id);
    _globalSentViewIds.add(post.id);

    if (_pendingViewIds.length >= 20) {
      _flushViewBatch();
    } else {
      _viewBatchTimer ??= Timer(const Duration(seconds: 3), _flushViewBatch);
    }
  }

  Future<void> _flushViewBatch() async {
    _viewBatchTimer?.cancel();
    _viewBatchTimer = null;

    if (_pendingViewIds.isEmpty) return;
    final batch = List<String>.from(_pendingViewIds);
    _pendingViewIds.clear();

    try {
      debugPrint('[POST_ACTIONS] [CommunityFeed] Sending view batch of ${batch.length} posts');
      await _feedRepo.recordPostViews(batch);

      final counters = await _feedRepo.getPostCounters(batch);
      if (counters.isNotEmpty) {
        for (final c in counters) {
          final id = c['id']?.toString();
          if (id == null) continue;
          final idx = posts.indexWhere((p) => p.id == id);
          if (idx != -1) {
            final p = posts[idx];
            posts[idx] = p.copyWith(
              viewCount: (c['views_count'] as num?)?.toInt() ?? p.viewCount,
              likeCount: (c['likes_count'] as num?)?.toInt() ?? p.likeCount,
              dislikeCount: (c['dislikes_count'] as num?)?.toInt() ?? p.dislikeCount,
              commentCount: (c['comments_count'] as num?)?.toInt() ?? p.commentCount,
              shareCount: (c['shares_count'] as num?)?.toInt() ?? p.shareCount,
            );
          }
        }
        posts.refresh();
      }
    } catch (e) {
      debugPrint('[POST_ACTIONS] [CommunityFeed] Error flushing view batch: $e');
    }
  }

  Future<void> fetchCommunityFeed({bool isRefresh = false}) async {
    if (communityId == null || communityId!.isEmpty) {
      feedState.value = CommunityFeedState.empty;
      return;
    }

    if (isRefresh) {
      if (posts.isEmpty) {
        feedState.value = CommunityFeedState.initialLoading;
      } else {
        feedState.value = CommunityFeedState.refreshing;
      }
      nextCursor = null;
      hasMore = false;
    } else {
      if (posts.isEmpty) {
        feedState.value = CommunityFeedState.initialLoading;
      }
    }

    try {
      debugPrint('[COMMUNITY_FEED] Fetching posts via get_community_feed for communityId=$communityId, isRefresh=$isRefresh');
      final result = await _feedRepo.getCommunityFeed(communityId!);
      final items = result['items'] as List<CommunityPost>;
      nextCursor = result['next_cursor']?.toString();
      hasMore = result['has_more'] == true;

      final remoteIds = items.map((post) => post.id).toSet();
      final pendingLocalPosts = posts.where((post) => post.isPublishing && !remoteIds.contains(post.id)).toList();
      posts.value = [...pendingLocalPosts, ...items];
      errorMessage.value = '';

      if (items.isEmpty) {
        feedState.value = CommunityFeedState.empty;
      } else {
        feedState.value = CommunityFeedState.loaded;
      }
    } catch (e, st) {
      debugPrint('[COMMUNITY_FEED] Error fetching community feed: $e\n$st');
      String msg = e.toString().replaceFirst('Exception: ', '').tr;
      if (e is PostgrestException) {
        msg = e.message;
      }
      errorMessage.value = msg;

      if (posts.isNotEmpty) {
        feedState.value = CommunityFeedState.loaded;
        Get.snackbar(
          'error'.tr,
          msg,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      } else {
        feedState.value = CommunityFeedState.error;
      }
    }
  }

  Future<void> loadMorePosts() async {
    if (isLoadingMore || !hasMore || nextCursor == null || communityId == null) return;
    isLoadingMore = true;

    try {
      debugPrint('[COMMUNITY_FEED] Loading more posts for communityId=$communityId, cursor=$nextCursor');
      final result = await _feedRepo.getCommunityFeed(communityId!, cursor: nextCursor);
      final items = result['items'] as List<CommunityPost>;
      nextCursor = result['next_cursor']?.toString();
      hasMore = result['has_more'] == true;

      final existingIds = posts.map((p) => p.id).toSet();
      final uniqueNew = items.where((p) => !existingIds.contains(p.id)).toList();
      posts.addAll(uniqueNew);
    } catch (e) {
      debugPrint('[COMMUNITY_FEED] Error loading more posts: $e');
    } finally {
      isLoadingMore = false;
    }
  }

  List<PostComment> getCommentsForPost(String postId) => commentsByPostId[postId] ?? [];

  Future<void> createPost({
    String? content,
    List<File>? imageFiles,
    String? audience,
    bool commentsEnabled = true,
    bool sharingEnabled = true,
    bool reactionsEnabled = true,
    List<String>? hashtags,
    List<String>? mentions,
    Map<String, dynamic>? poll,
    bool allowPromotion = true,
  }) async {
    final tempId = _generateUuidV4();
    final newPost = CommunityPost(
      id: tempId,
      authorName: 'Moi',
      authorId: 'me',
      authorColor: Colors.purple,
      authorRole: CommunityRole.member,
      timeAgo: 'publication_in_progress'.tr,
      content: content ?? '',
      media: imageFiles != null ? imageFiles.map((f) => PostMedia(type: 'photo', url: f.path)).toList() : [],
      likeCount: 0,
      commentCount: 0,
      shareCount: 0,
      isPublishing: true,
      poll: poll,
    );
    posts.insert(0, newPost);

    try {
      final service = Get.isRegistered<CommunityService>() ? Get.find<CommunityService>() : Get.put(CommunityService(Get.find(), Get.find()));
      await service.createCommunityPost(
        communityId: communityId ?? '',
        requestedPostId: tempId,
        content: content,
        imageFiles: imageFiles,
        audience: audience,
        commentsEnabled: commentsEnabled,
        sharingEnabled: sharingEnabled,
        reactionsEnabled: reactionsEnabled,
        hashtags: hashtags,
        mentions: mentions,
        poll: poll,
        allowPromotion: allowPromotion,
      );
      await fetchCommunityFeed(isRefresh: true);
    } catch (e) {
      posts.removeWhere((post) => post.id == tempId);
      posts.refresh();
      debugPrint('[POST] [Controller] createPost error: $e');
      Get.snackbar('error'.tr, e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  PostComment _commentFromMap(Map<String, dynamic> map) {
    final author = map['author'] is Map
        ? Map<String, dynamic>.from(map['author'] as Map)
        : <String, dynamic>{};
    final authorId = (map['author_id'] ?? map['user_id'] ?? author['user_id'] ?? author['id'] ?? '').toString();
    return PostComment(
      id: (map['id'] ?? map['comment_id'] ?? '').toString(),
      authorName: (map['author_name'] ?? author['display_name'] ?? author['username'] ?? 'Utilisateur').toString(),
      authorId: authorId,
      authorColor: authorId == currentUserId ? Colors.purple : Colors.blue,
      avatarUrl: (map['avatar_url'] ?? map['photo_url'] ?? author['avatar_url'] ?? author['photo_url'])?.toString(),
      timeAgo: (map['created_at'] ?? map['time_ago'] ?? '').toString(),
      content: (map['content'] ?? map['text'] ?? '').toString(),
      likesCount: (map['likes_count'] as num?)?.toInt() ?? 0,
      repliesCount: (map['replies_count'] as num?)?.toInt() ?? 0,
      isCertified: map['is_certified'] == true || author['is_certified'] == true,
      isOp: map['is_op'] == true || map['is_author'] == true,
    );
  }

  Future<void> loadCommentsForPost(String postId) async {
    commentsLoading[postId] = true;
    try {
      final result = await _feedRepo.getCommunityPostComments(postId);
      final rawItems = result['items'] ?? result['data'] ?? [];
      final parsed = rawItems is List
          ? rawItems.whereType<Map>().map((item) => _commentFromMap(Map<String, dynamic>.from(item))).where((item) => item.id.isNotEmpty).toList()
          : <PostComment>[];
      commentsByPostId[postId] = parsed;
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error loading comments for $postId: $e');
      Get.snackbar('error'.tr, e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM);
    } finally {
      commentsLoading[postId] = false;
      commentsByPostId.refresh();
    }
  }

  Future<void> addCommentToPost(String postId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (currentUserId == null) {
      Get.snackbar('error'.tr, 'authentication_required'.tr, snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final localId = _generateUuidV4();
    final list = commentsByPostId[postId] ?? [];
    final newComment = PostComment(
      id: localId,
      authorName: 'Moi',
      authorId: currentUserId!,
      authorColor: Colors.purple,
      timeAgo: 'just_now'.tr,
      content: trimmed,
    );
    commentsByPostId[postId] = [newComment, ...list];
    _incrementCommentCount(postId, 1);

    try {
      final result = await _feedRepo.commentCommunityPost(
        p_id: localId,
        postId: postId,
        content: trimmed,
      );
      final serverId = (result['id'] ?? result['comment_id'] ?? localId).toString();
      final updated = commentsByPostId[postId] ?? [];
      final index = updated.indexWhere((comment) => comment.id == localId);
      if (index != -1 && serverId != localId) {
        updated[index] = PostComment(
          id: serverId,
          authorName: newComment.authorName,
          authorId: newComment.authorId,
          authorColor: newComment.authorColor,
          timeAgo: newComment.timeAgo,
          content: newComment.content,
        );
        commentsByPostId[postId] = List<PostComment>.from(updated);
      }
    } catch (e) {
      commentsByPostId[postId] = (commentsByPostId[postId] ?? []).where((c) => c.id != localId).toList();
      _incrementCommentCount(postId, -1);
      Get.snackbar('error'.tr, e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> addReplyToComment(String postId, String commentId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (currentUserId == null) {
      Get.snackbar('error'.tr, 'authentication_required'.tr, snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final localId = _generateUuidV4();
    final list = repliesByCommentId[commentId] ?? [];
    final newReply = PostComment(
      id: localId,
      authorName: 'Moi',
      authorId: currentUserId!,
      authorColor: Colors.purple,
      timeAgo: 'just_now'.tr,
      content: trimmed,
    );
    repliesByCommentId[commentId] = [...list, newReply];
    try {
      final result = await _feedRepo.replyToCommunityComment(
        p_id: localId,
        commentId: commentId,
        content: trimmed,
      );
      final serverId = (result['id'] ?? result['comment_id'] ?? localId).toString();
      if (serverId != localId) {
        repliesByCommentId[commentId] = (repliesByCommentId[commentId] ?? []).map((reply) {
          if (reply.id != localId) return reply;
          return PostComment(
            id: serverId,
            authorName: newReply.authorName,
            authorId: newReply.authorId,
            authorColor: newReply.authorColor,
            timeAgo: newReply.timeAgo,
            content: newReply.content,
          );
        }).toList();
      }
    } catch (e) {
      repliesByCommentId[commentId] = (repliesByCommentId[commentId] ?? []).where((reply) => reply.id != localId).toList();
      Get.snackbar('error'.tr, e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  void _incrementCommentCount(String postId, int delta) {
    final index = posts.indexWhere((post) => post.id == postId);
    if (index == -1) return;
    final post = posts[index];
    posts[index] = post.copyWith(commentCount: (post.commentCount + delta).clamp(0, 1 << 30).toInt());
    posts.refresh();
  }

  Future<void> toggleCommentReaction(String postId, String commentId, PostReaction reaction) async {
    final list = commentsByPostId[postId];
    if (list == null) return;
    final index = list.indexWhere((comment) => comment.id == commentId);
    if (index == -1) return;

    final comment = list[index];
    final nextReaction = comment.userReaction == reaction ? PostReaction.none : reaction;
    final nextCount = (comment.likesCount + (comment.userReaction == PostReaction.like ? -1 : 0) + (nextReaction == PostReaction.like ? 1 : 0)).clamp(0, 1 << 30).toInt();
    list[index] = comment.copyWith(userReaction: nextReaction, likesCount: nextCount);
    commentsByPostId.refresh();

    try {
      await _feedRepo.setCommentReaction(commentId, nextReaction == PostReaction.like ? 'like' : (nextReaction == PostReaction.dislike ? 'dislike' : null));
    } catch (e) {
      list[index] = comment;
      commentsByPostId.refresh();
      Get.snackbar('error'.tr, e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> loadRepliesForComment(String commentId) async {
    loadingRepliesByCommentId[commentId] = true;
    try {
      final result = await _feedRepo.getCommunityCommentReplies(commentId);
      final rawItems = result['items'] ?? result['data'] ?? [];
      repliesByCommentId[commentId] = rawItems is List
          ? rawItems.whereType<Map>().map((item) => _commentFromMap(Map<String, dynamic>.from(item))).where((item) => item.id.isNotEmpty).toList()
          : <PostComment>[];
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error loading replies for $commentId: $e');
      Get.snackbar('error'.tr, e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM);
    } finally {
      loadingRepliesByCommentId[commentId] = false;
      repliesByCommentId.refresh();
    }
  }

  void deleteComment(String postId, String commentId) {
    final list = commentsByPostId[postId];
    if (list != null) {
      list.removeWhere((c) => c.id == commentId);
      commentsByPostId.refresh();
    }
  }

  void sharePost(CommunityPost post) {
    Get.snackbar('Partage', 'Publication partagée avec succès', snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> deletePost(String postId, {String? reason}) async {
    debugPrint('[DELETE] [Controller] Deleting community post postId=$postId');
    final oldPosts = List<CommunityPost>.from(posts);
    posts.removeWhere((p) => p.id == postId);
    posts.refresh();

    try {
      await _feedRepo.deletePost(postId, reason: reason);
      Get.snackbar('Succès', 'Publication supprimée', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[DELETE] [Controller] Error deleting community post: $e');
      posts.value = oldPosts;
      posts.refresh();
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> handleReaction(String postId, PostReaction reaction) async {
    final index = posts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final post = posts[index];
      if (post.isPublishing) return;
      final newReaction = post.userReaction == reaction ? PostReaction.none : reaction;
      int likes = post.likeCount;
      int dislikes = post.dislikeCount;

      if (post.userReaction == PostReaction.like) likes--;
      if (post.userReaction == PostReaction.dislike) dislikes--;
      if (newReaction == PostReaction.like) likes++;
      if (newReaction == PostReaction.dislike) dislikes++;

      posts[index] = post.copyWith(
        userReaction: newReaction,
        likeCount: likes,
        dislikeCount: dislikes,
      );
      posts.refresh();

      try {
        final reactionStr = newReaction == PostReaction.like ? 'like' : (newReaction == PostReaction.dislike ? 'dislike' : null);
        await _feedRepo.setCommunityPostReaction(postId, reactionStr);
      } catch (e) {
        debugPrint('[POST_ACTIONS] Error reacting to community post: $e');
        posts[index] = post;
        posts.refresh();
        Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      }
    }
  }
}
