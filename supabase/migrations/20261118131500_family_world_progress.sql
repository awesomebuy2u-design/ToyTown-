-- Cosmetic game progress shared by the adult-managed family.
-- Stars are game points only; they have no payment or discount value.
create table public.family_world_progress (
 family_id uuid primary key references public.families(id) on delete cascade,
 stars integer not null default 0 check(stars>=0),
 care_count integer not null default 0 check(care_count>=0),
 last_care_day integer,
 decorated boolean not null default false,
 legacy_imported boolean not null default false,
 updated_at timestamptz not null default now(),
 constraint world_points_consistent check(stars=care_count*3-case when decorated then 5 else 0 end)
);
alter table public.family_world_progress enable row level security;
revoke all on public.family_world_progress from public,anon,authenticated;
grant select on public.family_world_progress to authenticated;
create policy "parents read own family game" on public.family_world_progress for select to authenticated using(public.is_family_guardian(family_id));

create or replace function public.family_world_action(action text default 'read', target_family uuid default null, legacy jsonb default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare f uuid; p public.family_world_progress%rowtype; d integer; c integer; s integer; decorated_legacy boolean; stored boolean;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if action is null or action not in ('read','care','decorate','import') then raise exception 'Unknown game action';end if;
 if target_family is null then
  select family_id into f from public.family_members where user_id=auth.uid() order by created_at,family_id limit 1;
 else f:=target_family; end if;
 if f is null or not public.is_family_guardian(f) then raise exception 'Family profile required';end if;
 -- Serialize all devices and first imports for this family.
 perform 1 from public.families where id=f for update;
 d:=((now() at time zone 'Europe/Kyiv')::date-date '1970-01-01');
 select * into p from public.family_world_progress where family_id=f for update;
 stored:=found;
 if action='import' and not stored then
  c:=(legacy->>'careCount')::integer;
  s:=(legacy->>'stars')::integer;
  decorated_legacy:=(legacy->>'decorated')::boolean;
  if c is null or s is null or decorated_legacy is null or c not between 0 and 3650 or s<>(c*3-(case when decorated_legacy then 5 else 0 end)) or s<0 then raise exception 'Invalid local progress';end if;
  insert into public.family_world_progress(family_id,stars,care_count,last_care_day,decorated,legacy_imported)
  values(f,s,c,case when c>0 then d else null end,decorated_legacy,true) returning * into p;
  stored:=true;
 elsif action in ('care','decorate') then
  if not stored then
   insert into public.family_world_progress(family_id) values(f) returning * into p;
   stored:=true;
  end if;
  if action='care' and (p.last_care_day is null or p.last_care_day<d) then
   update public.family_world_progress set stars=stars+3,care_count=care_count+1,last_care_day=d,updated_at=now() where family_id=f returning * into p;
  elsif action='decorate' and not p.decorated then
   if p.stars<5 then raise exception 'Not enough stars';end if;
   update public.family_world_progress set stars=stars-5,decorated=true,updated_at=now() where family_id=f returning * into p;
  end if;
 end if;
 return jsonb_build_object('familyId',f,'stored',stored,'stars',coalesce(p.stars,0),'careCount',coalesce(p.care_count,0),'lastCareDay',p.last_care_day,'decorated',coalesce(p.decorated,false),'canCare',p.last_care_day is null or p.last_care_day<d);
end; $$;
revoke all on function public.family_world_action(text,uuid,jsonb) from public,anon;
grant execute on function public.family_world_action(text,uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
