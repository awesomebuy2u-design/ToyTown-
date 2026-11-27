-- Elevated access belongs to one live Auth session and an additional random proof.
-- The toy-town client never receives an elevated header or an account password.
create table private.guardian_pins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null,
  failures integer not null default 0,
  blocked_until timestamptz
);
create table private.guardian_sessions (
  session_id uuid primary key references auth.sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  token_digest bytea not null,
  active_until timestamptz not null,
  expires_at timestamptz not null
);
create index guardian_sessions_owner on private.guardian_sessions(user_id);
create table private.guardian_challenges (
  session_id uuid primary key references auth.sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  challenge_digest bytea not null unique,
  started_at timestamptz not null
);
create index guardian_challenges_owner on private.guardian_challenges(user_id);
revoke all on private.guardian_pins,private.guardian_sessions,private.guardian_challenges from public,anon,authenticated;

create function private.guardian_session_id() returns uuid language sql stable security invoker set search_path='' as $$
  select nullif(auth.jwt()->>'session_id','')::uuid
$$;
create function private.guardian_header() returns text language sql stable security invoker set search_path='' as $$
  select nullif(current_setting('request.headers',true),'')::jsonb->>'x-toytown-guardian'
$$;
create function private.guardian_valid() returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.guardian_sessions s
    where s.session_id=private.guardian_session_id() and s.user_id=auth.uid()
      and s.active_until>statement_timestamp() and s.expires_at>statement_timestamp()
      and s.token_digest=extensions.digest(private.guardian_header(),'sha256'))
$$;
create function private.guardian_has_pin() returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.guardian_pins where user_id=(select auth.uid()))
$$;
create function private.begin_guardian_setup() returns text language plpgsql security definer set search_path='' as $$
declare account uuid:=auth.uid(); sid uuid:=private.guardian_session_id(); challenge text:=encode(extensions.gen_random_bytes(32),'hex');
begin
  if not exists(select 1 from auth.sessions where id=sid and user_id=account) then raise insufficient_privilege; end if;
  insert into private.guardian_challenges(session_id,user_id,challenge_digest,started_at)
    values(sid,account,extensions.digest(challenge,'sha256'),clock_timestamp())
    on conflict(session_id) do update set challenge_digest=excluded.challenge_digest,started_at=excluded.started_at;
  return challenge;
end $$;
create function private.finish_guardian_setup(challenge text, new_pin text) returns void
language plpgsql security definer set search_path='' as $$
declare account uuid:=auth.uid(); proof_session uuid:=private.guardian_session_id();
  attempt private.guardian_challenges%rowtype; proof_time timestamptz; existing boolean;
begin
  if account is null or new_pin is null or new_pin !~ '^[0-9]{6}$' or length(challenge)<>64 then raise insufficient_privilege; end if;
  perform pg_advisory_xact_lock(hashtextextended(account::text, 274));
  select * into attempt from private.guardian_challenges where user_id=account
    and challenge_digest=extensions.digest(challenge,'sha256') for update;
  if not found or proof_session is null or proof_session=attempt.session_id
    or attempt.started_at<clock_timestamp()-interval '10 minutes' then raise insufficient_privilege; end if;
  select created_at into proof_time from auth.sessions where id=proof_session and user_id=account;
  if proof_time is null or proof_time<attempt.started_at then raise insufficient_privilege; end if;
  select exists(select 1 from private.guardian_pins where user_id=account) into existing;
  if not exists(select 1 from jsonb_array_elements(auth.jwt()->'amr') a
    where (a->>'method'='otp' or (not existing and a->>'method'='password'))
      and to_timestamp((a->>'timestamp')::double precision)>=date_trunc('second',attempt.started_at)) then raise insufficient_privilege; end if;
  insert into private.guardian_pins(user_id,pin_hash) values(account,extensions.crypt(new_pin,extensions.gen_salt('bf',10)))
    on conflict(user_id) do update set pin_hash=excluded.pin_hash,failures=0,blocked_until=null;
  delete from private.guardian_sessions where user_id=account;
  delete from private.guardian_challenges where user_id=account;
end $$;
create function private.unlock_guardian(entered_pin text) returns jsonb language plpgsql security definer set search_path='' as $$
declare account uuid:=auth.uid(); sid uuid:=private.guardian_session_id(); settings private.guardian_pins%rowtype;
  proof text; deadline timestamptz; instant timestamptz:=clock_timestamp();
begin
  if account is null or entered_pin is null or entered_pin !~ '^[0-9]{6}$'
    or not exists(select 1 from auth.sessions where id=sid and user_id=account) then return null; end if;
  select * into settings from private.guardian_pins where user_id=account for update;
  if not found or settings.blocked_until>instant then return null; end if;
  if extensions.crypt(entered_pin,settings.pin_hash)<>settings.pin_hash then
    update private.guardian_pins set
      failures=case when failures>=4 then 0 else failures+1 end,
      blocked_until=case when failures>=4 then instant+interval '15 minutes' else null end where user_id=account;
    return null;
  end if;
  update private.guardian_pins set failures=0,blocked_until=null where user_id=account;
  proof:=encode(extensions.gen_random_bytes(32),'hex'); deadline:=instant+interval '30 minutes';
  insert into private.guardian_sessions(session_id,user_id,token_digest,active_until,expires_at)
    values(sid,account,extensions.digest(proof,'sha256'),instant+interval '5 minutes',deadline)
    on conflict(session_id) do update set token_digest=excluded.token_digest,
      active_until=excluded.active_until,expires_at=excluded.expires_at;
  return jsonb_build_object('token',proof,'expires_at',deadline);
