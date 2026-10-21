import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import '../controllers/profile_controller.dart';

class ShareProfileScreen extends StatefulWidget {
  const ShareProfileScreen({super.key});

  @override
  State<ShareProfileScreen> createState() => _ShareProfileScreenState();
}

class _ShareProfileScreenState extends State<ShareProfileScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  ProfileController get _profile => Get.find<ProfileController>();

  String get _profileLink => 'scrole://user-profile/${_profile.userId.value}';

  Future<void> _shareLink() async {
    await SharePlus.instance.share(ShareParams(
      text: 'share_profile_link_message'.trParams({
        'name': _profile.displayName,
        'link': _profileLink,
      }),
      subject: 'share_profile_subject'.trParams({'name': _profile.displayName}),
    ));
  }

  Future<void> _shareQrCode() async {
    await SharePlus.instance.share(ShareParams(
      text: 'share_profile_qr_message'.trParams({'name': _profile.displayName, 'link': _profileLink}),
      subject: 'share_profile_subject'.trParams({'name': _profile.displayName}),
    ));
  }

  Future<void> _shareProfileCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Profile card is not ready');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Could not render profile card');
      final directory = await Directory.systemTemp.createTemp('scrole_profile_share_');
      final file = File('${directory.path}/scrole_profile.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: 'share_profile_card_message'.trParams({'name': _profile.displayName, 'link': _profileLink}),
        subject: 'share_profile_subject'.trParams({'name': _profile.displayName}),
      ));
    } catch (e) {
      if (mounted) Get.snackbar('error_title'.tr, 'share_profile_error'.tr, snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text('share_profile_title'.tr, style: const TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text('share_profile_intro'.tr, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14, height: 1.45)),
            const SizedBox(height: 22),
            RepaintBoundary(
              key: _cardKey,
              child: _ProfileShareCard(profile: _profile, link: _profileLink),
            ),
            const SizedBox(height: 24),
            _ShareOptionTile(
              icon: Icons.qr_code_2_rounded,
              title: 'share_profile_qr_title'.tr,
              subtitle: 'share_profile_qr_subtitle'.tr,
              onTap: _shareQrCode,
            ),
            const SizedBox(height: 10),
            _ShareOptionTile(
              icon: Icons.link_rounded,
              title: 'share_profile_link_title'.tr,
              subtitle: 'share_profile_link_subtitle'.tr,
              onTap: _shareLink,
            ),
            const SizedBox(height: 10),
            _ShareOptionTile(
              icon: Icons.image_outlined,
              title: 'share_profile_card_title'.tr,
              subtitle: 'share_profile_card_subtitle'.tr,
              onTap: _shareProfileCard,
              loading: _sharing,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileShareCard extends StatelessWidget {
  const _ProfileShareCard({required this.profile, required this.link});
  final ProfileController profile;
  final String link;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF161B33), Color(0xFF542C79), Color(0xFFDB4E79)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: colors.shadow.withValues(alpha: .16), blurRadius: 22, offset: const Offset(0, 12))],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 30, height: 30, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.bubble_chart_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 9),
            const Text('SCROLE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13)),
            const Spacer(),
            const Icon(Icons.person_add_alt_1_rounded, color: Colors.white70, size: 20),
          ]),
          const SizedBox(height: 28),
          Center(
            child: Container(
              width: 94,
              height: 94,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: .7), width: 1.5)),
              child: ClipOval(
                child: profile.profileImageUrl.value.isEmpty
                    ? Container(color: Colors.white.withValues(alpha: .15), child: Center(child: Text(profile.initials, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800))))
                    : AppCachedImage(imageUrl: profile.profileImageUrl.value, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Center(child: Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
          const SizedBox(height: 4),
          Center(child: Text('@${profile.username.value}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 14))),
          const SizedBox(height: 24),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('share_profile_card_caption'.tr, style: TextStyle(color: Colors.white.withValues(alpha: .86), fontSize: 12)),
              const SizedBox(height: 5),
              Text('scrole.app', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
            ])),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: 'scrole_user:${profile.userId.value}', size: 70, backgroundColor: Colors.white),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ShareOptionTile extends StatelessWidget {
  const _ShareOptionTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.loading = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: colors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: colors.primary, size: 23)),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.35)),
            ])),
            if (loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
