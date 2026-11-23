-- Rank social-discovery onboarding suggestions using platform-wide follower counts
-- and the current public profile certification level.
create or replace function public.get_social_discovery_suggested_profiles(
  p_limit integer default 20
)
returns table (
  user_id uuid,
  username text,
  first_name text,
  last_name text,
  photo_url text,
  account_status text,
  deleted_at timestamptz,
  followers_count bigint,
  certification_level text,
  is_certified boolean
)
language sql
stable
security invoker
set search_path = ''
as $function$
  with eligible_profiles as (
    select
      up.user_id,
      up.username,
      up.first_name,
      up.last_name,
      up.photo_url,
      up.account_status::text as account_status,
      up.deleted_at,
      coalesce(
        (to_jsonb(public.get_follow_stats(up.user_id))->>'followers_count')::bigint,
        0
      ) as followers_count,
      coalesce(
        public.get_public_profile_certification_level(up.user_id),
        'none'
      ) as certification_level
    from public.user_profiles up
    where auth.uid() is not null
      and up.user_id <> auth.uid()
      and lower(coalesce(up.account_status::text, 'active')) = 'active'
      and up.deleted_at is null
  )
  select
    ep.user_id,
    ep.username,
    ep.first_name,
    ep.last_name,
    ep.photo_url,
    ep.account_status,
    ep.deleted_at,
    ep.followers_count,
    ep.certification_level,
    (lower(ep.certification_level) <> 'none') as is_certified
  from eligible_profiles ep
  order by
    (lower(ep.certification_level) <> 'none') desc,
    ep.followers_count desc,
    case lower(ep.certification_level)
      when 'premium' then 3
      when 'pro' then 2
      when 'basique' then 1
      else 0
    end desc,
    ep.username asc nulls last
  limit greatest(1, least(coalesce(p_limit, 20), 100));
$function$;

revoke all on function public.get_social_discovery_suggested_profiles(integer) from public, anon;
grant execute on function public.get_social_discovery_suggested_profiles(integer) to authenticated;
