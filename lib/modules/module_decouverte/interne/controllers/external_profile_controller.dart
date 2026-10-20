import 'package:flutter/material.dart';
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
            isFollowing.value = result.profile!.isFollowing;
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
    if (current == null || current.connectionRequestSent || current.isConnected) return;

    isSendingRequest.value = true;
    try {
      await _repository.sendConnectionRequest(current.userId);
      final updated = current.copyWith(connectionRequestSent: true);
      profile.value = updated;
      await _repository.updateCachedProfile(updated);
      Get.snackbar('Demande envoyée', 'Votre demande de connexion a été envoyée.');
    } catch (e) {
      final message = e.toString();
      Get.snackbar(
        'Connexion',
        message.contains('connection_request_exists')
            ? 'Une demande est déjà en attente.'
            : message.contains('already_connected')
                ? 'Vous êtes déjà connectés.'
                : 'Impossible d’envoyer la demande.',
      );
    } finally {
      isSendingRequest.value = false;
    }
  }

  Future<void> handleConnectionTap() async {
    final current = profile.value;
    if (current == null || isSendingRequest.value) return;

    if (!current.isConnected && !current.connectionRequestSent) {
      await sendConnectionRequest();
      return;
    }

    final isPending = current.connectionRequestSent;
    final confirmed = await _showConnectionActionSheet(isPending);
    if (!confirmed) return;

    isSendingRequest.value = true;
    try {
      await _repository.cancelConnection(current.userId);

      final updated = isPending
          ? current.copyWith(connectionRequestSent: false)
          : current.copyWith(
              isConnected: false,
              friendCount: current.friendCount > 0 ? current.friendCount - 1 : 0,
            );

      profile.value = updated;
      await _repository.updateCachedProfile(updated);

      Get.snackbar(
        'Connexion',
        isPending ? 'Demande annulée.' : 'Connexion supprimée.',
      );
    } catch (e) {
      Get.snackbar(
        'Connexion',
        e.toString().contains('not_request_sender')
            ? 'Seul l’auteur de la demande peut l’annuler.'
            : 'Impossible de modifier la connexion.',
      );
    } finally {
      isSendingRequest.value = false;
    }
  }

  Future<bool> _showConnectionActionSheet(bool isPending) async {
    final result = await Get.bottomSheet<bool>(
      _ConnectionActionSheet(isPending: isPending),
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .35),
      isScrollControlled: false,
    );
    return result == true;
  }

  Future<void> toggleFollow() async {
    final current = profile.value;
    if (current == null || !current.isCertified || current.isPrivate) return;
    try {
      if (isFollowing.value) {
        await _repository.unfollow(current.userId);
        isFollowing.value = false;
        final updated = current.copyWith(isFollowing: false);
        profile.value = updated;
        await _repository.updateCachedProfile(updated);
      } else {
        await _repository.follow(current.userId);
        isFollowing.value = true;
        final updated = current.copyWith(isFollowing: true);
        profile.value = updated;
        await _repository.updateCachedProfile(updated);
      }
    } catch (_) {
      Get.snackbar('Suivre', 'Impossible de modifier le suivi.');
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
