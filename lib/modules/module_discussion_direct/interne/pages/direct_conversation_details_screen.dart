import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../module_decouverte/centre/models/external_profile_model.dart';
import '../../../module_decouverte/externe/repositories/external_profile_repository.dart';
import '../controllers/direct_conversation_controller.dart';
import 'chat_wallpaper_selection_screen.dart';

class DirectConversationDetailsScreen extends StatefulWidget {
  const DirectConversationDetailsScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userColor,
    this.userAvatar,
  });

  final String userId;
  final String userName;
  final Color userColor;
  final String? userAvatar;

  @override
  State<DirectConversationDetailsScreen> createState() =>
      _DirectConversationDetailsScreenState();
}

class _DirectConversationDetailsScreenState
    extends State<DirectConversationDetailsScreen> {
  final ExternalProfileRepository _profileRepository =
      ExternalProfileRepository();

  bool _notificationsEnabled = true;
  bool _mediaVisibilityEnabled = true;
  ExternalProfileModel? _profile;
  bool _canApplySharedWallpaper = false;
  bool _checkingWallpaperEntitlement = true;

  String get _displayName {
    final name = (_profile?.username ?? widget.userName).trim();
    if (name.isEmpty) return name;
    return name[0].toUpperCase() + name.substring(1);
  }

  String get _username => _profile?.username ?? '';

  String? get _avatarUrl {
    final value = _profile?.photoUrl ?? widget.userAvatar;
    return value == null || value.trim().isEmpty ? null : value;
  }

  String? get _coverUrl {
    final value = _profile?.photoUrl;
    return value == null || value.trim().isEmpty ? null : value;
  }

  bool get _isVerified => _profile?.isCertified ?? false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadWallpaperEntitlement();
  }

  Future<void> _loadProfile() async {
    if (widget.userId.trim().isEmpty) return;
    try {
      final profile = await _profileRepository.getProfile(widget.userId);
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (_) {
      // The chat-provided identity remains available if the profile request fails.
    }
  }

  Future<void> _loadWallpaperEntitlement() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final level = await Supabase.instance.client.rpc(
        'get_public_profile_certification_level',
        params: {'p_user_id': uid},
      );
      if (mounted) {
        setState(() => _canApplySharedWallpaper =
            const {'basique', 'pro', 'premium'}.contains('$level'.toLowerCase()));
      }
    } catch (_) {
      if (mounted) setState(() => _canApplySharedWallpaper = false);
    } finally {
      if (mounted) setState(() => _checkingWallpaperEntitlement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProfile,
          color: colors.primary,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildHeader(colors),
              const SizedBox(height: 12),
              _buildIdentity(colors),
              const SizedBox(height: 24),
              _buildSettingsSection(colors),
              const SizedBox(height: 16),
              _buildWallpaperSection(colors),
              const SizedBox(height: 16),
              _buildDangerSection(colors),
              const SizedBox(height: 16),
              _buildReportSection(colors),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colors) {
    return SizedBox(
      height: 185,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            height: 140,
            width: double.infinity,
            child: _coverUrl == null
                ? Container(color: AppColors.secondary.withValues(alpha: .25))
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      AppCachedImage(imageUrl: _coverUrl!, fit: BoxFit.cover),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: .28),
                              Colors.transparent,
                              colors.surface.withValues(alpha: .35),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          Positioned(
            top: 12,
            left: 16,
            child: _headerButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: Get.back,
            ),
          ),
          Positioned(
            top: 12,
            right: 16,
            child: _headerButton(
              icon: Icons.more_horiz_rounded,
              onTap: () => _comingSoon('direct_details_more_action'.tr),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 20,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 5),
                color: widget.userColor.withValues(alpha: .12),
              ),
              child: ClipOval(
                child: _avatarUrl == null
                    ? Center(
                        child: Text(
                          _displayName.isEmpty
                              ? '?'
                              : _displayName.characters.first.toUpperCase(),
                          style: TextStyle(
                            color: widget.userColor,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : AppCachedImage(imageUrl: _avatarUrl!, fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: .42),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildIdentity(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _displayName,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h4.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (_isVerified) ...[
                      const SizedBox(width: 6),
                      const UserCertifiedBadge(size: 20),
                    ],
                  ],
                ),
                if (_username.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '@$_username',
                    style: AppTextStyles.body.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Material(
                color: colors.surfaceContainerHighest.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  onTap: () => Get.toNamed(
                    AppPages.externalProfilePath(widget.userId),
                  ),
                  borderRadius: BorderRadius.circular(13),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 21,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _section(
        colors,
        children: [
          _switchTile(
            icon: Icons.notifications_none_rounded,
            title: 'direct_details_notifications'.tr,
            value: _notificationsEnabled,
            onChanged: (value) =>
                setState(() => _notificationsEnabled = value),
          ),
          _switchTile(
            icon: Icons.photo_library_outlined,
            title: 'direct_details_media_visibility'.tr,
            subtitle: 'direct_details_media_visibility_subtitle'.tr,
            value: _mediaVisibilityEnabled,
            onChanged: (value) =>
                setState(() => _mediaVisibilityEnabled = value),
          ),
        ],
      ),
    );
  }

  Widget _buildWallpaperSection(ColorScheme colors) {
    final controller = Get.isRegistered<DirectConversationController>()
        ? Get.find<DirectConversationController>()
        : null;

    if (controller == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _section(
        colors,
        children: [
          _actionTile(
            icon: Icons.wallpaper_rounded,
            title: 'direct_details_wallpaper'.tr,
            subtitle: _canApplySharedWallpaper
                ? 'Choisis un fond pour toi uniquement ou pour vous deux.'
                : 'Fond personnel. La modification commune nécessite la certification Basique ou supérieure.',
            onTap: () {
              Get.to(
                () => ChatWallpaperSelectionScreen(
                  initialWallpaper: controller.selectedWallpaper.value,
                  userName: _displayName,
                  userColor: widget.userColor,
                  userAvatar: _avatarUrl,
                  canApplyToBoth: _canApplySharedWallpaper && !_checkingWallpaperEntitlement,
                  initialApplyToBoth: controller.isSharedWallpaper.value,
                  onApply: (wallpaperKey, applyToBoth) =>
                      controller.setWallpaper(wallpaperKey, applyToBoth: applyToBoth),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDangerSection(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _section(
        colors,
        children: [
          _actionTile(
            icon: Icons.history_rounded,
            title: 'direct_details_clear'.tr,
            destructive: true,
            onTap: _confirmClearConversation,
          ),
          _actionTile(
            icon: Icons.block_rounded,
            title: 'direct_details_block'.trParams({'name': _displayName}),
            destructive: true,
            onTap: _confirmBlock,
          ),
        ],
      ),
    );
  }

  Widget _buildReportSection(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _section(
        colors,
        children: [
          _actionTile(
            icon: Icons.flag_outlined,
            title: 'direct_details_report'.trParams({'name': _displayName}),
            destructive: true,
            onTap: () => _comingSoon('direct_details_report_action'.tr),
          ),
        ],
      ),
    );
  }

  Widget _section(ColorScheme colors, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline.withValues(alpha: .08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive ? AppColors.error : colors.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: color, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant.withValues(alpha: .6),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
        child: Row(
          children: [
            Icon(icon, size: 21, color: colors.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  void _confirmBlock() {
    Get.dialog(
      AlertDialog(
        title: Text(
          'direct_details_block_title'.trParams({'name': _displayName}),
        ),
        content: Text('direct_details_block_message'.tr),
        actions: [
          TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Get.back();
              _comingSoon('direct_details_block_user'.tr);
            },
            child: Text('direct_details_block_action'.tr),
          ),
        ],
      ),
    );
  }

  void _confirmClearConversation() {
    Get.dialog(
      AlertDialog(
        title: Text('direct_details_clear_title'.tr),
        content: Text('direct_details_clear_message'.tr),
        actions: [
          TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
          FilledButton(
            onPressed: () {
              Get.back();
              _comingSoon('direct_details_clear_history'.tr);
            },
            child: Text('direct_details_clear_action'.tr),
          ),
        ],
      ),
    );
  }

  void _comingSoon(String feature) {
    Get.snackbar(
      'chats_title'.tr,
      'direct_details_coming_soon'.trParams({'feature': feature}),
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 2),
    );
  }
}
