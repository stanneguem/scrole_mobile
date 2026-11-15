import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'package:scrole/modules/module_evenement/centre/repositories/event_repository.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_model.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_outbox_processor.dart';
import 'package:scrole/app/local_storage/structured/app_cache_database.dart';
import 'package:scrole/app/local_storage/fast/fast_cache_key.dart';
import 'package:scrole/app/local_storage/fast/fast_cache_service.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/utils/supabase_error_mapper.dart';
import 'package:scrole/modules/module_discussion_direct/externe/repositories/social_repository.dart';
import 'package:uuid/uuid.dart';

enum HomeFeedState { initial, loading, loaded, empty, error, loadingMore }

class HomeFeedController extends GetxController {
  late final HomeFeedRepository _feedRepo;
  late final EventRepository _eventRepo;
  final AuthService _authService = Get.find<AuthService>();
  final AppDatabase _db = Get.find<AppDatabase>();
  FastCacheService? get _fastCache =>
      Get.isRegistered<FastCacheService>() ? Get.find<FastCacheService>() : null;
  static const int _homeFeedCacheLimit = 15;

  final Rx<HomeFeedState> state = HomeFeedState.initial.obs;
  final RxList<CommunityPost> posts = <CommunityPost>[].obs;
  final RxList<CommunityPost> sponsoredPosts = <CommunityPost>[].obs;
  final RxList<SuggestedProfileModel> suggestedProfiles = <SuggestedProfileModel>[].obs;
  final RxList<EventModel> suggestedEvents = <EventModel>[].obs;
  final RxString errorMessage = ''.obs;
  final RxBool hasMore = true.obs;
  final RxBool isRefreshing = false.obs;
  final RxBool isLoadingMore = false.obs;
  final RxString nextCursor = ''.obs;

  final Map<String, DateTime> _activeDwellStartedAt = {};
  final List<Map<String, dynamic>> _pendingDwellItems = [];
  Timer? _dwellBatchTimer;

  final Set<String> _sentViewIds = {};
  // Counter snapshots for reel items whose original post is not in the loaded home feed (e.g. reposts).
  final RxMap<String, CommunityPost> reelPostOverrides = <String, CommunityPost>{}.obs;
  final Map<String, CommunityPost> _qualifiedVideoPosts = {};
  final List<String> _pendingViewIds = [];
  Timer? _viewBatchTimer;
  Timer? _counterRefreshTimer;
  bool _refreshingVisibleCounters = false;

  // Protect against duplicate HomeFeedController instances issuing the same
  // periodic counters RPC at the same time.
  static bool _postCountersRequestInFlight = false;
  static DateTime? _lastPostCountersRequestAt;

  Future<List<Map<String, dynamic>>> _requestPostCounters(List<String> ids) async {
    if (ids.isEmpty || _postCountersRequestInFlight) return const [];
    final now = DateTime.now();
    final lastRequest = _lastPostCountersRequestAt;
    // Multiple feed controllers can exist briefly during route transitions.
    // Coalesce their identical refreshes instead of flooding Supabase.
    if (lastRequest != null && now.difference(lastRequest) < const Duration(seconds: 8)) {
      return const [];
    }
    _postCountersRequestInFlight = true;
    _lastPostCountersRequestAt = now;
    try {
      return await _feedRepo.getPostCounters(ids);
    } finally {
      _postCountersRequestInFlight = false;
    }
  }

  void startPostDwell(CommunityPost post) {
    if (post.isPublishing || post.id.isEmpty) return;
    final myId = _authService.userId;
    if (myId != null && post.authorId == myId) return;
    _activeDwellStartedAt.putIfAbsent(post.id, DateTime.now);
  }

  void stopPostDwell(String postId) {
    final startedAt = _activeDwellStartedAt.remove(postId);
    if (startedAt == null) return;
    final dwellMs = DateTime.now().difference(startedAt).inMilliseconds;
    if (dwellMs <= 0) return;
    _pendingDwellItems.add({'post_id': postId, 'dwell_ms': dwellMs});
    if (_pendingDwellItems.length >= 100) {
      unawaited(_flushPostDwell());
    } else {
      _dwellBatchTimer ??= Timer(const Duration(seconds: 5), _flushPostDwell);
    }
  }

