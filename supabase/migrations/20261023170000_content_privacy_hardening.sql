-- Scrole content privacy hardening.
-- Additive migration: preserves existing rows and media. Review and apply after
-- confirming private media is served through authenticated/signed URLs; public
-- object URLs cannot be made private retroactively by changing SQL alone.

begin;

alter table public.stories
  add column if not exists allow_reshare boolean not null default false;

-- Stories must be limited to the author's friends/followers (plus the author
-- and platform admins). A stored legacy "public" audience is intentionally not
-- treated as public access by this helper.
create or replace function public.can_view_story_row(p_author uuid, p_audience text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    (select auth.uid()) is not null
    and (
      p_author = (select auth.uid())
      or coalesce(public.is_admin_or_above(), false)
      or (
        not private.users_blocked((select auth.uid()), p_author)
        and (
          public.are_friends((select auth.uid()), p_author)
          or exists (
            select 1
            from public.user_follows f
            where f.follower_id = (select auth.uid())
              and f.followed_id = p_author
          )
        )
      )
    ),
    false
  );
$function$;

-- Revoke broad execution and expose the predicate only to authenticated callers.
revoke all on function public.can_view_story_row(uuid, text) from public, anon;
grant execute on function public.can_view_story_row(uuid, text) to authenticated;

-- A non-member may not receive mention records from a private community.
-- Public communities remain mentionable by any authenticated user.
create or replace function public.can_receive_community_post_mention(
  p_post_id uuid,
  p_recipient_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    exists (
      select 1
      from public.community_posts p
      join public.communities c on c.id = p.community_id
      where p.id = p_post_id
        and p.status = 'active'
        and (
          c.visibility = 'public'
          or (
            c.visibility = 'private'
            and exists (
              select 1
              from public.community_members cm
              where cm.community_id = c.id
                and cm.user_id = p_recipient_id
            )
          )
        )
    ),
    false
  );
$function$;

revoke all on function public.can_receive_community_post_mention(uuid, uuid) from public, anon;
grant execute on function public.can_receive_community_post_mention(uuid, uuid) to authenticated;

-- Server-side validation for repost creation. Callers must be the actor, must
-- have access to the source, and source community policy must permit promotion.
create or replace function public.can_repost_community_post(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    exists (
      select 1
      from public.community_posts p
      where p.id = p_post_id
        and p.status = 'active'
        and public.can_view_post_row(p.community_id, p.author_id, p.audience)
        and p.sharing_enabled
        and (
          p.community_id is null
          or exists (
            select 1
            from public.communities c
            where c.id = p.community_id
              and (
                c.visibility = 'public'
                or (
                  c.visibility = 'private'
                  and coalesce((
                    select cs.allow_post_promotion
                    from public.community_settings cs
                    where cs.community_id = c.id
                  ), false)
                )
              )
          )
        )
    ),
    false
  );
$function$;

revoke all on function public.can_repost_community_post(uuid) from public, anon;
grant execute on function public.can_repost_community_post(uuid) to authenticated;

-- Harden the direct stories table policy as well as the shared helper. RLS
-- remains the source of truth for direct PostgREST requests.
drop policy if exists stories_select on public.stories;
create policy stories_select
on public.stories
for select
to authenticated
using (
  status = 'active'
  and expires_at > now()
  and public.can_view_story_row(author_id, audience)
);

commit;
