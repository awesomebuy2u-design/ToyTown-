-- Cosmetic front sets are free; balances and existing purchases stay unchanged.
alter table public.family_world_progress add column shop_front text not null default 'classic' check(shop_front in ('classic','stars','clouds'));

create or replace function public.daily_family_world(action text default 'read', target_family uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare f uuid; p public.family_world_progress%rowtype; d integer; changed integer := 0; base jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if action is null or action not in ('read','feed','play','brush','theme_mint','theme_lavender','theme_sunset','front_classic','front_stars','front_clouds') then
  raise exception 'Unknown daily action';
 end if;
 if target_family is null then
  select family_id into f from public.family_members where user_id=auth.uid() order by created_at,family_id limit 1;
 else f := target_family; end if;
 if f is null or not public.is_family_guardian(f) then raise exception 'Family profile required'; end if;
 -- Same family lock as care, shopping and wardrobe, including old app versions.
 perform 1 from public.families where id=f for update;
 d := ((now() at time zone 'Europe/Kyiv')::date - date '1970-01-01');
 if action <> 'read' then
  insert into public.family_world_progress(family_id) values(f) on conflict do nothing;
  if action in ('feed','play','brush') then
   update public.family_world_progress set
    stars=stars+1, daily_stars=daily_stars+1,
    last_feed_day=case when action='feed' then d else last_feed_day end,
    last_play_day=case when action='play' then d else last_play_day end,
    last_brush_day=case when action='brush' then d else last_brush_day end,
    updated_at=now()
   where family_id=f and (
    (action='feed' and (last_feed_day is null or last_feed_day<d)) or
    (action='play' and (last_play_day is null or last_play_day<d)) or
    (action='brush' and (last_brush_day is null or last_brush_day<d))
   );
   get diagnostics changed = row_count;
  elsif action in ('front_classic','front_stars','front_clouds') then
   update public.family_world_progress set shop_front=substring(action from 7),updated_at=now() where family_id=f;
  else
   update public.family_world_progress set shop_theme=substring(action from 7),updated_at=now() where family_id=f;
  end if;
 end if;
 base := public.family_world_action('read',f);
 select * into p from public.family_world_progress where family_id=f;
 return base || jsonb_build_object(
  'dailyTasks',jsonb_build_object('feed',coalesce(p.last_feed_day>=d,false),'play',coalesce(p.last_play_day>=d,false),'brush',coalesce(p.last_brush_day>=d,false)),
  'shopFront',coalesce(p.shop_front,'classic'),'shopTheme',coalesce(p.shop_theme,'mint'),'rewarded',changed=1,'serverDay',d
 );
end; $$;
revoke all on function public.daily_family_world(text,uuid) from public,anon;
grant execute on function public.daily_family_world(text,uuid) to authenticated;
notify pgrst,'reload schema';
