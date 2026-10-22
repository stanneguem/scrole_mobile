# Group chats — implementation status

Branch: `feature/group-chats`

## Implemented in branch
- Group models and lifecycle/owner succession tests.
- Supabase group service: create/list groups, invitations, member roles/removal/leave, messages, read marker, wallpaper preference RPCs, private media upload and signed URL request.
- Standalone Flutter UI: group list, create group, invitations accept/refuse with group/inviter labels, message screen, Realtime message refresh, image attachment picker/upload, per-user wallpaper preference, member list and management, leave confirmation.
- Groups entry icon on the existing direct-message inbox.
- Read-only inspection of the deployed profile and notification table schemas.
- SQL review drafts for foundation, group RPCs, RLS/Realtime, private media, and invitation notifications/read receipts.

## Critical deployment caveat
These changes are not verified production-ready. The Flutter project was not available in a local build environment during this work, so `dart format`, `flutter analyze`, and Flutter tests were not run. The SQL drafts have not been applied or validated against a disposable Supabase database. No remote database schema was changed.

## Required final verification
1. Consolidate the review SQL into ordered migration(s), run on disposable Supabase, and fix all failures.
2. Verify every SECURITY DEFINER function's owner, search_path, execute grants, row locks, and concurrent invitation/owner-succession cases.
3. Verify RLS denies removed/left users for group messages and Storage signed URL creation; test two active members and a removed member.
4. Wire attachment signed-URL display, delivery/read receipt indicators, and notification deep links into the UI.
5. Add a user-search/contact picker instead of requiring invitees to enter a raw user UUID.
6. Integrate invitation revocation and admin restrictions; verify only owner can grant/revoke administrator role and no one can remove the owner.
7. Connect the group screen into named app routing if desired; current inbox entry opens the screen directly.
8. Run formatter, analyzer, unit/widget tests and integration tests.
9. Obtain explicit approval before applying final migration to the remote project.

## Contract
- Messaging is disabled until the third member accepts.
- Once activated, the group remains usable with two or one active members; zero active members closes it.
- Owner leaves: oldest active administrator succeeds; if none, oldest active ordinary member.
- Invitation acceptance alone creates membership; sending an invitation does not.
- Wallpapers are per user.
- Server-side membership checks must protect all messages, Realtime and private media.
