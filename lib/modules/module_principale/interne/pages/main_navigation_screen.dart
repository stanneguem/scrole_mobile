import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:scrole/app/utils/boot_timing.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/shared/widgets/search_screen.dart';
import 'package:scrole/shared/constantes/image_path.dart';
import 'package:scrole/shared/widgets/external_web_view_screen.dart';
import '../../../module_evenement/interne/pages/event_screen.dart';
import '../../../module_communautes/interne/pages/community_screen.dart';
import '../../../module_communautes/interne/controllers/community/community_controller.dart';
import '../pages/home_feed_screen.dart';
import '../pages/reels_screen.dart';
import '../../../../app_controller.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../controllers/main_layout_controller.dart';
import '../widgets/main_app_bar.dart';

class MainLayoutPage extends StatefulWidget {
  const MainLayoutPage({super.key});

  @override
  State<MainLayoutPage> createState() => _MainLayoutPageState();
}

class _MainLayoutPageState extends State<MainLayoutPage> {
  final GlobalKey<HomeFeedScreenState> _homeFeedKey = GlobalKey<HomeFeedScreenState>();
  int _currentIndex = 0;
  final List<bool> _visited = [true, false, false]; // Home, Community, Events
  bool _isBottomNavVisible = true;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<MainLayoutController>()) {
      ever(Get.find<MainLayoutController>().currentTab, (idx) {
        int navIdx = idx;
        int stackIdx = 0;
        if (navIdx == 1) stackIdx = 1;
        else if (navIdx == 3) stackIdx = 2;
        else stackIdx = 0;
        if (mounted && _currentIndex != stackIdx) {
          setState(() {
            _currentIndex = stackIdx;
            _visited[stackIdx] = true;
            _isBottomNavVisible = true;
          });
        }
      });
    }
  }

  late final List<Widget> _pages = [
    HomeFeedScreen(key: _homeFeedKey), // 0. Accueil
    CommunityScreen(),    // 1. Communautés
    EventScreen(),        // 2. Événements
  ];

  void _onTabChanged(int index) {
    if (index == 2) {
      // Reels open as a separate full-screen route, like the profile.
      Get.to(() => const ReelsScreen(), fullscreenDialog: true);
      return;
    }
    if (index == 4) {
      // Notifications are opened from the bottom navigation bar.
      Get.find<MainLayoutController>().openNotifications();
      return;
    }
    if (index == 5) {
      // Profile avatar
      Get.toNamed(AppPages.myprofil);
      return;
    }
    int stackIndex = 0;
    if (index == 1) {
      stackIndex = 1;
    } else if (index == 3) {
      stackIndex = 2;
    } else {
      stackIndex = 0;
    }

    final wasAlreadyOnSelectedTab = _currentIndex == stackIndex;

    setState(() {
      _currentIndex = stackIndex;
      _visited[stackIndex] = true;
      _isBottomNavVisible = true;
    });

    if (Get.isRegistered<MainLayoutController>()) {
      Get.find<MainLayoutController>().currentTab.value = index;
    }

    if (index == 0 && wasAlreadyOnSelectedTab) {
      _homeFeedKey.currentState?.scrollToTopAndRefresh();
    }

    // The community tab is kept alive in the page stack, so onInit alone
    // does not run again when the user returns to it.
    if (stackIndex == 1 && Get.isRegistered<CommunityController>()) {
      Get.find<CommunityController>().loadCommunities();
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.axis == Axis.horizontal) {
        return false;
      }
      if (notification.scrollDelta! > 10 && _isBottomNavVisible) {
        setState(() => _isBottomNavVisible = false);
      } else if (notification.scrollDelta! < -10 && !_isBottomNavVisible) {
        setState(() => _isBottomNavVisible = true);
      }
    }
    return false;
  }

  Widget _buildTabletNavigation(
    MainLayoutController controller,
    ColorScheme colorScheme,
  ) {
    Widget destination(int index, Widget icon, String tooltip) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Obx(() {
          final selected = controller.currentTab.value == index;
          return Tooltip(
            message: tooltip,
            child: Material(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.13)
                  : Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _onTabChanged(index),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Center(
                    child: IconTheme(
                      data: IconThemeData(
                        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        size: 25,
                      ),
                      child: icon,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      );
    }

    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.45))),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            destination(0, SvgPicture.asset('assets/svg_icons/japan-svgrepo-com.svg', width: 25, height: 25, colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn)), 'nav_home'.tr),
            destination(1, SvgPicture.asset('assets/svg_icons/discussion.svg', width: 25, height: 25, colorFilter: ColorFilter.mode(colorScheme.onSurfaceVariant, BlendMode.srcIn)), 'Communautés'),
            destination(2, const Icon(Icons.video_library_rounded), 'Réels'),
            destination(3, SvgPicture.asset('assets/svg_icons/event-promotion-sale-svgrepo-com.svg', width: 25, height: 25, colorFilter: ColorFilter.mode(colorScheme.onSurfaceVariant, BlendMode.srcIn)), 'nav_events'.tr),
            destination(4, Obx(() => Badge(
              isLabelVisible: controller.hasNotifications,
              label: Text(controller.notificationBadge),
              child: SvgPicture.asset('assets/svg_icons/notification-svgrepo-com.svg', width: 25, height: 25, colorFilter: ColorFilter.mode(colorScheme.onSurfaceVariant, BlendMode.srcIn)),
            )), 'Notifications'),
            destination(5, const _BottomNavProfileIcon(isSelected: false), 'nav_profile'.tr),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar(
    MainLayoutController controller,
    ColorScheme colorScheme,
  ) {
    Widget item({
      required int index,
      required String label,
      required Widget icon,
    }) {
      return Obx(() {
        final selected = controller.currentTab.value == index;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Material(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _onTabChanged(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    SizedBox(width: 28, height: 28, child: Center(child: icon)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? colorScheme.primary : colorScheme.onSurface,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      });
    }

    Widget svg(String asset, {bool badge = false}) {
      final image = SvgPicture.asset(
        asset,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(colorScheme.onSurfaceVariant, BlendMode.srcIn),
      );
      return badge
          ? Obx(() => Badge(
                isLabelVisible: controller.hasNotifications,
                label: Text(controller.notificationBadge),
                child: image,
              ))
          : image;
    }

    return Container(
      width: 244,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.45))),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 16, 18),
              child: Text(
                'Scrole',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
            ),
            item(index: 0, label: 'nav_home'.tr, icon: SvgPicture.asset('assets/svg_icons/japan-svgrepo-com.svg', width: 25, height: 25, colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn))),
            item(index: 1, label: 'Communautés', icon: svg('assets/svg_icons/discussion.svg')),
            item(index: 2, label: 'Réels', icon: Icon(Icons.video_library_rounded, color: colorScheme.onSurfaceVariant, size: 25)),
            item(index: 3, label: 'nav_events'.tr, icon: svg('assets/svg_icons/event-promotion-sale-svgrepo-com.svg')),
            item(index: 4, label: 'Notifications', icon: svg('assets/svg_icons/notification-svgrepo-com.svg', badge: true)),
            item(index: 5, label: 'nav_profile'.tr, icon: const _BottomNavProfileIcon(isSelected: false)),
            const Spacer(),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Text(
                'Scrole',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bootLog('MainNavigationScreen.build');
    if (!Get.isRegistered<MainLayoutController>()) {
      Get.put(MainLayoutController());
    }

    final controller = Get.find<MainLayoutController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(controller: controller),
      drawer: const AppDrawer(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 1100;
          final isTablet = constraints.maxWidth >= 760 && !isDesktop;
          return Row(
            children: [
              if (isDesktop) _buildDesktopSidebar(controller, colorScheme),
              if (isTablet) _buildTabletNavigation(controller, colorScheme),
              Expanded(
                child: Stack(
                  children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width >= 1100 ? 1180 : 1040,
                  ),
                  child: IndexedStack(
                    index: _currentIndex,
                    children: List.generate(_pages.length, (index) {
                      if (!_visited[index]) return const SizedBox.shrink();
                      return _pages[index];
                    }),
                  ),
                ),
              ),
            ),
          ),
                    if (!isDesktop && !isTablet)
                    Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedSlide(
                    duration: const Duration(milliseconds: 250),
                    offset: _isBottomNavVisible ? Offset.zero : const Offset(0, 1),
                    child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: _isBottomNavVisible ? 1.0 : 0.0,
                    child: BottomNavigationBar(
                    type: BottomNavigationBarType.fixed,
                    currentIndex: _currentIndex == 2 ? 4 : _currentIndex,
                    onTap: _onTabChanged,
                    backgroundColor: colorScheme.surface,
                    selectedItemColor: colorScheme.primary,
                    unselectedItemColor: colorScheme.onSurfaceVariant,
                    showSelectedLabels: false,
                    showUnselectedLabels: false,
                    elevation: 8,
                    iconSize: 25,
                    items: [
                    BottomNavigationBarItem(
                    icon: SvgPicture.asset(
                    'assets/svg_icons/japan-svgrepo-com.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(colorScheme.onSurfaceVariant, BlendMode.srcIn),
                    ),
                    activeIcon: SvgPicture.asset(
                    'assets/svg_icons/japan-svgrepo-com.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
                    ),
                    label: 'nav_home'.tr,
                    ),
                    BottomNavigationBarItem(
                    icon: SvgPicture.asset(
                    'assets/svg_icons/discussion.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(colorScheme.onSurfaceVariant, BlendMode.srcIn),
                    ),
                    activeIcon: SvgPicture.asset(
                    'assets/svg_icons/discussion.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
                    ),
                    label: 'Communautés',
                    ),
                    const BottomNavigationBarItem(
                    icon: Icon(Icons.video_library_outlined),
                    activeIcon: Icon(Icons.video_library_rounded),
                    label: 'Réels',
                    ),
                    BottomNavigationBarItem(
                    icon: SvgPicture.asset(
                    'assets/svg_icons/event-promotion-sale-svgrepo-com.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(colorScheme.onSurfaceVariant, BlendMode.srcIn),
                    ),
                    activeIcon: SvgPicture.asset(
                    'assets/svg_icons/event-promotion-sale-svgrepo-com.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
                    ),
                    label: 'nav_events'.tr,
                    ),
                    BottomNavigationBarItem(
                    icon: Obx(() => Badge(
                    isLabelVisible: controller.hasNotifications,
                    label: Text(controller.notificationBadge),
                    child: SvgPicture.asset(
                    'assets/svg_icons/notification-svgrepo-com.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(colorScheme.onSurfaceVariant, BlendMode.srcIn),
                    ),
                    )),
                    activeIcon: Obx(() => Badge(
                    isLabelVisible: controller.hasNotifications,
                    label: Text(controller.notificationBadge),
                    child: SvgPicture.asset(
                    'assets/svg_icons/notification-svgrepo-com.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
                    ),
                    )),
                    label: 'Notifications',
                    ),
                    BottomNavigationBarItem(
                    icon: const _BottomNavProfileIcon(isSelected: false),
                    activeIcon: _BottomNavProfileIcon(isSelected: true),
                    label: 'nav_profile'.tr,
                    ),
                    ],
                    ),
                    ),
                    ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BottomNavProfileIcon extends StatelessWidget {
  const _BottomNavProfileIcon({required this.isSelected});
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appController = Get.find<AppController>();

    return Obx(() {
      final profile = appController.profile.value;
      final avatar = profile?['photo_url']?.toString() ?? '';

      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: isSelected ? 2 : 1.5,
          ),
        ),
        child: ClipOval(
          child: avatar.isNotEmpty
              ? AppCachedImage(
                  imageUrl: avatar,
                  cacheInPersistentStore: true,
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                )
              : Container(
                  color: colorScheme.surfaceContainerHigh,
                  child: Icon(
                    Icons.person_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      );
    });
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Image.asset(
                    ImagePath.logoApp,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Scrole',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.folder_copy_outlined, color: colorScheme.tertiary),
              title: Text('drawer_my_content'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(context).pop();
                Get.toNamed(AppPages.myContent);
              },
            ),
            ListTile(
              leading: Icon(Icons.add_circle_outline_rounded, color: colorScheme.secondary),
              title: Text('drawer_creation'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(context).pop();
                Get.toNamed(AppPages.creationSelection);
              },
            ),
            ListTile(
              leading: Icon(Icons.info_outline_rounded, color: colorScheme.primary),
              title: Text('drawer_about'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(context).pop();
                Get.to(() => ExternalWebViewScreen(
                  url: 'https://about.scrole.fun',
                  title: 'webview_about_title'.tr,
                ));
              },
            ),
            ListTile(
              leading: Icon(Icons.settings_outlined, color: colorScheme.onSurfaceVariant),
              title: Text('drawer_settings'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(context).pop();
                Get.toNamed(AppPages.setting);
              },
            ),
            const Spacer(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
