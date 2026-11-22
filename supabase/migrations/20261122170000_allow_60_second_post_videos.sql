-- Align server-side post video validation with the 60-second limit used by clients.
-- Rewrites only the known duration check in the installed create_post function.
do $$
declare
  v_def text;
  v_updated text;
begin
  select pg_get_functiondef(
    'public.create_post(uuid,text,uuid,text,jsonb,text[],uuid[],boolean,boolean,boolean,jsonb,boolean,uuid,uuid)'::regprocedure
  ) into v_def;

  v_updated := replace(v_def, 'v_duration > 30', 'v_duration > 60');
  v_updated := replace(v_updated, 'au maximum 30 secondes', 'au maximum 60 secondes');

  if v_updated = v_def and position('v_duration > 60' in v_def) = 0 then
    raise exception 'Could not safely locate create_post video duration validation';
  end if;

  if v_updated <> v_def then
    execute v_updated;
  end if;
end
$$;

notify pgrst, 'reload schema';
