# Event feature-gate hardening

- Public mobile quota payload now includes `certified_event_horizon_months`.
- Guest invitations, sponsor invitations and tickets are gated for insert/update/delete when the event has no active event-level certification.
- Event financial, day-attendance and staff statistics now require an active event-level certification, while preserving existing ownership/staff authorization checks.
- The general interaction counter RPC remains available because it supports public event engagement UI and is not the owner statistics dashboard.

Test all event-management flows against disposable fixtures before relying on these gates in production.
