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

## In app
- `ParkRepository` loads asset, merges curated `hkSeedParks` (prices) onto nearby OSM pins
- Map/list shows **nearby window** (~150) for performance; full catalog searchable
- UGC report-new-park still works for gaps

## Next
- Google Places when key ready (enrich names / fill gaps)
- Optional backend sync of OSM dump weekly
