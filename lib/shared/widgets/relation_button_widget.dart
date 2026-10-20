import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/text_styles.dart';
import '../../modules/module_discussion_direct/centre/persistence/social_local_dao.dart';
import '../../modules/module_discussion_direct/externe/repositories/social_repository.dart';

class RelationButtonWidget extends StatefulWidget {
  final String targetUserId;
  final String? requestId;
  final String? senderId;
  final DateTime? nextRetryAt;
  final VoidCallback? onRelationChanged;

  const RelationButtonWidget({
    super.key,
    required this.targetUserId,
    this.requestId,
    this.senderId,
    this.nextRetryAt,
    this.onRelationChanged,
  });

  @override
  State<RelationButtonWidget> createState() => _RelationButtonWidgetState();
}

class _RelationButtonWidgetState extends State<RelationButtonWidget> {
  final SocialRepository _socialRepo = SocialRepository();
  RelationState _state = RelationState.none;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void didUpdateWidget(covariant RelationButtonWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetUserId != widget.targetUserId) {
      _loadState();
    }
  }

  Future<void> _loadState() async {
    setState(() => _isLoading = true);
    try {
      final state = await _socialRepo.getRelationState(widget.targetUserId);
      if (mounted) {
        setState(() {
          _state = state;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendRequest() async {
    setState(() => _isLoading = true);
    try {
      await _socialRepo.sendFriendRequest(widget.targetUserId);
      await _loadState();
      widget.onRelationChanged?.call();
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
      setState(() => _isLoading = false);
    }
  }

  Future<void> _respond(bool accept) async {
    final reqId = widget.requestId;
    if (reqId == null || reqId.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await _socialRepo.respondFriendRequest(reqId, accept, senderId: widget.senderId ?? widget.targetUserId);
      await _loadState();
      widget.onRelationChanged?.call();
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancel() async {
    final reqId = widget.requestId;
    if (reqId == null || reqId.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await _socialRepo.cancelFriendRequest(reqId);
      await _loadState();
      widget.onRelationChanged?.call();
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeFriend() async {
    setState(() => _isLoading = true);
    try {
      await _socialRepo.removeFriendship(widget.targetUserId);
      await _loadState();
      widget.onRelationChanged?.call();
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unblock() async {
    setState(() => _isLoading = true);
    try {
      await _socialRepo.unblockUser(widget.targetUserId);
      await _loadState();
      widget.onRelationChanged?.call();
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
      setState(() => _isLoading = false);
    }
  }

  Future<void> _block() async {
    setState(() => _isLoading = true);
    try {
      await _socialRepo.blockUser(widget.targetUserId);
      await _loadState();
      widget.onRelationChanged?.call();
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    switch (_state) {
      case RelationState.self:
        return const SizedBox.shrink();

      case RelationState.friend:
        return PopupMenuButton<String>(
          onSelected: (val) {
            if (val == 'remove') _removeFriend();
            if (val == 'block') _block();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'remove', child: Text('Retirer de mes amis')),
            const PopupMenuItem(value: 'block', child: Text('Bloquer', style: TextStyle(color: AppColors.error))),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_rounded, color: Colors.green, size: 18),
                const SizedBox(width: 6),
                Text('Amis', style: AppTextStyles.bodySmall.copyWith(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );

      case RelationState.requestSent:
        return OutlinedButton.icon(
          onPressed: _cancel,
          icon: const Icon(Icons.close_rounded, size: 16),
          label: const Text('Demande envoyée'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            textStyle: AppTextStyles.bodySmall,
          ),
        );

      case RelationState.requestReceived:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.error),
              onPressed: () => _respond(false),
            ),
            ElevatedButton(
              onPressed: () => _respond(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Accepter'),
            ),
          ],
        );

      case RelationState.retryLater:
        final dateStr = widget.nextRetryAt != null ? DateFormat('dd/MM').format(widget.nextRetryAt!) : '';
        return Tooltip(
          message: 'Disponible le $dateStr',
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.schedule_rounded, size: 16),
            label: Text('Demande envoyée ($dateStr)'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: AppTextStyles.bodySmall,
            ),
          ),
        );

      case RelationState.blockedByMe:
        return OutlinedButton(
          onPressed: _unblock,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Débloquer'),
        );

      case RelationState.none:
      default:
        return ElevatedButton.icon(
          onPressed: _sendRequest,
          icon: const Icon(Icons.person_add_rounded, size: 16),
          label: const Text('Ajouter'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.bold),
          ),
        );
    }
  }
}
