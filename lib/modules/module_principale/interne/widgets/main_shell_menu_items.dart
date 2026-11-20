import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/routes/app_pages.dart';
import '../pages/../../../../shared/widgets/external_web_view_screen.dart';

class MainShellMenuItem {
  const MainShellMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
}

/// Source unique des entrées du drawer mobile et du menu latéral grand écran.
abstract final class MainShellMenuItems {
  static List<MainShellMenuItem> build(
    ColorScheme colors, {
    VoidCallback? closeDrawer,
  }) {
    void close() => closeDrawer?.call();
    return [
      MainShellMenuItem(
        icon: Icons.folder_copy_outlined,
        label: 'drawer_my_content'.tr,
        color: colors.tertiary,
        onTap: () {
          close();
          Get.toNamed(AppPages.myContent);
        },
      ),
      MainShellMenuItem(
        icon: Icons.add_circle_outline_rounded,
        label: 'drawer_creation'.tr,
        color: colors.secondary,
        onTap: () {
          close();
          Get.toNamed(AppPages.creationSelection);
        },
      ),
      MainShellMenuItem(
        icon: Icons.info_outline_rounded,
        label: 'drawer_about'.tr,
        color: colors.primary,
        onTap: () {
          close();
          Get.to(() => ExternalWebViewScreen(
            url: 'https://about.scrole.fun',
            title: 'webview_about_title'.tr,
          ));
        },
      ),
      MainShellMenuItem(
        icon: Icons.settings_outlined,
        label: 'drawer_settings'.tr,
        color: colors.onSurfaceVariant,
        onTap: () {
          close();
          Get.toNamed(AppPages.setting);
        },
      ),
    ];
  }
}
