-- EV charging sibling JSON. Not tariff — parking chip stays parking-only.

alter table public.parks
  add column if not exists ev jsonb;

create or replace function public.catalog_dump()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'version', coalesce((select m.version from public.catalog_meta m where m.id = 1), 1),
    'parkCount', coalesce((select m.park_count from public.catalog_meta m where m.id = 1), 0),
    'updatedAt', (select m.updated_at from public.catalog_meta m where m.id = 1),
    'parks', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'name', p.name,
          'district', p.district,
          'lat', p.lat,
          'lng', p.lng,
          'heightM', p.height_m,
          'hourlyHkd', p.hourly_hkd,
          'dailyHkd', p.daily_hkd,
          'nightHkd', p.night_hkd,
          'priceNote', p.price_note,
          'ugcConfirms', p.ugc_confirms,
          'priceUpdatedAt', p.price_updated_at,
          'source', p.source,
          'priceVerificationStatus', p.price_verification_status,
          'priceVerifiedAt', p.price_verified_at,
          'priceProvenance', p.price_provenance,
          'tariff', p.tariff,
          'ev', p.ev
        )
        order by p.id
      )
      from public.parks p
    ), '[]'::jsonb)
  );
$$;

grant execute on function public.catalog_dump() to anon, authenticated;
