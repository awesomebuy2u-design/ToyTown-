-- Supplements the existing isolated schema with the Auth claims, roles and
-- marketplace objects used in deployed Supabase. No external accounts are read.
create schema extensions;
create extension pgcrypto with schema extensions;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb
$$;
create table auth.sessions(id uuid primary key, user_id uuid not null references auth.users, created_at timestamptz not null default clock_timestamp());
create schema storage;
create table storage.objects(id uuid primary key,bucket_id text);
alter table storage.objects enable row level security;
alter table public.families add column name text, add column guardian_name text, add column city text, add column created_by uuid;
create table public.child_profiles(id uuid primary key default gen_random_uuid());
create table public.profiles(id uuid primary key);
create table public.exchange_requests(id uuid primary key);
create table public.toy_listings(id uuid primary key);
create table public.partner_stores(id uuid primary key default gen_random_uuid(),name text, is_active boolean);
create table public.partner_products(id uuid primary key default gen_random_uuid(),store_id uuid references public.partner_stores, title text,product_url text,is_active boolean);
alter table public.partner_stores enable row level security;
alter table public.partner_products enable row level security;
create policy read_stores on public.partner_stores for select using(is_active);
create policy read_products on public.partner_products for select using(is_active);
grant select on public.partner_stores,public.partner_products to anon,authenticated;
create function public.start_listing_conversation(target_listing uuid) returns uuid language sql as $$
  select id from public.family_conversations where listing_id=target_listing limit 1
$$;
create role service_role bypassrls;
grant usage on schema public to service_role;
