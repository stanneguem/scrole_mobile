import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/service_global/privacy_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/models/user_models.dart';

class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key});

  static const _visibilityValues = {'only_me', 'friends', 'followers', 'everyone'};

  @override
  Widget build(BuildContext context) {
    final service = Get.find<PrivacyService>();
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('settings_privacy_data'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: Obx(() {
        final p = service.privacy.value;
        final visibility = _visibilityValues.contains(p.eventItineraryVisibility)
            ? p.eventItineraryVisibility : 'only_me';
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _intro(context, colors),
            const SizedBox(height: 24),
            _sectionLabel('privacy_section_profile'.tr, colors),
            const SizedBox(height: 8),
            _group(context, [
              _switchTile(
                context,
                icon: CupertinoIcons.lock_shield,
                title: 'follow_profile_private'.tr,
                subtitle: 'follow_profile_private_desc'.tr,
                value: p.profileVisibility == 'private',
                onChanged: (value) => _saveProfileVisibility(service, p, value),
                colors: colors,
              ),
              _switchTile(
                context,
                icon: CupertinoIcons.eye,
                title: 'privacy_show_online_status'.tr,
                subtitle: 'privacy_show_online_status_desc'.tr,
                value: p.showOnlineStatus,
                onChanged: (value) => _saveOnlineStatus(service, p, value),
                colors: colors,
              ),
            ], colors),
            const SizedBox(height: 24),
            _sectionLabel('privacy_section_event_planning'.tr, colors),
            const SizedBox(height: 8),
            _group(context, [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(CupertinoIcons.calendar, color: colors.primary, size: 21),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('event_itinerary_visibility_title'.tr,
                        style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('event_itinerary_visibility_desc'.tr,
                        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13, height: 1.35)),
                  ])),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: dark ? .45 : .6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: visibility,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(14),
                      items: [
                        DropdownMenuItem(value: 'only_me', child: Text('event_itinerary_visibility_only_me'.tr)),
                        DropdownMenuItem(value: 'friends', child: Text('event_itinerary_visibility_friends'.tr)),
                        DropdownMenuItem(value: 'followers', child: Text('event_itinerary_visibility_followers'.tr)),
                        DropdownMenuItem(value: 'everyone', child: Text('event_itinerary_visibility_everyone'.tr)),
                      ],
                      onChanged: (value) {
                        if (value != null && value != visibility) _saveItineraryVisibility(service, p, value);
                      },
                    ),
                  ),
                ),
              ),
            ], colors),
            const SizedBox(height: 24),
            _sectionLabel('privacy_section_data'.tr, colors),
            const SizedBox(height: 8),
            _group(context, [
              _actionTile(
                context,
                icon: CupertinoIcons.doc_text,
                title: 'privacy_request_all'.tr,
                subtitle: 'privacy_request_data_desc'.tr,
                colors: colors,
                onTap: () => Get.snackbar('privacy_request_data'.tr, 'privacy_request_data_info'.tr,
                    snackPosition: SnackPosition.BOTTOM),
              ),
            ], colors),
            const SizedBox(height: 24),
            _sectionLabel('privacy_policies_disclosures'.tr, colors),
            const SizedBox(height: 8),
            _group(context, [
              _actionTile(context, icon: CupertinoIcons.doc_plaintext, title: 'terms'.tr,
                colors: colors, onTap: () => Get.snackbar('terms'.tr, 'privacy_link_unavailable'.tr)),
              _actionTile(context, icon: CupertinoIcons.hand_raised, title: 'privacy_policy'.tr,
                colors: colors, onTap: () => Get.snackbar('privacy_policy'.tr, 'privacy_link_unavailable'.tr)),
            ], colors),
            const SizedBox(height: 20),
            Text('privacy_footer_notice'.tr,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.45)),
          ],
        );
      }),
    );
  }

  Widget _intro(BuildContext context, ColorScheme colors) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [colors.primary.withValues(alpha: .13), colors.primary.withValues(alpha: .04)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colors.primary.withValues(alpha: .12)),
    ),
    child: Row(children: [
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(color: colors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
        child: Icon(CupertinoIcons.shield_lefthalf_filled, color: colors.primary, size: 24),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('privacy_intro_title'.tr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.onSurface)),
        const SizedBox(height: 4),
        Text('privacy_intro_desc'.tr, style: TextStyle(fontSize: 13, height: 1.35, color: colors.onSurfaceVariant)),
      ])),
    ]),
  );

  Widget _sectionLabel(String title, ColorScheme colors) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(title.toUpperCase(), style: TextStyle(
      color: colors.onSurfaceVariant, fontSize: 11, letterSpacing: 1.05, fontWeight: FontWeight.w700)),
  );

  Widget _group(BuildContext context, List<Widget> children, ColorScheme colors) => Container(
    decoration: BoxDecoration(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: colors.outlineVariant.withValues(alpha: .35)),
    ),
    child: Column(children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) Divider(height: 1, indent: 54, endIndent: 14, color: colors.outlineVariant.withValues(alpha: .35)),
        children[i],
      ],
    ]),
  );

  Widget _switchTile(BuildContext context, {required IconData icon, required String title,
    required String subtitle, required bool value, required ValueChanged<bool> onChanged,
    required ColorScheme colors}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    child: Row(children: [
      Container(width: 34, height: 34, decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .09), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: colors.primary)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.3)),
      ])),
      const SizedBox(width: 8),
      CupertinoSwitch(value: value, onChanged: onChanged, activeTrackColor: colors.primary),
    ]),
  );

  Widget _actionTile(BuildContext context, {required IconData icon, required String title,
    String? subtitle, required ColorScheme colors, required VoidCallback onTap}) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    onPressed: onTap,
    child: Row(children: [
      Icon(icon, size: 20, color: colors.primary),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Align(alignment: Alignment.centerLeft, child: Text(title,
          style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600))),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Align(alignment: Alignment.centerLeft, child: Text(subtitle,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12))),
        ],
      ])),
      Icon(CupertinoIcons.chevron_right, size: 16, color: colors.onSurfaceVariant),
    ]),
  );

  Future<void> _saveProfileVisibility(PrivacyService service, AppPrivacy p, bool isPrivate) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return _showError();
    try {
      await client.from('user_privacy').upsert({
        'user_id': userId,
        'profile_visibility': isPrivate ? 'private' : 'public',
        'show_online_status': p.showOnlineStatus,
        'allow_messages_from': p.allowMessagesFrom,
        'afficher_pays': p.afficherPays,
        'afficher_ville': p.afficherVille,
        'afficher_derniere_connexion': p.afficherDerniereConnexion,
        'event_itinerary_visibility': p.eventItineraryVisibility,
      }, onConflict: 'user_id');
      service.applyPrivacy(AppPrivacy(profileVisibility: isPrivate ? 'private' : 'public',
        showOnlineStatus: p.showOnlineStatus, allowMessagesFrom: p.allowMessagesFrom,
        afficherPays: p.afficherPays, afficherVille: p.afficherVille,
        afficherDerniereConnexion: p.afficherDerniereConnexion,
        eventItineraryVisibility: p.eventItineraryVisibility));
    } catch (e) { debugPrint('[PRIVACY] profile visibility save failed: $e'); _showError(); }
  }

  Future<void> _saveOnlineStatus(PrivacyService service, AppPrivacy p, bool value) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return _showError();
    try {
      await client.from('user_privacy').upsert({
        'user_id': userId,
        'profile_visibility': p.profileVisibility,
        'show_online_status': value,
        'allow_messages_from': p.allowMessagesFrom,
        'afficher_pays': p.afficherPays,
        'afficher_ville': p.afficherVille,
        'afficher_derniere_connexion': p.afficherDerniereConnexion,
        'event_itinerary_visibility': p.eventItineraryVisibility,
      }, onConflict: 'user_id');
      service.applyPrivacy(AppPrivacy(profileVisibility: p.profileVisibility,
        showOnlineStatus: value, allowMessagesFrom: p.allowMessagesFrom,
        afficherPays: p.afficherPays, afficherVille: p.afficherVille,
        afficherDerniereConnexion: p.afficherDerniereConnexion,
        eventItineraryVisibility: p.eventItineraryVisibility));
    } catch (e) { debugPrint('[PRIVACY] online status save failed: $e'); _showError(); }
  }

  Future<void> _saveItineraryVisibility(PrivacyService service, AppPrivacy p, String value) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return _showError();
    try {
      await client.from('user_privacy').upsert({
        'user_id': userId,
        'profile_visibility': p.profileVisibility,
        'show_online_status': p.showOnlineStatus,
        'allow_messages_from': p.allowMessagesFrom,
        'afficher_pays': p.afficherPays,
        'afficher_ville': p.afficherVille,
        'afficher_derniere_connexion': p.afficherDerniereConnexion,
        'event_itinerary_visibility': value,
      }, onConflict: 'user_id');
      service.applyPrivacy(AppPrivacy(profileVisibility: p.profileVisibility,
        showOnlineStatus: p.showOnlineStatus, allowMessagesFrom: p.allowMessagesFrom,
        afficherPays: p.afficherPays, afficherVille: p.afficherVille,
        afficherDerniereConnexion: p.afficherDerniereConnexion,
        eventItineraryVisibility: value));
      Get.snackbar('privacy_saved_title'.tr, 'privacy_saved_message'.tr,
        snackPosition: SnackPosition.BOTTOM);
    } catch (e) { debugPrint('[PRIVACY] itinerary visibility save failed: $e'); _showError(); }
  }

  void _showError() => Get.snackbar('error_title'.tr, 'follow_action_failed'.tr,
    snackPosition: SnackPosition.BOTTOM);
}
