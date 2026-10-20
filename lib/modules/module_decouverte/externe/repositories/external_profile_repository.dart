import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/local_storage/fast/fast_cache_key.dart';
import '../../../../app/local_storage/fast/fast_cache_service.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../../../module_discussion_direct/centre/persistence/social_local_dao.dart';
import '../../../module_discussion_direct/externe/repositories/social_repository.dart';
import '../../centre/models/external_profile_model.dart';

enum ProfileResultStatus {
  loaded,
  deleted,
  notFound,
  suspended,
  banned,
  error,
}

class ExternalProfileResult {
  final ProfileResultStatus status;
  final ExternalProfileModel? profile;
  final String? errorMessage;

  const ExternalProfileResult({
    required this.status,
    this.profile,
    this.errorMessage,
  });
}

class ExternalProfileRepository {
  final _client = Get.find<SupabaseService>().client;
  final SocialRepository _socialRepo = SocialRepository();

  FastCacheService? get _cache =>
      Get.isRegistered<FastCacheService>() ? Get.find<FastCacheService>() : null;

  static const Duration _cacheTtl = Duration(minutes: 5);

  Future<ExternalProfileResult> getProfileResult(String userId) async {
    final cacheKey = FastCacheKey.externalProfile(userId);

    // 1. Check if a valid (< 5 min) cached profile exists
    final cachedMap = _cache?.get<Map<String, dynamic>>(cacheKey, maxAge: _cacheTtl);
    if (cachedMap != null && cachedMap.isNotEmpty) {
      debugPrint('[ExternalProfileRepository] Returning valid 5-min cache for $userId');
      return ExternalProfileResult(
        status: ProfileResultStatus.loaded,
        profile: ExternalProfileModel.fromJson(cachedMap),
      );
    }

    // 2. Request fresh data from backend RPC get_external_profile
    Map<String, dynamic>? rawJson;
    ProfileResultStatus? explicitStatus;

    try {
      final response = await _client.rpc('get_external_profile', params: {'p_user_id': userId});

      if (response is Map) {
        final errStr = (response['error'] ?? response['code'] ?? response['message'] ?? '').toString().toLowerCase();
        if (errStr.contains('profile_deleted') || response['status'] == 'deleted') {
          explicitStatus = ProfileResultStatus.deleted;
        } else if (errStr.contains('profile_suspended') || response['status'] == 'suspended') {
          explicitStatus = ProfileResultStatus.suspended;
          if (response['user_id'] != null) rawJson = Map<String, dynamic>.from(response);
        } else if (errStr.contains('profile_banned') || response['status'] == 'banned') {
          explicitStatus = ProfileResultStatus.banned;
          if (response['user_id'] != null) rawJson = Map<String, dynamic>.from(response);
        } else if (errStr.contains('profile_not_found') || response['status'] == 'not_found') {
          explicitStatus = ProfileResultStatus.notFound;
        } else if (response['user_id'] != null) {
          rawJson = Map<String, dynamic>.from(response);
          explicitStatus = ProfileResultStatus.loaded;
        }
      }
    } on PostgrestException catch (e) {
      debugPrint('[ExternalProfileRepository] PostgrestException in get_external_profile for $userId: code=${e.code}, msg=${e.message}, details=${e.details}');
      final fullMsg = '${e.message} ${e.details} ${e.code}'.toLowerCase();
      if (fullMsg.contains('profile_deleted') || fullMsg.contains('account_deleted')) {
        explicitStatus = ProfileResultStatus.deleted;
      } else if (fullMsg.contains('profile_suspended') || fullMsg.contains('account_suspended')) {
        explicitStatus = ProfileResultStatus.suspended;
      } else if (fullMsg.contains('profile_banned') || fullMsg.contains('account_banned')) {
        explicitStatus = ProfileResultStatus.banned;
      } else if (fullMsg.contains('profile_not_found') || fullMsg.contains('pgrst116') || e.code == 'PGRST116') {
        explicitStatus = ProfileResultStatus.notFound;
      }
    } catch (e) {
      debugPrint('[ExternalProfileRepository] RPC get_external_profile error for $userId: $e');
      final fullMsg = e.toString().toLowerCase();
      if (fullMsg.contains('profile_deleted') || fullMsg.contains('account_deleted')) {
        explicitStatus = ProfileResultStatus.deleted;
      } else if (fullMsg.contains('profile_suspended') || fullMsg.contains('account_suspended')) {
        explicitStatus = ProfileResultStatus.suspended;
      } else if (fullMsg.contains('profile_banned') || fullMsg.contains('account_banned')) {
        explicitStatus = ProfileResultStatus.banned;
      } else if (fullMsg.contains('profile_not_found')) {
        explicitStatus = ProfileResultStatus.notFound;
      }
    }

    // 3. Handle explicit deleted / notFound / suspended / banned statuses
    if (explicitStatus == ProfileResultStatus.deleted) {
      debugPrint('[ExternalProfileRepository] Profile $userId is DELETED. Invalidating cache.');
      await _cache?.remove(cacheKey);
      return const ExternalProfileResult(status: ProfileResultStatus.deleted);
    }

    if (explicitStatus == ProfileResultStatus.notFound) {
      debugPrint('[ExternalProfileRepository] Profile $userId is NOT FOUND. Invalidating cache.');
      await _cache?.remove(cacheKey);
      return const ExternalProfileResult(status: ProfileResultStatus.notFound);
    }

    if (explicitStatus == ProfileResultStatus.suspended) {
      debugPrint('[ExternalProfileRepository] Profile $userId is SUSPENDED.');
      await _cache?.remove(cacheKey);
      final model = rawJson != null ? ExternalProfileModel.fromJson(rawJson) : null;
      return ExternalProfileResult(status: ProfileResultStatus.suspended, profile: model);
    }

    if (explicitStatus == ProfileResultStatus.banned) {
      debugPrint('[ExternalProfileRepository] Profile $userId is BANNED.');
      await _cache?.remove(cacheKey);
      final model = rawJson != null ? ExternalProfileModel.fromJson(rawJson) : null;
      return ExternalProfileResult(status: ProfileResultStatus.banned, profile: model);
    }

    // 4. If RPC returned valid profile json, populate user activities and save to cache
    if (rawJson != null) {
      final modelTmp = ExternalProfileModel.fromJson(rawJson);
      if (!modelTmp.isPrivate && !modelTmp.isBlocked) {
        final acts = await fetchUserActivities(userId);
        if (acts.isNotEmpty) {
          rawJson['activities'] = acts;
        }
      }

      await _cache?.set(cacheKey, rawJson);
      return ExternalProfileResult(
        status: ProfileResultStatus.loaded,
        profile: ExternalProfileModel.fromJson(rawJson),
      );
    }

    // 5. Fallback query on user_profiles ONLY if RPC did NOT report deleted, suspended, banned or not_found
    try {
      final row = await _client
          .from('user_profiles')
          .select('user_id, username, first_name, last_name, photo_url, cover_url, bio, slogan')
          .eq('user_id', userId)
          .maybeSingle();

      if (row != null) {
        RelationState relationState = RelationState.none;
        try {
          relationState = await _socialRepo.getRelationState(userId);
        } catch (_) {}

        rawJson = {
          'user_id': userId,
          'username': row['username'] ?? '',
          'first_name': row['first_name'] ?? '',
          'last_name': row['last_name'] ?? '',
          'photo_url': row['photo_url'],
          'cover_url': row['cover_url'],
          'bio': row['bio'],
          'slogan': row['slogan'],
          'is_private': false,
          'is_blocked': relationState == RelationState.blockedByMe,
          'is_connected': relationState == RelationState.friend,
          'connection_request_sent': relationState == RelationState.requestSent,
          'incoming_connection_request': relationState == RelationState.requestReceived,
          'is_following': false,
          'is_certified': false,
          'can_message': relationState == RelationState.friend,
          'friend_count': 0,
          'interests': [],
        };

        final model = ExternalProfileModel.fromJson(rawJson);
        await _cache?.set(cacheKey, rawJson);
        return ExternalProfileResult(status: ProfileResultStatus.loaded, profile: model);
      }
    } catch (e) {
      debugPrint('[ExternalProfileRepository] Fallback query error for $userId: $e');
    }

    // 6. Network/RPC failed and fallback found nothing: Return stale cache if available
    final staleMap = _cache?.get<Map<String, dynamic>>(cacheKey);
    if (staleMap != null && staleMap.isNotEmpty) {
      debugPrint('[ExternalProfileRepository] Network failed for $userId, returning stale cache');
      return ExternalProfileResult(
        status: ProfileResultStatus.loaded,
        profile: ExternalProfileModel.fromJson(staleMap),
      );
    }

    return const ExternalProfileResult(
      status: ProfileResultStatus.error,
      errorMessage: 'Impossible de charger ce profil.',
    );
  }

