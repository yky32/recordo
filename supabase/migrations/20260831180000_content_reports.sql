-- Guideline 1.2: report inaccurate UGC name/price. Hide is on-device.

create table if not exists public.content_reports (
  id bigserial primary key,
  park_id text not null,
  kind text not null check (kind in ('name', 'price', 'other')),
  note text not null default '',
  created_at timestamptz not null default now()
);

alter table public.content_reports enable row level security;

drop policy if exists content_reports_insert on public.content_reports;
create policy content_reports_insert on public.content_reports
  for insert to anon, authenticated
  with check (char_length(btrim(park_id)) > 0);

grant insert on public.content_reports to anon, authenticated;
grant usage, select on sequence public.content_reports_id_seq to anon, authenticated;
