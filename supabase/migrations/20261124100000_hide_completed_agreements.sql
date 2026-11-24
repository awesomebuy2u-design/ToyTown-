-- Hide an agreement only from the current adult account; preserve the transaction for the other family.
create table if not exists public.hidden_exchange_agreements (
  agreement_id uuid not null references public.exchange_agreements(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (agreement_id, user_id)
);
alter table public.hidden_exchange_agreements enable row level security;
revoke all on public.hidden_exchange_agreements from anon, authenticated;
create or replace function public.hide_own_exchange_agreement(target_agreement uuid)
returns void language plpgsql security definer set search_path = public as $$
declare a public.exchange_agreements%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into a from public.exchange_agreements where id = target_agreement;
  if a.id is null or not (public.is_family_guardian(a.proposer_family) or public.is_family_guardian(a.receiver_family)) then
    raise exception 'Not an agreement participant';
  end if;
  if a.status not in ('cancelled', 'rejected', 'completed') then
    raise exception 'Finish or cancel the agreement before hiding it';
  end if;
  insert into public.hidden_exchange_agreements(agreement_id, user_id)
    values (target_agreement, auth.uid()) on conflict do nothing;
end; $$;
revoke all on function public.hide_own_exchange_agreement(uuid) from public, anon;
grant execute on function public.hide_own_exchange_agreement(uuid) to authenticated;
create or replace function public.my_hidden_exchange_agreements()
returns table(agreement_id uuid) language sql stable security definer set search_path = public as $$
  select h.agreement_id from public.hidden_exchange_agreements h
  where h.user_id = auth.uid()
    and exists (select 1 from public.exchange_agreements a where a.id = h.agreement_id
      and (public.is_family_guardian(a.proposer_family) or public.is_family_guardian(a.receiver_family)));
$$;
revoke all on function public.my_hidden_exchange_agreements() from public, anon;
grant execute on function public.my_hidden_exchange_agreements() to authenticated;
