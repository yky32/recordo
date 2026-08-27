-- Price patches must not bump catalog version (avoids full 3k dump
-- on every report). Clients pull changed prices via prices_updated_at.

alter table public.catalog_meta
  add column if not exists prices_updated_at timestamptz;

update public.catalog_meta
set prices_updated_at = coalesce(prices_updated_at, updated_at, now())
where id = 1;

create or replace function public.touch_prices_updated_at()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.catalog_meta (id, version, park_count, prices_updated_at, updated_at)
  values (1, 1, (select count(*)::int from public.parks), now(), now())
  on conflict (id) do update set
    prices_updated_at = now();
end;
$$;

create or replace function public.price_report_to_park()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('recordo.skip_catalog_bump', 'on', true);
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
  perform public.touch_prices_updated_at();
  return new;
end;
$$;

drop trigger if exists price_report_to_park on public.price_reports;
create trigger price_report_to_park
after insert on public.price_reports
for each row
execute function public.price_report_to_park();

grant execute on function public.touch_prices_updated_at() to postgres;
revoke all on function public.touch_prices_updated_at() from public, anon, authenticated;
