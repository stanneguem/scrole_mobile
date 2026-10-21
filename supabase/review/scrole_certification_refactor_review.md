# Scrole certification refactor — review package

## Scope
This is a prepared, additive migration for review. It has **not** been applied to Supabase. It does not alter `user_certifications`, existing event/community tables, or existing RPC signatures.

## Objects added
- `scrole_subscriptions`: Pro/Premium subscription record and validity.
- `event_certifications`, `community_certifications`: independent entity certification entitlements, provenance, status, subscription link and validity.
- `scrole_certification_audit`: audit trail.
- `scrole_subscription_quotas(text)`: quota lookup (Pro 1 event + 1 community; Premium 4 + 4).
- `scrole_change_subscription_plan(uuid,text,uuid,uuid)`: atomic plan change with explicit event/community selection for a downgrade to Pro.
- `scrole_suspend_expired_subscription_certifications()`: trusted-server lifecycle operation for expired subscriptions.

## Important assumptions / review blockers
1. The live schema audit did not find a dedicated Pro/Premium subscription table. This migration introduces a minimal registry but does not integrate a payment provider/webhook. The billing system must write and renew these rows before production use.
2. Subscription-included certifications must be created by a future trusted server RPC; direct client writes are revoked. No grant/renewal RPC is introduced in this first draft because payment/renewal source contracts have not yet been audited.
3. `scrole_change_subscription_plan` is a draft for a downgrade to Pro and currently expects the subscription to be active. It retains exactly one selected included event and community, or none if NULL is passed. It suspends other included certifications, not purchased/admin-granted ones.
4. The expiration function is not granted to clients. A trusted scheduler/backend must invoke it. The migration does not create a cron job or schedule it.
5. Event/community owner selection currently uses `events.creator_id` and `communities.creator_id`. Ownership transfer semantics must be reviewed before finalizing how certification entitlements follow a transferred entity.
6. Purchased certification validity needs a confirmed business rule. `valid_until` is stored but no automatic expiration worker for purchased certifications is included yet.
7. Profile certification remains independent in existing `user_certifications`. The profile badge tier is not migrated here.
8. The existing migration history in Supabase has 379 entries, while the repo only has a small set of current migration files. Do not replay historical migrations; reconcile schema state before applying this file.

## Pre-apply test plan
Run on a disposable Supabase branch/project first:
- Apply the migration twice; second application should succeed without duplicate table/index/policy failures.
- Anonymous role cannot read or execute privileged RPCs.
- Authenticated user can read only their subscription and owned entity certifications; cannot insert/update/delete certification rows directly.
- Owner cannot change another user's subscription.
- Pro downgrade requires selected IDs to be included certifications belonging to the same subscription and entities owned by the caller.
- Downgrade suspends all other included certifications, leaves purchased/admin-granted certifications unchanged, and records audit details.
- Expiration worker marks ended active subscriptions expired and suspends only their active subscription-included event/community certifications.
- Expiration never deletes events/communities and does not modify profile certifications.
- Renewal flow (not implemented in this draft) must be tested after a dedicated renewal/grant RPC is added; suspended entitlements must reactivate without duplicates and must obey current quotas.
- Test concurrent downgrade/renewal calls and verify transaction/locking behavior.
- Verify current Flutter RPC callers remain compatible; no existing RPC signature is changed by this draft.

## Known limitation before production
This is a foundation, not a complete production billing integration. Before applying, review and likely add: a renewal/reactivation RPC, a trusted grant-included-certification RPC, a plan-change path for Pro -> Premium, subscription provider/webhook reconciliation, and entity-transfer rules. Existing event-creation, calendar horizon, staff/ticket/sponsor and guest-invitation rules are outside this migration.