  Future<ExternalProfileModel?> getProfile(String userId) async {
    final res = await getProfileResult(userId);
    return res.profile;
  }

  /// Updates local cached profile map when a relationship action is performed.
  Future<void> updateCachedProfile(ExternalProfileModel model) async {
    final cacheKey = FastCacheKey.externalProfile(model.userId);
    await _cache?.set(cacheKey, model.toJson());
  }

  Future<List<Map<String, dynamic>>> fetchUserActivities(String userId) async {
    try {
      final response = await _client
          .from('activities')
          .select('id, name, base_price, currency_code, photo_url')
          .eq('user_id', userId)
          .limit(10);

      if (response is List) {
        return response
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (e) {
      debugPrint('[ExternalProfileRepository] fetchUserActivities error: $e');
    }
    return [];
  }

  Future<void> sendConnectionRequest(String userId) async {
    await _socialRepo.sendFriendRequest(userId);
  }

  Future<void> cancelConnection(String userId) async {
    await _socialRepo.removeFriendship(userId);
  }

  Future<void> respondConnectionRequest(String requestId, bool accept) async {
    await _socialRepo.respondFriendRequest(requestId, accept);
  }

  Future<bool> follow(String userId) async {
    try {
      await _client.rpc('follow_public_certified_profile', params: {'p_user_id': userId});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unfollow(String userId) async {
    try {
      await _client.rpc('unfollow_profile', params: {'p_user_id': userId});
      return true;
    } catch (_) {
      return false;
    }
  }
}
