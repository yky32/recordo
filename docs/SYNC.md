# Recordo sync — DB SoT + offline phone

## Goal
Supabase is the **only** shared source of truth.  
The phone keeps a **local replica** so 無網絡仍然可以搵場、睇上次價錢、記今次使費。

Sessions / 實付 stay **device-private**. Not synced.

## Layers

| Layer | What | Offline? |
|-------|------|----------|
| Server `parks` + `catalog_meta` | Shared catalog + denormalized prices | — |
| Server `price_reports` / `parks_ugc` | Write log (median / new parks) | — |
| Disk `catalog/parks_v1.json` | Last successful dump | Yes |
| Prefs `ugc_prices` / `ugc_new_parks` | This device overlay (instant UI) | Yes |
| Prefs `sync_outbox` | Unacked writes waiting to push | Yes |
| Bundle OSM | First-run / never-synced fallback | Yes |

```
          ┌─ push outbox ─┐
Phone  ───┤               ├──►  Supabase (SoT)
          └─ pull dump  ──┘
             ▲
        version check
```

## Pull (server → phone)

1. Paint **local snapshot** immediately.
2. `GET catalog_meta` (`version` + `prices_updated_at`).
3. **List changed** (`version` newer or local empty) → `catalog_dump` overwrite.
4. **Only prices changed** → patch rows with `price_updated_at > local`.
5. Overlay applies **only if this device’s write is newer than dump**.

No full dump when only a price report landed.  
No resume spam: throttle **≥ 30s**.

## Push (phone → server)

Always write local first, then enqueue outbox, then flush:

1. Overlay prefs (UI 即時變).
2. Append `sync_outbox` job (`price` / `park`).
3. If online: insert `price_reports` / `parks_ugc`. Success → drop job.
4. If offline / fail: job stays. Next pull / resume / manual sync flushes again.

Cap: last **80** jobs. FIFO drop oldest.  
Poison / 8 failed tries → drop (no infinite retry).

## When sync runs

| Event | Pull | Flush outbox |
|-------|------|----------------|
| Cold start | version check | yes |
| App resume (≥30s) | version check | yes |
| After edit | no extra dump | yes |
| Settings「檢查場庫更新」 | version check | yes |

## Conflict

- Shared list/detail after dump/patch: **server median** on `parks`.
- This device overlay wins **only while** `localTs > dumpTs`. After the cloud row is as new or newer, overlay is pruned.
- Seed-id overlay keys remap onto OSM catalog ids (~90m) after dump.
- Not last-write-wins across users.

## Not in v1

- Incremental `updated_at` patch — **prices now patch**; full dump still for new parks / list changes.
- Realtime websocket.
- Syncing parking sessions.
