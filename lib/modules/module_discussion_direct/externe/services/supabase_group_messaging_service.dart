import 'package:supabase_flutter/supabase_flutter.dart';

import '../../centre/models/group_conversation.dart';

/// Supabase client for group conversations.
///
/// This service intentionally calls group-specific RPCs. It never routes group
/// messages through direct-message RPCs. The matching SQL RPC migration must be
/// installed before these methods are used by the application.
class SupabaseGroupMessagingService {
  SupabaseGroupMessagingService(this._client);
  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Authentication required');
    return id;
  }

  Future<GroupConversation> createGroup({
    required String name,
    List<String> inviteUserIds = const [],
    String? avatarUrl,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 80) {
      throw ArgumentError.value(name, 'name', 'Group name must contain 1–80 characters.');
    }
    final response = await _client.rpc('create_group_conversation', params: {
      'p_name': cleanName,
      'p_avatar_url': avatarUrl,
      'p_invited_user_ids': inviteUserIds.toSet().where((id) => id != _userId).toList(),
    });
    return _parseGroup(response);
  }

  Future<List<GroupConversation>> fetchMyGroups() async {
    final response = await _client.rpc('get_my_group_conversations');
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map((row) => GroupConversation.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<GroupMember>> fetchMembers(String groupId) async {
    _validateId(groupId, 'groupId');
    final response = await _client.rpc('get_group_members', params: {'p_group_id': groupId});
    if (response is! List) return const [];
    return response.whereType<Map>()
        .map((row) => GroupMember.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<GroupInvitation>> fetchPendingInvitations() async {
    final response = await _client.rpc('get_my_pending_group_invitations');
    if (response is! List) return const [];
    return response.whereType<Map>()
        .map((row) => GroupInvitation.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> inviteMembers(String groupId, List<String> userIds) async {
    _validateId(groupId, 'groupId');
    final uniqueIds = userIds.map((id) => id.trim()).where((id) => id.isNotEmpty && id != _userId).toSet().toList();
    if (uniqueIds.isEmpty) return;
    await _client.rpc('invite_group_members', params: {
      'p_group_id': groupId,
      'p_invited_user_ids': uniqueIds,
    });
  }

  Future<void> respondToInvitation(String invitationId, {required bool accept}) async {
    _validateId(invitationId, 'invitationId');
    await _client.rpc('respond_to_group_invitation', params: {
      'p_invitation_id': invitationId,
      'p_accept': accept,
    });
  }

  Future<void> leaveGroup(String groupId) async {
    _validateId(groupId, 'groupId');
    await _client.rpc('leave_group_conversation', params: {'p_group_id': groupId});
  }

  Future<void> removeMember(String groupId, String userId) async {
    _validateId(groupId, 'groupId');
    _validateId(userId, 'userId');
    await _client.rpc('remove_group_member', params: {
      'p_group_id': groupId,
      'p_user_id': userId,
    });
  }

  Future<void> changeMemberRole(String groupId, String userId, GroupMemberRole role) async {
    _validateId(groupId, 'groupId');
    _validateId(userId, 'userId');
    if (role == GroupMemberRole.creator) {
      throw ArgumentError('Creator is a lifecycle role and cannot be assigned by this action.');
    }
    await _client.rpc('change_group_member_role', params: {
      'p_group_id': groupId,
      'p_user_id': userId,
      'p_role': role == GroupMemberRole.administrator ? 'administrator' : 'member',
    });
  }

  Future<List<Map<String, dynamic>>> fetchMessages(
    String groupId, {
    int limit = 50,
    DateTime? before,
  }) async {
    _validateId(groupId, 'groupId');
    final response = await _client.rpc('get_group_messages', params: {
      'p_group_id': groupId,
      'p_limit': limit.clamp(1, 100),
      'p_before': before?.toUtc().toIso8601String(),
    });
    if (response is! List) return const [];
    return response.whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> sendMessage({
    required String groupId,
    String? text,
    List<String> mediaPaths = const [],
    String type = 'text',
    String? repliedToId,
  }) async {
    _validateId(groupId, 'groupId');
    if (type != 'system' && (text?.trim().isNotEmpty != true) && mediaPaths.isEmpty) {
      throw ArgumentError('A message must contain text or media.');
    }
    final response = await _client.rpc('insert_group_message', params: {
      'p_group_id': groupId,
      'p_text': text?.trim(),
      'p_type': type,
      'p_media_paths': mediaPaths,
      'p_replied_to_id': repliedToId,
    });
    if (response is Map) return Map<String, dynamic>.from(response);
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    throw StateError('The server did not return the inserted group message.');
  }

  Future<void> markRead(String groupId, {String? lastMessageId, DateTime? readAt}) async {
    _validateId(groupId, 'groupId');
    await _client.rpc('mark_group_conversation_read', params: {
      'p_group_id': groupId,
      'p_last_read_message_id': lastMessageId,
      'p_last_read_at': (readAt ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  Future<void> setPersonalWallpaper(String groupId, String wallpaperKey) async {
    _validateId(groupId, 'groupId');
    const allowed = {'none', 'fond1', 'fond2', 'fond3'};
    if (!allowed.contains(wallpaperKey)) throw ArgumentError.value(wallpaperKey, 'wallpaperKey');
    await _client.rpc('set_group_personal_wallpaper', params: {
      'p_group_id': groupId,
      'p_wallpaper_key': wallpaperKey,
    });
  }

  static GroupConversation _parseGroup(dynamic response) {
    if (response is Map) return GroupConversation.fromJson(Map<String, dynamic>.from(response));
    if (response is List && response.isNotEmpty && response.first is Map) {
      return GroupConversation.fromJson(Map<String, dynamic>.from(response.first as Map));
    }
    throw StateError('The server did not return a group conversation.');
  }

  static void _validateId(String value, String name) {
    if (value.trim().isEmpty) throw ArgumentError.value(value, name);
  }
}
