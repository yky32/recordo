# Price / identity trust

## P0 (shipped — 20-person cohort)
1. **Insert clamp** (RLS + app): hourly $1–500, daily $10–3000, night $10–2000, note ≤200
2. **Display = median** of in-range reports (365d), not latest row
3. **UI**: amount + trust icon（藍剔 = 官方）
4. **Identity edit**: unofficial parks only. Operator official locked. Name 2–40, district chip list.

This does **not** stop a determined flood (anon insert). Cohort OK.

## Apply SQL
- `supabase/migrations/20260826000000_price_trust_p0.sql`
- `supabase/migrations/20260831160000_identity_reports.sql`

## P1 (required before public App Store)
- Anonymous Auth (stable user id)
- Edge Function rate limit on `price_reports` **and** `identity_reports`
- Hide / report outlier prices and junk names

Do not treat P0 clamp as public-launch trust.
