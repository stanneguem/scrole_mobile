import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:scrole/modules/module_communautes/interne/controllers/community/community_feed_controller.dart';
import 'package:scrole/modules/module_principale/interne/widgets/feed_post_card.dart';
import 'package:scrole/modules/module_principale/interne/widgets/community_comments_sheet.dart';
import 'create_community_post_screen.dart';
import 'community_settings_screen.dart';

class CommunityFeedScreen extends StatelessWidget {
  final String communityId;
  final String communityName;

  const CommunityFeedScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(CommunityFeedController(null, communityId), tag: communityId);
    controller.communityName.value = communityName;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: GestureDetector(
          onTap: () {
            Get.to(() => CommunitySettingsScreen(
                  communityId: communityId,
                  communityName: communityName,
                ));
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                communityName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: colorScheme.primary, size: 28),
            onPressed: () {
              Get.to(() => CreateCommunityPostScreen(
                    communityName: communityName,
                    communityId: communityId,
                  ));
            },
            tooltip: 'Créer une publication',
          ),
        ],
      ),
      body: Obx(() {
        final state = controller.feedState.value;
        final posts = controller.posts;

        switch (state) {
          case CommunityFeedState.initialLoading:
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'community_feed_loading'.tr,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );

          case CommunityFeedState.error:
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 56, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      controller.errorMessage.value.isNotEmpty
                          ? controller.errorMessage.value
                          : 'community_feed_error_msg'.tr,
                      style: TextStyle(color: colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => controller.fetchCommunityFeed(isRefresh: true),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('retry'.tr),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            );

          case CommunityFeedState.empty:
            return RefreshIndicator(
              onRefresh: () => controller.fetchCommunityFeed(isRefresh: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.forum_outlined, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      Text(
                        'community_feed_empty_title'.tr,
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          Get.to(() => CreateCommunityPostScreen(
                                communityName: communityName,
                                communityId: communityId,
                              ));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('community_feed_create_first_post'.tr),
                      ),
                    ],
                  ),
                ),
              ),
            );

          case CommunityFeedState.loaded:
          case CommunityFeedState.refreshing:
            return RefreshIndicator(
              onRefresh: () => controller.fetchCommunityFeed(isRefresh: true),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: posts.length + (controller.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == posts.length) {
                    controller.loadMorePosts();
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }

                  final post = posts[index];
                  return VisibilityDetector(
                    key: Key('comm_post_vis_${post.id}'),
                    onVisibilityChanged: (info) {
                      if (info.visibleFraction >= 0.5) {
                        controller.queuePostView(post);
                      }
                    },
                    child: FeedPostCard(
                      post: post,
                      currentCommunityId: communityId,
                      onReactionTap: (reaction) => controller.handleReaction(post.id, reaction),
                      onCommentTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CommunityCommentsSheet(post: post, controller: controller),
                        );
                      },
                    ),
                  );
                },
              ),
            );
        }
      }),
    );
  }
}
