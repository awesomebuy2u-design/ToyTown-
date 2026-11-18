alter table public.family_world_progress
 add column pet_hat boolean not null default false,
 add column pet_bow boolean not null default false,
 add column pet_outfit text not null default 'none' check(pet_outfit in ('none','mint','coral'));
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
 return jsonb_build_object('familyId',f,'stored',stored,'stars',coalesce(p.stars,0),'careCount',coalesce(p.care_count,0),'lastCareDay',p.last_care_day,'decorated',coalesce(p.decorated,false),'canCare',p.last_care_day is null or p.last_care_day<d,'petKind',coalesce(p.pet_kind,'dog'),'petName',coalesce(p.pet_name,'Дружок'),'flowers',coalesce(p.flowers,false),'awning',coalesce(p.awning,false),'petHat',coalesce(p.pet_hat,false),'petBow',coalesce(p.pet_bow,false),'petOutfit',coalesce(p.pet_outfit,'none'));
end; $$;


create or replace function public.dress_family_pet(target_family uuid, slot text, item text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or target_family is null or not public.is_family_guardian(target_family) then raise exception 'Family profile required';end if;
 perform 1 from public.families where id=target_family for update;
 if slot is null or item is null then raise exception 'Wardrobe selection required';end if;
 insert into public.family_world_progress(family_id) values(target_family) on conflict do nothing;
 if slot='outfit' and item in ('none','mint','coral') then
  update public.family_world_progress set pet_outfit=item,updated_at=now() where family_id=target_family;
 elsif slot='hat' and item in ('on','off') then
  update public.family_world_progress set pet_hat=(item='on'),updated_at=now() where family_id=target_family;
 elsif slot='bow' and item in ('on','off') then
  update public.family_world_progress set pet_bow=(item='on'),updated_at=now() where family_id=target_family;
 else raise exception 'Invalid wardrobe item';end if;
 return public.family_world_action('read',target_family);
end; $$;
revoke all on function public.dress_family_pet(uuid,text,text) from public,anon;
grant execute on function public.dress_family_pet(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
