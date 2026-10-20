import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';
import 'package:scrole/app/routes/app_pages.dart';
import '../../../module_discussion_direct/centre/services/chat_service.dart';
import '../../centre/models/external_profile_model.dart';
import '../../externe/repositories/external_profile_repository.dart';

enum ProfileScreenState {
  loading,
  loaded,
  deleted,
  notFound,
  suspended,
  banned,
  error,
}

class ExternalProfileController extends GetxController {
  final ExternalProfileRepository _repository = ExternalProfileRepository();
  final ChatService _chatService = Get.find<ChatService>();
  final Rxn<ExternalProfileModel> profile = Rxn<ExternalProfileModel>();
  final Rx<ProfileScreenState> profileState = ProfileScreenState.loading.obs;
  final RxBool isLoading = true.obs;
  final RxBool isSendingRequest = false.obs;
  final RxBool isFollowing = false.obs;
  final RxString error = ''.obs;
  final RxInt selectedTab = 0.obs;
  late final String userId;
  RealtimeChannel? _relationshipChannel;

  @override
  void onInit() {
    super.onInit();
    userId = Get.parameters['userId'] ?? '';
    if (userId.isEmpty) {
      error.value = 'Profil invalide.';
      profileState.value = ProfileScreenState.notFound;
      isLoading.value = false;
      update(['profile_initial']);
      return;
    }
    loadProfile();
    _subscribeToRelationshipChanges();
  }

