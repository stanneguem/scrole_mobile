import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/service_global/app_config_service.dart';

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = Get.find<AppConfigService>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final titleColor = Theme.of(context).colorScheme.onSurface;
    final description = config.updateMessage.value.trim();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 104, height: 104,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.system_update_rounded, size: 56, color: primary),
                  ),
                  const SizedBox(height: 28),
                  Text('update_required_title'.tr,
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: titleColor),
                    textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  Text(description.isNotEmpty ? description : 'update_required_message'.tr,
                    style: TextStyle(height: 1.55, color: dark ? Colors.white70 : Colors.black54),
                    textAlign: TextAlign.center),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openStore(config),
                      icon: const Icon(Icons.download_rounded),
                      label: Text('update_button'.tr),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${'update_required_version'.tr}: ${config.currentServerVersion.value}',
                    style: TextStyle(fontSize: 12, color: dark ? Colors.white54 : Colors.black45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openStore(AppConfigService config) async {
    final configuredUrl = Platform.isIOS ? config.iosStoreUrl.value : config.androidStoreUrl.value;
    final url = configuredUrl.trim();
    if (url.isEmpty) {
      Get.snackbar('update_required_title'.tr, 'update_store_unavailable'.tr,
        snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !{'https', 'http'}.contains(uri.scheme)) {
      Get.snackbar('update_required_title'.tr, 'update_store_unavailable'.tr,
        snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      Get.snackbar('update_required_title'.tr, 'update_store_unavailable'.tr,
        snackPosition: SnackPosition.BOTTOM);
    }
  }
}
