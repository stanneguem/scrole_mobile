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
    final imageUrl = community.avatarUrl?.toString() ?? '';
    final hasImage = imageUrl.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 196,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasImage)
                  AppCachedImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: _communityImageFallback(colorScheme, initial),
                  )
                else
                  _communityImageFallback(colorScheme, initial),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                      stops: [0.28, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              community.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                shadows: [Shadow(color: Colors.black26, blurRadius: 8)],
                              ),
                            ),
                            if (isPending) ...[
                              const SizedBox(height: 7),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFFFFD180)),
                                  const SizedBox(width: 5),
                                  Text(
                                    'community_creation_in_progress'.tr,
                                    style: const TextStyle(
                                      color: Color(0xFFFFD180),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _communityImageFallback(ColorScheme colors, String initial) {
    return Container(
      color: colors.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontSize: 56,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
