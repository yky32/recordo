# HK parking POI from OpenStreetMap

## Attribution
© OpenStreetMap contributors. Data available under the [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/).

Recordo uses OSM as a **POI skeleton** (name, coordinates). **Prices are never from OSM** — only UGC / curated seed.

## Refresh
```bash
python3 scripts/fetch_osm_parking.py
# writes assets/data/hk_osm_parks.json
```

Then commit the JSON + ship app. Overpass may rate-limit; script tries two endpoints.

## Cloud catalog
`scripts/seed_parks_catalog.py` upserts this JSON + curated seed into Supabase `parks`.
App dumps `catalog_dump()` to local disk and plays offline; re-downloads only when `catalog_meta.version` is newer.
Bundled JSON is first-run / offline fallback.

## In app
- Map/list shows **nearby window** (~150) for performance; full catalog searchable
- UGC report-new-park still works for gaps (writes `parks_ugc` → `parks` + version bump)

## Next
- Google Places when key ready (enrich names / fill gaps)
- Re-run OSM fetch + seed script when the map skeleton needs a refresh
