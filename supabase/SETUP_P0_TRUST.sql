-- P0 price trust: clamp inserts + median display (not last-write-wins)
-- Run in Supabase SQL Editor after SETUP_ALL.sql

-- Tighten insert policy (reject sky-high / junk)
drop policy if exists "price_reports_insert" on public.price_reports;
create policy "price_reports_insert" on public.price_reports
  for insert to anon, authenticated
  with check (
    (
      confirm_only = true
      or hourly_hkd is not null
      or daily_hkd is not null
      or night_hkd is not null
    )
    and (hourly_hkd is null or (hourly_hkd >= 1 and hourly_hkd <= 500))
    and (daily_hkd is null or (daily_hkd >= 10 and daily_hkd <= 3000))
    and (night_hkd is null or (night_hkd >= 10 and night_hkd <= 2000))
    and (price_note is null or char_length(price_note) <= 200)
  );

-- Display snapshot: median of in-range reports (last 365d), not latest row
create or replace view public.park_prices as
with base as (
  select
    park_id,
    hourly_hkd,
    daily_hkd,
    night_hkd,
    price_note,
    created_at,
    confirm_only
  from public.price_reports
  where created_at > (now() - interval '365 days')
    and (hourly_hkd is null or (hourly_hkd >= 1 and hourly_hkd <= 500))
    and (daily_hkd is null or (daily_hkd >= 10 and daily_hkd <= 3000))
    and (night_hkd is null or (night_hkd >= 10 and night_hkd <= 2000))
),
hourly_med as (
  select
    park_id,
    percentile_cont(0.5) within group (order by hourly_hkd) as hourly_hkd
  from base
  where hourly_hkd is not null
  group by park_id
),
daily_med as (
  select
    park_id,
    percentile_cont(0.5) within group (order by daily_hkd) as daily_hkd
  from base
  where daily_hkd is not null
  group by park_id
),
night_med as (
  select
    park_id,
    percentile_cont(0.5) within group (order by night_hkd) as night_hkd
  from base
  where night_hkd is not null
  group by park_id
),
counts as (
  select
    park_id,
    count(*)::int as ugc_confirms,
    max(created_at) as price_updated_at
  from base
  group by park_id
),
notes as (
  select distinct on (park_id)
    park_id,
    price_note
  from base
  where price_note is not null
    and length(trim(price_note)) > 0
  order by park_id, created_at desc
)
select
  c.park_id,
  round(h.hourly_hkd::numeric, 0)::double precision as hourly_hkd,
  round(d.daily_hkd::numeric, 0)::double precision as daily_hkd,
  round(n.night_hkd::numeric, 0)::double precision as night_hkd,
  nt.price_note,
  c.price_updated_at,
  c.ugc_confirms
from counts c
left join hourly_med h on h.park_id = c.park_id
left join daily_med d on d.park_id = c.park_id
left join night_med n on n.park_id = c.park_id
left join notes nt on nt.park_id = c.park_id;

grant select on public.park_prices to anon, authenticated;
