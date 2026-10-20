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
                  communitySlogan ?? 'Vivre la technologie ensemble',
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
        final comm = await _service.getCommunityById(widget.communityId);
        if (comm != null) {
          _avatarUrl = comm.avatarUrl;
          _slogan = comm.description;
        }
      } catch (_) {}
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
            communityName: widget.communityName,
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
            onTap: () => Get.to(() => CommunityModerationCenterScreen(communityId: widget.communityId, communityName: widget.communityName, communityAvatar: _avatarUrl)),
          ),
          const SizedBox(height: 12),

          // 2. Accès et règles -> Écran E (Admin only)
          if (_isAdmin)
            _buildTile(
              icon: Icons.security_outlined,
              iconColor: Colors.green,
              title: 'community_mgmt_access'.tr,
              subtitle: 'community_mgmt_access_sub'.tr,
              onTap: () => Get.to(() => CommunityAccessRulesHubScreen(communityId: widget.communityId, communityName: widget.communityName, communityAvatar: _avatarUrl)),
            ),
          if (_isAdmin) const SizedBox(height: 12),

          // 3. Informations de la communauté -> Écran H (Admin only)
          if (_isAdmin)
            _buildTile(
              icon: Icons.info_outline_rounded,
              iconColor: Colors.deepOrange,
              title: 'community_mgmt_info'.tr,
              subtitle: 'community_mgmt_info_sub'.tr,
              onTap: () => Get.to(() => CommunityInfoHubScreen(communityId: widget.communityId, communityName: widget.communityName, communityAvatar: _avatarUrl)),
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
      Get.snackbar('community_save_error'.tr, e.toString(), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> _resolveUserReport(String reportId, String action) async {
    try {
      await _service.resolveCommunityUserReport(reportId, action);
      await _loadReports();
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('community_save_error'.tr, e.toString(), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
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
                        title: Text('Signalement: ${r['target_type'] ?? ''}'),
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
                        title: const Text('Signalement membre'),
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
  List<dynamic> _joinRequests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final reqsRes = await _service.getCommunityJoinRequests(widget.communityId);
      _joinRequests = reqsRes['items'] is List ? reqsRes['items'] : [];
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _respondRequest(String requestId, bool accepted) async {
    try {
      await _service.respondCommunityJoinRequest(requestId, accepted);
      await _loadRequests();
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('community_save_error'.tr, e.toString(), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_mod_section_requests'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _joinRequests.isEmpty
              ? const Center(child: Text('Aucune demande en attente'))
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
class CommunityInfoHubScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('community_mgmt_info'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CommunityHeaderCard(communityName: communityName, communityAvatar: communityAvatar),
          _buildHubTile(context, title: 'community_info_sub_desc'.tr, subtitle: 'community_info_sub_desc_desc'.tr, icon: Icons.info_outline_rounded, iconColor: Colors.orange, onTap: () => Get.to(() => CommunityInfoSettingsScreen(communityId: communityId, communityName: communityName))),
          const SizedBox(height: 12),
          _buildHubTile(context, title: 'community_info_sub_interests'.tr, subtitle: 'community_info_sub_interests_desc'.tr, icon: Icons.favorite_border_rounded, iconColor: Colors.pink, onTap: () => Get.to(() => CommunityInterestsScreen(communityId: communityId))),
          const SizedBox(height: 12),
          _buildHubTile(context, title: 'community_info_sub_images'.tr, subtitle: 'community_info_sub_images_desc'.tr, icon: Icons.image_outlined, iconColor: Colors.purple, onTap: () => Get.to(() => CommunityImagesScreen(communityId: communityId))),
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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.communityName;
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
      await _service.updateCommunityInfo(
        id: widget.communityId,
        name: _nameController.text.trim(),
        slogan: _sloganController.text.trim().isEmpty ? null : _sloganController.text.trim(),
        description: _descController.text.trim(),
      );
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      Get.back();
    } catch (e) {
      Get.snackbar('community_save_error'.tr, e.toString(), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_info_sub_desc'.tr)),
      body: SingleChildScrollView(
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
  List<Map<String, dynamic>> _allInterests = [];
  Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadInterests();
  }

  Future<void> _loadInterests() async {
    setState(() => _isLoading = true);
    try {
      final all = await _service.getAvailableInterests();
      final current = await _service.getCommunityInterests(widget.communityId);
      _allInterests = all;
      _selectedIds = current.map((i) => i['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
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
      Get.snackbar('community_save_error'.tr, e.toString(), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
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
                    setState(() {
                      if (val == true) {
                        if (_selectedIds.length >= 10) return;
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
  bool _isLoading = false;
  String? _currentAvatarUrl;
  String? _currentCoverUrl;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      final comm = await _service.getCommunityById(widget.communityId);
      if (comm != null && mounted) {
        setState(() {
          _currentAvatarUrl = comm.avatarUrl;
          _currentCoverUrl = comm.bannerUrl;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickAndUploadImage({required bool isProfile}) async {
    showImageSourceSheet(
      context,
      onCamera: () => _processImage(isProfile: isProfile, source: ImageSource.camera),
      onGallery: () => _processImage(isProfile: isProfile, source: ImageSource.gallery),
    );
  }

  Future<void> _processImage({required bool isProfile, required ImageSource source}) async {
    final file = await _mediaService.pickImage(source: source);
    if (file == null) return;

    setState(() => _isLoading = true);
    try {
      final ext = p.extension(file.path);
      final path = 'communities/${widget.communityId}/${isProfile ? 'profile' : 'cover'}_${DateTime.now().millisecondsSinceEpoch}$ext';
      final url = await _storage.uploadFile(bucket: 'community-media', path: path, file: file);

      final comm = await _service.getCommunityById(widget.communityId);
      await _service.updateCommunityInfo(
        id: widget.communityId,
        name: comm?.name ?? '',
        description: comm?.description ?? '',
        photoProfile: isProfile ? url : _currentAvatarUrl,
        photoCover: !isProfile ? url : _currentCoverUrl,
      );

      if (mounted) {
        setState(() {
          if (isProfile) _currentAvatarUrl = url;
          else _currentCoverUrl = url;
        });
      }

      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('community_save_error'.tr, e.toString(), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_info_sub_images'.tr)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('Photo de profil'),
                    trailing: ElevatedButton(
                      onPressed: () => _pickAndUploadImage(isProfile: true),
                      child: const Text('Changer'),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.image),
                    title: const Text('Photo de couverture'),
                    trailing: ElevatedButton(
                      onPressed: () => _pickAndUploadImage(isProfile: false),
                      child: const Text('Changer'),
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
  String? _genderRestriction;
  int? _ageMin;
  int? _ageMax;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final res = await _service.getCommunityAccessRules(widget.communityId);
      _certificationRequired = res['certification_required'] == true;
      _genderRestriction = res['gender_restriction']?.toString();
      _ageMin = (res['age_min'] as num?)?.toInt();
      _ageMax = (res['age_max'] as num?)?.toInt();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      await _service.updateCommunitySettings(
        communityId: widget.communityId,
        visibility: _visibility,
        requireManualApproval: _requireManualApproval,
      );
      await _service.updateCommunityMemberVisibility(widget.communityId, _membersListVisible);
      await _service.updateCommunityAccessRules(
        communityId: widget.communityId,
        countriesEnabled: false,
        allowedCountries: [],
        citiesEnabled: false,
        allowedCities: [],
        certificationRequired: _certificationRequired,
        genderRestriction: _genderRestriction,
        ageMin: _ageMin,
        ageMax: _ageMax,
      );
      Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      Get.back();
    } catch (e) {
      Get.snackbar('community_save_error'.tr, e.toString(), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
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
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _visibility,
                        decoration: InputDecoration(labelText: 'community_settings_visibility_label'.tr),
                        items: const [
                          DropdownMenuItem(value: 'public', child: Text('Publique')),
                          DropdownMenuItem(value: 'prive', child: Text('Privée')),
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

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);
    try {
      _rules = await _service.getCommunityRules(widget.communityId);
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
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
          decoration: InputDecoration(hintText: 'community_rule_hint'.tr),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
          ElevatedButton(onPressed: () => Get.back(result: true), child: Text('confirm'.tr)),
        ],
      ),
    );

    if (confirmed == true && textController.text.trim().isNotEmpty) {
      try {
        await _service.setCommunityRule(
          p_id: ruleId,
          p_community_id: widget.communityId,
          p_text: textController.text.trim(),
          p_order_index: orderIndex,
        );
        _rules = await _service.getCommunityRules(widget.communityId);
        setState(() {});
        Get.snackbar('community_save_success'.tr, '', snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        Get.snackbar('community_save_error'.tr, e.toString(), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
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
        Get.snackbar('community_save_error'.tr, e.toString(), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
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
          : _rules.isEmpty
              ? Center(child: Text('Aucune règle pour le moment', style: TextStyle(color: colorScheme.onSurfaceVariant)))
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
  bool _isLoading = false;
  bool _postsRequireApproval = false;
  String _postPermission = 'members';

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
      Get.snackbar('community_save_error'.tr, e.toString(), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('community_access_sub_posts'.tr)),
      body: SingleChildScrollView(
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
                DropdownMenuItem(value: 'everyone', child: Text('Tout le monde')),
                DropdownMenuItem(value: 'members', child: Text('Membres')),
                DropdownMenuItem(value: 'admins_and_moderators', child: Text('Admins et modérateurs')),
                DropdownMenuItem(value: 'nobody', child: Text('Personne')),
              ],
              onChanged: (val) => setState(() => _postPermission = val ?? 'members'),
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
