-- Checklist / smoke tests for scrole_admin_managed_quotas.
-- Run only on a disposable Supabase project after applying the migrations in order.

select quota_key, value, category, min_value, max_value
from public.admin_get_scrole_quotas()
order by category, quota_key;

select public.scrole_subscription_quotas('pro') as pro,
       public.scrole_subscription_quotas('premium') as premium;

-- Through an authenticated administrator session:
-- select public.admin_update_scrole_quota('noncert_agenda_max_events', 3);
-- select * from public.admin_get_scrole_quotas()
-- where quota_key = 'noncert_agenda_max_events';
-- Expected: value=3 and a quota_updated row in public.scrole_certification_audit.
-- Restore the original value after the test.

-- Functional tests with test fixtures:
-- 1. Uncertified profile cannot add a third distinct event to event_calendar.
-- 2. Uncertified profile cannot add an event beyond the configured agenda horizon.
-- 3. A profile with active user_certifications can add more agenda events.
-- 4. Uncertified event cannot exceed configured duration/horizon.
-- 5. Uncertified event cannot exceed agenda audience / cofounder / staff limits.
-- 6. Active event/community certification exempts the event from applicable event limits.
-- 7. Unauthenticated users and authenticated non-admin users cannot read/update quota table.
-- 8. Authenticated user without certifications.manage cannot call quota mutation RPC.
