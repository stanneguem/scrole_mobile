import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/modules/module_communautes/centre/models/excluded_user.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';

class ExcludedMembersScreen extends StatefulWidget {
  final String communityId;
  const ExcludedMembersScreen({super.key, required this.communityId});

  @override
  State<ExcludedMembersScreen> createState() => _ExcludedMembersScreenState();
}

class _ExcludedMembersScreenState extends State<ExcludedMembersScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  List<ExcludedUser> _excluded = [];

  @override
  void initState() {
    super.initState();
    _loadExclusions();
  }

  Future<void> _loadExclusions() async {
    setState(() => _isLoading = true);
    try {
      final res = await _service.getCommunityExclusions(widget.communityId);
      final rawItems = res['items'] is List ? res['items'] as List : [];
      final parsed = rawItems.map((e) => ExcludedUser.fromJson(e is Map ? Map<String, dynamic>.from(e) : {})).toList();
      if (mounted) {
        setState(() {
          _excluded = parsed;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unexclude(String userId, String name) async {
    try {
      await _service.unexcludeCommunityMember(widget.communityId, userId);
      Get.snackbar(
        'excluded_members_readmit_title'.tr,
        'excluded_members_readmit_msg'.trParams({'name': name}),
        snackPosition: SnackPosition.BOTTOM,
      );
      _loadExclusions();
    } catch (e) {
      Get.snackbar('error'.tr, e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text('excluded_members_title'.tr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _excluded.isEmpty
              ? Center(
                  child: Text('excluded_members_empty'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _excluded.length,
                  itemBuilder: (context, index) {
                    final excludedUser = _excluded[index];
                    final displayName = excludedUser.displayName;
                    final avatar = excludedUser.avatarUrl;
                    final reason = excludedUser.reason;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: avatar != null && avatar.isNotEmpty
                                ? AppCachedImage(imageUrl: avatar, width: 44, height: 44, fit: BoxFit.cover)
                                : Container(
                                    width: 44,
                                    height: 44,
                                    color: colorScheme.primary.withValues(alpha: 0.2),
                                    alignment: Alignment.center,
                                    child: Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        displayName,
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (excludedUser.isVerified) ...[
                                      const SizedBox(width: 4),
                                      const UserCertifiedBadge(size: 16),
                                    ],
                                  ],
                                ),
                                if (reason != null && reason.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text('${'excluded_members_reason_prefix'.tr} $reason', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                ],
                              ],
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => _unexclude(excludedUser.userId, displayName),
                            style: OutlinedButton.styleFrom(foregroundColor: colorScheme.primary),
                            child: Text('excluded_members_readmit'.tr),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
