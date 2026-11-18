-- ToyTown v0.7.6: secure in-app notifications for adult family accounts.
create table if not exists public.family_notifications (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  body text not null default '' check (char_length(body) <= 500),
  kind text not null default 'info' check (kind in ('info','approved','rejected')),
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists family_notifications_feed_idx on public.family_notifications(family_id, created_at desc);
alter table public.family_notifications enable row level security;
create policy "family members read own notifications" on public.family_notifications
  for select to authenticated using (public.is_family_guardian(family_id));
create policy "family members mark own notifications read" on public.family_notifications
  for update to authenticated using (public.is_family_guardian(family_id))
  with check (public.is_family_guardian(family_id));
revoke all on public.family_notifications from anon, authenticated;
grant select on public.family_notifications to authenticated;
grant update (is_read) on public.family_notifications to authenticated;

create or replace function public.notify_listing_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    insert into public.family_notifications(family_id,title,body,kind)
    values (new.family_id, 'Оголошення надіслано', '«' || left(new.title, 80) || '» очікує перевірки дорослим.', 'info');
  elsif old.status is distinct from new.status and new.status in ('approved','rejected') then
    insert into public.family_notifications(family_id,title,body,kind)
    values (new.family_id,
      case when new.status = 'approved' then 'Оголошення підтверджено' else 'Оголошення відхилено' end,
      'Статус оголошення «' || left(new.title, 80) || '» змінено. ' || coalesce(new.moderation_note,''),
      new.status);
  end if;
  return new;
end; $$;
drop trigger if exists listings_notify_family on public.listings;
create trigger listings_notify_family after insert or update of status on public.listings
for each row execute function public.notify_listing_status_change();

create or replace function public.cancel_exchange_agreement(target_agreement uuid)
returns void language plpgsql security definer set search_path=public as $$
declare a public.exchange_agreements%rowtype;
begin
 select * into a from public.exchange_agreements where id=target_agreement for update;
 if auth.uid() is null or a.id is null or not (public.is_family_guardian(a.proposer_family) or public.is_family_guardian(a.receiver_family)) then raise exception 'Not an agreement participant'; end if;
 if a.status not in ('proposed','accepted') or a.proposer_confirmed_at is not null or a.receiver_confirmed_at is not null then raise exception 'Cannot cancel after handover confirmation'; end if;
 update public.exchange_agreements set status='cancelled',updated_at=now() where id=a.id;
end; $$;
revoke all on function public.cancel_exchange_agreement(uuid) from public,anon;
grant execute on function public.cancel_exchange_agreement(uuid) to authenticated;

create or replace function public.guard_agreement_listing()
returns trigger language plpgsql security definer set search_path=public as $$
declare listing_status text;
begin
 if (TG_OP='INSERT' or (new.status='accepted' and old.status='proposed')) then
  select status into listing_status from public.listings where id=new.listing_id for update;
  if listing_status is distinct from 'approved' then raise exception 'Listing is no longer available'; end if;
  if exists(select 1 from public.exchange_agreements where listing_id=new.listing_id and id<>new.id and status in ('accepted','completed')) then raise exception 'Listing already reserved'; end if;
 end if;
 return new;
end; $$;
create trigger guard_agreement_listing before insert or update of status on public.exchange_agreements for each row execute function public.guard_agreement_listing();

create or replace function public.notify_agreement_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare heading text;
begin
 if TG_OP='INSERT' then
  insert into public.family_notifications(family_id,title,body) values(new.receiver_family,'Нова пропозиція щодо іграшки','Відкрийте вкладку «Угоди», щоб переглянути умови та відповісти.');
 elsif old.status is distinct from new.status then
  heading:=case new.status when 'accepted' then 'Домовленість погоджено' when 'rejected' then 'Пропозицію відхилено' when 'cancelled' then 'Домовленість скасовано' when 'completed' then 'Передачу завершено' else 'Статус домовленості змінено' end;
  insert into public.family_notifications(family_id,title,body) values(new.proposer_family,heading,'Подробиці у вкладці «Угоди».');
  insert into public.family_notifications(family_id,title,body) values(new.receiver_family,heading,'Подробиці у вкладці «Угоди».');
  if new.status='completed' then
   update public.listings set status='archived' where id=new.listing_id;
   update public.exchange_agreements set status='cancelled',updated_at=now() where listing_id=new.listing_id and id<>new.id and status='proposed';
  end if;
 end if;
 return new;
end; $$;
create trigger notify_agreement_change after insert or update of status on public.exchange_agreements for each row execute function public.notify_agreement_change();

create or replace function public.notify_family_message()
returns trigger language plpgsql security definer set search_path=public as $$
declare recipient uuid; a uuid; b uuid;
begin
 select family_a,family_b into a,b from public.family_conversations where id=new.conversation_id;
 if exists(select 1 from public.family_members where family_id=a and user_id=new.sender_user_id) then recipient:=b; else recipient:=a; end if;
 insert into public.family_notifications(family_id,title,body) values(recipient,'Нове повідомлення','Відкрийте вкладку «Чати», щоб прочитати повідомлення іншої родини.');
 return new;
end; $$;
create trigger notify_family_message after insert on public.family_messages for each row execute function public.notify_family_message();
revoke all on function public.notify_listing_status_change() from public,anon,authenticated;
revoke all on function public.guard_agreement_listing() from public,anon,authenticated;
revoke all on function public.notify_agreement_change() from public,anon,authenticated;
revoke all on function public.notify_family_message() from public,anon,authenticated;
notify pgrst,'reload schema';
