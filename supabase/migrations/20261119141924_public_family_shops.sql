-- Public storefront projection: approved listings and cosmetic shop fields only.
-- Family names, guardian data, child profiles, pet data and balances stay private.
create or replace function public.browse_family_shops(search_term text default '', page_size integer default 24, page_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare term text := btrim(coalesce(search_term,'')); result jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if page_size is null or page_size not between 1 and 50 or page_offset is null or page_offset<0 or char_length(term)>100 then raise exception 'Invalid page'; end if;
 with grouped as (
  select l.family_id as shop_id,
   'Крамничка '||upper(substr(md5(l.family_id::text),1,6)) as shop_name,
   coalesce(array_agg(distinct btrim(l.city) order by btrim(l.city)) filter(where nullif(btrim(l.city),'') is not null),array[]::text[]) as cities,
   count(*) as listing_count
  from public.listings l where l.status='approved' group by l.family_id
 ), filtered as (
  select g.shop_id,g.shop_name,g.cities,g.listing_count,
   coalesce(w.shop_theme,'mint') as theme,coalesce(w.shop_front,'classic') as front,
   coalesce(w.decorated,false) as balloons,coalesce(w.flowers,false) as flowers,coalesce(w.awning,false) as awning
  from grouped g left join public.family_world_progress w on w.family_id=g.shop_id
  where term='' or position(lower(term) in lower(g.shop_name))>0
   or exists(select 1 from unnest(g.cities) as city where position(lower(term) in lower(city))>0)
 ), paged as (select * from filtered order by shop_name,shop_id limit page_size offset page_offset)
 select coalesce(jsonb_agg(to_jsonb(paged) order by shop_name,shop_id),'[]'::jsonb) into result from paged;
 return result;
end; $$;
revoke all on function public.browse_family_shops(text,integer,integer) from public,anon;
grant execute on function public.browse_family_shops(text,integer,integer) to authenticated;

-- Keep the existing public-listing projection and its RLS authorization.
create or replace function public.family_shop_listings(target_shop uuid, page_size integer default 24, page_offset integer default 0)
returns setof public.public_listings language plpgsql stable security invoker set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if target_shop is null or page_size is null or page_size not between 1 and 50 or page_offset is null or page_offset<0 then raise exception 'Invalid page'; end if;
 return query select v.* from public.public_listings v join public.listings l on l.id=v.id
 where l.family_id=target_shop and l.status='approved' order by v.created_at desc,v.id limit page_size offset page_offset;
end; $$;
revoke all on function public.family_shop_listings(uuid,integer,integer) from public,anon;
grant execute on function public.family_shop_listings(uuid,integer,integer) to authenticated;
notify pgrst,'reload schema';
