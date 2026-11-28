-- Support four-digit PINs while preserving existing six-digit hashes and older clients.
create or replace function private.finish_guardian_setup(challenge text, new_pin text) returns void
language plpgsql security definer set search_path='' as $$
declare account uuid:=auth.uid(); proof_session uuid:=private.guardian_session_id();
  attempt private.guardian_challenges%rowtype; proof_time timestamptz; existing boolean;
begin
  if account is null or new_pin is null or new_pin !~ '^([0-9]{4}|[0-9]{6})$' or length(challenge)<>64 then raise insufficient_privilege; end if;
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
create or replace function private.unlock_guardian(entered_pin text) returns jsonb language plpgsql security definer set search_path='' as $$
declare account uuid:=auth.uid(); sid uuid:=private.guardian_session_id(); settings private.guardian_pins%rowtype;
  proof text; deadline timestamptz; instant timestamptz:=clock_timestamp();
begin
  if account is null or entered_pin is null or entered_pin !~ '^([0-9]{4}|[0-9]{6})$'
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
