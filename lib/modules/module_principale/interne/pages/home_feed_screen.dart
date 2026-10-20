import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../controllers/home_feed_controller.dart';
import '../controllers/main_layout_controller.dart';
import '../controllers/stories_controller.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/community_comments_sheet.dart';
import 'package:scrole/modules/module_communautes/interne/controllers/community/community_feed_controller.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_model.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'story_viewer_screen.dart';
import 'create_story_screen.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  final ScrollController _scrollController = ScrollController();
  final RxBool _showScrollToTop = false.obs;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.offset > 300 && !_showScrollToTop.value) {
        _showScrollToTop.value = true;
      } else if (_scrollController.offset <= 300 && _showScrollToTop.value) {
        _showScrollToTop.value = false;
      }

      // Infinite scroll pagination trigger
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (Get.isRegistered<HomeFeedController>()) {
          Get.find<HomeFeedController>().loadMore();
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<HomeFeedController>()) {
      Get.put(HomeFeedController());
    }
    if (!Get.isRegistered<StoriesController>()) {
      Get.put(StoriesController());
    }

    final feedController = Get.find<HomeFeedController>();
    final storiesController = Get.find<StoriesController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          RefreshIndicator(
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            elevation: 0,
            onRefresh: () async {
              await Future.wait([
                feedController.fetchFeed(refresh: true),
                storiesController.fetchStories(),
              ]);
            },
            child: Obx(() {
              final state = feedController.state.value;

              if (state == HomeFeedState.loading) {
                return Center(
                  child: Lottie.asset(
                    'assets/lotties/Animation - 1791582964132.json',
                    width: 140,
                    height: 140,
                  ),
                );
              }

              if (state == HomeFeedState.error) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(feedController.errorMessage.value, style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => feedController.fetchFeed(),
                        child: Text('retry'.tr),
                      ),
                    ],
                  ),
                );
              }

              if (state == HomeFeedState.empty || feedController.posts.isEmpty) {
                return ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const _StoriesRow(),
                    const Divider(height: 1, thickness: 0.5),
                    const _SuggestedProfilesCarousel(),
                    const _SuggestedEventsCarousel(),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.4,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.feed_outlined, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                              const SizedBox(height: 16),
                              Text(
                                'home_feed_empty_invitation'.tr,
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                );
              }

              return ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 120),
                itemCount: feedController.posts.length + 3,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _StoriesRow(),
                        Divider(height: 1, thickness: 0.5, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ],
                    );
                  }

                  final insertIndex = feedController.posts.length >= 2 ? 3 : (feedController.posts.length == 1 ? 2 : 1);

                  if (index == insertIndex) {
                    return const _SuggestedProfilesCarousel();
                  }
                  if (index == insertIndex + 1) {
                    return const _SuggestedEventsCarousel();
                  }

                  int postIndex;
                  if (index < insertIndex) {
                    postIndex = index - 1;
                  } else {
                    postIndex = index - 3;
                  }

                  if (postIndex < 0 || postIndex >= feedController.posts.length) {
                    return const SizedBox.shrink();
                  }

                  final post = feedController.posts[postIndex];

                  return VisibilityDetector(
                    key: Key('post_vis_${post.id}'),
                    onVisibilityChanged: (info) {
                      if (info.visibleFraction >= 0.5) {
                        feedController.queuePostView(post);
                      }
                    },
                    child: FeedPostCard(
                      post: post,
                      onReactionTap: (reaction) => feedController.handleReaction(post.id, reaction),
                      onCommentTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CommunityCommentsSheet(
                            post: post,
                            controller: Get.isRegistered<CommunityFeedController>()
                                ? Get.find<CommunityFeedController>()
                                : Get.put(CommunityFeedController(null, post.eventId)),
                          ),
                        );
                      },
                      onHidePost: () => feedController.hidePost(post.id),
                    ),
                  );
                },
              );
            }),
          ),

          // --- Custom Refresh Lottie Indicator Overlay ---
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Obx(() {
                if (!feedController.isRefreshing.value) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Lottie.asset(
                    'assets/lotties/Animation - 1791582964132.json',
                    width: 44,
                    height: 44,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoriesRow extends GetView<StoriesController> {
  const _StoriesRow();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 108,
      child: Obx(() {
        final own = controller.ownGroup.value;
        final hasOwnStory = own != null && own.stories.isNotEmpty;
        final otherGroups = [
          ...controller.followingGroups,
          ...controller.suggestedGroups,
        ];
        final allGroupsForViewer = [
          if (hasOwnStory) own,
          ...otherGroups,
        ];

        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: otherGroups.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () {
                    if (hasOwnStory) {
                      Get.to(() => StoryViewerScreen(groups: [own], initialGroupIndex: 0));
                    } else {
                      Get.to(() => const CreateStoryScreen());
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          Container(
                            padding: EdgeInsets.all(hasOwnStory ? 2.5 : 0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: hasOwnStory
                                  ? Border.all(color: own.hasUnseen ? colorScheme.primary : colorScheme.outlineVariant, width: 2.5)
                                  : null,
                            ),
                            child: CircleAvatar(
                              radius: 28,
                              backgroundImage: own?.author.photoUrl != null && own!.author.photoUrl!.isNotEmpty
                                  ? NetworkImage(own.author.photoUrl!)
                                  : null,
                              child: own?.author.photoUrl == null || own!.author.photoUrl!.isEmpty
                                  ? Icon(Icons.person, color: colorScheme.onSurfaceVariant)
                                  : null,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => Get.to(() => const CreateStoryScreen()),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: colorScheme.surface, width: 2),
                                ),
                                child: const Icon(Icons.add, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('Ta story', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              );
            }

            final group = otherGroups[index - 1];
            final hasUnviewed = group.hasUnseen;

            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  controller.markAsViewed(group.author.userId);
                  final viewerIndex = hasOwnStory ? index : index - 1;
                  Get.to(() => StoryViewerScreen(groups: allGroupsForViewer, initialGroupIndex: viewerIndex));
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hasUnviewed ? colorScheme.primary : colorScheme.outlineVariant,
                          width: 2.5,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundImage: group.author.photoUrl != null && group.author.photoUrl!.isNotEmpty
                            ? NetworkImage(group.author.photoUrl!)
                            : null,
                        child: group.author.photoUrl == null || group.author.photoUrl!.isEmpty
                            ? Text(group.author.displayName.isNotEmpty ? group.author.displayName[0] : 'U')
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 64,
                      child: Text(
                        group.author.displayName,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _SuggestedProfilesCarousel extends GetView<HomeFeedController> {
  const _SuggestedProfilesCarousel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Obx(() {
      final profiles = controller.suggestedProfiles;
      if (profiles.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Suggestions de profils',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface),
                ),
                TextButton(
                  onPressed: () {},
                  child: Text('home_feed_see_more'.tr, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 195,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                final p = profiles[index];
                return Container(
                  width: 135,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: p.photoUrl != null && p.photoUrl!.isNotEmpty
                              ? AppCachedImage(imageUrl: p.photoUrl!, width: 60, height: 60, fit: BoxFit.cover)
                              : Container(width: 60, height: 60, color: colorScheme.primary, alignment: Alignment.center, child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(p.reasonSubtitle, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 32,
                        child: ElevatedButton(
                          onPressed: () {
                            p.isAdded = !p.isAdded;
                            controller.suggestedProfiles.refresh();
                          },
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            elevation: 0,
                            backgroundColor: p.isAdded ? colorScheme.surfaceContainerHighest : colorScheme.primary,
                            foregroundColor: p.isAdded ? colorScheme.onSurface : colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(p.isAdded ? 'Ajouté' : 'home_feed_add_profile'.tr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

class _SuggestedEventsCarousel extends GetView<HomeFeedController> {
  const _SuggestedEventsCarousel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Obx(() {
      final events = controller.suggestedEvents;
      if (events.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Événements suggérés',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface),
                ),
                TextButton(
                  onPressed: () {
                    try {
                      if (Get.isRegistered<MainLayoutController>()) {
                        Get.find<MainLayoutController>().goToEventSuggestionsTab();
                      }
                    } catch (e) {
                      debugPrint('[EVENTS] Error navigating to event suggestions: $e');
                    }
                  },
                  child: Text('see_more'.tr, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 165,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final ev = events[index];
                return GestureDetector(
                  onTap: () {
                    Get.toNamed(AppPages.eventPreviewPath(ev.id));
                  },
                  child: Container(
                    width: 155,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ev.coverImageUrl != null && ev.coverImageUrl!.isNotEmpty
                            ? AppCachedImage(imageUrl: ev.coverImageUrl!, width: 155, height: 85, fit: BoxFit.cover)
                            : Container(width: 155, height: 85, color: colorScheme.primaryContainer, child: const Icon(Icons.event, size: 28)),
                        Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ev.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(Icons.location_on_rounded, size: 12, color: colorScheme.primary),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      ev.city?.toString() ?? 'Virtuel',
                                      style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}
