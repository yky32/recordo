-- Recordo UGC schema (Supabase / Postgres)
-- Run in Supabase SQL Editor, or: supabase db push
-- OSM skeleton stays in the app bundle; this DB is for shared UGC only.

-- New parks reported by users (not already in OSM asset)
create table if not exists public.parks_ugc (
  id text primary key,
  name text not null,
  district text not null default '香港',
  address text,
  lat double precision not null,
  lng double precision not null,
  height_m double precision,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists parks_ugc_geo_idx on public.parks_ugc (lat, lng);

-- Price reports (any park_id: osm:… / seed / ugc-…)
create table if not exists public.price_reports (
  id uuid primary key default gen_random_uuid(),
  park_id text not null,
  hourly_hkd double precision,
  daily_hkd double precision,
  night_hkd double precision,
  confirm_only boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists price_reports_park_created_idx
  on public.price_reports (park_id, created_at desc);

-- Latest price snapshot per park (+ report count)
create or replace view public.park_prices as
select
  pr.park_id,
  pr.hourly_hkd,
  pr.daily_hkd,
  pr.night_hkd,
  pr.created_at as price_updated_at,
  c.cnt as ugc_confirms
from (
  select distinct on (park_id)
    park_id,
    hourly_hkd,
    daily_hkd,
    night_hkd,
    created_at
  from public.price_reports
  order by park_id, created_at desc
) pr
join (
  select park_id, count(*)::int as cnt
  from public.price_reports
  group by park_id
) c on c.park_id = pr.park_id;

-- RLS: public read + insert (anonymous UGC). Tighten later with auth/rate limits.
alter table public.parks_ugc enable row level security;
alter table public.price_reports enable row level security;

drop policy if exists "parks_ugc_select" on public.parks_ugc;
drop policy if exists "parks_ugc_insert" on public.parks_ugc;
drop policy if exists "price_reports_select" on public.price_reports;
drop policy if exists "price_reports_insert" on public.price_reports;

create policy "parks_ugc_select" on public.parks_ugc
  for select to anon, authenticated using (true);

create policy "parks_ugc_insert" on public.parks_ugc
  for insert to anon, authenticated with check (true);

create policy "price_reports_select" on public.price_reports
  for select to anon, authenticated using (true);

create policy "price_reports_insert" on public.price_reports
  for insert to anon, authenticated with check (
    hourly_hkd is null or (hourly_hkd >= 0 and hourly_hkd < 5000)
  );

-- Views use invoker; grant select
grant select on public.park_prices to anon, authenticated;
grant select, insert on public.parks_ugc to anon, authenticated;
grant select, insert on public.price_reports to anon, authenticated;
