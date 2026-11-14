import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrole/app/utils/boot_timing.dart';
import 'package:scrole/app/service_global/connectivity_service.dart';
import 'package:scrole/shared/widgets/search_screen.dart';
import '../../../module_communautes/interne/pages/create_community_post_screen.dart';

import '../../../../../shared/widgets/glas_buton.dart';
import '../controllers/main_layout_controller.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final MainLayoutController controller;

  const CustomAppBar({super.key, required this.controller});

  @override
  Size get preferredSize => const Size.fromHeight(72);

  final GlobalKey _actionsKey = GlobalKey();

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
              Text('Créer un post',
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
              Text('Créer un Scut',
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
    // Le compositeur général accepte les photos et les vidéos.
    // Les publications contenant une vidéo alimentent le fil des Scuts.
    Get.to(
      () => const CreateCommunityPostScreen(
        communityName: 'Fil d\\'actualité général',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bootLog('CustomAppBar.build');
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Container(
        height: preferredSize.height,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.transparent,
        child: Row(
          children: [
            Builder(
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
                      color: isOnline
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
                    ),
                    child: const Text('Scrole'),
                  );
                }),
              ),
            ),
            const Spacer(),
            Row(
              key: _actionsKey,
              children: [
                GlassmorphismButton(
                  icon: const Icon(Icons.add_rounded, size: 25),
                  onTap: () => _showCreationMenu(context),
                ),
                const SizedBox(width: 8),
                GlassmorphismButton(
                  icon: SvgPicture.asset(
                    'assets/svg_icons/search.svg',
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(
                      colorScheme.onSurface,
                      BlendMode.srcIn,
                    ),
                  ),
                  onTap: () => Get.to(() => const SearchScreen()),
                ),
                const SizedBox(width: 8),
                Obx(() => GlassmorphismButton(
                      icon: SvgPicture.asset(
                        'assets/svg_icons/chat-round-svgrepo-com.svg',
                        width: 22,
                        height: 22,
                        colorFilter: ColorFilter.mode(
                          colorScheme.onSurface,
                          BlendMode.srcIn,
                        ),
                      ),
                      badgeCount: double.tryParse(controller.messageBadge),
                      onTap: controller.openMessages,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
