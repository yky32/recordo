-- Recordo UGC v2: price notes (V1.5)
-- Run in Supabase SQL Editor after 20260324000000_recordo_ugc.sql

alter table public.price_reports
  add column if not exists price_note text;

-- Latest snapshot includes note from newest report
create or replace view public.park_prices as
select
  pr.park_id,
  pr.hourly_hkd,
  pr.daily_hkd,
  pr.night_hkd,
  pr.price_note,
  pr.created_at as price_updated_at,
  c.cnt as ugc_confirms
from (
  select distinct on (park_id)
    park_id,
    hourly_hkd,
    daily_hkd,
    night_hkd,
    price_note,
    created_at
  from public.price_reports
  order by park_id, created_at desc
) pr
join (
  select park_id, count(*)::int as cnt
  from public.price_reports
  group by park_id
) c on c.park_id = pr.park_id;

grant select on public.park_prices to anon, authenticated;