  Future<void> _flushPostDwell() async {
    _dwellBatchTimer?.cancel();
    _dwellBatchTimer = null;
    while (_pendingDwellItems.isNotEmpty) {
      final count = _pendingDwellItems.length > 100 ? 100 : _pendingDwellItems.length;
      final batch = _pendingDwellItems.take(count).toList();
      _pendingDwellItems.removeRange(0, count);
      try {
        final recorded = await _feedRepo.recordPostDwell(batch);
        debugPrint('[POST_DWELL] Recorded dwell for $recorded/${batch.length} posts');
      } catch (e) {
        debugPrint('[POST_DWELL] Batch failed and was dropped: $e');
      }
    }
  }

  bool _containsVideo(CommunityPost post) =>
      post.media.any((media) => media.isVideo) ||
      (post.sharedPost?.media.any((media) => media.isVideo) ?? false);

  void queuePostView(CommunityPost post) {
    // Video views are recorded only after 25% of effective playback.
    if (_containsVideo(post)) return;
    _queuePostViewId(post.id, post);
  }

  void queueQualifiedVideoPostView(String postId, CommunityPost post) {
    _qualifiedVideoPosts[postId] = post;
    _queuePostViewId(postId, post);
  }

  /// Refreshes the counters for a reel's original post, including originals
  /// that are only present inside a repost and not in [posts].
  Future<void> refreshPostCountersFor(CommunityPost post) async {
    if (post.id.isEmpty) return;
    try {
      final counters = await _feedRepo.getPostCounters([post.id]);
      if (counters.isEmpty) return;
      final c = counters.first;
      final updated = post.copyWith(
        viewCount: (c['views_count'] as num?)?.toInt() ?? post.viewCount,
        likeCount: (c['likes_count'] as num?)?.toInt() ?? post.likeCount,
        dislikeCount: (c['dislikes_count'] as num?)?.toInt() ?? post.dislikeCount,
        commentCount: (c['comments_count'] as num?)?.toInt() ?? post.commentCount,
        shareCount: (c['shares_count'] as num?)?.toInt() ?? post.shareCount,
      );
      reelPostOverrides[post.id] = updated;
      final idx = posts.indexWhere((item) => item.id == post.id);
      if (idx != -1) posts[idx] = updated;
      final sponsoredIdx = sponsoredPosts.indexWhere((item) => item.id == post.id);
      if (sponsoredIdx != -1) sponsoredPosts[sponsoredIdx] = updated;
      posts.refresh();
      sponsoredPosts.refresh();
    } catch (e) {
      debugPrint('[POST_ACTIONS] Reel counter refresh failed for ${post.id}: $e');
    }
  }

