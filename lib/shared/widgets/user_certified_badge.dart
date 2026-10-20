import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Badge de certification utilisateur officiel Scrole.
class UserCertifiedBadge extends StatelessWidget {
  final double size;
  final bool showTooltip;

  const UserCertifiedBadge({
    super.key,
    this.size = 18,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Image.asset(
      'assets/svg_icons/certified-svgrepo-com.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );

    if (showTooltip) {
      return Tooltip(
        message: 'profile_verified_tooltip'.tr,
        child: badge,
      );
    }
    return badge;
  }
}
