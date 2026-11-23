import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:get/get.dart';

import '../../../../app/routes/app_pages.dart';
import '../../../../shared/widgets/external_web_view_screen.dart';

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
        onTap: () async {
          close();
          final uri = Uri.parse('https://about.scrole.fun');
          if (kIsWeb) {
            // The About site is accessible directly but does not render inside
            // the Flutter Web iframe. Open it in a browser tab instead.
            final opened = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
            if (!opened) {
              Get.snackbar(
                'drawer_about'.tr,
                'Impossible d’ouvrir la page. Réessaie dans un instant.',
                snackPosition: SnackPosition.BOTTOM,
              );
            }
            return;
          }
          Get.to(() => ExternalWebViewScreen(
            url: uri.toString(),
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
