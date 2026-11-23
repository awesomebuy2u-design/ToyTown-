create table public.family_shop_layouts (
  family_id uuid primary key references public.families(id) on delete cascade,
  shelf_count integer not null default 3 check (shelf_count between 1 and 3),
  placements jsonb not null default '{}'::jsonb
    check (jsonb_typeof(placements) = 'object' and octet_length(placements::text) <= 65536)
);
alter table public.family_shop_layouts enable row level security;
revoke all on public.family_shop_layouts from anon, authenticated;
grant select, insert, update on public.family_shop_layouts to authenticated;

create function private.valid_family_shop_layout(target_family uuid, shelves integer, positions jsonb)
returns boolean language sql stable security invoker set search_path = '' as $$
  select case when jsonb_typeof(positions) is distinct from 'object'
    or shelves is null or shelves not between 1 and 3 then false
  else not exists (
    select 1 from jsonb_each(positions) p
    where p.value::text not in (select i::text from generate_series(0, shelves - 1) i)
      or not exists (select 1 from public.listings l
        where l.id::text = p.key and l.family_id = target_family
          and l.status = 'approved' and l.deleted_at is null)
  ) end;
$$;
revoke all on function private.valid_family_shop_layout(uuid,integer,jsonb) from public, anon;
grant execute on function private.valid_family_shop_layout(uuid,integer,jsonb) to authenticated;

create policy "guardians read their shelf drafts" on public.family_shop_layouts
for select to authenticated using (public.is_family_guardian(family_id));
create policy "guardians create their shelf layout" on public.family_shop_layouts
for insert to authenticated with check (public.is_family_guardian(family_id)
  and private.valid_family_shop_layout(family_id, shelf_count, placements));
create policy "guardians update their shelf layout" on public.family_shop_layouts
for update to authenticated using (public.is_family_guardian(family_id))
with check (public.is_family_guardian(family_id)
  and private.valid_family_shop_layout(family_id, shelf_count, placements));

-- Visitors see approved toy positions only; private/dropped IDs never leave here.
create function private.read_family_shop_layout(target_shop uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare shelves integer; positions jsonb;
begin
  if auth.uid() is null or (not public.is_family_guardian(target_shop)
    and not exists(select 1 from public.listings where family_id = target_shop
      and status = 'approved' and deleted_at is null)) then
    raise exception 'Shop unavailable' using errcode = '42501';
  end if;
  select shelf_count, placements into shelves, positions from public.family_shop_layouts where family_id = target_shop;
  select coalesce(jsonb_object_agg(p.key, p.value), '{}'::jsonb) into positions
    from jsonb_each(coalesce(positions, '{}'::jsonb)) p
    join public.listings l on l.id::text = p.key and l.family_id = target_shop
      and l.status = 'approved' and l.deleted_at is null;
  return jsonb_build_object('shelf_count', coalesce(shelves, 3), 'placements', positions);
end;
$$;
revoke all on function private.read_family_shop_layout(uuid) from public, anon;
grant execute on function private.read_family_shop_layout(uuid) to authenticated;

create function public.family_shop_layout(target_shop uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.read_family_shop_layout(target_shop);
$$;
revoke all on function public.family_shop_layout(uuid) from public, anon;
grant execute on function public.family_shop_layout(uuid) to authenticated;
-- Clearing a conversation is personal: the other participant and agreements stay.
create table public.conversation_user_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null references public.family_conversations(id) on delete cascade,
  cleared_at timestamptz not null,
  hidden boolean not null default true,
  primary key (user_id, conversation_id)
);
create index conversation_user_state_conversation_idx on public.conversation_user_state(conversation_id);
alter table public.conversation_user_state enable row level security;
revoke all on public.conversation_user_state from anon, authenticated;
grant select on public.conversation_user_state to authenticated;
create policy "participants read only their clearing state" on public.conversation_user_state
for select to authenticated using (user_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

create function private.clear_own_conversation(target_conversation uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare cutoff timestamptz;
begin
  if auth.uid() is null or not public.is_conversation_member(target_conversation) then
    raise exception 'Not a conversation participant' using errcode = '42501';
  end if;
  perform 1 from public.family_conversations where id = target_conversation for update;
  select greatest(clock_timestamp(), max(created_at)) into cutoff
    from public.family_messages where conversation_id = target_conversation;
  insert into public.conversation_user_state(user_id,conversation_id,cleared_at,hidden)
    values(auth.uid(),target_conversation,cutoff,true)
    on conflict(user_id,conversation_id) do update set cleared_at=excluded.cleared_at,hidden=true;
end;
$$;
revoke all on function private.clear_own_conversation(uuid) from public, anon;
grant execute on function private.clear_own_conversation(uuid) to authenticated;
create function public.clear_own_conversation(target_conversation uuid)
returns void language sql security invoker set search_path = '' as $$
  select private.clear_own_conversation(target_conversation);
$$;
revoke all on function public.clear_own_conversation(uuid) from public, anon;
grant execute on function public.clear_own_conversation(uuid) to authenticated;

drop policy "adult family members read conversation messages" on public.family_messages;
create policy "adult family members read conversation messages" on public.family_messages
for select to authenticated using (public.is_conversation_member(conversation_id)
  and created_at > coalesce((select s.cleared_at from public.conversation_user_state s
    where s.conversation_id=family_messages.conversation_id and s.user_id=(select auth.uid())), '-infinity'::timestamptz));

-- Serialize sends/clears on the conversation so incoming messages reopen it safely.
create function private.prepare_conversation_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare cutoff timestamptz;
begin
  if auth.uid() is not null and (new.sender_user_id<>auth.uid()
    or not public.is_conversation_member(new.conversation_id)) then
    raise exception 'Not a conversation participant' using errcode = '42501';
  end if;
  perform 1 from public.family_conversations where id=new.conversation_id for update;
  select max(cleared_at) into cutoff from public.conversation_user_state where conversation_id=new.conversation_id;
  new.created_at:=greatest(clock_timestamp(),cutoff + interval '1 microsecond');
  return new;
end;
$$;
revoke all on function private.prepare_conversation_message() from public, anon, authenticated;
create trigger prepare_conversation_message before insert on public.family_messages
for each row execute function private.prepare_conversation_message();

create function private.reopen_conversation_on_message()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.conversation_user_state set hidden=false where conversation_id=new.conversation_id;
  update public.family_conversations set updated_at=new.created_at where id=new.conversation_id;
  return new;
end;
$$;
revoke all on function private.reopen_conversation_on_message() from public, anon, authenticated;
create trigger zz_reopen_conversation_on_message after insert on public.family_messages
for each row execute function private.reopen_conversation_on_message();
notify pgrst, 'reload schema';
