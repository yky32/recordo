# Phase C — 20-driver cohort (CWB / TST)

Exit gates (1 week):

| Gate | Pass |
|------|------|
| Day-2 opens | ≥ **8 / 20** install_ids with `app_open` on a later calendar day |
| 實付 share | ≥ **40%** of `session_end` with `share_paid` + `cloud_ok` |
| Cross-device | Phone B sees Phone A row under **其他司機分享** |

## Before you leave for CWB

1. Apply migration in Supabase SQL editor:

   `supabase/migrations/20260828200000_phase_c_cohort_events.sql`

   (Also ensure `20260828100000_phase_b_ugc_loop.sql` is applied — `paid_sessions`.)

2. Auth → Providers → **Anonymous** ON.

3. Install latest TestFlight build (has Supabase dart-defines).

4. Smoke on your phone:
   - Open a wedge park → **開始計時** → end with 分享實付 ON
   - Snack should be `已分享實付 · 多謝` (not 「未接雲端」)
   - Second phone: same park detail → **其他司機分享**

## Invite copy

```
Recordo TestFlight — 銅鑼灣/尖沙咀泊車記低實付。
免費、唔賣訂閱。開場→開始計時→完結時分享實付。
試完第二日再開一次就得。
```

## SQL — exit gates

```sql
-- Day-2 opens
with first_open as (
  select install_id, min((created_at at time zone 'Asia/Hong_Kong')::date) as d0
  from cohort_events
  where event = 'app_open'
  group by 1
),
day2 as (
  select distinct e.install_id
  from cohort_events e
  join first_open f on f.install_id = e.install_id
  where e.event = 'app_open'
    and (e.created_at at time zone 'Asia/Hong_Kong')::date > f.d0
)
select
  (select count(*) from first_open) as installs,
  (select count(*) from day2) as day2_opens;

-- 實付 rate
select
  count(*) filter (where event = 'session_end') as sessions,
  count(*) filter (
    where event = 'session_end' and share_paid is true and cloud_ok is true
  ) as paid_shared_ok
from cohort_events;
```

## Do not

HK Store / TW / more OSM until gates pass.
