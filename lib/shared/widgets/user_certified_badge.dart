import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Types de badge de certification affichés dans Scrole.
enum CertificationBadgeType {
  basic,
  pro,
  premium,
  event,
  community,
}

extension CertificationBadgeTypeStyle on CertificationBadgeType {
  Color get color => switch (this) {
        CertificationBadgeType.basic => const Color(0xFF1877F2),
        CertificationBadgeType.pro => const Color(0xFF805AD5),
        CertificationBadgeType.premium => const Color(0xFFD4A017),
        CertificationBadgeType.event || CertificationBadgeType.community =>
          const Color(0xFF1877F2),
      };

  // Clé déjà traduite dans toutes les langues de l'application.
  String get tooltipKey => 'profile_verified_tooltip';
}

/// Badge centralisé : le niveau est fourni par le statut réel de l'entité,
/// jamais déduit automatiquement du niveau du propriétaire.
class UserCertifiedBadge extends StatelessWidget {
  final double size;
  final bool showTooltip;
  final CertificationBadgeType type;

  const UserCertifiedBadge({
    super.key,
    this.size = 18,
    this.showTooltip = true,
    this.type = CertificationBadgeType.basic,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Icon(
      Icons.verified_rounded,
      size: size,
      color: type.color,
      semanticLabel: type.tooltipKey.tr,
    );

    if (!showTooltip) return badge;
    return Tooltip(message: type.tooltipKey.tr, child: badge);
  }
}
