-- UGC name/district on existing parks. Anon cannot UPDATE parks.
-- Skip operator-official identity.

create table if not exists public.identity_reports (
  id bigserial primary key,
  park_id text not null,
  name text not null,
  district text not null,
  created_at timestamptz not null default now()
);

alter table public.identity_reports enable row level security;

drop policy if exists identity_reports_insert on public.identity_reports;
create policy identity_reports_insert on public.identity_reports
  for insert to anon, authenticated
  with check (
    char_length(btrim(name)) between 2 and 40
    and char_length(btrim(district)) between 2 and 16
  );

drop policy if exists identity_reports_select on public.identity_reports;
create policy identity_reports_select on public.identity_reports
  for select to anon, authenticated using (true);

grant select, insert on public.identity_reports to anon, authenticated;
grant usage, select on sequence public.identity_reports_id_seq to anon, authenticated;

create or replace function public.identity_report_to_park()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.parks p
  set
    name = btrim(new.name),
    district = btrim(new.district),
    updated_at = now()
  where p.id = new.park_id
    and coalesce(p.price_provenance, '') is distinct from 'operator';
  return new;
end;
$$;

drop trigger if exists identity_report_to_park on public.identity_reports;
create trigger identity_report_to_park
after insert on public.identity_reports
for each row
execute function public.identity_report_to_park();
