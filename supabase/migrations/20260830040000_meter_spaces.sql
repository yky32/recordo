-- Per-bay TD meters (HKeMeter). Not parks. Not the 984-street dump.

create table if not exists public.meter_spaces (
  id text primary key,
  pole_id text,
  district text not null default '',
  sub_district text not null default '',
  street text not null default '',
  section text not null default '',
  lat double precision not null,
  lng double precision not null,
  vehicle_type text not null default 'A',
  lpp int,
  hours_class text not null default '',
  time_unit int not null default 15,
  payment_unit numeric not null default 4,
  updated_at timestamptz not null default now()
);

create index if not exists meter_spaces_lat_lng on public.meter_spaces (lat, lng);

alter table public.meter_spaces enable row level security;

drop policy if exists meter_spaces_select_anon on public.meter_spaces;
create policy meter_spaces_select_anon on public.meter_spaces
  for select to anon, authenticated using (true);

create or replace function public.meter_spaces_in_bbox(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select jsonb_agg(row_to_json(x))
      from (
        select
          s.id,
          s.pole_id as "poleId",
          s.district,
          s.sub_district as "subDistrict",
          s.street,
          s.section,
          s.lat,
          s.lng,
          s.vehicle_type as "vehicleType",
          s.lpp,
          s.hours_class as "hoursClass",
          s.time_unit as "timeUnit",
          s.payment_unit as "paymentUnit"
        from public.meter_spaces s
        where s.lat between min_lat and max_lat
          and s.lng between min_lng and max_lng
        limit 400
      ) x
    ),
    '[]'::jsonb
  );
$$;

grant execute on function public.meter_spaces_in_bbox(double precision, double precision, double precision, double precision)
  to anon, authenticated;

grant select on public.meter_spaces to anon, authenticated;
