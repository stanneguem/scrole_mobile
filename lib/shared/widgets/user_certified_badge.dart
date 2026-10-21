import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CertificationBadgeType { basic, pro, premium, event, community }

extension CertificationBadgeTypeStyle on CertificationBadgeType {
  Color get color => switch (this) {
        CertificationBadgeType.basic => const Color(0xFF1877F2),
        CertificationBadgeType.pro => const Color(0xFF805AD5),
        CertificationBadgeType.premium => const Color(0xFFD4A017),
        CertificationBadgeType.event || CertificationBadgeType.community => const Color(0xFF1877F2),
      };
  String get tooltipKey => 'profile_verified_tooltip';
}

class _CertificationLevelResolver {
  static final Map<String, Future<CertificationBadgeType>> _cache = {};

  static Future<CertificationBadgeType> resolve(String userId) =>
      _cache.putIfAbsent(userId, () async {
        try {
          final client = Supabase.instance.client;
          final now = DateTime.now().toUtc();
          var level = CertificationBadgeType.basic;
          final rows = await client.from('user_certifications')
              .select('issued_at, expires_at, certification_type_id')
              .eq('user_id', userId).eq('status', 'active');
          final typeIds = <String>{};
          for (final raw in rows as List) {
            final row = Map<String, dynamic>.from(raw as Map);
            final issued = DateTime.tryParse('${row['issued_at'] ?? ''}')?.toUtc();
            final expires = DateTime.tryParse('${row['expires_at'] ?? ''}')?.toUtc();
            if (issued != null && !issued.isAfter(now) &&
                (expires == null || !expires.isBefore(now))) {
              final id = row['certification_type_id']?.toString();
              if (id != null && id.isNotEmpty) typeIds.add(id);
            }
          }
          if (typeIds.isNotEmpty) {
            final types = await client.from('certification_type')
                .select('id, code').inFilter('id', typeIds.toList());
            for (final raw in types as List) {
              final code = (raw['code'] ?? '').toString().toLowerCase();
              if (code == 'premium') return CertificationBadgeType.premium;
              if (code == 'pro') level = CertificationBadgeType.pro;
            }
          }
          final subscriptions = await client.from('scrole_subscriptions')
              .select('plan_code, starts_at, ends_at')
              .eq('user_id', userId).eq('status', 'active');
          for (final raw in subscriptions as List) {
            final row = Map<String, dynamic>.from(raw as Map);
            final starts = DateTime.tryParse('${row['starts_at'] ?? ''}')?.toUtc();
            final ends = DateTime.tryParse('${row['ends_at'] ?? ''}')?.toUtc();
            if ((starts != null && starts.isAfter(now)) ||
                (ends != null && ends.isBefore(now))) continue;
            final code = (row['plan_code'] ?? '').toString().toLowerCase();
            if (code == 'premium') return CertificationBadgeType.premium;
            if (code == 'pro') level = CertificationBadgeType.pro;
          }
          return level;
        } catch (_) {
          return CertificationBadgeType.basic;
        }
      });
}

class UserCertifiedBadge extends StatelessWidget {
  final double size;
  final bool showTooltip;
  final CertificationBadgeType type;
  final String? userId;

  const UserCertifiedBadge({
    super.key,
    this.size = 18,
    this.showTooltip = true,
    this.type = CertificationBadgeType.basic,
    this.userId,
  });

  @override
  Widget build(BuildContext context) {
    if (userId == null || userId!.isEmpty) return _buildBadge(type);
    return FutureBuilder<CertificationBadgeType>(
      future: _CertificationLevelResolver.resolve(userId!),
      builder: (context, snapshot) => _buildBadge(snapshot.data ?? type),
    );
  }

  Widget _buildBadge(CertificationBadgeType badgeType) {
    final badge = Icon(Icons.verified_rounded, size: size, color: badgeType.color,
        semanticLabel: badgeType.tooltipKey.tr);
    return showTooltip ? Tooltip(message: badgeType.tooltipKey.tr, child: badge) : badge;
  }
}
