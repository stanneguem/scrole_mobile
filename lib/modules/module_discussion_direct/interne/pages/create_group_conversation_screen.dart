import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/contacts_controller.dart';
import '../../externe/services/supabase_group_messaging_service.dart';

class CreateGroupConversationScreen extends StatefulWidget {
  const CreateGroupConversationScreen({super.key});
  @override State<CreateGroupConversationScreen> createState() => _CreateGroupConversationScreenState();
}

class _CreateGroupConversationScreenState extends State<CreateGroupConversationScreen> {
  final _name = TextEditingController();
  final _service = SupabaseGroupMessagingService(Supabase.instance.client);
  final Set<String> _selected = {};
  int _step = 0;
  bool _busy = false;
  @override void dispose() { _name.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_step == 0) {
      if (_name.text.trim().isEmpty) { Get.snackbar('Nom du groupe', 'Saisis un nom pour continuer.'); return; }
      final contacts = Get.find<ContactsController>();
      if (contacts.contacts.isEmpty) await contacts.loadContacts();
      if (mounted) setState(() => _step = 1);
      return;
    }
    if (_selected.isEmpty) { Get.snackbar('Membres', 'Sélectionne au moins un contact à inviter.'); return; }
    setState(() => _busy = true);
    try {
      await _service.createGroup(name: _name.text.trim(), inviteUserIds: _selected.toList());
      if (!mounted) return;
      Get.back();
      Get.snackbar('Groupe créé', 'Les invitations ont été envoyées.');
    } catch (e) { if (mounted) Get.snackbar('Création impossible', e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override Widget build(BuildContext context) {
    final contacts = Get.find<ContactsController>();
    return Scaffold(
      appBar: AppBar(title: Text(_step == 0 ? 'Créer un groupe' : 'Inviter des membres'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { if (_step == 1) { setState(() => _step = 0); } else { Get.back(); } })),
      body: SafeArea(child: Column(children: [
        Expanded(child: _step == 0
          ? ListView(padding: const EdgeInsets.all(20), children: [
              const CircleAvatar(radius: 42, child: Icon(Icons.groups_2_outlined, size: 34)),
              const SizedBox(height: 24),
              const Text('Nom du groupe'),
              const SizedBox(height: 8),
              TextField(controller: _name, maxLength: 80, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Ex. : Amis, famille, projet', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Text('Tu pourras sélectionner les contacts à inviter à l’étape suivante.', style: Theme.of(context).textTheme.bodyMedium),
            ])
          : Column(children: [
              Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => contacts.searchQuery.value = v, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un contact', border: OutlineInputBorder())),),
              Expanded(child: Obx(() {
                final list = contacts.filteredContacts;
                if (contacts.isLoading.value && list.isEmpty) return const Center(child: CircularProgressIndicator());
                if (list.isEmpty) return const Center(child: Text('Aucun contact disponible.'));
                return ListView.builder(itemCount: list.length, itemBuilder: (context, i) {
                  final c = list[i]; final chosen = _selected.contains(c.id);
                  return CheckboxListTile(value: chosen, onChanged: (v) => setState(() { if (v == true) { _selected.add(c.id); } else { _selected.remove(c.id); } }), secondary: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase())), title: Text(c.name), subtitle: Text('@' + c.username));
                });
              })),
            ])),
        Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const CircularProgressIndicator() : Text(_step == 0 ? 'Continuer' : 'Créer et inviter (' + _selected.length.toString() + ')')))),
      ])),
    );
  }
}