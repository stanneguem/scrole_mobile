import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../centre/models/group_conversation.dart';
import '../../externe/services/supabase_group_messaging_service.dart';

/// Standalone entry screen for group conversations. Register it in the app's
/// discussion navigation after the matching reviewed SQL is installed.
class GroupConversationsScreen extends StatefulWidget {
  const GroupConversationsScreen({super.key});

  @override
  State<GroupConversationsScreen> createState() => _GroupConversationsScreenState();
}

class _GroupConversationsScreenState extends State<GroupConversationsScreen> {
  late final SupabaseGroupMessagingService _service;
  late Future<List<GroupConversation>> _groupsFuture;
  late Future<List<GroupInvitation>> _invitationsFuture;

  @override
  void initState() {
    super.initState();
    _service = SupabaseGroupMessagingService(Supabase.instance.client);
    _refresh();
  }

  void _refresh() {
    _groupsFuture = _service.fetchMyGroups();
    _invitationsFuture = _service.fetchPendingInvitations();
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Créer un groupe'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Nom du groupe',
            hintText: 'Ex. Amis, famille, équipe…',
          ),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Créer')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await _service.createGroup(name: name);
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Groupe créé. Invitez des membres pour démarrer la discussion.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible de créer le groupe : $e')));
    }
  }

  Future<void> _respond(GroupInvitation invitation, bool accept) async {
    try {
      await _service.respondToInvitation(invitation.id, accept: accept);
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? 'Invitation acceptée.' : 'Invitation refusée.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groupes'),
        actions: [
          IconButton(tooltip: 'Créer un groupe', onPressed: _createGroup, icon: const Icon(Icons.group_add_outlined)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_refresh),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('Invitations reçues', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<GroupInvitation>>(
              future: _invitationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) return _errorTile('Chargement des invitations impossible.', snapshot.error.toString());
                final invitations = snapshot.data ?? const <GroupInvitation>[];
                if (invitations.isEmpty) return const ListTile(leading: Icon(Icons.mail_outline), title: Text('Aucune invitation en attente'));
                return Column(children: invitations.map((invite) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                    title: Text('Invitation à un groupe'),
                    subtitle: Text('Invitation reçue le ${MaterialLocalizations.of(context).formatShortDate(invite.createdAt.toLocal())}'),
                    trailing: Wrap(spacing: 4, children: [
                      IconButton(tooltip: 'Refuser', onPressed: () => _respond(invite, false), icon: const Icon(Icons.close)),
                      IconButton(tooltip: 'Accepter', onPressed: () => _respond(invite, true), icon: Icon(Icons.check_circle_outline, color: theme.colorScheme.primary)),
                    ]),
                  ),
                )).toList());
              },
            ),
            const SizedBox(height: 24),
            Text('Mes groupes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<GroupConversation>>(
              future: _groupsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) return _errorTile('Chargement des groupes impossible.', snapshot.error.toString());
                final groups = snapshot.data ?? const <GroupConversation>[];
                if (groups.isEmpty) return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Column(children: [Icon(Icons.groups_2_outlined, size: 44), SizedBox(height: 8), Text('Aucun groupe pour le moment'), Text('Créez un groupe ou acceptez une invitation.')]),
                );
                return Column(children: groups.map((group) {
                  final active = group.canSendMessages;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(active ? Icons.groups_2_outlined : Icons.group_add_outlined)),
                      title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(active ? '${group.activeMemberCount} membres' : 'En attente de 3 membres pour activer les messages'),
                      trailing: Icon(active ? Icons.chevron_right : Icons.hourglass_top_rounded),
                      onTap: () {
                        Get.to(() => GroupChatScreen(group: group, service: _service));
                      },
                    ),
                  );
                }).toList());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorTile(String title, String details) => ListTile(
    leading: const Icon(Icons.error_outline),
    title: Text(title),
    subtitle: Text(details, maxLines: 3, overflow: TextOverflow.ellipsis),
  );
}

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key, required this.group, required this.service});
  final GroupConversation group;
  final SupabaseGroupMessagingService service;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _composer = TextEditingController();
  late Future<List<Map<String, dynamic>>> _messagesFuture;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messagesFuture = widget.service.fetchMessages(widget.group.id);
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending || !widget.group.canSendMessages) return;
    setState(() => _sending = true);
    try {
      await widget.service.sendMessage(groupId: widget.group.id, text: text);
      _composer.clear();
      if (mounted) setState(() => _messagesFuture = widget.service.fetchMessages(widget.group.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Envoi impossible : $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = widget.group.canSendMessages;
    return Scaffold(
      appBar: AppBar(title: Text(widget.group.name)),
      body: Column(children: [
        if (!canSend)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(children: [Icon(Icons.info_outline), SizedBox(width: 8), Expanded(child: Text('La discussion sera activée lorsque 3 membres auront accepté et rejoint le groupe.'))]),
            ),
          ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _messagesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Impossible de charger les messages : ${snapshot.error}')));
              final messages = snapshot.data ?? const <Map<String, dynamic>>[];
              if (messages.isEmpty) return const Center(child: Text('Aucun message.'));
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final body = '${message['content'] ?? message['text'] ?? ''}';
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(body.isEmpty ? 'Pièce jointe' : body),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _composer,
                enabled: canSend && !_sending,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Écrire un message…', border: OutlineInputBorder(), isDense: true),
                onSubmitted: (_) => _send(),
              )),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: canSend && !_sending ? _send : null, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
