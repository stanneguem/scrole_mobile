-- Complete the community-report lifecycle:
-- - deduplicate by the real community scope (never reuse a report from another community)
-- - expose escalated community member reports to platform admins
-- - let platform admins resolve escalated user reports
-- - keep all resolution updates scoped to the same community and target.
-- Existing scheduler runs public.escalate_stale_community_reports() hourly; retain its 48-hour threshold.

create index if not exists idx_signalement_community_escalation
  on public.signalement (escalated_at, created_at desc)
  where community_id is not null and status = 'en_attente';

create or replace function public.report_content(
  p_target_type text,
  p_target_id uuid,
  p_reason_id uuid,
  p_description text default null
)
returns public.signalement
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_type public.user_activity_target_type;
  v_community_id uuid;
  v_owner uuid;
  v_allow boolean;
  v_visible boolean := false;
  v_post_author uuid;
  v_audience text;
  v_pstatus text;
  v_row public.signalement;
  v_desc text := nullif(btrim(p_description), '');
  v_story public.stories;
  v_report_community_id uuid;
begin
  if v_uid is null then raise exception 'Utilisateur non authentifié'; end if;
  if p_target_type is null or p_target_type not in ('post', 'comment', 'story', 'community') then
    raise exception 'Type de signalement invalide';
  end if;
  v_type := p_target_type::public.user_activity_target_type;
  if not exists (select 1 from public.signalement_raison r where r.id = p_reason_id and r.est_actif) then
    raise exception 'Motif de signalement invalide';
  end if;
  if char_length(coalesce(v_desc, '')) > 1000 then raise exception 'Description trop longue (1000 caractères maximum)'; end if;
  if (select count(*) from public.signalement s where s.reporter_id = v_uid and s.created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Trop de signalements envoyés, réessayez plus tard';
  end if;

  if p_target_type = 'post' then
    select cp.community_id, cp.author_id, cp.audience, cp.status
      into v_community_id, v_owner, v_audience, v_pstatus
    from public.community_posts cp where cp.id = p_target_id;
    if found and v_pstatus = 'active' then
      v_visible := public.can_view_post_row(v_community_id, v_owner, v_audience)
        and not private.users_blocked(v_uid, v_owner);
    end if;
  elsif p_target_type = 'comment' then
    select cp.community_id, c.author_id, cp.audience, cp.status, cp.author_id
      into v_community_id, v_owner, v_audience, v_pstatus, v_post_author
    from public.community_post_comments c
    join public.community_posts cp on cp.id = c.post_id
    where c.id = p_target_id;
    if found and v_pstatus = 'active' then
      v_visible := public.can_view_post_row(v_community_id, v_post_author, v_audience)
        and not private.users_blocked(v_uid, v_owner);
    end if;
  elsif p_target_type = 'story' then
    select * into v_story from public.stories s
    where s.id = p_target_id and s.status = 'active' and s.expires_at > now();
    if found then
      v_owner := v_story.author_id;
      v_visible := public.can_view_story_row(v_story.author_id, v_story.audience)
        and not private.users_blocked(v_uid, v_story.author_id);
    end if;
  else
    select c.id, c.creator_id into v_community_id, v_owner
    from public.communities c where c.id = p_target_id and c.status = 'active';
    if found then v_visible := public.can_view_community(v_community_id); end if;
  end if;

  if not coalesce(v_visible, false) then raise exception 'Contenu introuvable'; end if;
  if v_owner = v_uid then raise exception 'Vous ne pouvez pas signaler votre propre contenu'; end if;

  if p_target_type in ('post', 'comment') then
    v_report_community_id := v_community_id;
    if v_community_id is not null then
      select s.allow_reports into v_allow
      from public.community_settings s where s.community_id = v_community_id;
      if coalesce(v_allow, true) = false then
        raise exception 'Les signalements sont désactivés dans cette communauté';
      end if;
    end if;
  else
    -- Stories and community/profile-level reports stay platform-scoped.
    v_report_community_id := null;
  end if;

  -- Crucial: a report from community A must never be returned for the same target
  -- when the current report belongs to community B (especially user targets).
  select * into v_row from public.signalement s
  where s.reporter_id = v_uid
    and s.target_type = v_type
    and s.target_id = p_target_id
    and s.community_id is not distinct from v_report_community_id
    and s.status in ('en_attente', 'en_cours')
  order by s.created_at desc
  limit 1;
  if found then return v_row; end if;

  insert into public.signalement
    (reporter_id, target_type, target_id, reason_id, description, community_id)
  values (v_uid, v_type, p_target_id, p_reason_id, v_desc, v_report_community_id)
  returning * into v_row;
  return v_row;
end;
$function$;

revoke all on function public.report_content(text, uuid, uuid, text) from public, anon;
grant execute on function public.report_content(text, uuid, uuid, text) to authenticated;

create or replace function public.get_community_reports(
  p_community_id uuid,
  p_status text default 'open',
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_statuses text[];
  v_items jsonb;
  v_has_more boolean;
begin
  if auth.uid() is null then raise exception 'Utilisateur non authentifié'; end if;
  if not public.is_community_staff(p_community_id) and not coalesce(public.is_staff(), false) then
    raise exception 'Action réservée aux administrateurs et modérateurs de la communauté';
  end if;
  v_statuses := case p_status
    when 'handled' then array['resolu', 'rejete']
    when 'all' then array['en_attente', 'en_cours', 'resolu', 'rejete']
    else array['en_attente', 'en_cours'] end;

  with rows as (
    select s.* from public.signalement s
    where s.community_id = p_community_id
      and s.target_type::text in ('post', 'comment')
      and s.status::text = any(v_statuses)
    order by s.created_at desc, s.id desc
    offset v_offset limit v_limit + 1
  ), numbered as (
    select r.*, row_number() over (order by r.created_at desc, r.id desc) as rn from rows r
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id, 'target_type', n.target_type::text, 'target_id', n.target_id,
      'status', n.status::text, 'created_at', n.created_at, 'description', n.description,
      'reason', (select jsonb_build_object('id', r.id, 'code', r.code, 'nom', r.nom)
                 from public.signalement_raison r where r.id = n.reason_id),
      'reporter', (select jsonb_build_object('user_id', up.user_id, 'username', up.username,
                     'first_name', up.first_name, 'last_name', up.last_name, 'photo_url', up.photo_url)
                   from public.user_profiles up where up.user_id = n.reporter_id),
      'reports_count', (select count(*) from public.signalement s2
                        where s2.community_id = n.community_id and s2.target_type = n.target_type
                          and s2.target_id = n.target_id
                          and s2.status in ('en_attente', 'en_cours')),
      'escalated', n.escalated_at is not null,
      'community_action', n.community_action, 'community_note', n.community_note,
      'community_reviewed_at', n.community_reviewed_at,
      'target', case n.target_type::text
        when 'post' then (select jsonb_build_object(
                            'id', cp.id, 'content', left(cp.content, 300), 'status', cp.status,
                            'photos_count', coalesce(cardinality(cp.photos), 0),
                            'photos', coalesce(to_jsonb(cp.photos), '[]'::jsonb),
                            'video_url', cp.video_url, 'has_video', cp.video_url is not null,
                            'author', jsonb_build_object('user_id', a.user_id, 'username', a.username,
                                'first_name', a.first_name, 'last_name', a.last_name, 'photo_url', a.photo_url))
                          from public.community_posts cp
                          left join public.user_profiles a on a.user_id = cp.author_id
                          where cp.id = n.target_id and cp.community_id = p_community_id)
        when 'comment' then (select jsonb_build_object(
                            'id', c.id, 'post_id', c.post_id, 'content', left(c.content, 300),
                            'author', jsonb_build_object('user_id', a.user_id, 'username', a.username,
                                'first_name', a.first_name, 'last_name', a.last_name, 'photo_url', a.photo_url))
                          from public.community_post_comments c
                          join public.community_posts cp on cp.id = c.post_id
                          left join public.user_profiles a on a.user_id = c.author_id
                          where c.id = n.target_id and cp.community_id = p_community_id)
      end
    ) order by n.created_at desc, n.id desc) filter (where n.rn <= v_limit), '[]'::jsonb),
    count(*) > v_limit
  into v_items, v_has_more
  from numbered n;
  return jsonb_build_object('items', v_items, 'has_more', coalesce(v_has_more, false));
end;
$function$;

revoke all on function public.get_community_reports(uuid, text, integer, integer) from public, anon;
grant execute on function public.get_community_reports(uuid, text, integer, integer) to authenticated;

-- Platform report listing and resolution already support external profile reports and
-- escalated community-member reports in the deployed schema. Do not replace those
-- functions here: preserve their external-profile workflow and permission checks.

-- Only the scheduled database job should trigger escalations; end users must not force early escalation.
revoke all on function public.escalate_stale_community_reports() from public, anon, authenticated;
