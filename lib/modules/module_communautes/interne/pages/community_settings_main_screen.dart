import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import '../../centre/services/community_service.dart';
import '../../../../app/service_global/media_service.dart';
import '../../../../app/repository_global/storage_repository.dart';
import '../../../../shared/widgets/image_source_sheet.dart';

// --- Header Widget for Community Hubs ---
class _CommunityHeaderCard extends StatelessWidget {
  final String communityName;
  final String? communityAvatar;
  final String? communitySlogan;

  const _CommunityHeaderCard({
    required this.communityName,
    this.communityAvatar,
    this.communitySlogan,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: communityAvatar != null && communityAvatar!.isNotEmpty
                ? NetworkImage(communityAvatar!)
                : null,
            child: communityAvatar == null || communityAvatar!.isEmpty
                ? Text(communityName.isNotEmpty ? communityName[0].toUpperCase() : 'C', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  communityName,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  communitySlogan ?? 'community_slogan_default'.tr,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Écran B : Gestion de la communauté (3 entrées principales) ---
class CommunitySettingsMainScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;
  final String? communitySlogan;

  const CommunitySettingsMainScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
    this.communitySlogan,
  });

  @override
  State<CommunitySettingsMainScreen> createState() => _CommunitySettingsMainScreenState();
}

class _CommunitySettingsMainScreenState extends State<CommunitySettingsMainScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  String _role = 'member';
  Map<String, dynamic> _modCounts = {};
  String? _communityName;
  String? _avatarUrl;
  String? _slogan;

  @override
  void initState() {
    super.initState();
    _loadRoleAndCounts();
  }

