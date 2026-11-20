import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrole/app/utils/boot_timing.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/utils/main_responsive_breakpoints.dart';
import 'package:scrole/app/service_global/connectivity_service.dart';
import 'package:scrole/shared/widgets/search_screen.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import '../../../../app_controller.dart';
import '../../../module_communautes/interne/pages/create_community_post_screen.dart';
import '../pages/create_scut_camera_screen.dart';

import '../../../../../shared/widgets/glas_buton.dart';
import '../controllers/main_layout_controller.dart';

class _WideTopNavigation extends StatelessWidget {
  const _WideTopNavigation({
    required this.controller,
    required this.onSelected,
    required this.compact,
  });

  final MainLayoutController controller;
  final ValueChanged<int>? onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final destinations = <(int, Widget, String)>[
      (0, SvgPicture.asset('assets/svg_icons/japan-svgrepo-com.svg', width: 23, height: 23), 'nav_home'.tr),
      (1, SvgPicture.asset('assets/svg_icons/discussion.svg', width: 23, height: 23), 'Communautés'),
      (2, const Icon(Icons.video_library_outlined, size: 24), 'Réels'),
      (3, SvgPicture.asset('assets/svg_icons/event-promotion-sale-svgrepo-com.svg', width: 23, height: 23), 'nav_events'.tr),
      (4, SvgPicture.asset('assets/svg_icons/notification-svgrepo-com.svg', width: 23, height: 23), 'Notifications'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: destinations.map((destination) {
        final index = destination.$1;
        return Obx(() {
          final selected = controller.currentTab.value == index;
          Widget icon = IconTheme(
            data: IconThemeData(
              color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              size: 24,
            ),
            child: destination.$2,
          );
          if (index == 4) {
            icon = Badge(
              isLabelVisible: controller.hasNotifications,
              label: Text(controller.notificationBadge),
              child: icon,
            );
          }
          if (index == 5) {
            icon = const _TopNavProfileAvatar();
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Tooltip(
              message: destination.$3,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected?.call(index),
                child: Container(
                  width: compact ? 54 : 110,
                  height: 54,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selected ? colorScheme.primary : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Center(child: icon),
                ),
              ),
            ),
          );
        });
      }).toList(),
    );
  }
}

