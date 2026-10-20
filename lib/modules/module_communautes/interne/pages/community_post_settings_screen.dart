import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CommunityPostSettingsScreen extends StatefulWidget {
  final bool initialCommentsEnabled;
  final bool initialSharingEnabled;
  const CommunityPostSettingsScreen({
    super.key,
    this.initialCommentsEnabled = true,
    this.initialSharingEnabled = true,
  });

  @override
  State<CommunityPostSettingsScreen> createState() => _CommunityPostSettingsScreenState();
}

class _CommunityPostSettingsScreenState extends State<CommunityPostSettingsScreen> {
  late bool _comments = widget.initialCommentsEnabled;
  late bool _sharing = widget.initialSharingEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres de publication')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Activer les commentaires'),
            value: _comments,
            onChanged: (v) => setState(() => _comments = v),
          ),
          SwitchListTile(
            title: const Text('Activer le partage'),
            value: _sharing,
            onChanged: (v) => setState(() => _sharing = v),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () => Get.back(result: {'commentsEnabled': _comments, 'sharingEnabled': _sharing}),
              child: const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}
