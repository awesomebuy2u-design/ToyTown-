-- Empty isolated fixture database only; no production accounts are used.
begin;
do $$
declare f uuid; g uuid; u uuid; v uuid; a uuid; b uuid; pending uuid; foreign_toy uuid;
  data jsonb; denied boolean; affected integer; bad jsonb;
begin
  if current_setting('toytown.isolated_test_database',true) is distinct from 'on' then
    raise exception 'Run only in the isolated fixture database';
  end if;
  select family_id,user_id into f,u from public.family_members order by created_at limit 1;
  select family_id,user_id into g,v from public.family_members where family_id<>f order by created_at limit 1;
  insert into public.listings(family_id,title,condition,deal_type,city,status)
    values(f,'Shelf bear','used','gift','Полтава','approved') returning id into a;
  insert into public.listings(family_id,title,condition,deal_type,city,status)
    values(f,'Shelf car','used','gift','Полтава','approved') returning id into b;
  insert into public.listings(family_id,title,condition,deal_type,city,status)
    values(f,'Pending fixture','used','gift','Полтава','pending') returning id into pending;
  insert into public.listings(family_id,title,condition,deal_type,city,status)
    values(g,'Foreign fixture','used','gift','Київ','approved') returning id into foreign_toy;
  perform set_config('request.jwt.claim.sub',u::text,true);
  execute 'set local role authenticated';
  data:=public.family_shop_layout(f);
  if data->>'shelf_count'<>'3' or data->'placements'<>'{}'::jsonb then raise exception 'Wrong initial shelves'; end if;
  insert into public.family_shop_layouts(family_id,shelf_count,placements)
    values(f,3,jsonb_build_object(a::text,0,b::text,2));
  update public.family_shop_layouts set shelf_count=2,placements=jsonb_build_object(a::text,1,b::text,0) where family_id=f;
  data:=public.family_shop_layout(f);
  if data->>'shelf_count'<>'2' or data->'placements'->>a::text<>'1' then raise exception 'Arrangement did not persist'; end if;
  for bad in select unnest(array[
    jsonb_build_object(pending::text,0), jsonb_build_object(foreign_toy::text,0),
    jsonb_build_object(a::text,2), jsonb_build_object(a::text,'0'),
    jsonb_build_object(a::text,-1), '[]'::jsonb]) loop
    denied:=false;
    begin update public.family_shop_layouts set placements=bad where family_id=f;
    exception when insufficient_privilege or check_violation then denied:=true; end;
    if not denied then raise exception 'Invalid placement accepted'; end if;
  end loop;
  denied:=false;
  begin insert into public.family_shop_layouts(family_id,shelf_count,placements) values(g,3,'{}');
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'Cross-family insert allowed'; end if;
  perform set_config('request.jwt.claim.sub',v::text,true);
  if exists(select 1 from public.family_shop_layouts where family_id=f) then raise exception 'Raw arrangement visible to another family'; end if;
  data:=public.family_shop_layout(f);
  if data->'placements'->>a::text<>'1' or data->'placements'->>b::text<>'0' then raise exception 'Visitors see wrong shelves'; end if;
  update public.family_shop_layouts set shelf_count=1 where family_id=f;
  get diagnostics affected=row_count;
  if affected<>0 then raise exception 'Cross-family update allowed'; end if;
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform public.delete_own_listing(a);
  perform set_config('request.jwt.claim.sub',v::text,true);
  data:=public.family_shop_layout(f);
  if data->'placements' ? a::text or not (data->'placements' ? b::text) then raise exception 'Removed toy still on public shelf'; end if;
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform public.delete_own_listing(b);
  perform set_config('request.jwt.claim.sub',v::text,true);
  denied:=false;
  begin perform public.family_shop_layout(f);
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'Unpublished shop exposed'; end if;
  execute 'reset role';
  if has_function_privilege('anon','public.family_shop_layout(uuid)','execute')
    or has_function_privilege('anon','private.read_family_shop_layout(uuid)','execute') then raise exception 'Anonymous layout access allowed'; end if;
end; $$;
select 'PASS: shelf persistence, guardian ownership, visitor projection, pending/foreign/invalid placement rejection and withdrawn toy filtering' as result;
rollback;
