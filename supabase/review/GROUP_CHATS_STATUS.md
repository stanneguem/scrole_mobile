# Group chats — implementation status

Branch: `feature/group-chats`

## Added on this branch
- Group domain models and lifecycle/owner-succession unit tests.
- Group-specific Supabase client service at `lib/modules/module_discussion_direct/externe/services/supabase_group_messaging_service.dart`.
- Live-schema audit and media-storage security findings.
- Review-only SQL drafts:
  - `group_chats_foundation_draft.sql`
  - `group_chats_rpc_migration_draft.sql`

## Not production-ready yet
The SQL files are drafts, not migrations to apply. Before release:
1. Reconcile all RPCs against the exact profile schema, notification conventions and current database constraints.
2. Add a reviewed private storage bucket and policies for group attachments. The current `chat-media` bucket is public and is unsuitable for protected group files.
3. Add safe Realtime SELECT policies or a tested broadcast design for active members; the group Flutter service does not yet subscribe to group messages.
4. Add invitation notifications and revocation, message edit/delete, delivery/read receipt retrieval, and tests for member removal/rejoin/history privacy.
5. Build and connect group list, create group, invitation inbox, conversation, member management and personal wallpaper screens.
6. Run `dart format`, `flutter analyze`, `flutter test test/modules/module_discussion_direct/group_conversation_test.dart`, and SQL tests against a disposable local Supabase.
7. Review the complete final migration and obtain explicit approval before applying it to the remote project.

## Important behavior captured in the drafts
- Group sending is blocked until the third member accepts.
- After first activation, the group remains usable with two or one active members; zero active members closes it.
- Leaving owner succession: oldest active administrator first; otherwise oldest active ordinary member.
- Group wallpaper preferences are per-user.
- Client checks are convenience only; server authorization is required for every protected operation.
