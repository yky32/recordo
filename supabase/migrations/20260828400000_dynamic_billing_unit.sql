-- Driver reports can mark billing slice (15/20/30/60 min).
-- Do not overwrite operator-verified tariff (Times Square).

alter table public.price_reports
  add column if not exists unit_minutes int,
  add column if not exists unit_amount numeric,
  add column if not exists offpeak_amount numeric;

alter table public.price_reports
  drop constraint if exists price_reports_unit_minutes_check;
alter table public.price_reports
  add constraint price_reports_unit_minutes_check
  check (unit_minutes is null or (unit_minutes >= 5 and unit_minutes <= 180));

create or replace function public.price_report_to_park()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  op boolean;
  t jsonb;
begin
  select (price_provenance = 'operator' and price_verification_status = 'verified')
    into op
  from public.parks
  where id = new.park_id;

  if coalesce(op, false) then
    return new;
  end if;

  perform set_config('recordo.skip_catalog_bump', 'on', true);

  t := null;
  if new.unit_minutes is not null and new.unit_amount is not null then
    t := jsonb_build_object(
      'unitMinutes', new.unit_minutes,
      'bands', case
        when new.offpeak_amount is not null then jsonb_build_array(
          jsonb_build_object('days','daily','kind','peak','start','07:00','end','23:00','amount', new.unit_amount),
          jsonb_build_object('days','daily','kind','offpeak','start','23:00','end','07:00','amount', new.offpeak_amount)
        )
        else jsonb_build_array(
          jsonb_build_object('days','daily','kind','peak','start','07:00','end','23:00','amount', new.unit_amount)
        )
      end
    );
  end if;

  update public.parks p set
    hourly_hkd = v.hourly_hkd,
    daily_hkd = v.daily_hkd,
    night_hkd = v.night_hkd,
    price_note = coalesce(nullif(v.price_note, ''), p.price_note),
    ugc_confirms = v.ugc_confirms,
    price_updated_at = v.price_updated_at,
    tariff = coalesce(t, p.tariff),
    updated_at = now()
  from public.park_prices v
  where p.id = new.park_id
    and v.park_id = new.park_id;

  perform public.touch_prices_updated_at();
  return new;
end;
$$;
