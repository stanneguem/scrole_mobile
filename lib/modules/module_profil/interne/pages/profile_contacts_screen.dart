import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/relation_button_widget.dart';
import '../../../module_discussion_direct/interne/controllers/contacts_controller.dart';

class ProfileContactsScreen extends GetView<ContactsController> {
  const ProfileContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: colorScheme.surface,
          elevation: 0,
          centerTitle: true,
          title: Text(
            'AMIS & RELATIONS',
            style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.w900, letterSpacing: 1.2),
          ),
          bottom: TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.6),
            tabs: const [
              Tab(text: 'Mes Amis'),
              Tab(text: 'Demandes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Column(
              children: [
                _buildSearchBar(colorScheme),
                Expanded(child: _buildContactsList(colorScheme)),
              ],
            ),
            _buildRequestsTab(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          onChanged: (v) => controller.searchQuery.value = v,
          decoration: const InputDecoration(
            hintText: 'Rechercher un ami...',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsList(ColorScheme colorScheme) {
    return Obx(() {
      final list = controller.filteredContacts;
      if (controller.isLoading.value && list.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      if (list.isEmpty) {
        return const Center(child: Text('Aucun ami trouvé.'));
      }

      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        separatorBuilder: (_, index) => Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
        itemBuilder: (context, index) {
          final contact = list[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
              backgroundImage: contact.avatarUrl != null ? NetworkImage(contact.avatarUrl!) : null,
              child: contact.avatarUrl == null
                  ? Text(contact.name[0].toUpperCase(), style: TextStyle(color: colorScheme.primary))
                  : null,
            ),
            title: Text(contact.name, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text('@${contact.username}', style: TextStyle(color: Colors.grey[500])),
            trailing: RelationButtonWidget(
              targetUserId: contact.id,
              onRelationChanged: () => controller.loadContacts(),
            ),
            onTap: () => Get.toNamed(
              AppPages.externalProfilePath(contact.id),
            ),
          );
        },
      );
    });
  }

  Widget _buildRequestsTab(ColorScheme colorScheme) {
    return Obx(() {
      if (controller.isLoadingRequests.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final incoming = controller.incomingRequests;
      final outgoing = controller.outgoingRequests;

      if (incoming.isEmpty && outgoing.isEmpty) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mail_outline_rounded, size: 48, color: AppColors.textSecondary),
              SizedBox(height: 12),
              Text('Aucune demande d\'ami en attente'),
            ],
          ),
        );
      }

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (incoming.isNotEmpty) ...[
            Text('DEMANDES REÇUES (${incoming.length})', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
            const SizedBox(height: 12),
            ...incoming.map((req) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: req.otherPhotoUrl != null ? NetworkImage(req.otherPhotoUrl!) : null,
                      child: req.otherPhotoUrl == null ? Text(req.otherName[0].toUpperCase()) : null,
                    ),
                    title: Text(req.otherName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('@${req.otherUsername}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.error),
                          onPressed: () => controller.respondFriendRequest(req.id, false, req.senderId),
                        ),
                        ElevatedButton(
                          onPressed: () => controller.respondFriendRequest(req.id, true, req.senderId),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Accepter'),
                        ),
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 24),
          ],
          if (outgoing.isNotEmpty) ...[
            Text('DEMANDES ENVOYÉES (${outgoing.length})', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
            const SizedBox(height: 12),
            ...outgoing.map((req) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: req.otherPhotoUrl != null ? NetworkImage(req.otherPhotoUrl!) : null,
                      child: req.otherPhotoUrl == null ? Text(req.otherName[0].toUpperCase()) : null,
                    ),
                    title: Text(req.otherName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('@${req.otherUsername}'),
                    trailing: OutlinedButton(
                      onPressed: () => controller.cancelFriendRequest(req.id),
                      child: const Text('Annuler'),
                    ),
                  ),
                )),
          ],
        ],
      );
    });
  }
}
