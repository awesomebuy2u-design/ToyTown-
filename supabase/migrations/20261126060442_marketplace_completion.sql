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
