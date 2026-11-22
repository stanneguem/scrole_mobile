-- Accept browser-exported WebM clips alongside MP4 and MOV for posts.
do $$
declare
  v_def text;
  v_updated text;
  v_old text := $old$if right(lower(v_object_key), 4) <> '.mp4' and right(lower(v_object_key), 4) <> '.mov' then$old$;
  v_new text := $new$if right(lower(v_object_key), 4) <> '.mp4'
         and right(lower(v_object_key), 4) <> '.mov'
         and right(lower(v_object_key), 5) <> '.webm' then$new$;
begin
  select pg_get_functiondef(
    'public.create_post(uuid,text,uuid,text,jsonb,text[],uuid[],boolean,boolean,boolean,jsonb,boolean,uuid,uuid)'::regprocedure
  ) into v_def;

  v_updated := replace(v_def, v_old, v_new);
  if v_updated = v_def and position('right(lower(v_object_key), 5) <> ''.webm''' in v_def) = 0 then
    raise exception 'Could not safely locate create_post video format validation';
  end if;
  if v_updated <> v_def then execute v_updated; end if;
end
$$;

notify pgrst, 'reload schema';
