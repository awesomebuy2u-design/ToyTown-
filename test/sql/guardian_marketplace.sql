begin;
do $$
<<guardian_marketplace>>
declare
  u uuid; v uuid; f uuid; g uuid; sid uuid:=gen_random_uuid(); proof uuid:=gen_random_uuid();
  other uuid:=gen_random_uuid(); token text; challenge text; item uuid; b uuid; convo uuid:=gen_random_uuid();
  a uuid; claims jsonb; store_id uuid; result integer;
  recovery_proof uuid:=gen_random_uuid(); recovery_claims jsonb;
begin
  if current_setting('toytown.isolated_test_database',true) is distinct from 'on' then raise exception 'Isolated fixture required'; end if;
  select user_id,family_id into u,f from public.family_members order by family_id limit 1;
  select user_id,family_id into v,g from public.family_members where family_id<>f limit 1;
  insert into auth.sessions(id,user_id) values(sid,u),(other,v);
  insert into public.listings(family_id,title,condition,deal_type,city,status,brand,model_code)
    values(f,'Family toy','used','sale','Полтава','approved','Toy','A1') returning id into item;
  insert into public.family_conversations(id,family_a,family_b,listing_id) values(convo,least(f,g),greatest(f,g),item);
  insert into public.exchange_agreements(conversation_id,listing_id,proposer_family,receiver_family,created_by,note)
    values(convo,item,f,g,u,'Test agreement') returning id into a;
  update public.exchange_agreements set status='cancelled' where id=a;
  insert into public.partner_stores(name,is_active,offer_host) values('Fixture shop',true,'shop.example') returning id into store_id;
  insert into public.partner_products(store_id,title,product_url,is_active,brand,model_code,price_kopiykas,checked_at,in_stock)
    values(store_id,'Verified','https://shop.example/toy',true,'toy','a1',9900,now(),true),
    (store_id,'Different','https://shop.example/other',true,'toy','b2',5000,now(),true),
    (store_id,'Old','https://shop.example/old',true,'toy','a1',1000,now()-interval '25 hours',true);
  execute 'set local role service_role';
  result:=public.replace_partner_feed(store_id,now()-interval '2 minutes',
    '[{"source_id":"prev","title":"Previous","url":"https://shop.example/prev","price":9000,"available":true}]'::jsonb);
  if result<>1 then raise exception 'Partner feed import failed'; end if;
  result:=public.replace_partner_feed(store_id,now()-interval '1 minute',
    '[{"source_id":"next","title":"Next","url":"https://shop.example/next","price":10000,"available":true}]'::jsonb);
  if result<>1 or exists(select 1 from public.partner_products p where p.store_id=guardian_marketplace.store_id and source_id='prev' and is_active)
    then raise exception 'Partner feed retained a removed offer'; end if;
  begin
    perform public.replace_partner_feed(store_id,now(),
      '[{"source_id":"bad","title":"Bad","url":"https://other.example/next","price":10000,"available":true}]'::jsonb);
    raise data_exception;
  exception when raise_exception then null; end;
  if not exists(select 1 from public.partner_products where source_id='next' and is_active)
    then raise exception 'Malformed feed damaged the previous catalog'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',u::text,true);
  claims:=jsonb_build_object('sub',u,'session_id',sid);
  perform set_config('request.jwt.claims',claims::text,true);
  execute 'set local role authenticated';
  begin perform public.replace_partner_feed(store_id,now(),'[]'::jsonb); raise exception 'Child imported feed';
  exception when insufficient_privilege then null; end;
  challenge:=public.begin_guardian_setup();
  begin perform public.finish_guardian_setup(challenge,'555111'); raise exception 'Unverified PIN enrollment accepted';
  exception when insufficient_privilege then null; end;
  insert into public.listings(family_id,title,condition,deal_type,city,preferred_shelf)
    values(f,'Shop draft','used','gift','Полтава',2) returning id into b;
  if exists(select 1 from public.exchange_agreements) or exists(select 1 from public.partner_offers()) then raise exception 'Child accessed adult data'; end if;
  begin perform public.delete_own_listing(item); raise exception 'Child removed listing'; exception when insufficient_privilege then null; end;
  begin perform public.start_listing_conversation(item); raise exception 'Child opened conversation'; exception when insufficient_privilege then null; end;
  begin perform public.hide_own_exchange_agreement(a); raise exception 'Child hid agreement'; exception when insufficient_privilege then null; end;
  insert into public.saved_listings values(f,item);
  execute 'reset role';
  insert into auth.sessions(id,user_id) values(proof,u);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id',proof,'amr',jsonb_build_array(
    jsonb_build_object('method','password','timestamp',floor(extract(epoch from clock_timestamp())))))::text,true);
  execute 'set local role authenticated';
  perform public.finish_guardian_setup(challenge,'555111');
  if not public.guardian_has_pin() then raise exception 'PIN not enrolled'; end if;
  perform set_config('request.jwt.claims',claims::text,true);
  for i in 1..5 loop perform public.unlock_guardian('000000'); end loop;
  if public.unlock_guardian('555111') is not null then raise exception 'Rate limit failed'; end if;
  execute 'reset role';
  update private.guardian_pins set blocked_until=clock_timestamp()-interval '1 minute' where user_id=u;
  execute 'set local role authenticated';
  token:=public.unlock_guardian('555111')->>'token';
  if token is null then raise exception 'Verified PIN rejected'; end if;
  perform set_config('request.headers',jsonb_build_object('x-toytown-guardian',token)::text,true);
  if not private.guardian_valid() then raise exception 'Guardian proof rejected'; end if;
  perform public.hide_own_exchange_agreement(a); perform public.hide_own_exchange_agreement(a);
  if (select count(*) from public.my_hidden_exchange_agreements())<>1 then raise exception 'Agreement hiding failed'; end if;
  if (select count(*) from public.partner_offers(item))<>1 then raise exception 'Incorrect partner matching or expiry'; end if;
  if not public.touch_guardian() then raise exception 'Guardian renewal failed'; end if;
  perform set_config('request.jwt.claim.sub',v::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id',other)::text,true);
  if private.guardian_valid() or exists(select 1 from public.saved_listings)
    or exists(select 1 from public.my_hidden_exchange_agreements()) then raise exception 'Family isolation failed'; end if;
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',claims::text,true);
  execute 'reset role';
  update private.guardian_sessions set active_until=clock_timestamp()-interval '1 second' where session_id=sid;
  execute 'set local role authenticated';
  if public.touch_guardian() then raise exception 'Expired session was renewed'; end if;
  token:=public.unlock_guardian('555111')->>'token';
  perform set_config('request.headers',jsonb_build_object('x-toytown-guardian',token)::text,true);
  perform public.lock_guardian();
  if private.guardian_valid() then raise exception 'Explicit lock failed'; end if;
  token := public.unlock_guardian('555111')->>'token';
  perform set_config('request.headers',jsonb_build_object('x-toytown-guardian',token)::text,true);
  challenge := public.begin_guardian_setup();
  execute 'reset role';
  insert into auth.sessions(id,user_id) values(recovery_proof,u);
  recovery_claims := jsonb_build_object('session_id', recovery_proof, 'amr', jsonb_build_array(
    jsonb_build_object('method','otp','timestamp',floor(extract(epoch from clock_timestamp())))));
  perform set_config('request.jwt.claims',replace(recovery_claims::text,'"otp"','"password"'),true);
  execute 'set local role authenticated';
  begin
    perform public.finish_guardian_setup(challenge,'444222');
    raise exception 'A password could replace an existing PIN';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claims',recovery_claims::text,true);
  perform public.finish_guardian_setup(challenge,'444222');
  begin
    perform public.finish_guardian_setup(challenge,'123456');
    raise exception 'An already used email challenge accepted';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claims',claims::text,true);
  if private.guardian_valid() then raise exception 'Recovery retained an elevated session'; end if;
  if public.unlock_guardian('555111') is not null or public.unlock_guardian('444222') is null then
    raise exception 'Recovery did not replace the PIN';
  end if;
  execute 'reset role';
  update public.listings set status='approved' where id=b;
  if (select placements->>b::text from public.family_shop_layouts where family_id=f) is distinct from '2' then raise exception 'Approval lost requested shelf'; end if;
end $$;
select 'PASS: two-family guardian enrollment and recovery, PIN attempts, scoped access, idle lock, child drafts, shelves, bookmarks, hidden agreements and partner offers' as result;
rollback;
