-- Keep salon unread badges consistent with per-salon read positions.
-- Exclude messages sent before the current member joined and messages hidden by that user.
create or replace function public.list_community_chat_groups_with_preview(p_community_id uuid)
returns table(
  id uuid, community_id uuid, name text, description text, visibility text,
  created_by uuid, created_at timestamptz, updated_at timestamptz, avatar_url text,
  last_message text, last_message_type text, last_message_at timestamptz,
  last_message_sender_id uuid, last_message_sender_name text, unread_count bigint,
  last_message_all_read boolean, member_count bigint, my_status text, can_manage boolean
)
language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_community_member(p_community_id) then
    raise exception 'Vous devez être membre de la communauté';
  end if;
  return query
  select
    s.id, s.community_id, s.name, s.description, s.visibility,
    s.created_by, s.created_at, s.updated_at, s.avatar_url,
    latest.content, latest.type, latest.sent_at, latest.sender_id,
    case when latest.sender_id = v_uid then 'Vous'
      else coalesce(nullif(trim(concat_ws(' ', up.first_name, up.last_name)), ''), up.username, 'Membre') end,
    case
      when not (s.created_by = v_uid or exists (
        select 1 from public.community_salon_members mine
        where mine.salon_id = s.id and mine.user_id = v_uid
      )) then 0::bigint
      else (
        select count(*)::bigint
        from public.community_salon_messages um
        left join public.community_salon_message_receipts ur
          on ur.message_id = um.id and ur.user_id = v_uid
        where um.salon_id = s.id and not um.is_deleted
          and um.sender_id <> v_uid
          and um.sent_at >= coalesce(
            (select mine.joined_at from public.community_salon_members mine
             where mine.salon_id = s.id and mine.user_id = v_uid),
            case when s.created_by = v_uid then s.created_at else now() end
          )
          and ur.read_at is null
          and not exists (
            select 1 from public.community_salon_message_hidden_for hidden
            where hidden.message_id = um.id and hidden.user_id = v_uid
          )
      )
    end,
    case
      when latest.id is null or latest.sender_id <> v_uid then false
      else (
        select count(*) > 0 and count(*) = count(*) filter (where lr.read_at is not null)
        from public.community_salon_members lm
        left join public.community_salon_message_receipts lr
          on lr.message_id = latest.id and lr.user_id = lm.user_id
        where lm.salon_id = s.id and lm.user_id <> v_uid
          and lm.joined_at <= latest.sent_at
      )
    end,
    case when s.visibility = 'public' or s.created_by = v_uid
      or exists (select 1 from public.community_salon_members m where m.salon_id=s.id and m.user_id=v_uid)
      then (select count(*) from public.community_salon_members m where m.salon_id=s.id)
      else null end,
    case when s.created_by = v_uid or exists (
      select 1 from public.community_salon_members m where m.salon_id=s.id and m.user_id=v_uid
    ) then 'member'
    else coalesce((select r.status from public.community_salon_join_requests r
      where r.salon_id=s.id and r.user_id=v_uid), 'none') end,
    public.community_can(p_community_id, 'can_create_salon')
  from public.community_salons s
  left join lateral (
    select m.id,m.content,m.type,m.sent_at,m.sender_id
    from public.community_salon_messages m
    where m.salon_id=s.id and not m.is_deleted
    order by m.sent_at desc,m.id desc limit 1
  ) latest on true
  left join public.user_profiles up on up.user_id=latest.sender_id
  where s.community_id=p_community_id and (
    s.visibility='public' or s.created_by=v_uid
    or exists (select 1 from public.community_salon_members m where m.salon_id=s.id and m.user_id=v_uid)
    or exists (select 1 from public.community_salon_join_requests r where r.salon_id=s.id and r.user_id=v_uid and r.status='pending')
  )
  order by coalesce(latest.sent_at,s.updated_at) desc,s.created_at desc;
end;
$function$;
