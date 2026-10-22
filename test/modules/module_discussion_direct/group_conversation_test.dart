import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_discussion_direct/centre/models/group_conversation.dart';

void main() {
  GroupConversation group({GroupConversationStatus status = GroupConversationStatus.pendingMembers, bool everActivated = false, int members = 1}) => GroupConversation(
    id: 'g1', name: 'Test', creatorId: 'u1', status: status,
    everActivated: everActivated, activeMemberCount: members,
    createdAt: DateTime.utc(2026, 1, 1),
  );

  test('pending groups with one or two members cannot send', () {
    expect(group(members: 1).canSendMessages, isFalse);
    expect(group(members: 2).canSendMessages, isFalse);
  });
  test('third member activation enables messages', () {
    expect(group(status: GroupConversationStatus.active, everActivated: true, members: 3).canSendMessages, isTrue);
  });
  test('activated groups continue with two or one member', () {
    expect(group(status: GroupConversationStatus.active, everActivated: true, members: 2).canSendMessages, isTrue);
    expect(group(status: GroupConversationStatus.active, everActivated: true, members: 1).canSendMessages, isTrue);
  });
  test('zero members or closed status disables messaging', () {
    expect(group(status: GroupConversationStatus.closed, everActivated: true, members: 0).canSendMessages, isFalse);
    expect(group(status: GroupConversationStatus.active, everActivated: true, members: 0).canSendMessages, isFalse);
  });
  test('pending invitation remains separate from membership', () {
    final invite = GroupInvitation.fromJson({'id':'i1','group_id':'g1','invited_user_id':'u2','invited_by':'u1','status':'pending','created_at':'2026-01-01T00:00:00Z'});
    expect(invite.isPending, isTrue);
    expect(invite.status, GroupInvitationStatus.pending);
  });
}
