import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import '../controllers/community/community_controller.dart';
import 'create_community_screen.dart';
import 'community_feed_screen.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final CommunityController controller = Get.put(CommunityController());

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text(
          'community_my_communities'.tr,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: colorScheme.primary, size: 28),
            onPressed: () {
              Get.to(() => const CreateCommunityScreen())?.then((_) {
                controller.loadCommunities();
              });
            },
            tooltip: 'create_community_title'.tr,
          ),
        ],
      ),
      body: Obx(() {
        debugPrint('[COMMUNITY_SYNC] UI build stats: totalCommunities=${controller.communities.length}, pending=${controller.communities.where((c) => c.status == 'pending').length}, confirmed=${controller.communities.where((c) => c.status == 'confirmed').length}');
        if (controller.isLoading.value && controller.communities.isEmpty) {
          return Center(
            child: Lottie.asset(
              'assets/lotties/Animation - 1791582964132.json',
              width: 140,
              height: 140,
            ),
          );
        }

        if (controller.communities.isEmpty) {
          return RefreshIndicator(
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            elevation: 0,
            onRefresh: () => controller.loadCommunities(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.groups_outlined, size: 64, color: colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'community_empty_title'.tr,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'community_empty_subtitle'.tr,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              Get.to(() => const CreateCommunityScreen())?.then((_) {
                                controller.loadCommunities();
                              });
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: Text('community_create_button'.tr),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: Colors.transparent,
          backgroundColor: Colors.transparent,
          elevation: 0,
          onRefresh: () => controller.loadCommunities(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: controller.communities.length,
            itemBuilder: (context, index) {
              final community = controller.communities[index];
              final isPending = community.status == 'pending';

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Opacity(
                  opacity: isPending ? 0.6 : 1.0,
                  child: _MyCommunityTile(
                    community: community,
                    isPending: isPending,
                    onTap: isPending
                        ? () {
                            Get.snackbar(
                              'community_creation_in_progress'.tr,
                              'La communauté est en cours de création sur le serveur.',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                          }
                        : () {
                            Get.to(() => CommunityFeedScreen(
                                  communityId: community.id,
                                  communityName: community.name,
                                ));
                          },
                  ),
                ),
              );
            },
          ),
        );
      }),
    );
  }
}

class _MyCommunityTile extends StatelessWidget {
  final dynamic community;
  final bool isPending;
  final VoidCallback onTap;

  const _MyCommunityTile({
    required this.community,
    required this.isPending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = community.name.isNotEmpty ? community.name[0].toUpperCase() : 'C';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: community.avatarUrl != null && community.avatarUrl!.isNotEmpty
                    ? AppCachedImage(
                        imageUrl: community.avatarUrl!,
                        width: 62,
                        height: 62,
                        fit: BoxFit.cover,
                        errorWidget: Container(
                          width: 62,
                          height: 62,
                          color: colorScheme.primary.withValues(alpha: 0.15),
                          child: Center(
                            child: Text(
                              initial,
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Container(
                        width: 62,
                        height: 62,
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        child: Center(
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    community.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isPending ? Colors.orange : colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isPending ? 'community_creation_in_progress'.tr : 'status_online'.tr,
                        style: TextStyle(
                          fontSize: 12,
                          color: isPending ? Colors.orange : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
