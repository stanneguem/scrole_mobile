# Group chats — implementation and validation status

Branch: `feature/group-chats`

## Supabase backend
- Applied migration: `20261022170631_group_chats` (registered by Supabase as `group_chats`).
- Added group conversation, member, invitation, message, receipt and per-member wallpaper tables.
- Added SECURITY DEFINER RPCs for group creation, listing, invitations, activation, member management, messaging, read markers, wallpaper and receipt queries.
- Added member-scoped RLS, Realtime publication membership and a private `group-chat-media` bucket with membership-based Storage policies.
- Added an invitation notification trigger using the existing `public.notifications` schema.
- The consolidated migration was executed inside a transaction and rolled back successfully as a syntax/schema preflight, then applied with the Supabase migration API. Post-apply queries confirmed the group tables and private bucket exist.

## Flutter frontend
- Added group list, creation, invitation inbox, chat, member-management and leave-group screens.
- Added entry point from the direct-message inbox and registered the group service in MessagingBinding.
- Added image attachment upload to the private bucket and signed-URL display for images.
- Added personal wallpaper selection and persisted preferences.
- Added message refresh and activation-state refresh through Realtime.
- Added CI workflow for formatting, analysis and lifecycle unit tests.

## Validation status
- SQL preflight: passed (migration ran inside a transaction and was rolled back without errors).
- Supabase post-apply: confirmed the six group tables and private `group-chat-media` bucket.
- Supabase security/performance advisors: reviewed. They report many pre-existing project-wide findings; this migration adds no destructive change to existing direct-message data.
- Flutter CI: pending GitHub Actions result. Do not claim Flutter compilation/tests passed until the workflow concludes successfully.
- End-to-end testing with real authenticated users and access-denial tests for removed members/media is still required.

## Core contract
- Messages are disabled until the third member accepts.
- Once activated, the group remains usable with two or one active members; zero active members closes it.
- Owner departure: oldest active administrator succeeds; otherwise oldest active ordinary member.
- Invitation acceptance is required before membership is created.
- Wallpapers are per user.
- Server-side membership checks protect message RPCs, Realtime and private media.

## Follow-up before production sign-off
1. Wait for and fix any GitHub Actions failure.
2. Add a real contact/user search instead of requiring invitees to enter UUIDs.
3. Finish notification deep-link handling and visible read/delivery indicators.
4. Run authenticated integration tests covering acceptance races, ownership succession, removed-member access, signed media URLs and rejoining.
