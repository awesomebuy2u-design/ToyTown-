-- ToyTown v0.9.0: exchange agreements with two-sided handover confirmation.
create table if not exists public.exchange_agreements (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.family_conversations(id) on delete cascade,
  listing_id uuid references public.listings(id) on delete set null,
  proposer_family uuid not null references public.families(id) on delete cascade,
  receiver_family uuid not null references public.families(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  note text not null check (char_length(note) between 3 and 500),
  status text not null default 'proposed' check (status in ('proposed','accepted','rejected','completed','cancelled')),
  proposer_confirmed_at timestamptz,
  receiver_confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exchange_agreements_distinct_families check (proposer_family <> receiver_family)
);
create index if not exists exchange_agreements_proposer_idx on public.exchange_agreements(proposer_family,created_at desc);
create index if not exists exchange_agreements_receiver_idx on public.exchange_agreements(receiver_family,created_at desc);

alter table public.exchange_agreements enable row level security;
create policy "adult family members read their agreements" on public.exchange_agreements
 for select to authenticated using (public.is_family_guardian(proposer_family) or public.is_family_guardian(receiver_family));
revoke all on public.exchange_agreements from anon;
grant select on public.exchange_agreements to authenticated;

create or replace function public.create_exchange_agreement(target_conversation uuid, agreement_note text)
returns uuid language plpgsql security definer set search_path=public as $$
declare my_family uuid; other_family uuid; listing uuid; new_id uuid;
begin
 select fm.family_id into my_family from public.family_members fm where fm.user_id=auth.uid() limit 1;
 if auth.uid() is null or my_family is null then raise exception 'Family profile required'; end if;
 select c.listing_id, case when c.family_a=my_family then c.family_b when c.family_b=my_family then c.family_a else null end
 into listing, other_family from public.family_conversations c where c.id=target_conversation;
 if other_family is null then raise exception 'Not a conversation member'; end if;
 if char_length(trim(coalesce(agreement_note,''))) not between 3 and 500 then raise exception 'Agreement note must contain 3 to 500 characters'; end if;
 insert into public.exchange_agreements(conversation_id,listing_id,proposer_family,receiver_family,created_by,note)
 values(target_conversation,listing,my_family,other_family,auth.uid(),trim(agreement_note)) returning id into new_id;
 return new_id;
end; $$;

create or replace function public.accept_exchange_agreement(target_agreement uuid)
returns void language plpgsql security definer set search_path=public as $$
declare a public.exchange_agreements%rowtype; my_family uuid;
begin
 select family_id into my_family from public.family_members where user_id=auth.uid() limit 1;
 select * into a from public.exchange_agreements where id=target_agreement for update;
 if auth.uid() is null or my_family is null or a.id is null or my_family is distinct from a.receiver_family or a.status<>'proposed' then raise exception 'Agreement cannot be accepted'; end if;
 update public.exchange_agreements set status='accepted',updated_at=now() where id=target_agreement;
end; $$;

create or replace function public.reject_exchange_agreement(target_agreement uuid)
returns void language plpgsql security definer set search_path=public as $$
declare a public.exchange_agreements%rowtype; my_family uuid;
begin
 select family_id into my_family from public.family_members where user_id=auth.uid() limit 1;
 select * into a from public.exchange_agreements where id=target_agreement for update;
 if auth.uid() is null or my_family is null or a.id is null or my_family is distinct from a.receiver_family or a.status<>'proposed' then raise exception 'Agreement cannot be rejected'; end if;
 update public.exchange_agreements set status='rejected',updated_at=now() where id=target_agreement;
end; $$;

create or replace function public.confirm_exchange_handover(target_agreement uuid)
returns void language plpgsql security definer set search_path=public as $$
declare a public.exchange_agreements%rowtype; my_family uuid; p timestamptz; r timestamptz;
begin
 select family_id into my_family from public.family_members where user_id=auth.uid() limit 1;
 select * into a from public.exchange_agreements where id=target_agreement for update;
 if auth.uid() is null or my_family is null or a.id is null or my_family not in (a.proposer_family,a.receiver_family) or a.status<>'accepted' then raise exception 'Agreement is not ready for handover confirmation'; end if;
 p:=a.proposer_confirmed_at; r:=a.receiver_confirmed_at;
 if my_family=a.proposer_family then p:=now(); else r:=now(); end if;
 update public.exchange_agreements set proposer_confirmed_at=p,receiver_confirmed_at=r,
   status=case when p is not null and r is not null then 'completed' else 'accepted' end,updated_at=now()
 where id=target_agreement;
end; $$;

grant execute on function public.create_exchange_agreement(uuid,text) to authenticated;
grant execute on function public.accept_exchange_agreement(uuid) to authenticated;
grant execute on function public.reject_exchange_agreement(uuid) to authenticated;
grant execute on function public.confirm_exchange_handover(uuid) to authenticated;

-- Only signed-in parents may call mutation RPCs; table writes remain RPC-only.
revoke all on public.exchange_agreements from authenticated;
grant select on public.exchange_agreements to authenticated;
revoke all on function public.create_exchange_agreement(uuid,text) from public, anon;
revoke all on function public.accept_exchange_agreement(uuid) from public, anon;
revoke all on function public.reject_exchange_agreement(uuid) from public, anon;
revoke all on function public.confirm_exchange_handover(uuid) from public, anon;
notify pgrst, 'reload schema';
