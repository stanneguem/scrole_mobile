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

create or replace function public.get_platform_reports(
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
  if not coalesce(public.is_admin_or_above(), false) then
    raise exception 'Action réservée aux administrateurs de la plateforme';
  end if;

  v_statuses := case p_status
    when 'handled' then array['resolu', 'rejete']
    when 'all' then array['en_attente', 'en_cours', 'resolu', 'rejete']
    else array['en_attente', 'en_cours'] end;

  with rows as (
    select s.* from public.signalement s
    where s.status::text = any(v_statuses)
      and s.target_type::text in ('post', 'comment', 'story', 'user')
      and (s.community_id is null or s.escalated_at is not null)
    order by s.created_at desc, s.id desc
    offset v_offset limit v_limit + 1
  ), numbered as (
    select r.*, row_number() over (order by r.created_at desc, r.id desc) as rn from rows r
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id,
      'target_type', n.target_type::text,
      'target_id', n.target_id,
      'status', n.status::text,
      'created_at', n.created_at,
      'description', n.description,
      'escalated', n.escalated_at is not null,
      'from_community', n.community_id is not null,
      'community_id', n.community_id,
      'community', (select jsonb_build_object('id', c.id, 'name', c.name)
                    from public.communities c where c.id = n.community_id),
      'reason', (select jsonb_build_object('id', r.id, 'code', r.code, 'nom', r.nom)
                 from public.signalement_raison r where r.id = n.reason_id),
      'reporter', (select jsonb_build_object('user_id', up.user_id, 'username', up.username,
                      'first_name', up.first_name, 'last_name', up.last_name, 'photo_url', up.photo_url)
                   from public.user_profiles up where up.user_id = n.reporter_id),
      'reports_count', (select count(*) from public.signalement s2
                        where s2.target_type = n.target_type and s2.target_id = n.target_id
                          and s2.community_id is not distinct from n.community_id
                          and s2.status in ('en_attente', 'en_cours')),
      'target', case n.target_type::text
        when 'post' then (select jsonb_build_object('id', cp.id, 'content', left(cp.content, 300),
                            'status', cp.status, 'community_id', cp.community_id,
                            'photos_count', coalesce(cardinality(cp.photos), 0),
                            'author', jsonb_build_object('user_id', a.user_id, 'username', a.username,
                                'photo_url', a.photo_url))
                          from public.community_posts cp
                          left join public.user_profiles a on a.user_id = cp.author_id
                          where cp.id = n.target_id)
        when 'comment' then (select jsonb_build_object('id', c.id, 'post_id', c.post_id,
                            'content', left(c.content, 300),
                            'author', jsonb_build_object('user_id', a.user_id, 'username', a.username,
                                'photo_url', a.photo_url))
                          from public.community_post_comments c
                          left join public.user_profiles a on a.user_id = c.author_id
                          where c.id = n.target_id)
        when 'story' then (select jsonb_build_object('id', st.id, 'kind', st.kind,
                            'content', left(st.content, 300), 'image_url', st.image_url,
                            'expires_at', st.expires_at,
                            'author', jsonb_build_object('user_id', a.user_id, 'username', a.username,
                                'photo_url', a.photo_url))
                          from public.stories st
                          left join public.user_profiles a on a.user_id = st.author_id
                          where st.id = n.target_id)
        when 'user' then (select jsonb_build_object('user_id', up.user_id, 'username', up.username,
                            'first_name', up.first_name, 'last_name', up.last_name,
                            'photo_url', up.photo_url, 'account_status', up.account_status)
                          from public.user_profiles up where up.user_id = n.target_id)
      end
    ) order by n.created_at desc, n.id desc) filter (where n.rn <= v_limit), '[]'::jsonb),
    count(*) > v_limit
  into v_items, v_has_more
  from numbered n;

  return jsonb_build_object('items', v_items, 'has_more', coalesce(v_has_more, false));
end;
$function$;

revoke all on function public.get_platform_reports(text, integer, integer) from public, anon;
grant execute on function public.get_platform_reports(text, integer, integer) to authenticated;

