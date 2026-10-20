import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/service_global/privacy_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/models/user_models.dart';

class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final PrivacyService service = Get.find<PrivacyService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.grey[400]! : Colors.black54;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => Get.back(),
        ),
        title: Text(
          'settings_privacy_data'.tr,
          style: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: Obx(() {
        final p = service.privacy.value;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            _buildSwitchTile(
              title: 'privacy_use_data_improve'.tr,
              subtitle: 'privacy_use_data_improve_desc'.tr,
              value: true,
              onChanged: (val) {},
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            const SizedBox(height: 20),
            _buildSwitchTile(
              title: 'privacy_use_data_personalize'.tr,
              subtitle: 'privacy_use_data_personalize_desc'.tr,
              value: true,
              onChanged: (val) {},
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            const SizedBox(height: 20),
            _buildSwitchTile(
              title: 'Show online status', // Keep as is or add translation
              subtitle: 'Allows your friends and community members to see when you are active.',
              value: p.showOnlineStatus,
              onChanged: (val) {
                service.applyPrivacy(AppPrivacy(
                  profileVisibility: p.profileVisibility,
                  showOnlineStatus: val,
                  allowMessagesFrom: p.allowMessagesFrom,
                  afficherPays: p.afficherPays,
                  afficherVille: p.afficherVille,
                  afficherDerniereConnexion: p.afficherDerniereConnexion,
                ));
              },
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('privacy_request_data'.tr, textSecondary),
            const SizedBox(height: 12),
            _buildActionTile(
              title: 'privacy_request_all'.tr,
              onTap: () {},
              textPrimary: textPrimary,
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('privacy_policies_disclosures'.tr, textSecondary),
            const SizedBox(height: 12),
            _buildActionTile(
              title: 'terms'.tr,
              onTap: () {},
              textPrimary: textPrimary,
              showDivider: true,
            ),
            _buildActionTile(
              title: 'privacy_policy'.tr,
              onTap: () {},
              textPrimary: textPrimary,
            ),
            const SizedBox(height: 24),
            Text(
              'privacy_footer_notice'.tr,
              style: TextStyle(color: textSecondary, fontSize: 13, height: 1.5),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Text(
      title,
      style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.primary,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: textSecondary, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required String title,
    required VoidCallback onTap,
    required Color textPrimary,
    bool showDivider = false,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.black1,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
        if (showDivider) const SizedBox(height: 8),
      ],
    );
  }
}
