-- Phase C: lightweight cohort telemetry for exit gates
-- (day-2 opens + 實付 share rate). No PII beyond install_id.

create table if not exists public.cohort_events (
  id uuid primary key default gen_random_uuid(),
  install_id text not null,
  event text not null
    check (event in ('app_open', 'session_end')),
  park_id text,
  amount_hkd double precision,
  duration_minutes integer,
  share_paid boolean,
  cloud_ok boolean,
  created_at timestamptz not null default now()
);

create index if not exists cohort_events_install_created_idx
  on public.cohort_events (install_id, created_at);

create index if not exists cohort_events_event_created_idx
  on public.cohort_events (event, created_at desc);

alter table public.cohort_events enable row level security;

drop policy if exists "cohort_events_insert" on public.cohort_events;
drop policy if exists "cohort_events_select" on public.cohort_events;

-- Anonymous auth counts as authenticated.
create policy "cohort_events_insert" on public.cohort_events
  for insert to authenticated with check (
    length(trim(install_id)) > 8
    and event in ('app_open', 'session_end')
  );

-- Founder reads via SQL editor / service role; clients don't need select.
create policy "cohort_events_select" on public.cohort_events
  for select to authenticated using (false);

grant insert on public.cohort_events to authenticated;