end $$;
create function private.touch_guardian() returns boolean language plpgsql security definer set search_path='' as $$
begin
  update private.guardian_sessions set active_until=least(expires_at,clock_timestamp()+interval '5 minutes')
    where session_id=private.guardian_session_id() and user_id=auth.uid()
      and active_until>clock_timestamp() and expires_at>clock_timestamp()
      and token_digest=extensions.digest(private.guardian_header(),'sha256');
  return found;
end $$;
create function private.lock_guardian() returns void language sql security definer set search_path='' as $$
  delete from private.guardian_sessions where session_id=private.guardian_session_id()
    and user_id=auth.uid() and token_digest=extensions.digest(private.guardian_header(),'sha256')
$$;
create function public.guardian_has_pin() returns boolean language sql stable security invoker set search_path='' as $$ select private.guardian_has_pin() $$;
create function public.begin_guardian_setup() returns text language sql security invoker set search_path='' as $$ select private.begin_guardian_setup() $$;
create function public.finish_guardian_setup(challenge text,new_pin text) returns void language sql security invoker set search_path='' as $$ select private.finish_guardian_setup(challenge,new_pin) $$;
create function public.unlock_guardian(entered_pin text) returns jsonb language sql security invoker set search_path='' as $$ select private.unlock_guardian(entered_pin) $$;
create function public.touch_guardian() returns boolean language sql security invoker set search_path='' as $$ select private.touch_guardian() $$;
create function public.lock_guardian() returns void language sql security invoker set search_path='' as $$ select private.lock_guardian() $$;
revoke all on function private.guardian_header(),private.guardian_session_id() from public,anon,authenticated;
do $grants$
declare signature text; ns text;
begin
  foreach signature in array array['guardian_has_pin()','begin_guardian_setup()','finish_guardian_setup(text,text)',
    'unlock_guardian(text)','touch_guardian()','lock_guardian()'] loop
    foreach ns in array array['private','public'] loop
      execute format('revoke all on function %I.%s from public,anon,authenticated',ns,signature);
      execute format('grant execute on function %I.%s to authenticated',ns,signature);
    end loop;
  end loop;
end $grants$;
revoke all on function private.guardian_valid() from public,anon;
grant execute on function private.guardian_valid() to authenticated;

-- Restrictive policies apply alongside the existing ownership policies. Triggers
-- also cover security-definer business functions which execute above ordinary RLS.
do $policies$
declare rel text;
begin
  foreach rel in array array['families','child_profiles','family_conversations','family_messages',
    'exchange_agreements','exchange_requests','family_notifications','conversation_user_state',
    'profiles','partner_products','partner_stores'] loop
    execute format('create policy guardian_session_required on public.%I as restrictive for all to authenticated
      using ((select private.guardian_valid())) with check ((select private.guardian_valid()))',rel);
  end loop;
end $policies$;
revoke select on public.partner_products,public.partner_stores from public,anon;
create policy guardian_memberships on public.family_members as restrictive for select to authenticated
  using(user_id=(select auth.uid()) or (select private.guardian_valid()));
create function private.require_guardian_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if current_setting('role',true) in ('anon','authenticated') and not private.guardian_valid() then
    raise exception 'GUARDIAN_PIN_REQUIRED' using errcode='42501';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function private.require_guardian_change() from public,anon,authenticated;
do $triggers$
declare rel text;
begin
  foreach rel in array array['families','family_members','child_profiles','listings','family_conversations',
    'family_messages','exchange_agreements','exchange_requests','conversation_user_state',
    'hidden_exchange_agreements','toy_listings'] loop
    execute format('create trigger guardian_change before %s on public.%I for each row
      execute function private.require_guardian_change()',
      case when rel='listings' then 'update or delete' else 'insert or update or delete' end,rel);
  end loop;
end $triggers$;
create policy new_drafts_only on public.listings as restrictive for insert to authenticated
  with check (status='pending' and deleted_at is null and coalesce(moderation_note,'')='');
create policy guardian_media_delete on storage.objects as restrictive for delete to authenticated
  using(bucket_id not in ('listing-images','toy-images') or (select private.guardian_valid()));

-- Both reads can return an existing row without firing a write trigger.
alter function public.start_listing_conversation(uuid) set schema private;
alter function private.start_listing_conversation(uuid) rename to start_verified_conversation;
revoke all on function private.start_verified_conversation(uuid) from public,anon,authenticated;
create function private.open_guardian_conversation(target_listing uuid) returns uuid
language plpgsql security definer set search_path='' as $$
begin
  if not private.guardian_valid() then raise insufficient_privilege; end if;
  return private.start_verified_conversation(target_listing);
end $$;
revoke all on function private.open_guardian_conversation(uuid) from public,anon;
grant execute on function private.open_guardian_conversation(uuid) to authenticated;
create function public.start_listing_conversation(target_listing uuid) returns uuid
language sql security invoker set search_path='' as $$ select private.open_guardian_conversation(target_listing) $$;
revoke all on function public.start_listing_conversation(uuid) from public,anon;
grant execute on function public.start_listing_conversation(uuid) to authenticated;
create or replace function public.my_hidden_exchange_agreements() returns table(agreement_id uuid)
language sql stable security definer set search_path='' as $$
  select h.agreement_id from public.hidden_exchange_agreements h
  where (select private.guardian_valid()) and h.user_id=(select auth.uid())
    and exists(select 1 from public.exchange_agreements a where a.id=h.agreement_id
      and (public.is_family_guardian(a.proposer_family) or public.is_family_guardian(a.receiver_family)));
$$;
create policy guardian_media_update on storage.objects as restrictive for update to authenticated
  using(bucket_id not in ('listing-images','toy-images') or (select private.guardian_valid()))
  with check(bucket_id not in ('listing-images','toy-images') or (select private.guardian_valid()));
