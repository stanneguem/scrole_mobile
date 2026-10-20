import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';

class CommunityPostMentionsController extends GetxController {
  late final CommunityService _service = Get.isRegistered<CommunityService>()
      ? Get.find<CommunityService>()
      : Get.put(CommunityService());
  final String communityId = Get.parameters['communityId'] ?? Get.arguments?['communityId'] ?? '';

  final members = <Map<String, dynamic>>[].obs;
  final filteredMembers = <Map<String, dynamic>>[].obs;
  final selectedUserIds = <String>{}.obs;
  final isLoading = true.obs;
  final searchController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    final initialSelected = Get.arguments?['initialSelected'] as List<String>?;
    if (initialSelected != null) {
      selectedUserIds.addAll(initialSelected);
    }
    loadMembers();
    searchController.addListener(_filterMembers);
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  String _memberUserId(Map<String, dynamic> member) {
    final profile = member['user_profiles'] is Map
        ? Map<String, dynamic>.from(member['user_profiles'] as Map)
        : <String, dynamic>{};
    return (profile['user_id'] ?? profile['id'] ?? member['user_id'] ??
            member['userId'] ?? member['profile_id'] ?? member['id'] ?? '')
        .toString();
  }

  Future<void> loadMembers() async {
    isLoading.value = true;
    try {
      final client = Supabase.instance.client;
      final currentUserId = client.auth.currentUser?.id ??
          (Get.isRegistered<AuthService>() ? Get.find<AuthService>().userId : null);
      List<Map<String, dynamic>> res;

      if (communityId.isNotEmpty) {
        res = await _service.getCommunityMembers(communityId);
      } else {
        // General-feed mentions are limited to the user's friends.
        final uid = currentUserId;
        if (uid == null || uid.isEmpty) {
          res = [];
        } else {
          final relations = await client.from('friendships')
              .select('user_a_id,user_b_id')
              .or('user_a_id.eq.$uid,user_b_id.eq.$uid')
              .limit(300);
          final friendIds = <String>{};
          for (final relation in relations) {
            final other = relation['user_a_id']?.toString() == uid
                ? relation['user_b_id']?.toString()
                : relation['user_a_id']?.toString();
            if (other != null && other.isNotEmpty && other != uid) friendIds.add(other);
          }
          if (friendIds.isEmpty) {
            res = [];
          } else {
            final profiles = await client.from('user_profiles')
                .select('user_id,username,first_name,last_name,photo_url,is_verified')
                .inFilter('user_id', friendIds.toList())
                .limit(300);
            res = List<Map<String, dynamic>>.from(profiles);
          }
        }
      }

      final cleanMembers = res.where((member) {
        final uid = _memberUserId(member);
        return uid.isNotEmpty && uid != currentUserId;
      }).toList();
      members.assignAll(cleanMembers);
      filteredMembers.assignAll(cleanMembers);
    } catch (e) {
      debugPrint('[CommunityMentions] Error loading members: $e');
      members.clear();
      filteredMembers.clear();
    } finally {
      isLoading.value = false;
    }
  }

  void _filterMembers() {
    final query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      filteredMembers.value = members;
    } else {
      filteredMembers.value = members.where((m) {
        final username = (m['username'] ?? m['user_profiles']?['username'] ?? '').toString().toLowerCase();
        final firstName = (m['first_name'] ?? m['user_profiles']?['first_name'] ?? '').toString().toLowerCase();
        final lastName = (m['last_name'] ?? m['user_profiles']?['last_name'] ?? '').toString().toLowerCase();
        return username.contains(query) || firstName.contains(query) || lastName.contains(query);
      }).toList();
    }
  }

  void toggleSelection(String userId) {
    if (selectedUserIds.contains(userId)) {
      selectedUserIds.remove(userId);
    } else {
      if (selectedUserIds.length >= 20) {
        Get.snackbar('Limite atteinte', 'Vous ne pouvez identifier que 20 personnes au maximum.', snackPosition: SnackPosition.BOTTOM);
        return;
      }
      selectedUserIds.add(userId);
    }
  }

  void confirm() {
    final selected = members.where((member) {
      return selectedUserIds.contains(_memberUserId(member));
    }).map((member) {
      final profile = member['user_profiles'] is Map
          ? Map<String, dynamic>.from(member['user_profiles'] as Map)
          : <String, dynamic>{};
      return <String, dynamic>{
        ...profile,
        ...member,
        'user_id': _memberUserId(member),
        'username': member['username'] ?? profile['username'],
        'first_name': member['first_name'] ?? profile['first_name'],
        'last_name': member['last_name'] ?? profile['last_name'],
        'photo_url': member['photo_url'] ?? profile['photo_url'],
      };
    }).toList();
    Get.back(result: selected);
  }
}

class CommunityPostMentionsScreen extends StatelessWidget {
  const CommunityPostMentionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(CommunityPostMentionsController());
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Mentionner des personnes', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        actions: [
          Obx(() => TextButton(
                onPressed: controller.selectedUserIds.isEmpty ? null : controller.confirm,
                child: Text(
                  'Valider (${controller.selectedUserIds.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: controller.selectedUserIds.isEmpty ? colors.outline : AppColors.primary,
                  ),
                ),
              )),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: controller.searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher un membre...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: colors.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              }
              if (controller.filteredMembers.isEmpty) {
                return Center(child: Text('Aucun membre trouvé.', style: AppTextStyles.body.copyWith(color: colors.onSurfaceVariant)));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: controller.filteredMembers.length,
                itemBuilder: (context, index) {
                  final m = controller.filteredMembers[index];
                  final profile = m['user_profiles'] is Map ? Map<String, dynamic>.from(m['user_profiles']) : <String, dynamic>{};
                  final userId = controller._memberUserId(m);
                  final username = profile['username']?.toString() ?? m['username']?.toString() ?? 'Membre';
                  final firstName = profile['first_name']?.toString() ?? m['first_name']?.toString() ?? '';
                  final lastName = profile['last_name']?.toString() ?? m['last_name']?.toString() ?? '';
                  final displayName = (firstName.isNotEmpty || lastName.isNotEmpty) ? '$firstName $lastName'.trim() : username;
                  final photoUrl = profile['photo_url']?.toString() ?? m['photo_url']?.toString();
                  final isSelected = controller.selectedUserIds.contains(userId);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    leading: ClipOval(
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? AppCachedImage(imageUrl: photoUrl, width: 40, height: 40, fit: BoxFit.cover)
                          : Container(
                              width: 40,
                              height: 40,
                              color: AppColors.primary.withValues(alpha: 0.15),
                              alignment: Alignment.center,
                              child: Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : 'M', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                            ),
                    ),
                    title: Text(displayName, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text('@$username', style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant)),
                    trailing: CupertinoCheckbox(
                      value: isSelected,
                      activeColor: AppColors.primary,
                      onChanged: (_) => controller.toggleSelection(userId),
                    ),
                    onTap: () => controller.toggleSelection(userId),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}