create or replace function public.resolve_platform_report(
  p_report_id uuid,
  p_action text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_rep public.signalement;
  v_note text := nullif(btrim(p_note), '');
  v_new public.signalement_status;
  v_n integer;
  v_admin uuid;
  v_c record;
  v_user_exists boolean := false;
begin
  if v_uid is null then raise exception 'Utilisateur non authentifié'; end if;
  if not coalesce(public.is_admin_or_above(), false) then
    raise exception 'Action réservée aux administrateurs de la plateforme';
  end if;
  if p_action is null or p_action not in ('dismiss', 'remove_content', 'suspend_user') then
    raise exception 'Action invalide';
  end if;
  if char_length(coalesce(v_note, '')) > 1000 then
    raise exception 'Note trop longue (1000 caractères maximum)';
  end if;

  select * into v_rep from public.signalement where id = p_report_id for update;
  if not found then raise exception 'Signalement introuvable'; end if;
  if v_rep.status::text not in ('en_attente', 'en_cours') then
    raise exception 'Ce signalement a déjà été traité';
  end if;
  select id into v_admin from public.administrateur_profil
  where auth_id = v_uid and actif limit 1;

  if p_action = 'suspend_user' then
    if v_rep.target_type::text <> 'user' or v_rep.community_id is null or v_rep.escalated_at is null then
      raise exception 'La suspension est réservée aux signalements de membre escaladés depuis une communauté';
    end if;
    update public.user_profiles set account_status = 'suspended', updated_at = now()
    where user_id = v_rep.target_id and deleted_at is null;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Utilisateur introuvable ou déjà supprimé'; end if;
    insert into public.admin_user_moderation_actions (user_id, admin_id, action, reason)
    values (v_rep.target_id, v_admin, 'suspend', coalesce(v_note, 'Signalement communautaire escaladé après 48 heures'));
    v_new := 'resolu';
  elsif p_action = 'remove_content' then
    if v_rep.target_type::text = 'post' then
      perform public.delete_post(v_rep.target_id, v_note);
    elsif v_rep.target_type::text = 'story' then
      perform public.delete_story(v_rep.target_id, v_note);
    elsif v_rep.target_type::text = 'comment' then
      select c.author_id, c.post_id, cp.community_id, left(coalesce(c.content, ''), 200) as excerpt
        into v_c
      from public.community_post_comments c
      join public.community_posts cp on cp.id = c.post_id
      where c.id = v_rep.target_id;
      if found then
        delete from public.community_post_comments where id = v_rep.target_id;
        insert into public.content_removals
          (content_type, content_id, community_id, author_id, removed_by, removed_by_role, reason, excerpt)
        values ('comment', v_rep.target_id, v_c.community_id, v_c.author_id, v_uid,
          'platform_admin', v_note, v_c.excerpt);
        perform private.notify_community_user(v_c.author_id, 'comment_removed', v_uid,
          jsonb_build_object('post_id', v_c.post_id, 'community_id', v_c.community_id,
            'actor_id', v_uid, 'raison', coalesce(v_note, '')),
          'Commentaire supprimé', 'Votre commentaire a été supprimé par la modération.');
      end if;
    else
      raise exception 'Cette action est uniquement disponible pour une publication, un commentaire ou une story';
    end if;
    v_new := 'resolu';
  else
    v_new := 'rejete';
  end if;

  -- Do not resolve a member's reports from unrelated communities.
  update public.signalement
  set status = v_new, reviewed_at = now(), reviewed_by = v_admin
  where target_type = v_rep.target_type
    and target_id = v_rep.target_id
    and community_id is not distinct from v_rep.community_id
    and status in ('en_attente', 'en_cours');
  get diagnostics v_n = row_count;
  return jsonb_build_object('updated', v_n, 'status', v_new::text);
end;
$function$;

revoke all on function public.resolve_platform_report(uuid, text, text) from public, anon;
grant execute on function public.resolve_platform_report(uuid, text, text) to authenticated;

-- Only the scheduled database job should trigger escalations; end users must not force early escalation.
revoke all on function public.escalate_stale_community_reports() from public, anon, authenticated;
