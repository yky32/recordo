# Recordo × Supabase

## What lives where

| Data | Where |
|------|--------|
| OSM parking skeleton (~3k) | App asset `assets/data/hk_osm_parks.json` |
| Curated seed prices | `hk_seed_parks.dart` |
| **Shared UGC prices** | Supabase `price_reports` + view `park_prices` |
| **Shared new parks** | Supabase `parks_ugc` |
| Offline / no key | Local SharedPreferences (still works) |

## 1. Create project

1. https://supabase.com → New project  
2. SQL Editor → paste `supabase/migrations/20260324000000_recordo_ugc.sql` → Run  
3. Project Settings → API → copy **Project URL** + **anon public** key  

## 2. Run app with keys

```bash
cd ~/Documents/git/personal/recordo
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
```

Or VS Code / Xcode scheme env, or:

```bash
# optional local file (gitignored)
# .vscode/launch.json dart-defines
```

**Never commit** service_role key. Anon key is OK in client with RLS.

## 3. Verify

```sql
select * from park_prices limit 20;
select * from parks_ugc order by created_at desc limit 20;
```

In app: 改收費 / 報告新場 → should appear for other devices after pull.

## 4. Later

- Anonymous Auth `signInAnonymously` + `user_id` column  
- Rate limit (Edge Function)  
- Admin delete spam  
- Optional: sync OSM IDs only (not full dump) for analytics  

## CLI (optional)

```bash
npx supabase login
npx supabase link --project-ref <ref>
npx supabase db push
```
