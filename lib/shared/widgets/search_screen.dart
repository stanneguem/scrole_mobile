import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../modules/module_principale/centre/models/community_post.dart';
import '../../modules/module_principale/interne/controllers/home_feed_controller.dart';
import '../controllers/search_controller.dart';
import '../widgets/app_cached_image.dart';
import '../widgets/user_certified_badge.dart';
import '../widgets/entity_certified_badge.dart';
import '../../modules/module_decouverte/centre/models/discover_models.dart';
import '../../app/theme/text_styles.dart';
import 'relation_button_widget.dart';
import 'profile_post_detail_screen.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AppSearchController>()) {
      Get.put(AppSearchController());
    }
    final controller = Get.find<AppSearchController>();
    // Search is opened from the main app bar, where the cache-first home feed
    // is already available. Reuse its organic posts for the default Discover grid.
    if (!Get.isRegistered<HomeFeedController>()) {
      Get.put(HomeFeedController(), permanent: true);
    }
    final discoverFeed = Get.find<HomeFeedController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: controller.textController,
              autofocus: true,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                hintText: 'search_hint'.tr,
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  fontSize: 15,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                suffixIcon: Obx(() => controller.query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                        onPressed: controller.clearQuery,
                        splashRadius: 18,
                      )
                    : const SizedBox.shrink()),
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: controller.onQueryChanged,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // --- Instagram-style Tabs ---
          Obx(() {
            if (controller.state.value == SearchState.initial) {
              return const SizedBox.shrink();
            }
            return Container(
              height: 48,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _SearchTabItem(
                    label: 'filter_all'.tr,
                    isSelected: controller.filter.value == SearchFilter.all,
                    onTap: () => controller.setFilter(SearchFilter.all),
                  ),
                  _SearchTabItem(
                    label: 'filter_users'.tr,
                    isSelected: controller.filter.value == SearchFilter.users,
                    onTap: () => controller.setFilter(SearchFilter.users),
                  ),
                  _SearchTabItem(
                    label: 'filter_communities'.tr,
                    isSelected: controller.filter.value == SearchFilter.communities,
                    onTap: () => controller.setFilter(SearchFilter.communities),
                  ),
                  _SearchTabItem(
                    label: 'filter_events'.tr,
                    isSelected: controller.filter.value == SearchFilter.events,
                    onTap: () => controller.setFilter(SearchFilter.events),
                  ),
                  _SearchTabItem(
                    label: 'filter_activities'.tr,
                    isSelected: controller.filter.value == SearchFilter.activities,
                    onTap: () => controller.setFilter(SearchFilter.activities),
                  ),
                  _SearchTabItem(
                    label: 'filter_tags'.tr,
                    isSelected: controller.filter.value == SearchFilter.tags,
                    onTap: () => controller.setFilter(SearchFilter.tags),
                  ),
                ],
              ),
            );
          }),

          // --- Content Body ---
          Expanded(
            child: Obx(() {
              final state = controller.state.value;

              switch (state) {
                case SearchState.initial:
                  return _DiscoverPostsGrid(controller: discoverFeed);

                case SearchState.loading:
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text('search_in_progress'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  );

                case SearchState.empty:
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'no_results_for'.trParams({'query': controller.query.value}),
                        style: AppTextStyles.body.copyWith(color: colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );

                case SearchState.error:
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            controller.errorMessage.value,
                            style: AppTextStyles.body.copyWith(color: colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: controller.retryLastSearch,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text('retry'.tr),
                          ),
                        ],
                      ),
                    ),
                  );

                case SearchState.success:
                  final items = controller.filteredResults;
                  if (items.isEmpty) {
                    if (controller.filter.value == SearchFilter.communities) {
                      return Center(
                        child: Text(
                          'no_communities_found'.tr,
                          style: AppTextStyles.body.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      );
                    }
                    return Center(
                      child: Text(
                        'no_results_for'.trParams({'query': controller.query.value}),
                        style: AppTextStyles.body.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _SearchResultTile(item: item, onTap: () => controller.onItemTap(item));
                    },
                  );
              }
            }),
          ),
        ],
      ),
    );
  }
}


/// Pinterest-style media discovery grid shown before the user starts searching.
/// The grid reuses the same post objects and detail screen as profile posts.
class _DiscoverPostsGrid extends StatefulWidget {
  final HomeFeedController controller;

  const _DiscoverPostsGrid({required this.controller});

  @override
  State<_DiscoverPostsGrid> createState() => _DiscoverPostsGridState();
}

