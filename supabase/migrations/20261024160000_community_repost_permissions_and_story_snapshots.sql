-- Community-level repost permission and safe story snapshots.
ALTER TABLE public.community_settings
  ADD COLUMN IF NOT EXISTS allow_post_sharing boolean NOT NULL DEFAULT true;

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS shared_post_snapshot jsonb;

ALTER TABLE public.community_posts
  ADD COLUMN IF NOT EXISTS shared_post_snapshot jsonb;

CREATE OR REPLACE FUNCTION private.story_post_snapshot(p_post_id uuid, p_viewer uuid, p_depth integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p public.community_posts;
  v_item jsonb;
  v_nested jsonb;
begin
  if p_depth > 8 then
    return jsonb_build_object('id', p_post_id, 'available', false, 'can_open_original', false);
  end if;
  select * into v_p from public.community_posts where id = p_post_id;
  if not found or v_p.status <> 'active'
     or not public.can_view_post_row(v_p.community_id, v_p.author_id, v_p.audience)
     or private.users_blocked(p_viewer, v_p.author_id) then
    return jsonb_build_object('id', p_post_id, 'available', false, 'can_open_original', false);
  end if;
  v_item := private.post_item(p_post_id, p_viewer);
  if v_p.shared_post_id is not null then
    if exists (
      select 1 from public.community_posts source
      where source.id = v_p.shared_post_id
        and source.community_id is not null
        and not (coalesce(public.is_admin_or_above(), false) or public.is_community_member(source.community_id))
    ) then
      v_nested := coalesce(
        v_p.shared_post_snapshot,
        jsonb_build_object('id', v_p.shared_post_id, 'available', false, 'can_open_original', false)
      );
    else
      v_nested := private.story_post_snapshot(v_p.shared_post_id, p_viewer, p_depth + 1);
    end if;
    v_item := jsonb_set(v_item, '{shared_post}', v_nested, true);
  end if;
  -- Snapshot de contenu et d'attribution uniquement : pas de communauté,
  -- réactions/commentaires source ni de navigation vers la publication.
  v_item := v_item - array[
    'community_id','community','likes_count','dislikes_count','comments_count',
    'viewer_reaction','views_count','viewers_count','shares_count',
    'viewer_has_shared','shared_comment_id','shared_comment','poll'
  ];
  v_item := v_item || jsonb_build_object(
    'available', true,
    'can_open_original', false,
    'shared_post_can_open_original', false,
    'likes_count', 0,
    'dislikes_count', 0,
    'comments_count', 0,
    'shares_count', 0,
    'views_count', 0,
    'viewer_reaction', null
  );
  return v_item;
end
$function$;

REVOKE ALL ON FUNCTION private.story_post_snapshot(uuid, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.story_post_snapshot(uuid, uuid, integer) TO authenticated;

CREATE OR REPLACE FUNCTION private.story_can_open_original(p_post_id uuid, p_viewer uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_p public.community_posts;
begin
  select * into v_p from public.community_posts where id = p_post_id;
  if not found or v_p.status <> 'active'
     or private.users_blocked(p_viewer, v_p.author_id)
     or not public.can_view_post_row(v_p.community_id, v_p.author_id, v_p.audience) then
    return false;
  end if;
  if v_p.community_id is not null
     and not (coalesce(public.is_admin_or_above(), false) or public.is_community_member(v_p.community_id)) then
    return false;
  end if;
  return true;
end
$function$;

REVOKE ALL ON FUNCTION private.story_can_open_original(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.story_can_open_original(uuid, uuid) TO authenticated;


CREATE OR REPLACE FUNCTION public.get_community_management_settings(p_community_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_community public.communities; v_access public.community_access_rules; v_settings public.community_settings;
begin
  if (select auth.uid()) is null then raise exception 'Utilisateur non authentifié'; end if;
  if not public.is_community_admin(p_community_id) then raise exception 'Action réservée aux administrateurs de la communauté'; end if;
  select * into v_community from public.communities c where c.id = p_community_id and c.status = 'active';
  if not found then raise exception 'Communauté introuvable'; end if;
  select * into v_access from public.community_access_rules r where r.community_id = p_community_id;
  select * into v_settings from public.community_settings s where s.community_id = p_community_id;
  return jsonb_build_object(
    'community', jsonb_build_object('id',v_community.id,'name',v_community.name,'slug',v_community.slug,'description',v_community.description,'slogan',v_community.slogan,'photo_profile',v_community.photo_profile,'photo_cover',v_community.photo_cover,'visibility',v_community.visibility,'require_manual_approval',v_community.require_manual_approval),
    'access_rules', jsonb_build_object('countries_enabled',coalesce(v_access.countries_enabled,false),'allowed_countries',coalesce(to_jsonb(v_access.allowed_countries),'[]'::jsonb),'cities_enabled',coalesce(v_access.cities_enabled,false),'allowed_cities',coalesce(to_jsonb(v_access.allowed_cities),'[]'::jsonb),'certification_required',coalesce(v_access.certification_required,false),'gender_restriction',v_access.gender_restriction,'age_min',v_access.age_min,'age_max',v_access.age_max),
    'settings', jsonb_build_object('members_list_visible',coalesce(v_settings.members_list_visible,true),'posts_require_approval',coalesce(v_settings.posts_require_approval,false),'post_permission',coalesce(v_settings.post_permission,'everyone'),'allow_reports',coalesce(v_settings.allow_reports,true),'allow_comments',coalesce(v_settings.allow_comments,true),'allow_reactions',coalesce(v_settings.allow_reactions,true),'allow_post_promotion',coalesce(v_settings.allow_post_promotion,true),'allow_post_sharing',coalesce(v_settings.allow_post_sharing,true))
  );
end; $function$


CREATE OR REPLACE FUNCTION private.post_extras(p_post_id uuid, p_viewer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_shared uuid;
  v_scomment uuid;
  v_snapshot jsonb;
  v_card jsonb := null;
  v_ccard jsonb := null;
  v_orig public.community_posts;
begin
  select shared_post_id, shared_comment_id, shared_post_snapshot
    into v_shared, v_scomment, v_snapshot
  from public.community_posts where id = p_post_id;

  if v_shared is not null then
    select * into v_orig from public.community_posts where id = v_shared;
    if found and v_orig.status = 'active'
       and private.story_can_open_original(v_shared, p_viewer) then
      v_card := private.post_item(v_shared, p_viewer) || jsonb_build_object('available', true, 'can_open_original', true);
    elsif v_snapshot is not null then
      v_card := v_snapshot || jsonb_build_object('available', true, 'can_open_original', false);
    else
      v_card := jsonb_build_object('id', v_shared, 'available', false, 'can_open_original', false);
    end if;
  end if;

  if v_scomment is not null then
    v_ccard := private.comment_card(v_scomment, p_viewer);
  end if;

  return jsonb_build_object(
    'views_count', (select coalesce(sum(v.view_count), 0)::bigint from public.post_views v where v.post_id = p_post_id),
    'viewers_count', (select count(*) from public.post_views v where v.post_id = p_post_id),
    'shares_count', (select count(*) from public.community_posts s where s.shared_post_id = p_post_id and s.status = 'active'),
    'viewer_has_shared', exists (select 1 from public.community_posts s where s.shared_post_id = p_post_id and s.author_id = p_viewer),
    'shared_post_id', v_shared,
    'shared_post', v_card,
    'shared_post_can_open_original', coalesce((v_card ->> 'can_open_original')::boolean, false),
    'shared_comment_id', v_scomment,
    'shared_comment', v_ccard
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.share_post(
  p_id uuid,
  p_original_post_id uuid,
  p_community_id uuid DEFAULT NULL::uuid,
  p_audience text DEFAULT 'public'::text,
  p_comment text DEFAULT NULL::text
) RETURNS public.community_posts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_source public.community_posts;
  v_shared public.community_posts;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_original_post_id is null then raise exception 'Publication indisponible'; end if;

  select * into v_source from public.community_posts where id = p_original_post_id;
  if not found or v_source.status <> 'active'
     or not public.can_view_post_row(v_source.community_id, v_source.author_id, v_source.audience)
     or private.users_blocked(v_uid, v_source.author_id) then
    raise exception 'Publication indisponible';
  end if;
  if not v_source.sharing_enabled then
    raise exception 'Le partage est désactivé sur cette publication';
  end if;
  if v_source.community_id is not null then
    if not exists (
      select 1 from public.communities c
      where c.id = v_source.community_id and c.status = 'active'
        and (c.visibility = 'public' or public.is_community_member(c.id))
    ) then raise exception 'Publication indisponible'; end if;
    if exists (
      select 1 from public.community_settings cs
      where cs.community_id = v_source.community_id
        and not coalesce(cs.allow_post_sharing, true)
    ) then raise exception 'Le repartage est désactivé par les administrateurs de cette communauté'; end if;
  elsif v_source.audience <> 'public' then
    raise exception 'Cette publication ne peut pas être repartagée';
  end if;

  v_shared := public.create_post(
    p_id, p_comment, p_community_id, p_audience, '[]'::jsonb, '{}'::text[], '{}'::uuid[],
    true, true, true, null, true, p_original_post_id
  );
  update public.community_posts
    set shared_post_snapshot = private.story_post_snapshot(p_original_post_id, v_uid, 0)
    where id = v_shared.id
    returning * into v_shared;
  return v_shared;
end
$function$;

REVOKE ALL ON FUNCTION public.share_post(uuid, uuid, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_post(uuid, uuid, uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.share_post_to_story(p_id uuid, p_original_post_id uuid, p_caption text DEFAULT NULL::text, p_background text DEFAULT NULL::text, p_audience text DEFAULT 'public'::text)
 RETURNS stories
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid(); v_row public.stories; v_orig public.community_posts;
  v_audience text := lower(btrim(coalesce(p_audience, 'public')));
  v_caption text := nullif(btrim(p_caption), ''); v_bg text := nullif(btrim(p_background), '');
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_id is null then raise exception 'L''identifiant de la story est obligatoire'; end if;
  select * into v_row from public.stories where id = p_id;
  if found then
    if v_row.author_id = v_uid then return v_row; end if;
    raise exception 'Identifiant de story déjà utilisé';
  end if;
  if not exists (select 1 from public.user_profiles up where up.user_id = v_uid and up.account_status = 'active' and up.deleted_at is null) then
    raise exception 'Compte indisponible';
  end if;
  if v_audience not in ('public', 'followers', 'friends') then raise exception 'Audience invalide'; end if;
  if char_length(coalesce(p_caption, '')) > 500 then raise exception 'Le texte ne peut pas dépasser 500 caractères'; end if;
  if v_bg is not null and v_bg !~ '^(#[0-9A-Fa-f]{6}|[a-z0-9_-]{1,30})$' then raise exception 'Fond invalide'; end if;

  if p_original_post_id is null then raise exception 'Publication indisponible'; end if;
  select * into v_orig from public.community_posts where id = p_original_post_id;
  if not found then raise exception 'Publication indisponible'; end if;
  -- Conserver exactement le post sélectionné : ne jamais aplatir la chaîne de republications.
  if v_orig.status <> 'active' or not public.can_view_post_row(v_orig.community_id, v_orig.author_id, v_orig.audience) then
    raise exception 'Publication indisponible';
  end if;
  if private.users_blocked(v_uid, v_orig.author_id) then raise exception 'Action impossible'; end if;
  if not v_orig.sharing_enabled then raise exception 'Le partage est désactivé sur ce post'; end if;
  if v_orig.community_id is not null then
    if not exists (
      select 1 from public.communities c
      where c.id = v_orig.community_id and c.status = 'active'
        and (c.visibility = 'public' or public.is_community_member(c.id))
    ) then raise exception 'Ce post ne peut pas être partagé'; end if;
    if exists (
      select 1 from public.community_settings cs
      where cs.community_id = v_orig.community_id
        and not coalesce(cs.allow_post_sharing, true)
    ) then raise exception 'Le repartage est désactivé par les administrateurs de cette communauté'; end if;
  elsif v_orig.audience <> 'public' then
    raise exception 'Ce post ne peut pas être partagé';
  end if;

  if (select count(*) from public.stories s where s.author_id = v_uid and s.created_at > now() - interval '24 hours') >= 20 then
    raise exception 'Limite de stories atteinte : 20 stories par 24 heures';
  end if;

  begin
    insert into public.stories (id, author_id, kind, content, background, audience, shared_post_id, shared_post_snapshot, expires_at)
    values (p_id, v_uid, 'post', v_caption, v_bg, v_audience, v_orig.id,
      private.story_post_snapshot(v_orig.id, v_uid, 0), now() + interval '24 hours')
    returning * into v_row;
  exception when unique_violation then
    raise exception 'Vous avez déjà partagé ce post dans une story';
  end;

  if v_orig.author_id <> v_uid then
    perform private.notify_community_user(v_orig.author_id, 'post_shared_story', v_uid,
      jsonb_build_object('post_id', v_orig.id, 'story_id', p_id, 'community_id', v_orig.community_id, 'actor_id', v_uid),
      'Publication partagée en story', 'Quelqu''un a partagé votre publication dans sa story.');
  end if;
  return v_row;
end $function$


CREATE OR REPLACE FUNCTION private.story_groups(p_scope text, p_limit integer, p_offset integer, p_author uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := auth.uid(); v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  with vis as (
    select s.id, s.author_id, s.kind, s.content, s.image_url, s.background, s.shared_post_id, s.shared_post_snapshot, s.audience, s.created_at, s.expires_at,
           exists (select 1 from public.story_views sv where sv.story_id = s.id and sv.viewer_id = v_uid) as viewed
    from public.stories s
    where s.status = 'active' and s.expires_at > now()
      and public.can_view_story_row(s.author_id, s.audience)
      and case p_scope when 'own' then s.author_id = v_uid when 'user' then s.author_id = p_author else s.author_id <> v_uid end
  ),
  rel as (
    select a.author_id,
      case when a.author_id = v_uid then 'own'
           when public.are_friends(v_uid, a.author_id) then 'friend'
           when exists (select 1 from public.user_follows f where f.follower_id = v_uid and f.followed_id = a.author_id) then 'follow'
           else 'other' end as relation
    from (select distinct author_id from vis) a
  ),
  grp as (
    select v.author_id, r.relation, max(v.created_at) as latest_at, count(*)::int as stories_count,
           bool_or(not v.viewed) as has_unseen
    from vis v join rel r on r.author_id = v.author_id
    group by v.author_id, r.relation
  ),
  filtered as (
    select g.*,
      case when p_scope = 'suggested' then (
          least(50, (select count(*) from public.friendships f
                     where (f.user_a_id = g.author_id and public.are_friends(v_uid, f.user_b_id))
                        or (f.user_b_id = g.author_id and public.are_friends(v_uid, f.user_a_id))) * 10)
        + least(32, (select count(*) from public.community_members a join public.community_members b
                     on b.community_id = a.community_id and b.user_id = g.author_id where a.user_id = v_uid) * 8)
        + least(20, (select count(*) from public.user_interests a join public.user_interests b
                     on b.interest_id = a.interest_id and b.user_id = v_uid where a.user_id = v_uid) * 5)
        + least(30, round(5 * ln(1 + (select count(distinct sv.viewer_id) from public.story_views sv
                     join vis v2 on v2.id = sv.story_id where v2.author_id = g.author_id))))
        + floor(20 * exp(-extract(epoch from (now() - g.latest_at)) / 43200.0))
      )::numeric else 0::numeric end as score
    from grp g
    join public.user_profiles up on up.user_id = g.author_id and up.account_status = 'active' and up.deleted_at is null
    where case p_scope
            when 'following' then g.relation in ('friend', 'follow')
            when 'suggested' then g.relation = 'other' and g.has_unseen
            else true end
  ),
  ordered as (
    select f.*, row_number() over (
      order by case when p_scope = 'suggested' then -f.score else (case when f.has_unseen then 0 else 1 end)::numeric end,
               f.latest_at desc, f.author_id) as rn
    from filtered f
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'author', jsonb_build_object('user_id', up.user_id, 'username', up.username, 'pseudo', up.username, 'first_name', up.first_name,
                 'last_name', up.last_name, 'photo_url', up.photo_url,
                 'is_certified', exists (select 1 from public.user_certifications uc where uc.user_id = up.user_id
                                         and uc.status::text = 'active' and uc.issued_at <= now()
                                         and (uc.expires_at is null or uc.expires_at >= now()))),
      'relation', o.relation, 'has_unseen', o.has_unseen, 'latest_at', o.latest_at, 'stories_count', o.stories_count,
      'stories', (select jsonb_agg(jsonb_build_object(
                    'id', v.id, 'kind', v.kind, 'content', v.content, 'image_url', v.image_url, 'background', v.background,
                    'shared_post_id', v.shared_post_id,
                    'shared_post_can_open_original', case when v.shared_post_id is null then false else private.story_can_open_original(v.shared_post_id, v_uid) end,
                    'shared_post', case
                      when v.shared_post_id is null then null
                      when private.story_can_open_original(v.shared_post_id, v_uid) then private.story_post_card(v.shared_post_id, v_uid)
                      else coalesce(v.shared_post_snapshot, jsonb_build_object('id', v.shared_post_id, 'available', false, 'can_open_original', false))
                    end,
                    'audience', v.audience, 'created_at', v.created_at, 'expires_at', v.expires_at, 'viewed', v.viewed,
                    'viewers_count', case when v.author_id = v_uid then (select count(*) from public.story_views sv where sv.story_id = v.id) end,
                    'comments_count', (select count(*)::integer from public.story_comments c
                                       join public.user_profiles cup on cup.user_id = c.author_id
                                       where c.story_id = v.id and c.parent_comment_id is null
                                         and cup.account_status = 'active' and cup.deleted_at is null),
                    'viewer_has_liked', exists (select 1 from public.story_likes sl where sl.story_id = v.id and sl.user_id = v_uid),
                    'likes_count', case when v.author_id = v_uid then (select count(*) from public.story_likes sl where sl.story_id = v.id) end,
                    'poll', private.story_poll_state(v.id, v_uid)) order by v.created_at)
                  from vis v where v.author_id = o.author_id)
    ) order by o.rn), '[]'::jsonb)
  into v_result
  from ordered o join public.user_profiles up on up.user_id = o.author_id
  where o.rn > p_offset and o.rn <= p_offset + p_limit;
  return v_result;
end $function$


CREATE OR REPLACE FUNCTION public.set_community_post_sharing_enabled(
  p_community_id uuid,
  p_enabled boolean
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'Utilisateur non authentifié'; end if;
  if not public.is_community_admin(p_community_id) then
    raise exception 'Action réservée aux administrateurs de la communauté';
  end if;
  if not exists (select 1 from public.communities c where c.id = p_community_id and c.status = 'active') then
    raise exception 'Communauté introuvable';
  end if;
  insert into public.community_settings (community_id, allow_post_sharing)
  values (p_community_id, p_enabled)
  on conflict (community_id) do update
    set allow_post_sharing = excluded.allow_post_sharing, updated_at = now();
  return jsonb_build_object('community_id', p_community_id, 'allow_post_sharing', p_enabled);
end
$function$;

REVOKE ALL ON FUNCTION public.set_community_post_sharing_enabled(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_community_post_sharing_enabled(uuid, boolean) TO authenticated;