  Future<void> _loadRoleAndCounts() async {
    try {
      _role = await _service.getCurrentUserRole(widget.communityId);
      if (_role != 'admin' && _role != 'moderator') {
        Get.back();
        Get.snackbar('error'.tr, 'community_access_denied'.tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
        return;
      }
      try {
        _modCounts = await _service.getCommunityModerationCounts(widget.communityId);
      } catch (e) {
        debugPrint('[CommunitySettingsMainScreen] Moderation counts unavailable: $e');
      }
      try {
        final comm = await _service.getCommunityById(widget.communityId);
        if (comm != null) {
          _communityName = comm.name;
          _avatarUrl = comm.avatarUrl;
          _slogan = widget.communitySlogan ?? comm.description;
        }
      } catch (e) {
        debugPrint('[CommunitySettingsMainScreen] Local community summary unavailable: $e');
      }
      if (_role == 'admin') {
        try {
          final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
          final community = snapshot['community'] is Map
              ? Map<String, dynamic>.from(snapshot['community'] as Map)
              : <String, dynamic>{};
          _communityName = community['name']?.toString() ?? _communityName;
          _avatarUrl = community['photo_profile']?.toString() ?? _avatarUrl;
          _slogan = community['slogan']?.toString() ?? _slogan;
        } catch (e) {
          debugPrint('[CommunitySettingsMainScreen] Summary refresh failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[CommunitySettingsMainScreen] Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isAdmin => _role == 'admin';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(appBar: AppBar(title: Text('community_management_title'.tr)), body: const Center(child: CircularProgressIndicator()));
    }

    if (!_isAdmin && _role != 'moderator') {
      return Scaffold(
        appBar: AppBar(title: Text('community_management_title'.tr)),
        body: Center(child: Text('community_access_denied'.tr, style: TextStyle(color: colorScheme.error, fontSize: 16))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('community_management_title'.tr),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CommunityHeaderCard(
            communityName: _communityName ?? widget.communityName,
            communityAvatar: _avatarUrl ?? widget.communityAvatar,
            communitySlogan: _slogan ?? widget.communitySlogan,
          ),
          // 1. Modération -> Écran C
          _buildTile(
            icon: Icons.admin_panel_settings_outlined,
            iconColor: Colors.indigo,
            title: 'community_mgmt_mod'.tr,
            subtitle: 'community_mgmt_mod_sub'.tr,
            badgeCount: (_modCounts['pending_reports'] ?? 0) + (_modCounts['pending_posts'] ?? 0) + (_modCounts['pending_join_requests'] ?? 0),
            onTap: () => Get.to(() => CommunityModerationCenterScreen(communityId: widget.communityId, communityName: _communityName ?? widget.communityName, communityAvatar: _avatarUrl)),
          ),
          const SizedBox(height: 12),

          // 2. Accès et règles -> Écran E (Admin only)
          if (_isAdmin)
            _buildTile(
              icon: Icons.security_outlined,
              iconColor: Colors.green,
              title: 'community_mgmt_access'.tr,
              subtitle: 'community_mgmt_access_sub'.tr,
              onTap: () => Get.to(() => CommunityAccessRulesHubScreen(communityId: widget.communityId, communityName: _communityName ?? widget.communityName, communityAvatar: _avatarUrl)),
            ),
          if (_isAdmin) const SizedBox(height: 12),

          // 3. Informations de la communauté -> Écran H (Admin only)
          if (_isAdmin)
            _buildTile(
              icon: Icons.info_outline_rounded,
              iconColor: Colors.deepOrange,
              title: 'community_mgmt_info'.tr,
              subtitle: 'community_mgmt_info_sub'.tr,
              onTap: () async {
                await Get.to(() => CommunityInfoHubScreen(
                  communityId: widget.communityId,
                  communityName: _communityName ?? widget.communityName,
                  communityAvatar: _avatarUrl,
                ));
                if (mounted) await _loadRoleAndCounts();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTile({required IconData icon, Color? iconColor, required String title, required String subtitle, int badgeCount = 0, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: (iconColor ?? colorScheme.primary).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor ?? colorScheme.primary, size: 24),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Text('$badgeCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

// --- Écran C : Modération (2 entrées : Signalements -> Écran D, Demandes -> Écran D2) ---
class CommunityModerationCenterScreen extends StatelessWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityModerationCenterScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_mgmt_mod'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CommunityHeaderCard(communityName: communityName, communityAvatar: communityAvatar),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            child: ListTile(
              onTap: () => Get.to(() => CommunityPendingPostsScreen(communityId: communityId)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.pending_actions_outlined, color: Colors.orange, size: 24),
              ),
              title: Text('community_mod_pending_posts_title'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('community_mod_pending_posts_subtitle'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5)),
              trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            child: ListTile(
              onTap: () => Get.to(() => CommunityReportsHubScreen(communityId: communityId, communityName: communityName, communityAvatar: communityAvatar)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.report_problem_outlined, color: Colors.red, size: 24),
              ),
              title: Text('community_mod_section_reports'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('community_mod_tab_reports'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5)),
              trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            child: ListTile(
              onTap: () => Get.to(() => CommunityJoinRequestsScreen(communityId: communityId, communityName: communityName, communityAvatar: communityAvatar)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.group_add_outlined, color: colorScheme.primary, size: 24),
              ),
              title: Text('community_mod_section_requests'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('community_mod_tab_requests'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5)),
              trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}


class CommunityPendingPostsScreen extends StatefulWidget {
  final String communityId;
  const CommunityPendingPostsScreen({super.key, required this.communityId});

  @override
  State<CommunityPendingPostsScreen> createState() => _CommunityPendingPostsScreenState();
}

class _CommunityPendingPostsScreenState extends State<CommunityPendingPostsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  String? _loadError;
  List<dynamic> _posts = [];
  final Set<String> _busyPostIds = {};

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final response = await _service.getCommunityPendingPosts(widget.communityId);
      if (response['items'] is! List) {
        throw const FormatException('Réponse invalide des publications en attente.');
      }
      _posts = response['items'] as List;
    } catch (e) {
      debugPrint('[CommunityPendingPostsScreen] Failed to load pending posts: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _moderate(String postId, String action) async {
    if (_busyPostIds.contains(postId)) return;
    if (action == 'reject') {
      final confirmed = await Get.dialog<bool>(
        AlertDialog(
          title: Text('community_mod_reject_post_confirm_title'.tr),
          content: Text('community_mod_reject_post_confirm_message'.tr),
          actions: [
            TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Get.back(result: true),
              child: Text('community_mod_reject_post'.tr),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busyPostIds.add(postId));
    try {
      await _service.moderateCommunityPost(postId, action);
      await _loadPosts();
      Get.snackbar(
        'community_save_success'.tr,
        action == 'approve'
            ? 'community_mod_post_approved'.tr
            : 'community_mod_post_rejected'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint('[CommunityPendingPostsScreen] Moderation failed: $e');
      Get.snackbar(
        'community_save_error'.tr,
        _service.localizedCommunityError(e),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyPostIds.remove(postId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_mod_pending_posts_title'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _loadPosts, child: Text('retry'.tr)),
                      ],
                    ),
                  ),
                )
              : _posts.isEmpty
                  ? Center(child: Text('community_mod_pending_posts_empty'.tr))
                  : RefreshIndicator(
                      onRefresh: _loadPosts,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _posts.length,
                        itemBuilder: (context, index) {
                          final post = Map<String, dynamic>.from(_posts[index] as Map);
                          final id = post['id']?.toString() ?? '';
                          final author = post['author'] is Map
                              ? Map<String, dynamic>.from(post['author'] as Map)
                              : <String, dynamic>{};
                          final authorName = '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'.trim();
                          final username = author['username']?.toString();
                          final content = post['content']?.toString() ?? '';
                          final busy = _busyPostIds.contains(id);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    authorName.isNotEmpty ? authorName : (username == null ? 'excluded_members_unknown_user'.tr : '@$username'),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  if (content.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(content, maxLines: 6, overflow: TextOverflow.ellipsis),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: busy || id.isEmpty ? null : () => _moderate(id, 'reject'),
                                          icon: const Icon(Icons.close),
                                          label: Text('community_mod_reject_post'.tr),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: busy || id.isEmpty ? null : () => _moderate(id, 'approve'),
                                          icon: const Icon(Icons.check),
                                          label: Text('community_mod_approve_post'.tr),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (busy) const LinearProgressIndicator(),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

// --- Écran D : Signalements (TabView interne avec Contenus et Membres) ---
class CommunityReportsHubScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityReportsHubScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  State<CommunityReportsHubScreen> createState() => _CommunityReportsHubScreenState();
}

class _CommunityReportsHubScreenState extends State<CommunityReportsHubScreen> with SingleTickerProviderStateMixin {
  final CommunityService _service = Get.find<CommunityService>();
  late TabController _tabController;

  bool _isLoading = true;
  String _role = 'member';
  String? _loadError;
  List<dynamic> _reports = [];
  List<dynamic> _userReports = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      _role = await _service.getCurrentUserRole(widget.communityId);
      final reportsRes = await _service.getCommunityReports(widget.communityId);
      final userReportsRes = await _service.getCommunityUserReports(widget.communityId);
      if (reportsRes['items'] is! List || userReportsRes['items'] is! List) {
        throw const FormatException('Réponse invalide lors du chargement des signalements.');
      }
      _reports = reportsRes['items'] as List;
      _userReports = userReportsRes['items'] as List;
    } catch (e) {
      debugPrint('[CommunityReportsHubScreen] Failed to load reports: $e');
      _loadError = 'community_reports_load_error'.tr;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _resolveReport(String reportId, String action) async {
    try {
      await _service.resolveCommunityReport(reportId, action);
      await _loadReports();
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> _resolveUserReport(String reportId, String action) async {
    try {
      await _service.resolveCommunityUserReport(reportId, action);
      await _loadReports();
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('community_mod_section_reports'.tr),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'community_reports_tab_content'.tr),
            Tab(text: 'community_reports_tab_members'.tr),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _loadReports, child: Text('excluded_members_retry'.tr)),
                      ],
                    ),
                  ),
                )
              : TabBarView(
              controller: _tabController,
              children: [
                // 1. Content Reports
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reports.length,
                  itemBuilder: (context, index) {
                    final r = _reports[index];
                    return Card(
                      child: ListTile(
                        title: Text('community_report_item_title'.trParams({'type': r['target_type']?.toString() ?? ''})),
                        subtitle: Text(r['description'] ?? r['reason'] ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => _resolveReport(r['id'], 'dismiss')),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _resolveReport(r['id'], 'remove_content')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // 2. Member Reports
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _userReports.length,
                  itemBuilder: (context, index) {
                    final r = _userReports[index];
                    return Card(
                      child: ListTile(
                        title: Text('community_member_report_title'.tr),
                        subtitle: Text(r['description'] ?? r['reason'] ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => _resolveUserReport(r['id'], 'dismiss')),
                            if (_role == 'admin')
                              IconButton(
                                tooltip: 'community_exclude_action'.tr,
                                icon: const Icon(Icons.block, color: Colors.red),
                                onPressed: () => _resolveUserReport(r['id'].toString(), 'exclude_member'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

// --- Écran D2 : Demandes d'adhésion ---
class CommunityJoinRequestsScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityJoinRequestsScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  State<CommunityJoinRequestsScreen> createState() => _CommunityJoinRequestsScreenState();
}

class _CommunityJoinRequestsScreenState extends State<CommunityJoinRequestsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  String? _loadError;
  List<dynamic> _joinRequests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final reqsRes = await _service.getCommunityJoinRequests(widget.communityId);
      if (reqsRes['items'] is! List) {
        throw const FormatException('Réponse invalide des demandes d’adhésion.');
      }
      _joinRequests = reqsRes['items'] as List;
    } catch (e) {
      debugPrint('[CommunityJoinRequestsScreen] Failed to load requests: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _respondRequest(String requestId, bool accepted) async {
    try {
      await _service.respondCommunityJoinRequest(requestId, accepted);
      await _loadRequests();
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_mod_section_requests'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadRequests, child: Text('retry'.tr)),
                  ]),
                ))
              : _joinRequests.isEmpty
                  ? Center(child: Text('community_requests_empty'.tr))
                  : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _joinRequests.length,
                  itemBuilder: (context, index) {
                    final req = _joinRequests[index];
                    final user = req['user'] is Map ? req['user'] : {};
                    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                    return Card(
                      child: ListTile(
                        title: Text(name.isEmpty ? (user['username'] ?? 'Utilisateur') : name),
                        subtitle: Text(user['username'] != null ? '@${user['username']}' : ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => _respondRequest(req['id'], true)),
                            IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => _respondRequest(req['id'], false)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// --- Écran E : Accès et règles Hub (3 entrées) ---
class CommunityAccessRulesHubScreen extends StatelessWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityAccessRulesHubScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_mgmt_access'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CommunityHeaderCard(communityName: communityName, communityAvatar: communityAvatar),
          _buildHubTile(context, title: 'community_access_sub_posts'.tr, subtitle: 'community_access_sub_posts_desc'.tr, icon: Icons.article_outlined, iconColor: Colors.blue, onTap: () => Get.to(() => CommunityPostSettingsScreen(communityId: communityId))),
          const SizedBox(height: 12),
          _buildHubTile(context, title: 'community_access_sub_access'.tr, subtitle: 'community_access_sub_access_desc'.tr, icon: Icons.security_outlined, iconColor: Colors.green, onTap: () => Get.to(() => CommunityAccessDetailsScreen(communityId: communityId))),
          const SizedBox(height: 12),
          _buildHubTile(context, title: 'community_access_sub_rules'.tr, subtitle: 'community_access_sub_rules_desc'.tr, icon: Icons.rule_rounded, iconColor: Colors.deepOrange, onTap: () => Get.to(() => CommunityRulesScreen(communityId: communityId))),
        ],
      ),
    );
  }

  Widget _buildHubTile(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color iconColor, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
      ),
    );
  }
}

// --- Écran H : Informations de la communauté Hub (3 entrées) ---
class CommunityInfoHubScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String? communityAvatar;

  const CommunityInfoHubScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.communityAvatar,
  });

  @override
  State<CommunityInfoHubScreen> createState() => _CommunityInfoHubScreenState();
}

class _CommunityInfoHubScreenState extends State<CommunityInfoHubScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  late String _communityName;
  String? _communityAvatar;

  @override
  void initState() {
    super.initState();
    _communityName = widget.communityName;
    _communityAvatar = widget.communityAvatar;
    _loadCommunitySummary();
  }

  Future<void> _loadCommunitySummary() async {
    try {
      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final community = snapshot['community'] is Map
          ? Map<String, dynamic>.from(snapshot['community'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _communityName = community['name']?.toString() ?? _communityName;
        _communityAvatar = community['photo_profile']?.toString() ?? _communityAvatar;
      });
    } catch (e) {
      debugPrint('[CommunityInfoHubScreen] Failed to refresh community summary: $e');
    }
  }

  Future<void> _openSubpage(Widget page) async {
    await Get.to(() => page);
    await _loadCommunitySummary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_mgmt_info'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CommunityHeaderCard(communityName: _communityName, communityAvatar: _communityAvatar),
          _buildHubTile(context, title: 'community_info_sub_desc'.tr, subtitle: 'community_info_sub_desc_desc'.tr, icon: Icons.info_outline_rounded, iconColor: Colors.orange, onTap: () => _openSubpage(CommunityInfoSettingsScreen(communityId: widget.communityId, communityName: _communityName))),
          const SizedBox(height: 12),
          _buildHubTile(context, title: 'community_info_sub_interests'.tr, subtitle: 'community_info_sub_interests_desc'.tr, icon: Icons.favorite_border_rounded, iconColor: Colors.pink, onTap: () => _openSubpage(CommunityInterestsScreen(communityId: widget.communityId))),
          const SizedBox(height: 12),
          _buildHubTile(context, title: 'community_info_sub_images'.tr, subtitle: 'community_info_sub_images_desc'.tr, icon: Icons.image_outlined, iconColor: Colors.purple, onTap: () => _openSubpage(CommunityImagesScreen(communityId: widget.communityId))),
        ],
      ),
    );
  }

  Widget _buildHubTile(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color iconColor, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
      ),
    );
  }
}

// 1. Informations descriptives
class CommunityInfoSettingsScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  const CommunityInfoSettingsScreen({super.key, required this.communityId, required this.communityName});

  @override
  State<CommunityInfoSettingsScreen> createState() => _CommunityInfoSettingsScreenState();
}

class _CommunityInfoSettingsScreenState extends State<CommunityInfoSettingsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _sloganController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadCommunityInfo();
  }

  Future<void> _loadCommunityInfo() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final community = snapshot['community'] is Map
          ? Map<String, dynamic>.from(snapshot['community'] as Map)
          : <String, dynamic>{};
      _nameController.text = community['name']?.toString() ?? widget.communityName;
      _sloganController.text = community['slogan']?.toString() ?? '';
      _descController.text = community['description']?.toString() ?? '';
    } catch (e) {
      debugPrint('[CommunityInfoSettingsScreen] Failed to load current values: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sloganController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        Get.snackbar('community_save_error'.tr, 'community_settings_name_required'.tr,
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      await _service.updateCommunityInfo(
        id: widget.communityId,
        name: name,
        slogan: _sloganController.text.trim(),
        description: _descController.text.trim(),
      );
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      Get.back();
    } catch (e) {
      debugPrint('[CommunityInfoSettingsScreen] Save failed: $e');
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_info_sub_desc'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadCommunityInfo, child: Text('retry'.tr)),
                  ]),
                ))
              : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              maxLength: 60,
              decoration: InputDecoration(labelText: 'community_settings_name_label'.tr),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sloganController,
              maxLength: 160,
              decoration: InputDecoration(labelText: 'community_settings_slogan_label'.tr),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLength: 500,
              maxLines: 4,
              decoration: InputDecoration(labelText: 'community_settings_desc_label'.tr),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _save,
              child: _isLoading ? const CircularProgressIndicator() : Text('community_save'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

// 2. Centres d'intérêt
class CommunityInterestsScreen extends StatefulWidget {
  final String communityId;
  const CommunityInterestsScreen({super.key, required this.communityId});

  @override
  State<CommunityInterestsScreen> createState() => _CommunityInterestsScreenState();
}

class _CommunityInterestsScreenState extends State<CommunityInterestsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  String? _loadError;
  List<Map<String, dynamic>> _allInterests = [];
  Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadInterests();
  }

  Future<void> _loadInterests() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final all = await _service.getAvailableInterests();
      final current = await _service.getCommunityInterests(widget.communityId);
      _allInterests = all;
      _selectedIds = current.map((i) => i['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    } catch (e) {
      debugPrint('[CommunityInterestsScreen] Failed to load interests: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_selectedIds.length > 10) {
      Get.snackbar('error'.tr, 'community_max_interests_error'.tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _service.updateCommunityInterests(widget.communityId, _selectedIds.toList());
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      Get.back();
    } catch (e) {
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('community_info_sub_interests'.tr),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _isLoading ? null : _save),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadInterests, child: Text('retry'.tr)),
                  ]),
                ))
              : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _allInterests.length,
              itemBuilder: (context, index) {
                final item = _allInterests[index];
                final id = item['id']?.toString() ?? '';
                final name = item['nom']?.toString() ?? item['name']?.toString() ?? '';
                final isSelected = _selectedIds.contains(id);
                return CheckboxListTile(
                  title: Text(name),
                  value: isSelected,
                  onChanged: (val) {
                    if (val == true && !_selectedIds.contains(id) && _selectedIds.length >= 10) {
                      Get.snackbar(
                        'error'.tr,
                        'community_max_interests_error'.tr,
                        snackPosition: SnackPosition.BOTTOM,
                      );
                      return;
                    }
                    setState(() {
                      if (val == true) {
                        _selectedIds.add(id);
                      } else {
                        _selectedIds.remove(id);
                      }
                    });
                  },
                );
              },
            ),
    );
  }
}