class _TopNavProfileAvatar extends StatelessWidget {
  const _TopNavProfileAvatar();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appController = Get.find<AppController>();
    return Obx(() {
      final profile = appController.profile.value;
      final avatarUrl = profile?['photo_url']?.toString() ?? '';
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.primary, width: 1.5),
        ),
        child: ClipOval(
          child: avatarUrl.isNotEmpty
              ? AppCachedImage(
                  imageUrl: avatarUrl,
                  cacheInPersistentStore: true,
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                )
              : Container(
                  color: colorScheme.surfaceContainerHigh,
                  child: Icon(Icons.person_rounded, size: 17, color: colorScheme.onSurfaceVariant),
                ),
        ),
      );
    });
  }
}

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final MainLayoutController controller;
  final ValueChanged<int>? onDestinationSelected;
  final VoidCallback? onLogoTap;

  const CustomAppBar({
    super.key,
    required this.controller,
    this.onDestinationSelected,
    this.onLogoTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(72);

  static final GlobalKey _actionsKey = GlobalKey();

  Future<void> _showCreationMenu(BuildContext context) async {
    final actionsContext = _actionsKey.currentContext;
    final actionsBox = actionsContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (actionsBox == null || overlayBox == null) return;

    final topLeft = actionsBox.localToGlobal(
      Offset(0, actionsBox.size.height),
      ancestor: overlayBox,
    );
    final bottomRight = actionsBox.localToGlobal(
      Offset(actionsBox.size.width, actionsBox.size.height),
      ancestor: overlayBox,
    );
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlayBox.size,
      ),
      color: Theme.of(context).colorScheme.surfaceContainer,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'post',
          child: Row(
            children: [
              Icon(Icons.post_add_rounded,
                  color: Theme.of(context).colorScheme.onSurface, size: 21),
              const SizedBox(width: 12),
              Text('creation_menu_create_post'.tr,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  )),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'scut',
          child: Row(
            children: [
              Icon(Icons.video_library_rounded,
                  color: Theme.of(context).colorScheme.onSurface, size: 21),
              const SizedBox(width: 12),
              Text('creation_menu_create_scut'.tr,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  )),
            ],
          ),
        ),
      ],
    );
    if (selected != null) _openCreation(selected);
  }

  void _openCreation(String type) {
    if (type == 'scut') {
      Get.to(() => const CreateScutCameraScreen(), fullscreenDialog: true);
      return;
    }
    Get.to(
      () => const CreateCommunityPostScreen(
        communityName: 'Fil d\'actualité général',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bootLog('CustomAppBar.build');
    final width = MediaQuery.sizeOf(context).width;
    if (MainResponsiveBreakpoints.isMobile(width)) {
      return _buildMobileAppBar(context);
    }
    return _buildWideAppBar(context, width);
  }

  Widget _buildMobileAppBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.transparent,
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Builder(
                  builder: (drawerContext) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Scaffold.of(drawerContext).openDrawer(),
                    child: Obx(() {
                      final isOnline = Get.find<ConnectivityService>().isConnected.value;
                      return AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                        style: GoogleFonts.grandHotel(
                          fontSize: 39,
                          fontWeight: FontWeight.w400,
                          height: 1.05,
                          letterSpacing: 0.15,
                          color: isOnline ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
                        ),
                        child: const Text('Scrole'),
                      );
                    }),
                  ),
                ),
              ),
            ),
            const Spacer(flex: 2),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlassmorphismButton(
                        icon: SvgPicture.asset('assets/svg_icons/search.svg', width: 22, height: 22,
                          colorFilter: ColorFilter.mode(colorScheme.onSurface, BlendMode.srcIn)),
                        onTap: () => Get.to(() => const SearchScreen()),
                      ),
                      const SizedBox(width: 8),
                      GlassmorphismButton(
                        icon: const Icon(Icons.add_rounded, size: 25),
                        onTap: () => _showCreationMenu(context),
                      ),
                      const SizedBox(width: 8),
                      Obx(() => GlassmorphismButton(
                        icon: SvgPicture.asset('assets/svg_icons/chat-round-svgrepo-com.svg', width: 22, height: 22,
                          colorFilter: ColorFilter.mode(colorScheme.onSurface, BlendMode.srcIn)),
                        badgeCount: double.tryParse(controller.messageBadge),
                        onTap: controller.openMessages,
                      )),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideAppBar(BuildContext context, double width) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTablet = MainResponsiveBreakpoints.isTablet(width);
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: .35))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: isTablet ? 130 : 310,
            child: Row(
              children: [
                GestureDetector(
                  onTap: onLogoTap,
                  child: Text(
                    'Scrole',
                    style: GoogleFonts.grandHotel(fontSize: 34, color: colorScheme.onSurface, height: 1.0),
                  ),
                ),
                if (!isTablet) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => Get.to(() => const SearchScreen()),
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: .7),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded, size: 19, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Rechercher sur Scrole', maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else
                  IconButton(
                    tooltip: 'Rechercher',
                    onPressed: () => Get.to(() => const SearchScreen()),
                    icon: const Icon(Icons.search_rounded),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _WideTopNavigation(
                  controller: controller,
                  onSelected: onDestinationSelected,
                  compact: isTablet,
                ),
              ),
            ),
          ),
          SizedBox(
            width: isTablet ? 190 : 310,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _roundAction(
                  context,
                  icon: Icons.explore_outlined,
                  tooltip: 'Explorer',
                  onTap: () => Get.to(() => const SearchScreen()),
                ),
                _roundAction(
                  context,
                  icon: Icons.add_rounded,
                  tooltip: 'Créer',
                  onTap: () => _showCreationMenu(context),
                ),
                Obx(() => _roundAction(
                  context,
                  icon: Icons.chat_bubble_outline_rounded,
                  tooltip: 'Messages',
                  badge: double.tryParse(controller.messageBadge),
                  onTap: controller.openMessages,
                )),
                if (!isTablet)
                  Obx(() => _roundAction(
                    context,
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Notifications',
                    badge: controller.hasNotifications ? double.tryParse(controller.notificationBadge) ?? 1 : null,
                    onTap: controller.openNotifications,
                  )),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => Get.toNamed(AppPages.myprofil),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: _TopNavProfileAvatar(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundAction(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double? badge,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: .8),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: badge != null && badge > 0
                    ? Badge(label: Text(badge.toInt().toString()), child: Icon(icon, size: 21))
                    : Icon(icon, size: 21, color: colorScheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
