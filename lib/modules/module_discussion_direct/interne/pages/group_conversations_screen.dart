import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
                    title: Text(invite.groupName?.isNotEmpty == true ? invite.groupName! : 'Invitation à un groupe'),
                    subtitle: Text('${invite.inviterName?.isNotEmpty == true ? '${invite.inviterName} · ' : ''}Invitation reçue le ${MaterialLocalizations.of(context).formatShortDate(invite.createdAt.toLocal())}'),
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
  String _wallpaperKey = 'none';
  late GroupConversation _group;
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _messagesFuture = widget.service.fetchMessages(widget.group.id);
    widget.service.getPersonalWallpaper(widget.group.id).then((value) {
      if (mounted) setState(() => _wallpaperKey = value);
    }).catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.service.markRead(widget.group.id);
      } catch (_) {
        // A pending group has no readable history until it activates.
      }
    });
    _messagesChannel = Supabase.instance.client
        .channel('group-messages-${widget.group.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: widget.group.id,
          ),
          callback: (_) {
            if (mounted) {
              setState(() {
                _messagesFuture = widget.service.fetchMessages(widget.group.id);
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.group.id,
          ),
          callback: (_) async {
            try {
              final groups = await widget.service.fetchMyGroups();
              final refreshed = groups.where((group) => group.id == widget.group.id);
              if (mounted && refreshed.isNotEmpty) {
                setState(() => _group = refreshed.first);
                _reloadMessages();
              }
            } catch (_) {
              // The group may have been closed or access revoked.
            }
          },
        )
        .subscribe();
  }

  void _reloadMessages() {
    if (mounted) setState(() => _messagesFuture = widget.service.fetchMessages(widget.group.id));
  }

  @override
  void dispose() {
    _composer.dispose();
    final channel = _messagesChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _chooseWallpaper() async {
    const choices = <String, String>{
      'none': 'Aucun fond',
      'fond1': 'Fond 1',
      'fond2': 'Fond 2',
      'fond3': 'Fond 3',
    };
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Fond de discussion personnel'),
        children: choices.entries.map((entry) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, entry.key),
          child: Text(entry.value),
        )).toList(),
      ),
    );
    if (selected == null) return;
    try {
      await widget.service.setPersonalWallpaper(widget.group.id, selected);
      if (mounted) setState(() => _wallpaperKey = selected);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Votre préférence de fond a été enregistrée.')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de modifier le fond : $e')),
      );
    }
  }

  Future<void> _attachImage() async {
    if (_sending || !widget.group.canSendMessages) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final file = File(picked.path);
      final path = await widget.service.uploadGroupMedia(
        groupId: widget.group.id,
        file: file,
        contentType: picked.mimeType ?? 'image/jpeg',
      );
      await widget.service.sendMessage(groupId: widget.group.id, type: 'image', mediaPaths: [path]);
      if (mounted) setState(() => _messagesFuture = widget.service.fetchMessages(widget.group.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Envoi de la pièce jointe impossible : $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending || !widget.group.canSendMessages) return;
    setState(() => _sending = true);
    try {
      await widget.service.sendMessage(groupId: widget.group.id, text: text);
      _composer.clear();
      if (mounted) {
        await widget.service.markRead(widget.group.id);
        setState(() => _messagesFuture = widget.service.fetchMessages(widget.group.id));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Envoi impossible : $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _group.canSendMessages;
    return Scaffold(
      appBar: AppBar(
        title: Text(_group.name),
        actions: [
          IconButton(
            tooltip: 'Fond personnel',
            icon: const Icon(Icons.wallpaper_outlined),
            onPressed: _chooseWallpaper,
          ),
          IconButton(
            tooltip: 'Membres et paramètres',
            icon: const Icon(Icons.people_outline),
            onPressed: () => Get.to(() => GroupMembersScreen(group: widget.group, service: widget.service)),
          ),
        ],
      ),
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
          child: Container(
            color: _wallpaperKey == 'none'
                ? Theme.of(context).scaffoldBackgroundColor
                : Color.alphaBlend(
                    ({
                      'fond1': const Color(0xFF4F86F7),
                      'fond2': const Color(0xFF38A58A),
                      'fond3': const Color(0xFFE2A44B),
                    }[_wallpaperKey] ?? Theme.of(context).colorScheme.surfaceTint).withValues(alpha: 0.10),
                    Theme.of(context).colorScheme.surface,
                  ),
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
                  final senderId = '${message['sender_id'] ?? ''}';
                  final mine = senderId == Supabase.instance.client.auth.currentUser?.id;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
                      decoration: BoxDecoration(
                        color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (!mine && (message['sender_name'] as String?)?.isNotEmpty == true)
                          Text(message['sender_name'] as String, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                        if (message['type'] == 'image' && message['media_urls'] is List && (message['media_urls'] as List).isNotEmpty)
                          FutureBuilder<String>(
                            future: widget.service.createSignedMediaUrl('${(message['media_urls'] as List).first}'),
                            builder: (context, mediaSnapshot) {
                              if (mediaSnapshot.hasError) return const Text('Image inaccessible');
                              if (!mediaSnapshot.hasData) return const SizedBox(width: 180, height: 120, child: Center(child: CircularProgressIndicator()));
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(mediaSnapshot.data!, width: 220, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Text('Impossible de charger l’image')),
                              );
                            },
                          )
                        else if (body.isNotEmpty) Text(body)
                        else const Text('Pièce jointe'),
                        if (message['created_at'] != null)
                          Align(alignment: Alignment.bottomRight, child: Text(MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(DateTime.parse('${message['created_at']}').toLocal())), style: Theme.of(context).textTheme.labelSmall)),
                      ]),
                    ),
                  );
                },
              );
            },
            ),
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


