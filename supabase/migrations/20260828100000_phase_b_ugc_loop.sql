-- Phase B: paid session UGC + anonymous auth rate limits

create table if not exists public.paid_sessions (
  id uuid primary key default gen_random_uuid(),
  park_id text not null,
  amount_hkd double precision not null
    check (amount_hkd >= 0 and amount_hkd < 10000),
  duration_minutes integer not null
    check (duration_minutes >= 0 and duration_minutes < 10080),
  reporter_id uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists paid_sessions_park_created_idx
  on public.paid_sessions (park_id, created_at desc);

alter table public.paid_sessions enable row level security;

drop policy if exists "paid_sessions_select" on public.paid_sessions;
drop policy if exists "paid_sessions_insert" on public.paid_sessions;

create policy "paid_sessions_select" on public.paid_sessions
  for select to anon, authenticated using (true);

create policy "paid_sessions_insert" on public.paid_sessions
  for insert to authenticated with check (
    amount_hkd >= 0
    and amount_hkd < 10000
    and duration_minutes >= 0
    and duration_minutes < 10080
    and (
      select count(*)::int
      from public.paid_sessions ps
      where ps.park_id = paid_sessions.park_id
        and ps.reporter_id = auth.uid()
        and ps.created_at > now() - interval '1 hour'
    ) < 5
  );

grant select, insert on public.paid_sessions to authenticated;
grant select on public.paid_sessions to anon;

-- Track reporter on price_reports for per-user rate limits
alter table public.price_reports
  add column if not exists reporter_id uuid default auth.uid();

create or replace function public.enforce_price_report_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recent int;
begin
  if auth.uid() is null then
    raise exception 'sign in required';
  end if;
  select count(*)::int into recent
  from public.price_reports
  where park_id = new.park_id
    and reporter_id = auth.uid()
    and created_at > now() - interval '1 hour';
  if recent >= 5 then
    raise exception 'rate limit exceeded for park %', new.park_id;
  end if;
  new.reporter_id := auth.uid();
  return new;
end;
$$;

drop trigger if exists price_reports_rate_limit on public.price_reports;
create trigger price_reports_rate_limit
  before insert on public.price_reports
  for each row execute function public.enforce_price_report_rate_limit();

-- Require authenticated (anonymous counts) for new price reports
drop policy if exists "price_reports_insert" on public.price_reports;
create policy "price_reports_insert" on public.price_reports
  for insert to authenticated with check (
    hourly_hkd is null or (hourly_hkd >= 0 and hourly_hkd < 5000)
  );
