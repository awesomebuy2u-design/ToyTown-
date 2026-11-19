begin;
do $$
declare f uuid; g uuid; u uuid; a uuid; hidden uuid; b uuid; city text; shops jsonb; page1 jsonb; page2 jsonb; listing jsonb; total integer; rejected boolean;
begin
 select family_id,user_id into f,u from public.family_members order by created_at limit 1;
 select family_id into g from public.family_members where family_id<>f order by created_at limit 1;
 if f is null or g is null then raise exception 'Fixture requires two families'; end if;
 city := 'Test City '||substr(gen_random_uuid()::text,1,12);
 insert into public.listings(family_id,title,description,category,condition,deal_type,city,status)
 values(f,'Test approved','Rollback-only fixture','Інше','used','gift',city,'approved') returning id into a;
 insert into public.listings(family_id,title,description,category,condition,deal_type,city,status)
 values(f,'Test pending','Must stay private','Інше','used','gift',city,'pending') returning id into hidden;
 insert into public.listings(family_id,title,description,category,condition,deal_type,city,status)
 values(g,'Other family approved','Rollback-only fixture','Інше','used','gift',city,'approved') returning id into b;
 perform set_config('request.jwt.claim.sub',u::text,true);
 -- Test the real signed-in role, including RLS on listing reads.
 execute 'set local role authenticated';
 shops := public.browse_family_shops(lower(city),24,0);
 if jsonb_array_length(shops)<>2 then raise exception 'Search must find two approved shops'; end if;
 if exists(select 1 from jsonb_array_elements(shops) item,jsonb_object_keys(item) k where k not in ('shop_id','shop_name','cities','listing_count','theme','front','balloons','flowers','awning')) then raise exception 'Private field in shop projection'; end if;
 select count(*) into total from public.listings where family_id=f and status='approved';
 if (select (item->>'listing_count')::integer from jsonb_array_elements(shops) item where item->>'shop_id'=f::text)<>total then raise exception 'Wrong approved count'; end if;
 page1 := public.browse_family_shops(city,1,0); page2 := public.browse_family_shops(city,1,1);
 if jsonb_array_length(page1)<>1 or jsonb_array_length(page2)<>1 or page1->0->>'shop_id'=page2->0->>'shop_id' then raise exception 'Pagination failed'; end if;
 if not exists(select 1 from public.family_shop_listings(g,50,0) where id=b) then raise exception 'Other family approved toy missing'; end if;
 if exists(select 1 from public.family_shop_listings(g,50,0) where id=a) then raise exception 'Shop filtering failed'; end if;
 if exists(select 1 from public.family_shop_listings(f,50,0) where id=hidden) then raise exception 'Pending listing exposed'; end if;
 select to_jsonb(x) into listing from public.family_shop_listings(f,50,0) x where id=a;
 if listing is null or listing ? 'family_id' or listing ? 'child_profile_id' or listing ? 'moderation_note' then raise exception 'Listing projection failed'; end if;
 rejected := false;
 begin perform public.browse_family_shops('',0,0);
 exception when others then if sqlerrm='Invalid page' then rejected:=true; else raise; end if; end;
 if not rejected then raise exception 'Unbounded page accepted'; end if;
 if has_function_privilege('anon','public.browse_family_shops(text,integer,integer)','execute') or has_function_privilege('anon','public.family_shop_listings(uuid,integer,integer)','execute') then raise exception 'Anonymous grant'; end if;
 execute 'reset role';
 update public.listings set status='archived' where id=a;
 execute 'set local role authenticated';
 if exists(select 1 from public.family_shop_listings(f,50,0) where id=a) then raise exception 'Archived listing exposed'; end if;
 shops := public.browse_family_shops(city,24,0);
 if jsonb_array_length(shops)<>1 or shops->0->>'shop_id'<>g::text then raise exception 'Unpublished listing still discovers shop'; end if;
 perform set_config('request.jwt.claim.sub','',true);
 rejected := false;
 begin perform public.browse_family_shops('',24,0);
 exception when others then if sqlerrm='Sign in required' then rejected:=true; else raise; end if; end;
 if not rejected then raise exception 'Unauthenticated request accepted'; end if;
end $$;
select 'PASS: signed-in role, two families, approved-only listings, search, counts, paging and private-field filtering' as result;
rollback;
