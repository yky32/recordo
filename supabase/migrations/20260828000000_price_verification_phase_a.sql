-- Phase A: honest price provenance + verification (no fake seed confirms).

alter table public.parks
  add column if not exists price_verification_status text not null default 'unverified',
  add column if not exists price_verified_at timestamptz,
  add column if not exists price_provenance text not null default 'unknown';

alter table public.parks
  drop constraint if exists parks_price_verification_status_check;
alter table public.parks
  add constraint parks_price_verification_status_check
  check (price_verification_status in ('unverified', 'verified', 'disputed'));

alter table public.parks
  drop constraint if exists parks_price_provenance_check;
alter table public.parks
  add constraint parks_price_provenance_check
  check (price_provenance in ('unknown', 'seed', 'osm', 'ugc', 'gate', 'operator'));

-- Strip fabricated social proof from seed/demo rows.
update public.parks
set
  ugc_confirms = 0,
  price_verification_status = 'unverified',
  price_provenance = case
    when source in ('seed', 'seed+osm') then 'seed'
    when source like 'ugc%' then 'ugc'
    else 'osm'
  end
where source in ('seed', 'seed+osm')
   or (hourly_hkd is not null or daily_hkd is not null or night_hkd is not null);

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
          'priceProvenance', p.price_provenance
        )
        order by p.id
      )
      from public.parks p
    ), '[]'::jsonb)
  );
$$;

create or replace function public.price_report_to_park()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.parks p set
    hourly_hkd = v.hourly_hkd,
    daily_hkd = v.daily_hkd,
    night_hkd = v.night_hkd,
    price_note = coalesce(nullif(v.price_note, ''), p.price_note),
    ugc_confirms = v.ugc_confirms,
    price_updated_at = v.price_updated_at,
    price_provenance = 'ugc',
    price_verification_status = case
      when p.price_verification_status = 'verified' then 'verified'
      else 'unverified'
    end,
    updated_at = now()
  from public.park_prices v
  where p.id = new.park_id
    and v.park_id = new.park_id;
  return new;
end;
$$;

-- Force clients to re-download catalog after backfill.
select set_config('recordo.skip_catalog_bump', 'off', true);
update public.catalog_meta
set version = version + 1, updated_at = now()
where id = 1;
