-- Isolated test database only. Seed two synthetic families before running.
-- Fixtures and notifications are rolled back. Production execution is blocked.
begin;
do $$
declare
  f uuid; g uuid; u uuid; v uuid; outsider uuid := gen_random_uuid();
  a uuid; b uuid; active_listing uuid; completed_listing uuid; extra uuid;
  c uuid; active_chat uuid; completed_chat uuid; active_agreement uuid; done_agreement uuid;
  mine uuid; theirs uuid; denied boolean; affected integer; listing_status text;
begin
  if current_setting('toytown.isolated_test_database',true) is distinct from 'on' then
    raise exception 'Run only in the isolated fixture database';
  end if;
  select family_id,user_id into f,u from public.family_members order by created_at limit 1;
  select family_id,user_id into g,v from public.family_members where family_id<>f order by created_at limit 1;
  if f is null or g is null then raise exception 'Fixture requires two families'; end if;
  insert into public.listings(family_id,title,condition,deal_type,city,status)
    values(f,'Delete fixture','used','gift','Полтава','approved') returning id into a;
  insert into public.listings(family_id,title,condition,deal_type,city,status)
    values(g,'Other fixture','used','gift','Київ','approved') returning id into b;
  insert into public.listings(family_id,title,condition,deal_type,city,status)
    values(f,'Active fixture','used','gift','Полтава','approved') returning id into active_listing;
  insert into public.listings(family_id,title,condition,deal_type,city,status)
    values(f,'Completed fixture','used','gift','Полтава','approved') returning id into completed_listing;
  insert into public.family_conversations(family_a,family_b,listing_id)
    values(least(f,g),greatest(f,g),a) returning id into c;
  insert into public.family_conversations(family_a,family_b,listing_id)
    values(least(f,g),greatest(f,g),active_listing) returning id into active_chat;
  insert into public.family_conversations(family_a,family_b,listing_id)
    values(least(f,g),greatest(f,g),completed_listing) returning id into completed_chat;
  insert into public.family_messages(conversation_id,sender_user_id,body)
    values(c,u,'Own rollback fixture') returning id into mine;
  insert into public.family_messages(conversation_id,sender_user_id,body)
    values(c,v,'Other rollback fixture') returning id into theirs;
  insert into public.exchange_agreements(conversation_id,listing_id,proposer_family,receiver_family,created_by,note)
    values(active_chat,active_listing,f,g,u,'Rollback test agreement') returning id into active_agreement;
  insert into public.exchange_agreements(conversation_id,listing_id,proposer_family,receiver_family,created_by,note)
    values(completed_chat,completed_listing,f,g,u,'Rollback completed agreement') returning id into done_agreement;
  update public.exchange_agreements set status='accepted' where id=done_agreement;
  update public.exchange_agreements set status='completed',proposer_confirmed_at=now(),receiver_confirmed_at=now() where id=done_agreement;

  perform set_config('request.jwt.claim.sub',u::text,true);
  execute 'set local role authenticated';
  denied := false;
  begin perform public.delete_own_message(theirs);
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'RPC deleted another author message'; end if;
  delete from public.family_messages where id=theirs;
  get diagnostics affected = row_count;
  if affected<>0 then raise exception 'Direct DELETE bypassed message ownership'; end if;
  perform public.delete_own_message(mine);
  if exists(select 1 from public.family_messages where id=mine) then raise exception 'Own message remains'; end if;
  if not exists(select 1 from public.family_messages where id=theirs) then raise exception 'Other message was lost'; end if;

  denied := false;
  begin perform public.delete_own_listing(b);
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Deleted another family listing'; end if;
  denied := false;
  begin perform public.delete_own_listing(active_listing);
  exception when object_not_in_prerequisite_state then denied := true; end;
  if not denied then raise exception 'Deleted listing with proposed agreement'; end if;
  perform public.delete_own_listing(a);
  perform public.delete_own_listing(a); -- Repeat requests are harmless.
  if not exists(select 1 from public.listings where id=a and status='archived' and deleted_at is not null) then raise exception 'Listing not removed persistently'; end if;
  if exists(select 1 from public.public_listings where id=a) then raise exception 'Deleted listing remains public'; end if;
  if exists(select 1 from public.family_shop_listings(f,50,0) where id=a) then raise exception 'Deleted listing remains in storefront'; end if;
  if not exists(select 1 from public.family_conversations where id=c and listing_id=a) then raise exception 'Conversation history lost'; end if;
  update public.listings set status='pending',deleted_at=null where id=a;
  get diagnostics affected = row_count;
  if affected<>0 then raise exception 'Direct update restored deleted listing'; end if;
  perform public.delete_own_listing(completed_listing);
  if not exists(select 1 from public.exchange_agreements where id=done_agreement and status='completed') then raise exception 'Completed history lost'; end if;

  perform set_config('request.jwt.claim.sub',v::text,true);
  if exists(select 1 from public.family_messages where id=mine) then raise exception 'Recipient still sees removed message'; end if;
  if not exists(select 1 from public.family_messages where id=theirs) then raise exception 'Recipient reply was removed'; end if;
  perform public.accept_exchange_agreement(active_agreement);
  perform set_config('request.jwt.claim.sub',u::text,true);
  denied := false;
  begin perform public.delete_own_listing(active_listing);
  exception when object_not_in_prerequisite_state then denied := true; end;
  if not denied then raise exception 'Deleted listing with accepted agreement'; end if;
  perform public.cancel_exchange_agreement(active_agreement);
  perform public.delete_own_listing(active_listing);
  if not exists(select 1 from public.exchange_agreements where id=active_agreement and status='cancelled') then raise exception 'Cancelled history lost'; end if;

  perform set_config('request.jwt.claim.sub',outsider::text,true);
  denied := false;
  begin perform public.delete_own_message(theirs);
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Outsider deleted chat message'; end if;
  denied := false;
  begin perform public.delete_own_listing(a);
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Outsider accessed deleted listing'; end if;
  execute 'reset role';

  foreach listing_status in array array['pending','rejected','archived'] loop
    insert into public.listings(family_id,title,condition,deal_type,city,status)
      values(f,'Other status fixture','used','gift','Полтава',listing_status) returning id into extra;
    perform set_config('request.jwt.claim.sub',u::text,true);
    execute 'set local role authenticated';
    perform public.delete_own_listing(extra);
    if not exists(select 1 from public.listings where id=extra and deleted_at is not null) then raise exception 'Status % was not removed',listing_status; end if;
    execute 'reset role';
  end loop;
  if has_function_privilege('anon','public.delete_own_message(uuid)','execute')
    or has_function_privilege('anon','public.delete_own_listing(uuid)','execute')
    or has_function_privilege('anon','private.delete_family_listing(uuid)','execute') then
    raise exception 'Deletion callable anonymously';
  end if;
end;
$$;
select 'PASS: author/family ownership, direct RLS, persistent removal, both chat participants, all listing statuses, active agreement guards and preserved history' as result;
rollback;