// 3. Images
class CommunityImagesScreen extends StatefulWidget {
  final String communityId;
  const CommunityImagesScreen({super.key, required this.communityId});

  @override
  State<CommunityImagesScreen> createState() => _CommunityImagesScreenState();
}

class _CommunityImagesScreenState extends State<CommunityImagesScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  final StorageRepository _storage = StorageRepository();
  final MediaService _mediaService = MediaService();
  bool _isLoading = true;
  String? _loadError;
  String? _currentAvatarUrl;
  String? _currentCoverUrl;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final community = snapshot['community'] is Map
          ? Map<String, dynamic>.from(snapshot['community'] as Map)
          : <String, dynamic>{};
      if (mounted) {
        setState(() {
          _currentAvatarUrl = community['photo_profile']?.toString();
          _currentCoverUrl = community['photo_cover']?.toString();
        });
      }
    } catch (e) {
      debugPrint('[CommunityImagesScreen] Failed to load images: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadImage({required bool isProfile}) async {
    showImageSourceSheet(
      context,
      onCamera: () => _processImage(isProfile: isProfile, source: ImageSource.camera),
      onGallery: () => _processImage(isProfile: isProfile, source: ImageSource.gallery),
    );
  }

  Future<void> _processImage({required bool isProfile, required ImageSource source}) async {
    final pickedFile = await _mediaService.pickImage(source: source);
    if (pickedFile == null) return;

    setState(() => _isLoading = true);
    try {
      final file = await _mediaService.compressImage(pickedFile, quality: 75);
      if (file == null) {
        throw Exception('community_settings_image_compression_failed');
      }
      if (await file.length() > 5 * 1024 * 1024) {
        throw Exception('community_settings_image_too_large');
      }
      final ext = p.extension(file.path);
      final path = 'communities/${widget.communityId}/${isProfile ? 'profile' : 'cover'}_${DateTime.now().millisecondsSinceEpoch}$ext';
      final url = await _storage.uploadFile(bucket: 'community-media', path: path, file: file);

      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final community = snapshot['community'] is Map
          ? Map<String, dynamic>.from(snapshot['community'] as Map)
          : <String, dynamic>{};
      await _service.updateCommunityInfo(
        id: widget.communityId,
        name: community['name']?.toString() ?? '',
        slogan: community['slogan']?.toString(),
        description: community['description']?.toString() ?? '',
        photoProfile: isProfile ? url : _currentAvatarUrl,
        photoCover: !isProfile ? url : _currentCoverUrl,
      );
      final previousUrl = isProfile ? _currentAvatarUrl : _currentCoverUrl;
      if (previousUrl != null && previousUrl != url) {
        await _storage.deletePublicFile(bucket: 'community-media', publicUrl: previousUrl);
      }

      if (mounted) {
        setState(() {
          if (isProfile) _currentAvatarUrl = url;
          else _currentCoverUrl = url;
        });
      }

      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[CommunityImagesScreen] Upload failed: $e');
      final rawError = e.toString().replaceFirst('Exception: ', '');
      final userMessage = rawError == 'community_settings_image_too_large' ||
              rawError == 'community_settings_image_compression_failed'
          ? rawError.tr
          : _service.localizedCommunityError(e);
      Get.snackbar('community_save_error'.tr, userMessage, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_info_sub_images'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: colorScheme.error)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadImages, child: Text('retry'.tr)),
                  ]),
                ))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundImage: _currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty
                          ? NetworkImage(_currentAvatarUrl!)
                          : null,
                      child: _currentAvatarUrl == null || _currentAvatarUrl!.isEmpty
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text('community_settings_profile_photo'.tr),
                    trailing: ElevatedButton(
                      onPressed: _isLoading ? null : () => _pickAndUploadImage(isProfile: true),
                      child: Text('community_settings_change_photo'.tr),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: _currentCoverUrl != null && _currentCoverUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              _currentCoverUrl!,
                              width: 48,
                              height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.image),
                            ),
                          )
                        : const SizedBox(
                            width: 48,
                            height: 36,
                            child: Icon(Icons.image),
                          ),
                    title: Text('community_settings_cover_photo'.tr),
                    trailing: ElevatedButton(
                      onPressed: _isLoading ? null : () => _pickAndUploadImage(isProfile: false),
                      child: Text('community_settings_change_photo'.tr),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// --- Écran G : Accès Details ---
class CommunityAccessDetailsScreen extends StatefulWidget {
  final String communityId;
  const CommunityAccessDetailsScreen({super.key, required this.communityId});

  @override
  State<CommunityAccessDetailsScreen> createState() => _CommunityAccessDetailsScreenState();
}

class _CommunityAccessDetailsScreenState extends State<CommunityAccessDetailsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  String? _loadError;
  String _visibility = 'public';
  bool _requireManualApproval = false;
  bool _certificationRequired = false;
  bool _membersListVisible = true;
  bool _allowReports = true;
  bool _allowComments = true;
  bool _allowReactions = true;
  bool _allowPostPromotion = true;
  bool _countriesEnabled = false;
  bool _citiesEnabled = false;
  String? _genderRestriction;
  int? _ageMin;
  int? _ageMax;
  final TextEditingController _ageMinController = TextEditingController();
  final TextEditingController _ageMaxController = TextEditingController();
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _cities = [];
  Set<String> _allowedCountries = {};
  Set<String> _allowedCities = {};

  List<String> _toIdList(dynamic value) {
    if (value is! List) return <String>[];
    return value.map((item) => item.toString()).where((id) => id.isNotEmpty).toList();
  }

  Future<Set<String>?> _chooseLocations({
    required String title,
    required List<Map<String, dynamic>> items,
    required Set<String> selected,
  }) async {
    final searchController = TextEditingController();
    final draft = Set<String>.from(selected);
    final result = await Get.dialog<Set<String>>(
      StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final query = searchController.text.trim().toLowerCase();
          final filtered = items.where((item) {
            final name = item['nom']?.toString().toLowerCase() ?? '';
            final code = item['code_iso']?.toString().toLowerCase() ?? '';
            return query.isEmpty || name.contains(query) || code.contains(query);
          }).toList();
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              height: MediaQuery.of(dialogContext).size.height * 0.55,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'community_settings_location_search'.tr,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('community_settings_no_locations'.tr))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final id = item['id']?.toString() ?? '';
                              final name = item['nom']?.toString() ?? '';
                              if (id.isEmpty) return const SizedBox.shrink();
                              return CheckboxListTile(
                                dense: true,
                                title: Text(name),
                                subtitle: item['code_iso'] == null ? null : Text(item['code_iso'].toString()),
                                value: draft.contains(id),
                                onChanged: (checked) => setDialogState(() {
                                  if (checked == true) {
                                    draft.add(id);
                                  } else {
                                    draft.remove(id);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: Text('cancel'.tr),
              ),
              FilledButton(
                onPressed: () => Get.back(result: draft),
                child: Text('confirm'.tr),
              ),
            ],
          );
        },
      ),
    );
    searchController.dispose();
    return result;
  }

  @override
  void dispose() {
    _ageMinController.dispose();
    _ageMaxController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final community = snapshot['community'] is Map
          ? Map<String, dynamic>.from(snapshot['community'] as Map)
          : <String, dynamic>{};
      final access = snapshot['access_rules'] is Map
          ? Map<String, dynamic>.from(snapshot['access_rules'] as Map)
          : <String, dynamic>{};
      final settings = snapshot['settings'] is Map
          ? Map<String, dynamic>.from(snapshot['settings'] as Map)
          : <String, dynamic>{};
      _visibility = community['visibility']?.toString() ?? 'public';
      _requireManualApproval = community['require_manual_approval'] == true;
      _membersListVisible = settings['members_list_visible'] != false;
      _allowReports = settings['allow_reports'] != false;
      _allowComments = settings['allow_comments'] != false;
      _allowReactions = settings['allow_reactions'] != false;
      _allowPostPromotion = settings['allow_post_promotion'] != false;
      _certificationRequired = access['certification_required'] == true;
      _countriesEnabled = access['countries_enabled'] == true;
      _citiesEnabled = access['cities_enabled'] == true;
      _allowedCountries = _toIdList(access['allowed_countries']).toSet();
      _allowedCities = _toIdList(access['allowed_cities']).toSet();
      _genderRestriction = access['gender_restriction']?.toString();
      _ageMin = (access['age_min'] as num?)?.toInt();
      _ageMax = (access['age_max'] as num?)?.toInt();
      _ageMinController.text = _ageMin?.toString() ?? '';
      _ageMaxController.text = _ageMax?.toString() ?? '';
      _countries = await _service.getAvailableCountries();
      _cities = await _service.getAvailableCities();
    } catch (e) {
      debugPrint('[CommunityAccessDetailsScreen] Failed to load settings: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    final parsedAgeMin = int.tryParse(_ageMinController.text.trim());
    final parsedAgeMax = int.tryParse(_ageMaxController.text.trim());
    if ((_ageMinController.text.trim().isNotEmpty && parsedAgeMin == null) ||
        (_ageMaxController.text.trim().isNotEmpty && parsedAgeMax == null) ||
        (parsedAgeMin != null && (parsedAgeMin < 0 || parsedAgeMin > 120)) ||
        (parsedAgeMax != null && (parsedAgeMax < 0 || parsedAgeMax > 120)) ||
        (parsedAgeMin != null && parsedAgeMax != null && parsedAgeMin > parsedAgeMax)) {
      Get.snackbar('community_save_error'.tr, 'community_settings_age_invalid'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (_countriesEnabled && _allowedCountries.isEmpty) {
      Get.snackbar('community_save_error'.tr, 'community_settings_select_at_least_one_country'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (_citiesEnabled && _allowedCities.isEmpty) {
      Get.snackbar('community_save_error'.tr, 'community_settings_select_at_least_one_city'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _service.updateCommunityManagementSettings(
        communityId: widget.communityId,
        visibility: _visibility,
        requireManualApproval: _requireManualApproval,
        membersListVisible: _membersListVisible,
        allowReports: _allowReports,
        allowComments: _allowComments,
        allowReactions: _allowReactions,
        allowPostPromotion: _allowPostPromotion,
        certificationRequired: _certificationRequired,
        countriesEnabled: _countriesEnabled,
        allowedCountries: _allowedCountries.toList(),
        citiesEnabled: _citiesEnabled,
        allowedCities: _allowedCities.toList(),
        genderRestriction: _genderRestriction,
        ageMin: parsedAgeMin,
        ageMax: parsedAgeMax,
        clearAgeMin: _ageMinController.text.trim().isEmpty,
        clearAgeMax: _ageMaxController.text.trim().isEmpty,
        clearGender: _genderRestriction == null,
      );
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      Get.back();
    } catch (e) {
      debugPrint('[CommunityAccessDetailsScreen] Save failed: $e');
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_access_sub_access'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!, style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadRules, child: Text('retry'.tr)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text('community_settings_manual_approval'.tr),
                        value: _requireManualApproval,
                        onChanged: (val) => setState(() => _requireManualApproval = val),
                      ),
                      SwitchListTile(
                        title: Text('community_settings_certification'.tr),
                        value: _certificationRequired,
                        onChanged: (val) => setState(() => _certificationRequired = val),
                      ),
                      SwitchListTile(
                        title: Text('community_settings_members_visible'.tr),
                        value: _membersListVisible,
                        onChanged: (val) => setState(() => _membersListVisible = val),
                      ),
                      SwitchListTile(
                        title: Text('community_settings_allow_reports'.tr),
                        value: _allowReports,
                        onChanged: (val) => setState(() => _allowReports = val),
                      ),
                      SwitchListTile(
                        title: Text('community_settings_allow_comments'.tr),
                        value: _allowComments,
                        onChanged: (val) => setState(() => _allowComments = val),
                      ),
                      SwitchListTile(
                        title: Text('community_settings_allow_reactions'.tr),
                        value: _allowReactions,
                        onChanged: (val) => setState(() => _allowReactions = val),
                      ),
                      SwitchListTile(
                        title: Text('community_settings_allow_post_promotion'.tr),
                        value: _allowPostPromotion,
                        onChanged: (val) => setState(() => _allowPostPromotion = val),
                      ),
                      SwitchListTile(
                        title: Text('community_settings_countries_enabled'.tr),
                        subtitle: Text('community_settings_countries_help'.tr),
                        value: _countriesEnabled,
                        onChanged: (val) => setState(() {
                          _countriesEnabled = val;
                          if (val && _allowedCountries.isNotEmpty) {
                            _allowedCities.removeWhere((cityId) {
                              final matches = _cities.where((item) => item['id']?.toString() == cityId);
                              final city = matches.isEmpty ? null : matches.first;
                              final countryId = city?['country_id']?.toString();
                              return countryId == null || !_allowedCountries.contains(countryId);
                            });
                          }
                        }),
                      ),
                      ListTile(
                        enabled: _countriesEnabled,
                        title: Text('community_settings_choose_countries'.tr),
                        subtitle: Text('community_settings_selected_count'.trParams({'count': _allowedCountries.length.toString()})),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: !_countriesEnabled ? null : () async {
                          final selected = await _chooseLocations(
                            title: 'community_settings_choose_countries'.tr,
                            items: _countries,
                            selected: _allowedCountries,
                          );
                          if (selected != null && mounted) {
                            setState(() {
                              _allowedCountries = selected;
                              if (_countriesEnabled) {
                                _allowedCities.removeWhere((cityId) {
                                  final matches = _cities.where((item) => item['id']?.toString() == cityId);
                                  final city = matches.isEmpty ? null : matches.first;
                                  final countryId = city?['country_id']?.toString();
                                  return countryId == null || !_allowedCountries.contains(countryId);
                                });
                              }
                            });
                          }
                        },
                      ),
                      SwitchListTile(
                        title: Text('community_settings_cities_enabled'.tr),
                        subtitle: Text('community_settings_cities_help'.tr),
                        value: _citiesEnabled,
                        onChanged: (val) => setState(() => _citiesEnabled = val),
                      ),
                      ListTile(
                        enabled: _citiesEnabled,
                        title: Text('community_settings_choose_cities'.tr),
                        subtitle: Text('community_settings_selected_count'.trParams({'count': _allowedCities.length.toString()})),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: !_citiesEnabled ? null : () async {
                          final selected = await _chooseLocations(
                            title: 'community_settings_choose_cities'.tr,
                            items: _countriesEnabled && _allowedCountries.isNotEmpty
                                ? _cities.where((city) => _allowedCountries.contains(city['country_id']?.toString())).toList()
                                : _cities,
                            selected: _allowedCities,
                          );
                          if (selected != null && mounted) setState(() => _allowedCities = selected);
                        },
                      ),
                      DropdownButtonFormField<String>(
                        value: _genderRestriction ?? 'none',
                        decoration: InputDecoration(labelText: 'community_settings_gender_restriction'.tr),
                        items: [
                          DropdownMenuItem(value: 'none', child: Text('community_settings_no_gender_restriction'.tr)),
                          DropdownMenuItem(value: 'homme', child: Text('community_settings_gender_male'.tr)),
                          DropdownMenuItem(value: 'femme', child: Text('community_settings_gender_female'.tr)),
                        ],
                        onChanged: (value) => setState(() => _genderRestriction = value == null || value == 'none' ? null : value),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _ageMinController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: 'community_settings_age_min'.tr),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _ageMaxController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: 'community_settings_age_max'.tr),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _visibility,
                        decoration: InputDecoration(labelText: 'community_settings_visibility_label'.tr),
                        items: const [
                          DropdownMenuItem(value: 'public', child: Text('community_settings_visibility_public'.tr)),
                          DropdownMenuItem(value: 'prive', child: Text('community_settings_visibility_private'.tr)),
                        ],
                        onChanged: (val) => setState(() => _visibility = val ?? 'public'),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _save,
                        child: Text('community_save'.tr),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// --- Écran G2 : Règles ---
class CommunityRulesScreen extends StatefulWidget {
  final String communityId;
  const CommunityRulesScreen({super.key, required this.communityId});

  @override
  State<CommunityRulesScreen> createState() => _CommunityRulesScreenState();
}

class _CommunityRulesScreenState extends State<CommunityRulesScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  List<Map<String, dynamic>> _rules = [];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  String? _loadError;

  Future<void> _loadRules() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      _rules = await _service.getCommunityRules(widget.communityId);
    } catch (e) {
      debugPrint('[CommunityRulesScreen] Failed to load rules: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showRuleDialog({Map<String, dynamic>? existingRule}) async {
    final textController = TextEditingController(text: existingRule?['text']?.toString() ?? '');
    final ruleId = existingRule?['id']?.toString() ?? const Uuid().v4();
    final orderIndex = existingRule?['order_index'] is int ? existingRule!['order_index'] as int : _rules.length;

    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text(existingRule == null ? 'community_rule_add'.tr : 'community_rule_edit'.tr),
        content: TextField(
          controller: textController,
          maxLines: 3,
          maxLength: 1000,
          decoration: InputDecoration(hintText: 'community_rule_hint'.tr),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
          ElevatedButton(onPressed: () => Get.back(result: true), child: Text('confirm'.tr)),
        ],
      ),
    );
    final ruleText = textController.text.trim();
    textController.dispose();

    if (confirmed == true && ruleText.isEmpty) {
      Get.snackbar('community_save_error'.tr, 'community_rule_required'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    if (confirmed == true && ruleText.isNotEmpty) {
      try {
        await _service.setCommunityRule(
          p_id: ruleId,
          p_community_id: widget.communityId,
          p_text: ruleText,
          p_order_index: orderIndex,
        );
        _rules = await _service.getCommunityRules(widget.communityId);
        if (mounted) setState(() {});
        Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        debugPrint('[CommunityRulesScreen] Save rule failed: $e');
        Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      }
    }
  }

  Future<void> _deleteRule(String ruleId) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('community_rule_delete_title'.tr),
        content: Text('community_rule_delete_msg'.tr),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () => Get.back(result: true), child: Text('confirm'.tr)),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteCommunityRule(ruleId);
        _rules.removeWhere((r) => r['id']?.toString() == ruleId);
        setState(() {});
        Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_access_sub_rules'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadRules, child: Text('retry'.tr)),
                  ]),
                ))
              : _rules.isEmpty
                  ? Center(child: Text('community_rules_empty'.tr, style: TextStyle(color: colorScheme.onSurfaceVariant)))
                  : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rules.length,
                  itemBuilder: (context, index) {
                    final rule = _rules[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(rule['text']?.toString() ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _showRuleDialog(existingRule: rule)),
                            IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => _deleteRule(rule['id']?.toString() ?? '')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRuleDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// --- Écran F : Publications ---
class CommunityPostSettingsScreen extends StatefulWidget {
  final String communityId;
  const CommunityPostSettingsScreen({super.key, required this.communityId});

  @override
  State<CommunityPostSettingsScreen> createState() => _CommunityPostSettingsScreenState();
}

class _CommunityPostSettingsScreenState extends State<CommunityPostSettingsScreen> {
  final CommunityService _service = Get.find<CommunityService>();
  bool _isLoading = true;
  String? _loadError;
  bool _postsRequireApproval = false;
  String _postPermission = 'everyone';

  @override
  void initState() {
    super.initState();
    _loadPostSettings();
  }

  Future<void> _loadPostSettings() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final snapshot = await _service.getCommunityManagementSettings(widget.communityId);
      final settings = snapshot['settings'] is Map
          ? Map<String, dynamic>.from(snapshot['settings'] as Map)
          : <String, dynamic>{};
      _postsRequireApproval = settings['posts_require_approval'] == true;
      final permission = settings['post_permission']?.toString() ?? 'everyone';
      _postPermission = const {'everyone', 'admins_and_moderators', 'nobody'}.contains(permission)
          ? permission
          : 'everyone';
    } catch (e) {
      debugPrint('[CommunityPostSettingsScreen] Failed to load settings: $e');
      _loadError = _service.localizedCommunityError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      await _service.updateCommunityPostSettings(
        communityId: widget.communityId,
        postPermission: _postPermission,
        postsRequireApproval: _postsRequireApproval,
      );
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      Get.back();
    } catch (e) {
      debugPrint('[CommunityPostSettingsScreen] Save failed: $e');
      Get.snackbar('community_save_error'.tr, _service.localizedCommunityError(e), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_access_sub_posts'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadPostSettings, child: Text('retry'.tr)),
                  ]),
                ))
              : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              title: Text('community_settings_posts_approval'.tr),
              value: _postsRequireApproval,
              onChanged: (val) => setState(() => _postsRequireApproval = val),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _postPermission,
              decoration: InputDecoration(labelText: 'community_post_permissions_label'.tr),
              items: const [
                DropdownMenuItem(value: 'everyone', child: Text('community_post_permission_everyone'.tr)),
                DropdownMenuItem(value: 'admins_and_moderators', child: Text('community_post_permission_admins'.tr)),
                DropdownMenuItem(value: 'nobody', child: Text('community_post_permission_nobody'.tr)),
              ],
              onChanged: (val) => setState(() => _postPermission = val ?? 'everyone'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _save,
              child: _isLoading ? const CircularProgressIndicator() : Text('community_save'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
