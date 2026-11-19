-- Run against a test database, or in this rollback-only transaction.
-- No names, messages, credentials or identifiers are returned.
begin;
do $$
declare f uuid; u uuid; d integer; before_stars integer; result jsonb; rejected boolean;
begin
 select family_id,user_id into f,u from public.family_members order by created_at limit 1;
 if f is null then raise exception 'Fixture requires one family member'; end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 insert into public.family_world_progress(family_id) values(f) on conflict do nothing;
 update public.family_world_progress set last_feed_day=null,last_play_day=null,last_brush_day=null where family_id=f;
 result := public.daily_family_world('read',f);
 before_stars := (result->>'stars')::integer;
 d := (result->>'serverDay')::integer;
 result := public.daily_family_world('feed',f);
 if result->>'rewarded'<>'true' or (result->>'stars')::integer<>before_stars+1 then raise exception 'Feed reward failed'; end if;
 result := public.daily_family_world('feed',f);
 if result->>'rewarded'<>'false' or (result->>'stars')::integer<>before_stars+1 then raise exception 'Duplicate reward'; end if;
 perform public.daily_family_world('play',f);
 result := public.daily_family_world('brush',f);
 if (result->>'stars')::integer<>before_stars+3 or result->'dailyTasks'<>'{"feed":true,"play":true,"brush":true}'::jsonb then raise exception 'Three tasks failed'; end if;
 result := public.daily_family_world('read',f);
 if (result->>'stars')::integer<>before_stars+3 then raise exception 'Reload lost balance'; end if;
 update public.family_world_progress set last_feed_day=d-1 where family_id=f;
 result := public.daily_family_world('read',f);
 if result->'dailyTasks'->>'feed'<>'false' then raise exception 'Next-day reset failed'; end if;
 result := public.daily_family_world('feed',f);
 if (result->>'stars')::integer<>before_stars+4 then raise exception 'Next-day reward failed'; end if;
 result := public.daily_family_world('theme_lavender',f);
 result := public.daily_family_world('read',f);
 if result->>'shopTheme'<>'lavender' or (result->>'stars')::integer<>before_stars+4 then raise exception 'Theme persistence or free price failed'; end if;
 -- Old clients can still care and buy balloons with the new consistency constraint.
 update public.family_world_progress set last_care_day=null where family_id=f;
 result := public.family_world_action('care',f);
 if (result->>'stars')::integer<>before_stars+7 then raise exception 'Old-client care regression'; end if;
 update public.family_world_progress set decorated=false,flowers=false,awning=false,stars=care_count*3+daily_stars where family_id=f;
 select stars into before_stars from public.family_world_progress where family_id=f;
 result := public.family_world_action('decorate',f);
 if result->>'decorated'<>'true' or (result->>'stars')::integer<>before_stars-5 then raise exception 'Old-client shop regression'; end if;
 -- Every action rejects a signed-in user who does not belong to the family.
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 rejected := false;
 begin perform public.daily_family_world('feed',f);
 exception when others then if sqlerrm='Family profile required' then rejected:=true; else raise; end if; end;
 if not rejected then raise exception 'Unrelated account gained access'; end if;
 perform set_config('request.jwt.claim.sub','',true);
 rejected := false;
 begin perform public.daily_family_world('feed',f);
 exception when others then if sqlerrm='Sign in required' then rejected:=true; else raise; end if; end;
 if not rejected then raise exception 'Unauthenticated access'; end if;
 if has_function_privilege('anon','public.daily_family_world(text,uuid)','execute') then raise exception 'Anonymous RPC grant'; end if;
 if has_table_privilege('authenticated','public.family_world_progress','update') then raise exception 'Direct balance update grant'; end if;
end $$;
select 'PASS: rewards, duplicate rejection, next day, reload, themes, old clients, account isolation' as result;
rollback;
