-- Isolated synthetic database only. This never runs against Supabase.
begin;
do $$
declare f uuid; g uuid; u uuid; v uuid; c uuid; listing uuid; agreement uuid;
  old_a uuid; old_b uuid; fresh uuid; denied boolean; total integer;
begin
  if current_setting('toytown.isolated_test_database',true) is distinct from 'on' then raise exception 'Isolated database required'; end if;
  select family_id,user_id into f,u from public.family_members order by created_at limit 1;
  select family_id,user_id into g,v from public.family_members where family_id<>f order by created_at limit 1;
  insert into public.listings(family_id,title,condition,deal_type,city,status)
    values(f,'Chat fixture','used','gift','Полтава','approved') returning id into listing;
  insert into public.family_conversations(family_a,family_b,listing_id)
    values(least(f,g),greatest(f,g),listing) returning id into c;
  insert into public.family_messages(conversation_id,sender_user_id,body) values(c,u,'Old mine') returning id into old_a;
  insert into public.family_messages(conversation_id,sender_user_id,body) values(c,v,'Old reply') returning id into old_b;
  insert into public.exchange_agreements(conversation_id,listing_id,proposer_family,receiver_family,created_by,note)
    values(c,listing,f,g,u,'Existing agreement') returning id into agreement;
  perform set_config('request.jwt.claim.sub',u::text,true);
  execute 'set local role authenticated';
  perform public.clear_own_conversation(c);
  perform public.clear_own_conversation(c);
  if not exists(select 1 from public.conversation_user_state where conversation_id=c and user_id=u and hidden) then raise exception 'Chat not hidden'; end if;
  select count(*) into total from public.family_messages where conversation_id=c;
  if total<>0 then raise exception 'Cleared history remains visible to clearer'; end if;
  if not exists(select 1 from public.exchange_agreements where id=agreement and status='proposed') then raise exception 'Agreement lost'; end if;
  denied:=false;
  begin update public.conversation_user_state set hidden=false where conversation_id=c;
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'Clearing state is directly writable'; end if;
  perform set_config('request.jwt.claim.sub',v::text,true);
  if exists(select 1 from public.conversation_user_state where conversation_id=c) then raise exception 'Other account clearing state exposed'; end if;
  select count(*) into total from public.family_messages where conversation_id=c;
  if total<>2 then raise exception 'Other participant lost history'; end if;
  insert into public.family_messages(conversation_id,sender_user_id,body,created_at)
    values(c,v,'Fresh reply','2000-01-01'::timestamptz) returning id into fresh;
  perform set_config('request.jwt.claim.sub',u::text,true);
  if not exists(select 1 from public.conversation_user_state where conversation_id=c and not hidden) then raise exception 'New message did not reopen chat'; end if;
  select count(*) into total from public.family_messages where conversation_id=c;
  if total<>1 or not exists(select 1 from public.family_messages where id=fresh) then raise exception 'Old history reappeared or fresh message was hidden'; end if;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  denied:=false;
  begin perform public.clear_own_conversation(c);
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'Outsider cleared chat'; end if;
  execute 'reset role';
  if (select count(*) from public.family_messages where conversation_id=c)<>3 then raise exception 'Conversation was physically deleted'; end if;
  if has_function_privilege('anon','public.clear_own_conversation(uuid)','execute') then raise exception 'Anonymous clearing allowed'; end if;
end; $$;
select 'PASS: whole chat clearing, per-user history and inbox, counterpart preservation, agreement preservation, new message reopening and outsider denial' as result;
rollback;
