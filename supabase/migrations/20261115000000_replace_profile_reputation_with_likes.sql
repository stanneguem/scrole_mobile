create or replace function public.get_profile_engagement_stats(p_user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_me uuid := auth.uid();
  v_target uuid;
  v_visibility text := 'public';
  v_status text;
  v_deleted_at timestamptz;
  v_connected boolean := false;
  v_following boolean := false;
  v_blocked boolean := false;
  v_posts integer := 0;
  v_likes integer := 0;
  v_dislikes integer := 0;
  v_attended integer := 0;
  v_organized integer := 0;
  v_friends integer := 0;
  v_comments integer := 0;
  v_reactions_given integer := 0;
  v_messages integer := 0;
  v_interactions integer := 0;
  v_certified boolean := false;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  v_target := coalesce(p_user_id, v_me);

  select lower(coalesce(up.account_status, 'active')), up.deleted_at
    into v_status, v_deleted_at
  from public.user_profiles up where up.user_id = v_target;

  if not found then raise exception 'profile_not_found'; end if;
  if v_deleted_at is not null or v_status = 'deleted' then raise exception 'profile_deleted'; end if;
  if v_status = 'suspended' then raise exception 'profile_suspended'; end if;
  if v_status in ('banned', 'ban', 'banni', 'bannie') then raise exception 'profile_banned'; end if;
  if v_status <> 'active' then raise exception 'profile_unavailable'; end if;

  if v_target <> v_me then
    select lower(coalesce(upv.profile_visibility, 'public')) into v_visibility
    from public.user_privacy upv where upv.user_id = v_target;
    v_visibility := coalesce(v_visibility, 'public');

    select exists (
      select 1 from public.blocage_utilisateur b
      where b.statut
        and ((b.bloqueur_id = v_me and b.bloque_id = v_target)
          or (b.bloqueur_id = v_target and b.bloque_id = v_me))
        and (b.bloque_jusquau is null or b.bloque_jusquau > now())
    ) into v_blocked;
    if v_blocked then raise exception 'profile_blocked'; end if;

    select exists (
      select 1 from public.friendships f
      where f.user_a_id = least(v_me, v_target)
        and f.user_b_id = greatest(v_me, v_target)
    ) into v_connected;
    select exists (
      select 1 from public.user_follows f
      where f.follower_id = v_me and f.followed_id = v_target
    ) into v_following;

    if v_visibility in ('private', 'prive', 'privé')
       and not v_connected and not v_following then
      raise exception 'profile_private';
    end if;
  end if;

  select count(*)::integer into v_posts
  from public.community_posts p
  where p.author_id = v_target and p.status = 'active' and p.deleted_at is null
    and not exists (select 1 from public.post_hides h where h.post_id = p.id and h.user_id = v_me);

  select count(*) filter (where r.reaction = 'like')::integer,
         count(*) filter (where r.reaction = 'dislike')::integer
    into v_likes, v_dislikes
  from public.community_post_reactions r
  join public.community_posts p on p.id = r.post_id
  where p.author_id = v_target and p.status = 'active' and p.deleted_at is null;

  select count(distinct ec.event_id)::integer into v_attended
  from public.event_checkins ec join public.events e on e.id = ec.event_id
  where ec.user_id = v_target and lower(ec.status) = 'valid'
    and e.status = 'active' and coalesce(e.ends_at, e.starts_at) < now();

  select count(distinct e.id)::integer into v_organized
  from public.events e
  where e.status = 'active' and coalesce(e.ends_at, e.starts_at) < now()
    and (e.creator_id = v_target or exists (
      select 1 from public.event_co_creators cc
      where cc.event_id = e.id and cc.user_id = v_target
        and lower(cc.status) in ('accepted', 'acceptee', 'active')
    ));

  select count(*)::integer into v_friends
  from public.friendships f
  join public.user_profiles friend
    on friend.user_id = case when f.user_a_id = v_target then f.user_b_id else f.user_a_id end
   and friend.account_status = 'active' and friend.deleted_at is null
  where f.user_a_id = v_target or f.user_b_id = v_target;

  select count(*)::integer into v_comments
  from public.community_post_comments c join public.community_posts p on p.id = c.post_id
  where c.author_id = v_target and p.author_id <> v_target
    and p.status = 'active' and p.deleted_at is null;

  select count(*)::integer into v_reactions_given
  from public.community_post_reactions r join public.community_posts p on p.id = r.post_id
  where r.user_id = v_target and p.author_id <> v_target
    and p.status = 'active' and p.deleted_at is null;

  select count(*)::integer into v_messages
  from public.direct_messages dm where dm.sender_id = v_target and dm.deleted_at is null;

  v_interactions := coalesce(v_comments, 0) + coalesce(v_reactions_given, 0) + coalesce(v_messages, 0);

  select coalesce(up.is_verified, false) or exists (
    select 1 from public.user_certifications uc
    where uc.user_id = v_target and uc.status::text = 'active'
      and uc.issued_at <= now() and (uc.expires_at is null or uc.expires_at >= now())
  ) into v_certified
  from public.user_profiles up where up.user_id = v_target;

  return jsonb_build_object(
    'user_id', v_target,
    'posts_count', v_posts,
    'total_likes_received', v_likes,
    'total_dislikes_received', v_dislikes,
    'events_attended_count', v_attended,
    'events_organized_count', v_organized,
    'friends_count', v_friends,
    'interactions_count', v_interactions,
    'is_certified', v_certified
  );
end;
$function$;

create or replace function public.get_external_profile(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_me uuid := auth.uid();
  v_account_status text;
  v_deleted_at timestamptz;
  v_exists boolean := false;
  v_profile jsonb;
  v_total_likes bigint := 0;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if p_user_id is null or p_user_id = v_me then raise exception 'invalid_profile_user'; end if;

  select lower(coalesce(up.account_status::text, 'active')), up.deleted_at, true
    into v_account_status, v_deleted_at, v_exists
  from public.user_profiles up where up.user_id = p_user_id;

  if not v_exists then raise exception 'profile_not_found'; end if;
  if v_deleted_at is not null or v_account_status = 'deleted' then raise exception 'profile_deleted'; end if;
  if v_account_status = 'suspended' then raise exception 'profile_suspended'; end if;
  if v_account_status in ('banned', 'ban', 'banni', 'bannie') then raise exception 'profile_banned'; end if;

  v_profile := public.get_external_profile_legacy(p_user_id);

  if coalesce(v_profile ->> 'is_private', 'false') <> 'true'
     and coalesce(v_profile ->> 'is_blocked', 'false') <> 'true' then
    select count(*)::bigint into v_total_likes
    from public.community_post_reactions r
    join public.community_posts p on p.id = r.post_id
    where p.author_id = p_user_id and p.status = 'active'
      and p.deleted_at is null and r.reaction = 'like';

    v_profile := jsonb_set(v_profile, '{total_likes_received}', to_jsonb(v_total_likes), true);
  end if;

  return v_profile;
end;
$function$;