  void _subscribeToRelationshipChanges() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    try {
      _relationshipChannel = Supabase.instance.client
          .channel('user:$uid', opts: const RealtimeChannelConfig(private: true))
          .onBroadcast(
            event: 'relationship_changed',
            callback: (payload) {
              final changedUserId = payload['user_id']?.toString();
              if (changedUserId == userId) {
                debugPrint('[FOLLOW] relationship_changed user_id=$changedUserId; refreshing profile relation and stats');
                unawaited(loadProfile());
              }
            },
          )
          ..subscribe();
    } catch (e, stack) {
      debugPrint('[FOLLOW] relationship_changed subscription exception=$e\\n$stack');
    }
  }

  @override
  void onClose() {
    final channel = _relationshipChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
      _relationshipChannel = null;
    }
    super.onClose();
  }

  Future<void> loadProfile() async {
    isLoading.value = true;
    error.value = '';
    profileState.value = ProfileScreenState.loading;

    try {
      final result = await _repository.getProfileResult(userId);
      switch (result.status) {
        case ProfileResultStatus.deleted:
          profileState.value = ProfileScreenState.deleted;
          profile.value = null;
          break;
        case ProfileResultStatus.notFound:
          profileState.value = ProfileScreenState.notFound;
          profile.value = null;
          break;
        case ProfileResultStatus.suspended:
          profileState.value = ProfileScreenState.suspended;
          if (result.profile != null) profile.value = result.profile;
          break;
        case ProfileResultStatus.banned:
          profileState.value = ProfileScreenState.banned;
          if (result.profile != null) profile.value = result.profile;
          break;
        case ProfileResultStatus.loaded:
          if (result.profile != null) {
            profileState.value = ProfileScreenState.loaded;
            profile.value = result.profile;
            final relation = await _repository.getRelationship(userId, forceRefresh: true);
            final stats = await _repository.getFollowStats(userId: userId);
            final relationState = (relation['state'] ?? 'none').toString();
            final updated = result.profile!.copyWith(
              isFollowing: relation['is_following'] == true,
              isConnected: relation['is_friend'] == true,
              connectionRequestSent: relationState == 'requested',
              followsMe: relation['follows_me'] == true,
              relationshipState: relationState,
              requestId: relation['request_id']?.toString(),
              retryAt: relation['retry_at'] == null ? null : DateTime.tryParse(relation['retry_at'].toString()),
              friendCount: (stats['friends_count'] as num?)?.toInt() ?? result.profile!.friendCount,
              followersCount: (stats['followers_count'] as num?)?.toInt() ?? result.profile!.followersCount,
              followingCount: (stats['following_count'] as num?)?.toInt() ?? result.profile!.followingCount,
              friendsCount: (stats['friends_count'] as num?)?.toInt() ?? result.profile!.friendsCount,
            );
            profile.value = updated;
            isFollowing.value = updated.isFollowing;
          } else {
            profileState.value = ProfileScreenState.error;
            error.value = 'Impossible de charger ce profil.';
          }
          break;
        case ProfileResultStatus.error:
          profileState.value = ProfileScreenState.error;
          error.value = result.errorMessage ?? 'Impossible de charger ce profil.';
          break;
      }
    } catch (_) {
      profileState.value = ProfileScreenState.error;
      error.value = 'Impossible de charger ce profil.';
    } finally {
      isLoading.value = false;
      update(['profile_initial']);
    }
  }

  Future<void> sendConnectionRequest() async {
    final current = profile.value;
    if (current == null || isSendingRequest.value) return;
    await _performFollow(current);
  }

  Future<void> _performFollow(ExternalProfileModel current) async {
    isSendingRequest.value = true;
    try {
      final relation = await _repository.getRelationship(current.userId, forceRefresh: true);
      final state = (relation['state'] ?? 'none').toString();
      if (state == 'blocked' || state == 'self') return;
      final result = await _repository.follow(current.userId);
      final freshRelation = await _repository.getRelationship(current.userId, forceRefresh: true);
      final nextState = (freshRelation['state'] ?? (result ? 'following' : state)).toString();
      final updated = current.copyWith(
        isFollowing: freshRelation['is_following'] == true || nextState == 'following' || nextState == 'friends',
        isConnected: freshRelation['is_friend'] == true || nextState == 'friends',
        connectionRequestSent: nextState == 'requested',
        followsMe: freshRelation['follows_me'] == true,
        relationshipState: nextState,
        requestId: freshRelation['request_id']?.toString(),
        retryAt: freshRelation['retry_at'] == null ? null : DateTime.tryParse(freshRelation['retry_at'].toString()),
        canMessage: freshRelation['is_friend'] == true || nextState == 'friends',
      );
      profile.value = updated;
      isFollowing.value = updated.isFollowing;
      await _repository.updateCachedProfile(updated);
    } catch (e, stack) {
      debugPrint('[FOLLOW] follow_user exception=$e\\n$stack');
      Get.snackbar('error_title'.tr, 'follow_action_failed'.tr);
    } finally {
      isSendingRequest.value = false;
    }
  }

  Future<void> handleConnectionTap() async {
    final current = profile.value;
    if (current == null || isSendingRequest.value) return;
    final state = current.relationshipState;
    if (state == 'none' || state == 'follow_back') {
      await _performFollow(current);
      return;
    }
    if (state == 'requested') {
      isSendingRequest.value = true;
      try {
        await _repository.getRelationship(current.userId, forceRefresh: true);
        await _repository.cancelConnection(current.userId);
        final relation = await _repository.getRelationship(current.userId, forceRefresh: true);
        final updated = current.copyWith(
          isFollowing: relation['is_following'] == true,
          isConnected: relation['is_friend'] == true,
          connectionRequestSent: false,
          relationshipState: (relation['state'] ?? 'none').toString(),
          requestId: relation['request_id']?.toString(),
        );
        profile.value = updated;
        await _repository.updateCachedProfile(updated);
      } catch (e, stack) {
        debugPrint('[FOLLOW] cancel_follow_request exception=$e\\n$stack');
        Get.snackbar('error_title'.tr, 'follow_action_failed'.tr);
      } finally {
        isSendingRequest.value = false;
      }
      return;
    }
    if (state == 'following' || state == 'friends') {
      final action = await Get.bottomSheet<String>(
        _RelationshipActionSheet(isFriend: state == 'friends'),
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .35),
      );
      if (action == null) return;
      isSendingRequest.value = true;
      try {
        if (action == 'unfollow') {
          await _repository.cancelConnection(current.userId);
        } else if (action == 'remove_friend') {
          await _repository.removeFriend(current.userId);
        }
        final relation = await _repository.getRelationship(current.userId, forceRefresh: true);
        final updated = current.copyWith(
          isFollowing: relation['is_following'] == true,
          isConnected: relation['is_friend'] == true,
          connectionRequestSent: relation['state'] == 'requested',
          followsMe: relation['follows_me'] == true,
          relationshipState: (relation['state'] ?? 'none').toString(),
          requestId: relation['request_id']?.toString(),
          retryAt: relation['retry_at'] == null ? null : DateTime.tryParse(relation['retry_at'].toString()),
        );
        profile.value = updated;
        isFollowing.value = updated.isFollowing;
        await _repository.updateCachedProfile(updated);
      } catch (e, stack) {
        debugPrint('[FOLLOW] relationship action exception=$e\\n$stack');
        Get.snackbar('error_title'.tr, 'follow_action_failed'.tr);
      } finally {
        isSendingRequest.value = false;
      }
      return;
    }
    if (state == 'request_received') {
      final requestId = current.requestId;
      if (requestId == null || requestId.isEmpty) {
        Get.snackbar('follow_request_received_title'.tr, 'follow_request_received_hint'.tr);
        return;
      }
      isSendingRequest.value = true;
      try {
        await _repository.respondConnectionRequest(requestId, true, targetUserId: current.userId);
        final relation = await _repository.getRelationship(current.userId, forceRefresh: true);
        final updated = current.copyWith(
          isFollowing: relation['is_following'] == true,
          isConnected: relation['is_friend'] == true,
          connectionRequestSent: relation['state'] == 'requested',
          followsMe: relation['follows_me'] == true,
          relationshipState: (relation['state'] ?? 'none').toString(),
          canMessage: relation['is_friend'] == true,
        );
        profile.value = updated;
        isFollowing.value = updated.isFollowing;
        await _repository.updateCachedProfile(updated);
      } catch (e, stack) {
        debugPrint('[FOLLOW] respond_follow_request exception=$e\\n$stack');
        Get.snackbar('error_title'.tr, 'follow_action_failed'.tr);
      } finally {
        isSendingRequest.value = false;
      }
    }
  }

  Future<void> openConversation() async {
    final current = profile.value;
    if (current == null || !current.canMessage) return;
    final conversation = await _chatService.startConversation(current.userId);
    if (conversation == null) {
      Get.snackbar('Message', 'Impossible d’ouvrir cette conversation.');
      return;
    }
    await Get.toNamed(
      AppPages.conversation,
      arguments: {
        'name': current.displayName,
        'color': Theme.of(Get.context!).colorScheme.primary,
        'avatar': current.photoUrl,
      },
      parameters: {'chatId': conversation.id},
    );
  }
}

class _ConnectionActionSheet extends StatelessWidget {
  const _ConnectionActionSheet({required this.isPending});

  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                    child: Row(
                      children: [
                        Icon(
                          isPending ? Icons.person_remove_alt_1_rounded : Icons.person_off_outlined,
                          color: scheme.error,
                          size: 22,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            isPending ? 'Annuler la demande' : 'Retirer cette connexion',
                            style: TextStyle(
                              color: scheme.error,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'cancel'.tr,
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelationshipActionSheet extends StatelessWidget {
  const _RelationshipActionSheet({required this.isFriend});
  final bool isFriend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget action(String value, String label, IconData icon) => ListTile(
      leading: Icon(icon, color: scheme.error),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(value),
    );
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            action('unfollow', 'follow_unfollow_action'.tr, Icons.person_remove_alt_1_rounded),
            if (isFriend) action('remove_friend', 'follow_remove_friend_action'.tr, Icons.person_off_outlined),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: Text('cancel'.tr),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
