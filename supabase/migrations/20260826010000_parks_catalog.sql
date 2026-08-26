-- Canonical park catalog on cloud. Clients dump once to local disk,
-- then re-download only when catalog_meta.version is newer.

create table if not exists public.parks (
  id text primary key,
  name text not null,
  district text not null default '香港',
  address text,
  lat double precision not null,
  lng double precision not null,
  height_m double precision,
  hourly_hkd double precision,
  daily_hkd double precision,
  night_hkd double precision,
  price_note text,
  ugc_confirms integer not null default 0,
  price_updated_at timestamptz,
  source text not null default 'osm',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists parks_geo_idx on public.parks (lat, lng);
create index if not exists parks_source_idx on public.parks (source);

create table if not exists public.catalog_meta (
  id integer primary key default 1 check (id = 1),
  version bigint not null default 1,
  park_count integer not null default 0,
  updated_at timestamptz not null default now()
);

insert into public.catalog_meta (id, version, park_count)
values (1, 1, 0)
on conflict (id) do nothing;

create or replace function public.bump_catalog_version()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('recordo.skip_catalog_bump', true) = 'on' then
    return;
  end if;
  insert into public.catalog_meta (id, version, park_count, updated_at)
  values (1, 1, (select count(*)::int from public.parks), now())
  on conflict (id) do update set
    version = public.catalog_meta.version + 1,
    park_count = (select count(*)::int from public.parks),
    updated_at = now();
end;
$$;

create or replace function public.parks_after_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.bump_catalog_version();
  return null;
end;
$$;

drop trigger if exists parks_after_change on public.parks;
create trigger parks_after_change
after insert or update or delete on public.parks
for each statement
execute function public.parks_after_change();

-- 報新場 → canonical catalog (anon cannot write parks directly).
create or replace function public.parks_ugc_to_catalog()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.parks (
    id, name, district, address, lat, lng, height_m, price_note, source
  ) values (
    new.id,
    new.name,
    new.district,
    new.address,
    new.lat,
    new.lng,
    new.height_m,
    new.note,
    'ugc'
  )
  on conflict (id) do update set
    name = excluded.name,
    district = excluded.district,
    address = excluded.address,
    lat = excluded.lat,
    lng = excluded.lng,
    height_m = coalesce(excluded.height_m, public.parks.height_m),
    price_note = coalesce(nullif(excluded.price_note, ''), public.parks.price_note),
    source = case
      when public.parks.source like 'ugc%' then public.parks.source
      else 'ugc'
    end,
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists parks_ugc_to_catalog on public.parks_ugc;
create trigger parks_ugc_to_catalog
after insert or update on public.parks_ugc
for each row
execute function public.parks_ugc_to_catalog();

-- Denormalize median view onto parks so the dump is self-contained.
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
    updated_at = now()
  from public.park_prices v
  where p.id = new.park_id
    and v.park_id = new.park_id;
  return new;
end;
$$;

drop trigger if exists price_report_to_park on public.price_reports;
create trigger price_report_to_park
after insert on public.price_reports
for each row
execute function public.price_report_to_park();

-- One-shot dump for the app (anon RPC).
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
          'source', p.source
        )
        order by p.id
      )
      from public.parks p
    ), '[]'::jsonb)
  );
$$;

alter table public.parks enable row level security;
alter table public.catalog_meta enable row level security;

drop policy if exists "parks_select" on public.parks;
create policy "parks_select" on public.parks
  for select to anon, authenticated using (true);

drop policy if exists "catalog_meta_select" on public.catalog_meta;
create policy "catalog_meta_select" on public.catalog_meta
  for select to anon, authenticated using (true);

grant select on public.parks to anon, authenticated;
grant select on public.catalog_meta to anon, authenticated;
grant execute on function public.catalog_dump() to anon, authenticated;

revoke all on function public.bump_catalog_version() from public, anon, authenticated;
revoke all on function public.parks_after_change() from public, anon, authenticated;
revoke all on function public.parks_ugc_to_catalog() from public, anon, authenticated;
revoke all on function public.price_report_to_park() from public, anon, authenticated;

-- Existing UGC parks (if any) join the canonical catalog.
insert into public.parks (
  id, name, district, address, lat, lng, height_m, price_note, source
)
select
  u.id, u.name, u.district, u.address, u.lat, u.lng, u.height_m, u.note, 'ugc'
from public.parks_ugc u
on conflict (id) do nothing;
