/// Domain model for group conversations.
///
/// Supabase remains authoritative for membership, activation, ownership and access.
enum GroupConversationStatus { pendingMembers, active, closed }
enum GroupMemberRole { owner, creator, administrator, member }
enum GroupMembershipStatus { active, left, removed }
enum GroupInvitationStatus { pending, accepted, refused, revoked, expired }

class GroupConversation {
  const GroupConversation({
    required this.id, required this.name, required this.creatorId,
    required this.status, required this.everActivated,
    required this.activeMemberCount, required this.createdAt,
    this.avatarUrl, this.updatedAt,
  });
  final String id;
  final String name;
  final String creatorId;
  final String? avatarUrl;
  final GroupConversationStatus status;
  /// One-way latch: never reset after first activation.
  final bool everActivated;
  final int activeMemberCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get canSendMessages => status == GroupConversationStatus.active &&
      everActivated && activeMemberCount > 0;
  bool get isClosed => status == GroupConversationStatus.closed || activeMemberCount == 0;

  factory GroupConversation.fromJson(Map<String, dynamic> json) {
    final status = switch ('${json['status'] ?? 'pending_members'}') {
      'active' => GroupConversationStatus.active,
      'closed' => GroupConversationStatus.closed,
      _ => GroupConversationStatus.pendingMembers,
    };
    return GroupConversation(
      id: '${json['id']}', name: '${json['name'] ?? ''}',
      creatorId: '${json['creator_id'] ?? ''}',
      avatarUrl: json['avatar_url'] as String?,
      status: status, everActivated: json['ever_activated'] == true,
      activeMemberCount: (json['active_member_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse('${json['created_at']}').toUtc(),
      updatedAt: json['updated_at'] == null ? null : DateTime.parse('${json['updated_at']}').toUtc(),
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.userId, required this.role, required this.status,
    required this.joinedAt, this.displayName, this.avatarUrl,
  });
  final String userId;
  final GroupMemberRole role;
  final GroupMembershipStatus status;
  final DateTime? joinedAt;
  final String? displayName;
  final String? avatarUrl;
  bool get isActive => status == GroupMembershipStatus.active;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final role = switch ('${json['role'] ?? 'member'}') {
      'owner' => GroupMemberRole.owner,
      'creator' => GroupMemberRole.creator,
      'administrator' || 'admin' => GroupMemberRole.administrator,
      _ => GroupMemberRole.member,
    };
    final status = switch ('${json['status'] ?? 'active'}') {
      'left' => GroupMembershipStatus.left,
      'removed' => GroupMembershipStatus.removed,
      _ => GroupMembershipStatus.active,
    };
    return GroupMember(
      userId: '${json['user_id'] ?? ''}', role: role, status: status,
      joinedAt: json['joined_at'] == null ? null : DateTime.parse('${json['joined_at']}').toUtc(),
      displayName: json['display_name'] as String?, avatarUrl: json['avatar_url'] as String?,
    );
  }
}

/// Client-side mirror for display/tests only; the database performs the real transfer.
String? selectNextGroupOwnerId(Iterable<GroupMember> members) {
  final eligible = members.where((member) =>
      member.isActive &&
      (member.role == GroupMemberRole.administrator ||
       member.role == GroupMemberRole.member)).toList();
  eligible.sort((a, b) {
    final rolePriority = (a.role == GroupMemberRole.administrator ? 0 : 1)
        .compareTo(b.role == GroupMemberRole.administrator ? 0 : 1);
    if (rolePriority != 0) return rolePriority;
    final aJoined = a.joinedAt;
    final bJoined = b.joinedAt;
    if (aJoined == null && bJoined != null) return 1;
    if (aJoined != null && bJoined == null) return -1;
    if (aJoined != null && bJoined != null) {
      final byDate = aJoined.compareTo(bJoined);
      if (byDate != 0) return byDate;
    }
    return a.userId.compareTo(b.userId);
  });
  return eligible.isEmpty ? null : eligible.first.userId;
}

class GroupInvitation {
  const GroupInvitation({
    required this.id, required this.groupId, required this.invitedUserId,
    required this.invitedBy, required this.status, required this.createdAt,
    this.respondedAt,
  });
  final String id;
  final String groupId;
  final String invitedUserId;
  final String invitedBy;
  final GroupInvitationStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;
  bool get isPending => status == GroupInvitationStatus.pending;

  factory GroupInvitation.fromJson(Map<String, dynamic> json) {
    final status = switch ('${json['status'] ?? 'pending'}') {
      'accepted' => GroupInvitationStatus.accepted,
      'refused' => GroupInvitationStatus.refused,
      'revoked' => GroupInvitationStatus.revoked,
      'expired' => GroupInvitationStatus.expired,
      _ => GroupInvitationStatus.pending,
    };
    return GroupInvitation(
      id: '${json['id']}', groupId: '${json['group_id']}',
      invitedUserId: '${json['invited_user_id']}', invitedBy: '${json['invited_by']}',
      status: status, createdAt: DateTime.parse('${json['created_at']}').toUtc(),
      respondedAt: json['responded_at'] == null ? null : DateTime.parse('${json['responded_at']}').toUtc(),
    );
  }
}
