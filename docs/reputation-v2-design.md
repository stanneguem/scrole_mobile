# Scrole Reputation V2 — design and rollout

## Why this is a foundation, not a score cutover

The live `public.user_statistics` table currently exposes `points`, `level`, `posts_count`, and `communities_count`. A read-only scan of public routine definitions found references to that table in the admin user detail function, but did not identify the definitive points-awarding routine. Therefore V2 must not silently overwrite existing points or change level thresholds until the awarding triggers, RPCs, and client-side display/calculation paths are fully traced.

## Principles

- Reputation reflects sustained, constructive participation and community recognition, not raw volume or paid status.
- Keep a global score and a separate score for each community. Niche participation can be highly respected locally without requiring a massive global audience.
- Treat reputation as a useful signal, never proof that a person's claim is true.
- Every award/reversal is auditable and idempotent; clients cannot directly award points.
- Reward distinct, meaningful interactions; penalize spam/manipulation; apply diminishing returns and daily caps.
- Inactivity decay is gradual and starts only after a grace period. It must be applied deterministically and idempotently, not by repeatedly subtracting points on every profile view.

## Initial candidate weights (admin configurable)

| Event | Candidate points | Guardrail |
| --- | ---: | --- |
| Meaningful original post | +2 | First 3/day eligible; quality/anti-spam checks |
| Constructive comment | +1 | First 5/day eligible; minimum content quality checks |
| Comment receives positive reaction | +1 | Per distinct reactor; cap per comment and per day |
| Post receives positive reaction | +1 | Distinct non-author reactors; cap per day |
| Helpful reply marked by recipient/community process | +3 | One award per source event |
| Meaningful activity day | +1 | Once/day; streak bonus grows slowly and caps |
| Spam/moderation-confirmed abuse | negative | Reversal references source ledger entry; moderation-only |

These are starting defaults for review, not hard-coded product decisions. Follows, friends, raw membership counts, views, self-reactions, repeated reactions, and paid certification should not directly grant reputation.

## Anti-abuse

- Enforce unique ledger identity for each user, scope, event, and source.
- No self-reactions; only count eligible reactions from distinct accounts.
- Apply daily caps and diminishing returns by action type.
- Do not reward repeated edits, repost loops, duplicate comments, or repeated toggling of a reaction.
- Detect reciprocal/repeated small-group reaction rings before granting high-value awards; do not punish legitimate niche communities solely for being small.
- Reverse points when the source action is deleted or invalidated, with a compensating ledger entry instead of deleting history.

## Decay

- Start after 30 days without meaningful activity (configurable).
- Reduce only a small fraction of the inactive score per week (candidate 1%, capped per week), with a configurable floor and no negative total.
- Apply decay as a dated ledger event with a unique period key so retries cannot double-charge.
- Community reputation decays independently from global reputation based on meaningful activity in that community.
- Preserve earned history; do not decay solely because a user is on vacation or cannot access the service.

## Levels

Levels should use a slowly increasing threshold curve rather than one point per action. Level is derived from current score and configurable thresholds; it is not an independent award source. Avoid resetting existing user levels until historical scores have been reconciled.

## Community reputation

Community-scoped ledger entries require a verified community context (post/comment/reaction belongs to that community). Show the community score in that community's member/profile surfaces; show global score elsewhere. Avoid adding scores from arbitrary communities together in a way that allows joining many inactive communities to inflate the global score.

## Admin controls and security

- Manage rule weights, daily caps, grace period, decay rate, and level thresholds through a platform-admin-only interface backed by a server-verified admin check.
- Client roles get read-only access to enabled rules and their own score/ledger. No client insert/update/delete policies for ledger or scoring rules.
- Use trusted SQL functions/triggers or server-side code for awards. Never accept arbitrary point deltas from the mobile client.
- Log rule version and decision metadata for auditability.

## Rollout checklist

1. Inventory all routines/triggers and Flutter/admin code that writes or reads points and levels.
2. Establish a baseline and simulate V2 scores on production-shaped data without mutating live scores.
3. Add ledger and community-score storage (migration provided separately).
4. Add server-side idempotent award/reversal functions and tests.
5. Add admin-configurable rules with strict admin authorization.
6. Backfill/simulate, compare results, and review with product owner.
7. Enable V2 behind a feature flag; migrate profile/comment/community UI to the correct scope.
8. Only after validation, decide how legacy points and levels are mapped.

## Current migration safety

`20261022090000_reputation_v2_foundation.sql` creates only new tables/indexes/policies and does not change `user_statistics`, award points, or alter existing data. Review it before applying to any environment.
