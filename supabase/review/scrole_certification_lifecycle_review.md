# Scrole certification lifecycle and feature gates — review

This migration follows the two previously applied migrations. It does not delete existing rows or alter the existing profile-certification table.

## Additional behavior
- Event horizon/duration limits use event-level certification only. A certified profile or community does not automatically certify an event.
- Non-certified events cannot accept new or updated guest invitations, sponsor invitations or ticket rows.
- Event statistics RPC requires an active event-level certification.
- Premium -> Pro has an array-based RPC so selected active certifications follow the quotas currently stored in `scrole_quota_settings`.
- A trusted billing backend can call `scrole_renew_subscription` after confirming a successful payment; it reactivates only selected included certifications, suspends the rest and updates their validity without creating duplicates.

## Required before production
- Integrate the renewal RPC into the real payment provider/webhook and test using the service role only.
- Build the UI for selecting several entitlements if administration increases Pro/Premium quotas above the current defaults.
- Implement an included-certification grant RPC once subscription provisioning/payment flow is wired. The renewal RPC reactivates existing entitlements; it intentionally does not create a certification for a brand-new entity.
- Confirm whether event statistics should be available to event co-creators/staff as well as the owner. The underlying private statistics function keeps its existing authorization check.
- Verify existing ticket/invitation records: this trigger blocks inserts/updates, not read access to historical rows.
