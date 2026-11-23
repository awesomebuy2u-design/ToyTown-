-- Minimal pre-1.0.14 schema for an empty, isolated Postgres database only.
-- Ownership policies and the public projection match the deployed schema.
create role anon;
create role authenticated;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
grant usage on schema auth,public to authenticated,anon;
create table public.families(id uuid primary key default gen_random_uuid());
create table public.family_members(
  family_id uuid references public.families(id), user_id uuid references auth.users(id),
  role text not null default 'guardian' check(role in ('guardian','co_guardian')),
  created_at timestamptz not null default now(), primary key(family_id,user_id));
create function public.is_family_guardian(target_family uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.family_members where family_id=target_family and user_id=auth.uid());
$$;
create table public.listings(
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
  title text not null check(char_length(title) between 2 and 80), description text not null default '',
  category text not null default 'Інше', condition text not null check(condition in ('new','used')),
  deal_type text not null check(deal_type in ('gift','exchange','sale')), city text not null,
  price integer, photo_path text, moderation_note text,
  status text not null default 'pending' check(status in ('pending','approved','rejected','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.family_conversations(
  id uuid primary key default gen_random_uuid(), family_a uuid not null references public.families(id),
  family_b uuid not null references public.families(id), listing_id uuid references public.listings(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create function public.is_conversation_member(target_conversation uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.family_conversations where id=target_conversation
    and (public.is_family_guardian(family_a) or public.is_family_guardian(family_b)));
$$;
create table public.family_messages(
  id uuid primary key default gen_random_uuid(), conversation_id uuid not null references public.family_conversations(id) on delete cascade,
  sender_user_id uuid not null references auth.users(id), body text not null check(char_length(body) between 1 and 1000),
  created_at timestamptz not null default now());
alter table public.listings enable row level security;
alter table public.family_messages enable row level security;
alter table public.family_conversations enable row level security;
create policy owner_read on public.listings for select to authenticated using(public.is_family_guardian(family_id));
create policy public_read on public.listings for select to anon,authenticated using(status='approved');
create policy owner_insert on public.listings for insert to authenticated with check(public.is_family_guardian(family_id) and status='pending');
create policy owner_edit on public.listings for update to authenticated
  using(public.is_family_guardian(family_id) and status in ('pending','rejected'))
  with check(public.is_family_guardian(family_id) and status in ('pending','rejected'));
create policy owner_delete_pending on public.listings for delete to authenticated
  using(public.is_family_guardian(family_id) and status in ('pending','rejected'));
create policy chat_read on public.family_conversations for select to authenticated
  using(public.is_family_guardian(family_a) or public.is_family_guardian(family_b));
create policy "adult family members read conversation messages" on public.family_messages for select to authenticated using(public.is_conversation_member(conversation_id));
create policy message_insert on public.family_messages for insert to authenticated
  with check(sender_user_id=auth.uid() and public.is_conversation_member(conversation_id));
grant select,insert,update,delete on public.listings,public.family_messages to authenticated;
grant select on public.family_conversations,public.family_members to authenticated;
grant select on public.listings to anon;
create view public.public_listings with(security_invoker=true) as
  select id,title,description,category,condition,deal_type,city,price,photo_path,created_at
  from public.listings where status='approved';
grant select on public.public_listings to anon,authenticated;
create table public.family_world_progress(
  family_id uuid primary key references public.families(id), shop_theme text default 'mint',
  shop_front text default 'classic',decorated boolean default false,flowers boolean default false,awning boolean default false);

-- No names, contacts, user messages or production identifiers are imported.
do $$ declare u uuid; f uuid; begin
  for i in 1..2 loop
    u:=gen_random_uuid(); f:=gen_random_uuid();
    insert into auth.users values(u); insert into public.families values(f);
    insert into public.family_members(family_id,user_id) values(f,u);
  end loop;
end; $$;
select set_config('toytown.isolated_test_database','on',false);
