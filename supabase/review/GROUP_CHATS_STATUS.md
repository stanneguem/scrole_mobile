# Group chats — implementation status

Branch: `feature/group-chats`

## Added on this branch
- Group domain models and tests for activation and owner succession.
- Group-specific Supabase service at `lib/modules/module_discussion_direct/externe/services/supabase_group_messaging_service.dart`.
- Initial UI at `lib/modules/module_discussion_direct/interne/pages/group_conversations_screen.dart`: group list, create group, invitation inbox, basic chat composer, Realtime refresh, member list, invite by user ID, role changes, member removal and leave group.
- Messaging binding registration for the group service.
- Read-only live schema audit, including confirmation that `public.user_profiles` is the profile table and inspection of notification columns.
- Review-only SQL drafts:
  - `group_chats_foundation_draft.sql`
  - `group_chats_rpc_migration_draft.sql`
  - `group_chat_rls_realtime_draft.sql`
  - `group_chat_private_storage_draft.sql`
  - `group_chat_notifications_receipts_draft.sql`

## Important release caveat
This is not production-ready. The SQL files remain review drafts and have not been applied. Some integrations are still incomplete, and the client code has not been compiled or tested in this environment.

## Remaining before release
1. Review/fix the SQL drafts as a single ordered migration, including edge cases and consistency with the exact deployed schema.
2. Implement message attachment upload/download using `group-chat-media`; do not use public `chat-media` for group files.
3. Complete delivery/read receipt UI and notification navigation.
4. Connect the group screen into the app's existing discussion navigation; the screen currently exists as a standalone route target.
5. Add tests for RPC authorization, concurrent acceptance/activation, owner succession, member removal, rejoin and storage access.
6. Run `dart format`, `flutter analyze`, `flutter test test/modules/module_discussion_direct/group_conversation_test.dart`, and SQL tests against a disposable local Supabase.
7. Review the complete final migration and obtain explicit approval before applying it to the remote project.

## Core behavior captured
- Sending blocked until the third member accepts.
- After first activation, group remains usable with two or one active members; zero active members closes it.
- On owner departure: oldest active administrator succeeds; if none, oldest active ordinary member.
- Group wallpaper preferences are per-user.
- Membership checks must be enforced server-side for messages, Realtime and media.