class GroupMembersScreen extends StatefulWidget {
  const GroupMembersScreen({super.key, required this.group, required this.service});
  final GroupConversation group;
  final SupabaseGroupMessagingService service;

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  late Future<List<GroupMember>> _membersFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _membersFuture = widget.service.fetchMembers(widget.group.id);
  }

  void _reload() => setState(() => _membersFuture = widget.service.fetchMembers(widget.group.id));

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitter le groupe ?'),
        content: const Text('Si vous êtes propriétaire, la propriété sera transmise à l’administrateur actif le plus ancien, sinon au membre actif le plus ancien.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Quitter')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.service.leaveGroup(widget.group.id);
      if (!mounted) return;
      Get.until((route) => route.isFirst || route.settings.name == null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vous avez quitté le groupe.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible de quitter le groupe : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    final controller = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool searching = false;
    String? searchError;
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> search(String value) async {
            if (value.trim().length < 2) {
              setDialogState(() { results = []; searching = false; searchError = null; });
              return;
            }
            setDialogState(() { searching = true; searchError = null; });
            try {
              final found = await widget.service.searchUsersForGroupInvite(widget.group.id, value);
              setDialogState(() { results = found; searching = false; });
            } catch (e) {
              setDialogState(() { searching = false; searchError = 'Recherche impossible : $e'; });
            }
          }

          return AlertDialog(
            title: const Text('Inviter un membre'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nom ou pseudo',
                      hintText: 'Saisir au moins 2 caractères',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: search,
                  ),
                  const SizedBox(height: 12),
                  if (searching) const LinearProgressIndicator(),
                  if (searchError != null) Text(searchError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  if (!searching && searchError == null && controller.text.trim().length >= 2 && results.isEmpty)
                    const Padding(padding: EdgeInsets.all(12), child: Text('Aucun utilisateur disponible trouvé.')),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final user = results[index];
                        final username = '${user['username'] ?? ''}';
                        final displayName = '${user['display_name'] ?? username}';
                        final avatar = user['avatar_url'] as String?;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: avatar?.isNotEmpty == true ? NetworkImage(avatar!) : null,
                            child: avatar?.isNotEmpty == true ? null : const Icon(Icons.person_outline),
                          ),
                          title: Text(displayName),
                          subtitle: Text(username.isEmpty ? 'Utilisateur Scrole' : '@$username'),
                          onTap: () => Navigator.of(dialogContext).pop(user),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Annuler'))],
          );
        },
      ),
    );
    controller.dispose();
    final id = selected?['user_id'] as String?;
    if (id == null || id.isEmpty) return;
    try {
      await widget.service.inviteMembers(widget.group.id, [id]);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation envoyée. Le membre devra l’accepter.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invitation impossible : $e')));
    }
  }

  Future<void> _changeRole(GroupMember member) async {
    final newRole = member.role == GroupMemberRole.administrator
        ? GroupMemberRole.member
        : GroupMemberRole.administrator;
    try {
      await widget.service.changeMemberRole(widget.group.id, member.userId, newRole);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Modification impossible : $e')));
    }
  }

  Future<void> _remove(GroupMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer ce membre ?'),
        content: const Text('Cette personne perdra immédiatement l’accès au groupe et à ses médias protégés. Elle devra recevoir une nouvelle invitation pour revenir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.removeMember(widget.group.id, member.userId);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retrait impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Membres du groupe')),
      body: FutureBuilder<List<GroupMember>>(
        future: _membersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Impossible de charger les membres : ${snapshot.error}'));
          final members = snapshot.data ?? const <GroupMember>[];
          final currentUserId = Supabase.instance.client.auth.currentUser?.id;
          GroupMember? currentMember;
          for (final member in members) {
            if (member.userId == currentUserId) { currentMember = member; break; }
          }
          final canManage = currentMember?.role == GroupMemberRole.owner || currentMember?.role == GroupMemberRole.administrator;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (canManage) FilledButton.icon(onPressed: _busy ? null : _invite, icon: const Icon(Icons.person_add_alt_1), label: const Text('Inviter un membre')),
              const SizedBox(height: 8),
              ...members.map((member) => Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(member.role == GroupMemberRole.owner ? Icons.workspace_premium : member.role == GroupMemberRole.administrator ? Icons.admin_panel_settings_outlined : Icons.person_outline)),
                  title: Text(member.displayName?.isNotEmpty == true ? member.displayName! : 'Membre'),
                  subtitle: Text(member.role == GroupMemberRole.owner ? 'Propriétaire' : member.role == GroupMemberRole.administrator ? 'Administrateur' : 'Membre'),
                  trailing: canManage && member.userId != currentUserId && member.role != GroupMemberRole.owner
                      ? PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'role') _changeRole(member);
                            if (action == 'remove') _remove(member);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'role', child: Text(member.role == GroupMemberRole.administrator ? 'Rétrograder en membre' : 'Nommer administrateur')),
                            const PopupMenuItem(value: 'remove', child: Text('Retirer du groupe')),
                          ],
                        )
                      : null,
                ),
              )),
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: _busy ? null : _leave, icon: const Icon(Icons.exit_to_app), label: const Text('Quitter le groupe')),
            ],
          );
        },
      ),
    );
  }
}
