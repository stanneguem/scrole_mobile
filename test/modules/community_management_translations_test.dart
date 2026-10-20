import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/app/translation/app_translation_additions.dart';

void main() {
  group('Community management translations', () {
    const languages = ['fr', 'en', 'es', 'de', 'it', 'pt', 'zh', 'ja', 'ru'];
    const requiredKeys = [
      'community_access_denied',
      'community_access_sub_access',
      'community_access_sub_access_desc',
      'community_access_sub_posts',
      'community_access_sub_posts_desc',
      'community_access_sub_rules',
      'community_access_sub_rules_desc',
      'community_info_sub_desc',
      'community_info_sub_desc_desc',
      'community_info_sub_images',
      'community_info_sub_images_desc',
      'community_info_sub_interests',
      'community_info_sub_interests_desc',
      'community_leave_success_msg',
      'community_leave_success_title',
      'community_leave_title',
      'community_max_interests_error',
      'community_mgmt_access_sub',
      'community_mgmt_info_sub',
      'community_mgmt_mod_sub',
      'community_mod_section_reports',
      'community_mod_section_requests',
      'community_mod_tab_reports',
      'community_mod_tab_requests',
      'community_post_permissions_label',
      'community_report_description_hint',
      'community_report_description_label',
      'community_report_reason_hint',
      'community_report_reason_label',
      'community_report_submit',
      'community_report_success_msg',
      'community_report_success_title',
      'community_report_title',
      'community_reports_tab_content',
      'community_reports_tab_members',
      'community_settings_slogan_label',
    ];

    test('all supported languages define every community management label', () {
      for (final language in languages) {
        final translations = AppTranslationAdditions.keys[language];
        expect(translations, isNotNull, reason: 'Missing language: $language');

        for (final key in requiredKeys) {
          expect(
            translations!.containsKey(key),
            isTrue,
            reason: 'Missing translation for "$key" in "$language"',
          );
          expect(
            translations[key]!.trim().isNotEmpty,
            isTrue,
            reason: 'Empty translation for "$key" in "$language"',
          );
        }
      }
    });
  });
}
