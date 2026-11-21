-- Removing a listing keeps its conversation and agreement references intact.
alter table public.listings add column if not exists deleted_at timestamptz;
alter table public.listings add constraint deleted_listing_is_archived
  check (deleted_at is null or status = 'archived');

-- A message may be removed only by its author while still a chat participant.
create policy "authors delete their own conversation messages" on public.family_messages
  for delete to authenticated
  using (sender_user_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

create function public.delete_own_message(target_message uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare removed uuid;
begin
  if auth.uid() is null then
    raise exception 'Message unavailable or not yours' using errcode = '42501';
  end if;
  delete from public.family_messages
  where id = target_message and sender_user_id = auth.uid()
    and public.is_conversation_member(conversation_id)
  returning id into removed;
  if removed is null then
    raise exception 'Message unavailable or not yours' using errcode = '42501';
  end if;
end;
$$;
revoke all on function public.delete_own_message(uuid) from public, anon;
grant execute on function public.delete_own_message(uuid) to authenticated;

-- Archiving an approved row requires a narrowly scoped privileged action.
-- Keep that implementation outside the exposed API schema.
create schema if not exists private;
grant usage on schema private to authenticated;
create function private.delete_family_listing(target_listing uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare target public.listings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Listing unavailable or not yours' using errcode = '42501';
  end if;
  select * into target from public.listings where id = target_listing for update;
  if target.id is null or not public.is_family_guardian(target.family_id) then
    raise exception 'Listing unavailable or not yours' using errcode = '42501';
  end if;
  if target.deleted_at is not null then return; end if;
  if exists (select 1 from public.exchange_agreements
    where listing_id = target.id and status in ('proposed', 'accepted')) then
    raise exception 'LISTING_HAS_ACTIVE_AGREEMENT' using errcode = '55000';
  end if;
  update public.listings set status = 'archived', deleted_at = now(), updated_at = now()
  where id = target.id;
end;
$$;
revoke all on function private.delete_family_listing(uuid) from public, anon;
grant execute on function private.delete_family_listing(uuid) to authenticated;

create function public.delete_own_listing(target_listing uuid)
returns void language sql security invoker set search_path = '' as $$
  select private.delete_family_listing(target_listing);
$$;
revoke all on function public.delete_own_listing(uuid) from public, anon;
grant execute on function public.delete_own_listing(uuid) to authenticated;
notify pgrst, 'reload schema';