  void _queuePostViewId(String postId, CommunityPost post) {
    if (post.isPublishing || postId.isEmpty) return;
    final myId = _authService.userId;
    if (myId != null && post.authorId == myId) return;
    if (_sentViewIds.contains(postId)) return;
    if (_pendingViewIds.contains(postId)) return;

    _pendingViewIds.add(postId);
    _sentViewIds.add(postId);

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
      debugPrint('[POST_ACTIONS] Sending view batch of ${batch.length} posts');
      await _feedRepo.recordPostViews(batch);

      final counters = await _requestPostCounters(batch);
      if (counters.isNotEmpty) {
        for (final c in counters) {
          final id = c['id']?.toString();
          if (id == null) continue;
          final idx = posts.indexWhere((p) => p.id == id);
          final base = idx != -1 ? posts[idx] : _qualifiedVideoPosts[id];
          if (base != null) {
            final updated = base.copyWith(
              viewCount: (c['views_count'] as num?)?.toInt() ?? base.viewCount,
              likeCount: (c['likes_count'] as num?)?.toInt() ?? base.likeCount,
              dislikeCount: (c['dislikes_count'] as num?)?.toInt() ?? base.dislikeCount,
              commentCount: (c['comments_count'] as num?)?.toInt() ?? base.commentCount,
              shareCount: (c['shares_count'] as num?)?.toInt() ?? base.shareCount,
            );
            reelPostOverrides[id] = updated;
            if (idx != -1) posts[idx] = updated;
          }
        }
        posts.refresh();
        unawaited(_cacheCurrentFeed());
      }
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error recording view batch or fetching counters: $e');
    }
  }

  String? _campaignIdFromSponsoredPost(String postId) => postId.startsWith('promotion_') ? postId.substring('promotion_'.length) : null;

  Future<void> recordSponsoredImpression(CommunityPost post) async {
    final id = _campaignIdFromSponsoredPost(post.id);
    if (!post.isSponsored || id == null || id.isEmpty) return;
    await _feedRepo.recordPromotionImpression(id);
  }

  Future<void> recordSponsoredInteraction(CommunityPost post, {String type = 'click'}) async {
    final id = _campaignIdFromSponsoredPost(post.id);
    if (!post.isSponsored || id == null || id.isEmpty) return;
    await _feedRepo.recordPromotionInteraction(id, type);
  }

  Future<void> _refreshVisibleCounters() async {
    if (_refreshingVisibleCounters || posts.isEmpty || state.value != HomeFeedState.loaded) return;
    final ids = posts.take(50).map((p) => p.id).toSet().toList();
    if (ids.isEmpty) return;
    _refreshingVisibleCounters = true;
    try {
      final counters = await _requestPostCounters(ids);
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
        unawaited(_cacheCurrentFeed());
      }
    } catch (e) {
      debugPrint('[POST_ACTIONS] Counter refresh failed; will retry on next interval: $e');
    } finally {
      _refreshingVisibleCounters = false;
    }
  }

  @override
  void onInit() {
    super.onInit();
    _feedRepo = HomeFeedRepository();
    try {
      _eventRepo = Get.find<EventRepository>();
    } catch (_) {
      _eventRepo = Get.put<EventRepository>(
        EventRepository(Get.find(), Get.find()),
        permanent: true,
      );
    }
    fetchFeed();
    _counterRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshVisibleCounters());
  }

  @override
  void onClose() {
    _dwellBatchTimer?.cancel();
    for (final postId in _activeDwellStartedAt.keys.toList()) {
      stopPostDwell(postId);
    }
    unawaited(_flushPostDwell());
    _viewBatchTimer?.cancel();
    _counterRefreshTimer?.cancel();
    _flushViewBatch();
    for (final t in _reactionDebouncers.values) {
      t.cancel();
    }
    _reactionDebouncers.clear();
    super.onClose();
  }

  String eventAgendaRestrictionMessageKey(Object error) => _eventRepo.agendaRestrictionMessageKey(error);

  final Set<String> _profileSuggestionActionsInFlight = {};

  Future<void> followSuggestedProfile(SuggestedProfileModel profile) async {
    if (profile.id.isEmpty || !_profileSuggestionActionsInFlight.add(profile.id)) return;
    try {
      final relation = await SocialRepository().followUser(profile.id);
      final state = (relation['state'] ?? '').toString();
      profile.isAdded = state == 'friends' || state == 'following' || relation['is_following'] == true;
      profile.isRequestSent = state == 'requested' || relation['request_sent'] == true;
      suggestedProfiles.refresh();
      if (!profile.isAdded && !profile.isRequestSent) {
        throw StateError('Le suivi n’a pas été confirmé');
      }
    } finally {
      _profileSuggestionActionsInFlight.remove(profile.id);
    }
  }

  Future<void> dismissSuggestedProfile(SuggestedProfileModel profile) async {
    if (profile.id.isEmpty || !_profileSuggestionActionsInFlight.add(profile.id)) return;
    try {
      await _feedRepo.dismissSuggestedProfile(profile.id);
      suggestedProfiles.removeWhere((item) => item.id == profile.id);
    } finally {
      _profileSuggestionActionsInFlight.remove(profile.id);
    }
  }

  void removeSuggestedEvent(String eventId) {
    suggestedEvents.removeWhere((event) => event.id == eventId);
  }

  Future<void> dismissSuggestedEvent(String eventId) async {
    await _eventRepo.dismissHomeEventSuggestion(eventId);
    removeSuggestedEvent(eventId);
  }

  Future<void> fetchFeed({bool refresh = false}) async {
    if (refresh) {
      isRefreshing.value = true;
    } else if (posts.isEmpty) {
      state.value = HomeFeedState.loading;
    }

    try {
      final userId = _authService.userId;
      if (userId == null) {
        state.value = HomeFeedState.empty;
        isRefreshing.value = false;
        return;
      }

      // 1. Cache-first loading. Pending outbox entries are represented by
      // the publishing progress bar above Stories, never by incomplete feed cards.
      if (!refresh) {
        await _loadCachedFeedAndOutbox(userId);
      }

      debugPrint('[HOME_FEED] fetchFeed started with refresh=$refresh');

      // 2. Remote fetch via get_home_feed RPC
      final result = await _feedRepo.getHomeFeed(limit: 20, cursor: null);
      final remoteItems = result['items'] as List<CommunityPost>;
      nextCursor.value = result['next_cursor']?.toString() ?? '';
      hasMore.value = result['has_more'] == true;

      debugPrint('[HOME_FEED] Fetched remote items count: ${remoteItems.length}, next_cursor=${nextCursor.value}, has_more=${hasMore.value}');

      // Count item types for logs
      int postTypeCount = remoteItems.where((p) => p.communityId == null).length;
      int communityPostCount = remoteItems.where((p) => p.communityId != null).length;
      debugPrint('[HOME_FEED] Item counts per type -> Standard Posts: $postTypeCount, Community Posts: $communityPostCount');

      final immediatelyCountableIds = remoteItems
          .where((post) => !_containsVideo(post))
          .map((post) => post.id)
          .toList();
      if (immediatelyCountableIds.isNotEmpty) {
        unawaited(_feedRepo.recordPostViews(immediatelyCountableIds));
      }

      // Only fully-created posts are displayed in the feed.
      final Map<String, CommunityPost> uniqueMap = {};
      for (final post in remoteItems) {
        uniqueMap[post.id] = post;
      }
      posts.value = uniqueMap.values.toList();

      // Keep the first 15 complete cards available for the next cold start.
      // Cache only after the new feed has been installed in memory.
      await _cacheFeedItems(userId, remoteItems);

      // Fetch suggested profiles and suggested events
      try {
        final profiles = await _feedRepo.getSuggestedProfiles(limit: 10);
        suggestedProfiles.assignAll(profiles);
        debugPrint('[HOME_FEED] Suggested profiles count: ${profiles.length}');
      } catch (e) {
        debugPrint('[HOME_FEED] Error fetching suggested profiles: $e');
      }

      try {
        final events = await _eventRepo.getSuggestedEvents(forceRefresh: refresh);
        suggestedEvents.assignAll(events);
        debugPrint('[HOME_FEED] Suggested events count: ${events.length}');
      } catch (e) {
        debugPrint('[HOME_FEED] Error fetching suggested events: $e');
      }

      // Ads are loaded separately from organic posts. Targeting and expiry
      // are enforced by get_targeted_promotion_campaigns() in PostgreSQL.
      try {
        final campaigns = await _feedRepo.getTargetedPromotionCampaigns(limit: 10);
        sponsoredPosts.assignAll(campaigns);
        debugPrint('[PROMOTIONS] Loaded ${campaigns.length} eligible campaigns');
      } catch (e) {
        debugPrint('[PROMOTIONS] Campaign loading skipped: $e');
        sponsoredPosts.clear();
      }

      state.value = posts.isEmpty ? HomeFeedState.empty : HomeFeedState.loaded;
    } catch (e, st) {
      debugPrint('[HOME_FEED] Error in fetchFeed: $e\n$st');
      if (posts.isNotEmpty) {
        state.value = HomeFeedState.loaded;
      } else {
        final appError = mapSupabaseError(e);
        errorMessage.value = appError.message;
        state.value = HomeFeedState.error;
      }
    } finally {
      isRefreshing.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value || nextCursor.value.isEmpty) return;
    isLoadingMore.value = true;

    try {
      debugPrint('[HOME_FEED] Loading more feed with cursor: ${nextCursor.value}');
      final result = await _feedRepo.getHomeFeed(limit: 20, cursor: nextCursor.value);
      final moreItems = result['items'] as List<CommunityPost>;
      nextCursor.value = result['next_cursor']?.toString() ?? '';
      hasMore.value = result['has_more'] == true;

      debugPrint('[HOME_FEED] Loaded more items count: ${moreItems.length}, next_cursor=${nextCursor.value}, has_more=${hasMore.value}');

      if (moreItems.isNotEmpty) {
        final existingIds = posts.map((p) => p.id).toSet();
        final newItems = moreItems.where((p) => !existingIds.contains(p.id)).toList();
        posts.addAll(newItems);
        unawaited(_cacheCurrentFeed());
      }
    } catch (e) {
      debugPrint('[HOME_FEED] Error in loadMore: $e');
    } finally {
      isLoadingMore.value = false;
    }
  }

  /// Removes a post that has just been reported. The report_content RPC
  /// already persisted the per-user hide, so this only updates memory/cache.
  void onPostReported(String postId) {
    posts.removeWhere((post) => post.id == postId);
    unawaited(_cacheCurrentFeed());
  }

  Future<void> hidePost(String postId) async {
    try {
      debugPrint('[HOME_FEED] Hiding post $postId locally and calling RPC hide_post');
      posts.removeWhere((p) => p.id == postId);
      await _feedRepo.hidePost(postId);
      await _cacheCurrentFeed();
      Get.snackbar('Succès', 'Publication masquée', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[HOME_FEED] Error hiding post $postId: $e');
      final appError = mapSupabaseError(e);
      showAppErrorDialog(Get.context!, appError.message);
    }
  }

  Future<void> _loadCachedFeedAndOutbox(String userId) async {
    try {
      final cachedRows = _fastCache?.get<List<dynamic>>(
        FastCacheKey.homeFeed(userId),
      );
      final cachedPosts = <CommunityPost>[];
      if (cachedRows != null) {
        for (final row in cachedRows.take(_homeFeedCacheLimit)) {
          if (row is! Map) continue;
          try {
            final data = Map<String, dynamic>.from(row);
            final post = CommunityPost.fromMap(data);
            if (post.id.isNotEmpty) cachedPosts.add(post);
          } catch (e) {
            debugPrint('[HOME_FEED] Ignoring invalid cached post: $e');
          }
        }
      }

      // Render cached cards immediately; do not wait for the outbox DB read.
      if (cachedPosts.isNotEmpty) {
        posts.assignAll(cachedPosts);
        state.value = HomeFeedState.loaded;
      }

      if (cachedPosts.isNotEmpty) {
        posts.assignAll(cachedPosts);
        state.value = HomeFeedState.loaded;
      }
      debugPrint(
        '[HOME_FEED] Restored ${cachedPosts.length}/$_homeFeedCacheLimit complete cached cards.',
      );
    } catch (e, st) {
      debugPrint('[HOME_FEED] Error loading complete cached feed: $e\\n$st');
    }
  }

  Future<void> _cacheFeedItems(String userId, List<CommunityPost> items) async {
    try {
      final unique = <String, CommunityPost>{};
      for (final post in items) {
        if (post.id.isNotEmpty && !post.isPublishing) unique[post.id] = post;
      }
      final snapshot = unique.values
          .take(_homeFeedCacheLimit)
          .map((post) => post.toCacheMap())
          .toList(growable: false);
      await _fastCache?.set(FastCacheKey.homeFeed(userId), snapshot);
      debugPrint(
        '[HOME_FEED] Saved ${snapshot.length} complete cards in the offline cache.',
      );
    } catch (e, st) {
      debugPrint('[HOME_FEED] Error caching complete feed cards: $e\\n$st');
    }
  }

  Future<void> _cacheCurrentFeed() async {
    final userId = _authService.userId;
    if (userId == null) return;
    final visiblePosts = posts.where((post) => !post.isPublishing).toList();
    await _cacheFeedItems(userId, visiblePosts);
  }

  final Map<String, Timer> _reactionDebouncers = {};

  Future<void> retryQueuedPost(String postId) async {
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      final db = await _db.database;
      final rows = await db.query(
        'post_outbox',
        columns: ['id'],
        where: 'user_id = ? AND operation_id = ? AND status = ?',
        whereArgs: [userId, postId, 'failed'],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await db.update(
        'post_outbox',
        {'status': 'pending', 'attempt_count': 0, 'next_retry_at': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
      if (!Get.isRegistered<CommunityOutboxProcessor>()) {
        Get.put(CommunityOutboxProcessor());
      }
      unawaited(Get.find<CommunityOutboxProcessor>().processPendingPosts());
      await fetchFeed(refresh: true);
    } catch (e) {
      debugPrint('[HOME_FEED] Retry queued post failed postId=$postId error=$e');
      Get.snackbar('Réessai impossible', e.toString().replaceFirst('Exception: ', ''), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> handleReaction(String postId, PostReaction reaction, {CommunityPost? fallbackPost}) async {
    final index = posts.indexWhere((p) => p.id == postId);
    final post = index == -1
        ? (reelPostOverrides[postId] ?? fallbackPost)
        : posts[index];
    if (post == null) return;
    if (post.isPublishing) return;

    final newReaction = post.userReaction == reaction ? PostReaction.none : reaction;
    int likes = post.likeCount;
    int dislikes = post.dislikeCount;

    if (post.userReaction == PostReaction.like) likes--;
    if (post.userReaction == PostReaction.dislike) dislikes--;
    if (newReaction == PostReaction.like) likes++;
    if (newReaction == PostReaction.dislike) dislikes++;

    final updatedPost = post.copyWith(
      userReaction: newReaction,
      likeCount: likes,
      dislikeCount: dislikes,
    );
    reelPostOverrides[postId] = updatedPost;
    if (index != -1) {
      posts[index] = updatedPost;
      posts.refresh();
      unawaited(_cacheCurrentFeed());
    }

    _reactionDebouncers[postId]?.cancel();

    _reactionDebouncers[postId] = Timer(const Duration(milliseconds: 600), () async {
      _reactionDebouncers.remove(postId);
      try {
        final reactionStr = newReaction == PostReaction.like ? 'like' : (newReaction == PostReaction.dislike ? 'dislike' : null);
        await _feedRepo.setCommunityPostReaction(postId, reactionStr);
      } catch (e) {
        debugPrint('[POST_ACTIONS] Error reacting to post: $e');
        if (!isClosed) {
          final curIdx = posts.indexWhere((p) => p.id == postId);
          reelPostOverrides[postId] = post;
          if (curIdx != -1) {
            posts[curIdx] = post;
            posts.refresh();
            unawaited(_cacheCurrentFeed());
          }
          Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
        }
      }
    });
  }

  Future<void> sharePost({
    required String originalPostId,
    String? communityId,
    String audience = 'public',
    String? comment,
  }) async {
    final pId = const Uuid().v4();
    debugPrint('[POST_ACTIONS] Sharing post original=$originalPostId, community=$communityId, audience=$audience');

    try {
      await _feedRepo.sharePost(
        p_id: pId,
        p_original_post_id: originalPostId,
        p_community_id: communityId,
        p_audience: audience,
        p_comment: comment,
      );
      await fetchFeed(refresh: true);
      Get.snackbar('Succès', 'Publication partagée avec succès !', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error sharing post: $e');
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> deletePost(String postId, {String? reason}) async {
    debugPrint('[DELETE] [Controller] Deleting post postId=$postId');
    final oldPosts = List<CommunityPost>.from(posts);
    posts.removeWhere((p) => p.id == postId);
    posts.refresh();

    try {
      await _feedRepo.deletePost(postId, reason: reason);
      await _cacheCurrentFeed();
      Get.snackbar('Succès', 'Publication supprimée', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[DELETE] [Controller] Error deleting post: $e');
      posts.value = oldPosts;
      posts.refresh();
      unawaited(_cacheCurrentFeed());
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
}
