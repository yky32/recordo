-- On-street TD meters. Separate from parks catalog_dump (meters barely change).

create table if not exists public.meters (
  id text primary key,
  district text not null,
  street text not null,
  hours_class text not null,
  spaces_car int not null default 0,
  spaces_goods int not null default 0,
  spaces_bus int not null default 0,
  lat double precision,
  lng double precision,
  tariff jsonb,
  source text not null default 'td',
  updated_at timestamptz not null default now()
);

create table if not exists public.meters_meta (
  id int primary key default 1,
  version int not null default 1,
  meter_count int not null default 0,
  updated_at timestamptz not null default now(),
  constraint meters_meta_one_row check (id = 1)
);

insert into public.meters_meta (id, version, meter_count)
values (1, 1, 0)
on conflict (id) do nothing;

alter table public.meters enable row level security;
alter table public.meters_meta enable row level security;

drop policy if exists meters_select_anon on public.meters;
create policy meters_select_anon on public.meters
  for select to anon, authenticated using (true);

drop policy if exists meters_meta_select_anon on public.meters_meta;
create policy meters_meta_select_anon on public.meters_meta
  for select to anon, authenticated using (true);

create or replace function public.meters_dump()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'version', coalesce((select m.version from public.meters_meta m where m.id = 1), 1),
    'count', coalesce((select m.meter_count from public.meters_meta m where m.id = 1), 0),
    'updatedAt', (select m.updated_at from public.meters_meta m where m.id = 1),
    'source', 'td',
    'meters', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', x.id,
          'kind', 'meter',
          'name', '咪錶 · ' || x.street,
          'district', x.district,
          'street', x.street,
          'lat', x.lat,
          'lng', x.lng,
          'spacesCar', x.spaces_car,
          'spacesGoods', x.spaces_goods,
          'spacesBus', x.spaces_bus,
          'hoursClass', x.hours_class,
          'tariff', x.tariff,
          'source', x.source
        )
        order by x.id
      )
      from public.meters x
    ), '[]'::jsonb)
  );
$$;

grant execute on function public.meters_dump() to anon, authenticated;
