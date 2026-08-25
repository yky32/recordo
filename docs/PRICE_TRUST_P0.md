# Price trust P0

## Problem
Last-write-wins + free anonymous insert → sky-high fake prices.

## Fix
1. **Insert clamp** (RLS + app): hourly $1–500, daily $10–3000, night $10–2000, note ≤200
2. **Display = median** of in-range reports (365d), not latest row
3. **UI**: `約 $X/時 · N 人` + trust label

## Apply SQL
Supabase SQL Editor → run `supabase/migrations/20260826000000_price_trust_p0.sql`
(or `supabase/SETUP_P0_TRUST.sql`)

## After
- Rate limit / anonymous auth (P1)