class _DiscoverPostsGridState extends State<_DiscoverPostsGrid> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 700 &&
        widget.controller.hasMore.value &&
        !widget.controller.isLoadingMore.value) {
      widget.controller.loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Obx(() {
      final posts = widget.controller.posts
          .where((post) => !post.isPublishing && post.media.isNotEmpty)
          .toList(growable: false);

      if (posts.isEmpty &&
          (widget.controller.state.value == HomeFeedState.loading ||
              widget.controller.state.value == HomeFeedState.initial)) {
        return const Center(child: CircularProgressIndicator());
      }

      if (posts.isEmpty) {
        return RefreshIndicator(
          onRefresh: () => widget.controller.fetchFeed(refresh: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.55,
                child: Center(
                  child: Text(
                    'Aucune publication à découvrir pour le moment.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      final leftColumn = <Widget>[];
      final rightColumn = <Widget>[];
      for (var index = 0; index < posts.length; index++) {
        final tile = _DiscoverPostTile(post: posts[index], index: index);
        (index.isEven ? leftColumn : rightColumn).add(tile);
      }

      return RefreshIndicator(
        onRefresh: () => widget.controller.fetchFeed(refresh: true),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: leftColumn)),
              const SizedBox(width: 8),
              Expanded(child: Column(children: rightColumn)),
            ],
          ),
        ),
      );
    });
  }
}

class _DiscoverPostTile extends StatelessWidget {
  final CommunityPost post;
  final int index;

  const _DiscoverPostTile({required this.post, required this.index});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final media = post.media.first;
    final imageUrl = media.isVideo
        ? (media.thumbnailUrl?.trim().isNotEmpty == true
            ? media.thumbnailUrl!
            : media.url)
        : media.url;
    final tileHeight = 178.0 + ((index * 37) % 91).toDouble();
    final caption = post.content.trim();

    return GestureDetector(
      onTap: () => Get.to(() => ProfilePostDetailScreen(post: post)),
      child: Container(
        height: tileHeight,
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.trim().isNotEmpty)
              AppCachedImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                progressive: true,
                lowResolutionWidth: 480,
                highResolutionWidth: 720,
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    caption.isEmpty ? 'Scrole' : caption,
                    maxLines: 7,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (caption.isNotEmpty && imageUrl.trim().isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB8000000)],
                    ),
                  ),
                  child: Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            if (media.isVideo)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 23,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
            if (post.media.length > 1)
              const Positioned(
                top: 8,
                left: 8,
                child: Icon(
                  Icons.collections_rounded,
                  color: Colors.white,
                  size: 20,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchTabItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SearchTabItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              height: 2,
              width: 24,
              decoration: BoxDecoration(
                color: isSelected ? colorScheme.onSurface : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SearchResultItem item;
  final VoidCallback onTap;

  const _SearchResultTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    IconData fallbackIcon = Icons.search_rounded;
    if (item.category == 'user') fallbackIcon = Icons.person_rounded;
    if (item.category == 'event') fallbackIcon = Icons.event_rounded;
    if (item.category == 'activity') fallbackIcon = Icons.local_activity_rounded;
    if (item.category == 'community') fallbackIcon = Icons.groups_rounded;
    if (item.category == 'tag' || item.category == 'hashtag') fallbackIcon = Icons.tag_rounded;

    String localizedCategory = item.category;
    if (item.category == 'user') localizedCategory = 'filter_users'.tr;
    if (item.category == 'event') localizedCategory = 'filter_events'.tr;
    if (item.category == 'activity') localizedCategory = 'filter_activities'.tr;
    if (item.category == 'community') localizedCategory = 'filter_communities'.tr;
    if (item.category == 'tag' || item.category == 'hashtag') localizedCategory = 'filter_tags'.tr;

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: item.category == 'user' ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: item.category != 'user' ? BorderRadius.circular(10) : null,
          color: colorScheme.surfaceContainerHighest,
        ),
        child: ClipRRect(
          borderRadius: item.category != 'user' ? BorderRadius.circular(10) : BorderRadius.circular(23),
          child: item.photoUrl != null && item.photoUrl!.isNotEmpty
              ? AppCachedImage(imageUrl: item.photoUrl!, fit: BoxFit.cover)
              : Icon(fallbackIcon, color: colorScheme.onSurfaceVariant),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              item.title,
              style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (item.category == 'user' && item.isCertified) ...[
            const SizedBox(width: 4),
            UserCertifiedBadge(size: 16, userId: item.id),
          ],
          if (item.category == 'event' || item.category == 'community') ...[
            EntityCertifiedBadge(
              entityType: item.category == 'community' ? 'community' : 'event',
              entityId: item.id,
              size: 16,
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              item.subtitle!,
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (item.category == 'user' && item.followsMe) ...[
            const SizedBox(height: 2),
            Text('follow_te_follows_you'.tr, style: TextStyle(color: colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
          if (item.category == 'user' && item.friendCount != null && item.friendCount! > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${item.friendCount} amis en commun',
              style: TextStyle(color: colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
      trailing: item.category == 'user'
          ? RelationButtonWidget(targetUserId: item.id)
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                localizedCategory.toUpperCase(),
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
    );
  }
}
