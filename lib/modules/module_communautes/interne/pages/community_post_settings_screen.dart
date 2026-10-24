import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../externe/repositories/community_repository.dart';

class CommunityPostSettingsScreen extends StatefulWidget {
  final String communityId;

  const CommunityPostSettingsScreen({
    super.key,
    required this.communityId,
  });

  @override
  State<CommunityPostSettingsScreen> createState() => _CommunityPostSettingsScreenState();
}

class _CommunityPostSettingsScreenState extends State<CommunityPostSettingsScreen> {
  final CommunityRepository _repository = CommunityRepository();
  bool _comments = true;
  bool _sharing = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _repository.getCommunityManagementSettings(widget.communityId);
      final settings = response['settings'] is Map
          ? Map<String, dynamic>.from(response['settings'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _comments = settings['allow_comments'] != false;
        _sharing = settings['allow_post_sharing'] != false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repository.updateCommunityManagementSettings(
        communityId: widget.communityId,
        allowComments: _comments,
      );
      await _repository.setCommunityPostSharingEnabled(
        communityId: widget.communityId,
        enabled: _sharing,
      );
      if (!mounted) return;
      Get.snackbar(
        'Paramètres enregistrés',
        'Les autorisations de publication de la communauté ont été mises à jour.',
        snackPosition: SnackPosition.BOTTOM,
      );
      Get.back(result: {
        'commentsEnabled': _comments,
        'sharingEnabled': _sharing,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres des publications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Choisissez les actions autorisées pour les publications de cette communauté.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        title: const Text('Autoriser les commentaires'),
                        subtitle: const Text('Les membres peuvent commenter les publications de la communauté.'),
                        value: _comments,
                        onChanged: _saving ? null : (value) => setState(() => _comments = value),
                      ),
                      const Divider(height: 1),
                      SwitchListTile.adaptive(
                        title: const Text('Autoriser le repartage des publications'),
                        subtitle: const Text('Si cette option est désactivée, aucune publication de la communauté ne peut être repartagée dans un fil ou une story.'),
                        value: _sharing,
                        onChanged: _saving ? null : (value) => setState(() => _sharing = value),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: colors.error)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _loadSettings,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _saveSettings,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer'),
                ),
              ],
            ),
    );
  }
}
