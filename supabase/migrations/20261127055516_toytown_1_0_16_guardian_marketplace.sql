-- Store only the listing reference. Existing families and their inventory are preserved.
create table public.saved_listings (
  family_id uuid not null references public.families(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  primary key (family_id, listing_id)
);
create index saved_listings_listing_idx on public.saved_listings(listing_id);
alter table public.saved_listings enable row level security;
revoke all on public.saved_listings from public, anon, authenticated;
grant select, insert, delete on public.saved_listings to authenticated;
create policy "read own bookmarks" on public.saved_listings for select to authenticated
  using (public.is_family_guardian(family_id));
create policy "bookmark published toys" on public.saved_listings for insert to authenticated
  with check (public.is_family_guardian(family_id) and exists
    (select 1 from public.listings l where l.id=listing_id and l.status='approved' and l.deleted_at is null));
create policy "remove own bookmarks" on public.saved_listings for delete to authenticated
  using (public.is_family_guardian(family_id));

alter table public.listings
  add column brand text check (char_length(brand) <= 80),
  add column model_code text check (char_length(model_code) <= 80),
  add column preferred_shelf integer check (preferred_shelf between 0 and 2);
alter table public.partner_stores add column offer_host text
  check (offer_host ~ '^[a-z0-9][a-z0-9.-]*[.][a-z]{2,}$');
alter table public.partner_products
  add column brand text,
  add column model_code text,
  add column price_kopiykas integer check (price_kopiykas > 0),
  add column checked_at timestamptz,
  add column in_stock boolean not null default false;
create index partner_product_model_idx on public.partner_products(lower(btrim(brand)), lower(btrim(model_code)));

create function public.partner_offers(target_listing uuid default null, search_term text default '', page_offset integer default 0)
returns table(id uuid, store text, title text, brand text, model text, price_kopiykas integer,
  affiliate_url text, allowed_host text, checked_at timestamptz, in_stock boolean)
language sql stable security invoker set search_path = '' as $$
  select p.id, s.name, p.title, p.brand, p.model_code, p.price_kopiykas,
    p.product_url, s.offer_host, p.checked_at, p.in_stock
  from public.partner_products p join public.partner_stores s on s.id=p.store_id
  where p.is_active and s.is_active and p.in_stock and p.price_kopiykas>0
    and p.checked_at between now()-interval '24 hours' and now()
    and p.product_url like 'https://%/%'
    and lower(split_part(substr(p.product_url,9),'/',1))=s.offer_host
    and (target_listing is null or exists (select 1 from public.listings l
      where l.id=target_listing and l.deleted_at is null
        and nullif(lower(btrim(l.brand)), '')=lower(btrim(p.brand))
        and nullif(lower(btrim(l.model_code)), '')=lower(btrim(p.model_code))))
    and (coalesce(search_term,'')='' or strpos(lower(p.title||' '||s.name), lower(left(search_term,80)))>0)
  order by p.price_kopiykas, p.id limit 30 offset greatest(coalesce(page_offset,0),0)
$$;
revoke all on function public.partner_offers(uuid,text,integer) from public,anon;
grant execute on function public.partner_offers(uuid,text,integer) to authenticated;

create function private.my_family_city() returns text language sql stable security definer set search_path='' as $$
  select f.city from public.family_members m join public.families f on f.id=m.family_id
  where m.user_id=(select auth.uid()) order by m.created_at, m.family_id limit 1
$$;
revoke all on function private.my_family_city() from public,anon;
grant execute on function private.my_family_city() to authenticated;
create function public.my_family_city() returns text language sql stable security invoker set search_path='' as $$
  select private.my_family_city()
$$;
revoke all on function public.my_family_city() from public,anon;
grant execute on function public.my_family_city() to authenticated;

create function public.save_family_profile(family_name text, adult_name text, settlement text)
returns uuid language plpgsql security invoker set search_path='' as $$
declare account uuid := auth.uid(); family uuid;
begin
  if account is null or nullif(btrim(family_name),'') is null or nullif(btrim(adult_name),'') is null
      or nullif(btrim(settlement),'') is null then raise exception 'Missing family details'; end if;
  perform pg_advisory_xact_lock(hashtextextended(account::text, 271));
  select family_id into family from public.family_members where user_id=account order by created_at,family_id limit 1;
  if family is null then
    insert into public.families(name,guardian_name,city,created_by)
      values(btrim(family_name),btrim(adult_name),btrim(settlement),account) returning id into family;
    insert into public.family_members(family_id,user_id,role) values(family,account,'guardian');
  else
    update public.families set name=btrim(family_name), guardian_name=btrim(adult_name), city=btrim(settlement)
      where id=family;
    if not found then raise exception 'Family unavailable' using errcode='42501'; end if;
  end if;
  return family;
end $$;
revoke all on function public.save_family_profile(text,text,text) from public,anon;
grant execute on function public.save_family_profile(text,text,text) to authenticated;

create function private.place_approved_shelf_toy() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status='approved' and old.status is distinct from 'approved' and new.preferred_shelf is not null then
    insert into public.family_shop_layouts(family_id,shelf_count,placements)
      values(new.family_id,3,jsonb_build_object(new.id::text,new.preferred_shelf))
      on conflict(family_id) do update set placements=public.family_shop_layouts.placements||
        jsonb_build_object(new.id::text,least(new.preferred_shelf,public.family_shop_layouts.shelf_count-1));
  end if;
  return new;
end $$;
revoke all on function private.place_approved_shelf_toy() from public,anon,authenticated;
create trigger place_approved_shelf_toy after update of status on public.listings
  for each row execute function private.place_approved_shelf_toy();

-- Registered stores can be refreshed independently from a complete supplier feed.
alter table public.partner_stores add column feed_checked_at timestamptz;
alter table public.partner_products add column source_id text;
create unique index partner_product_external_id on public.partner_products(store_id, source_id);

create function public.replace_partner_feed(target_store uuid, observed_at timestamptz, offers jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare shop public.partner_stores%rowtype; entry_count integer;
begin
  if observed_at is null or observed_at not between now()-interval '24 hours' and now()
      or jsonb_typeof(offers) is distinct from 'array' then raise exception 'Invalid feed header'; end if;
  entry_count := jsonb_array_length(offers);
  if entry_count not between 1 and 50000 then raise exception 'Incomplete or oversized feed'; end if;
  select * into strict shop from public.partner_stores where id=target_store and is_active for update;
  if shop.offer_host is null then raise exception 'Store has no approved offer host'; end if;
  if shop.feed_checked_at >= observed_at then return 0; end if;
  if exists(select 1 from jsonb_to_recordset(offers) as r(source_id text,title text,url text,price integer,available boolean)
    where nullif(btrim(r.source_id),'') is null or nullif(btrim(r.title),'') is null
      or r.price is null or r.price<=0 or r.available is null or r.url is null
      or r.url not like 'https://%/%' or lower(split_part(substr(r.url,9),'/',1))<>shop.offer_host)
    then raise exception 'Invalid partner offer'; end if;
  insert into public.partner_products(store_id,source_id,title,product_url,is_active,brand,model_code,price_kopiykas,checked_at,in_stock)
    select target_store,r.source_id,r.title,r.url,true,r.brand,r.model,r.price,observed_at,r.available
    from jsonb_to_recordset(offers) as r(source_id text,title text,url text,brand text,model text,price integer,available boolean)
    on conflict(store_id,source_id) do update set title=excluded.title,product_url=excluded.product_url,
      is_active=true,brand=excluded.brand,model_code=excluded.model_code,price_kopiykas=excluded.price_kopiykas,
      checked_at=excluded.checked_at,in_stock=excluded.in_stock;
  update public.partner_products set is_active=false,in_stock=false
    where store_id=target_store and source_id is not null and checked_at<observed_at;
  update public.partner_stores set feed_checked_at=observed_at where id=target_store;
  return entry_count;
end $$;
revoke all on function public.replace_partner_feed(uuid,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.replace_partner_feed(uuid,timestamptz,jsonb) to service_role;
grant select, update on public.partner_stores to service_role;
grant select, insert, update on public.partner_products to service_role;


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
