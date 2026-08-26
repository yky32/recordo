#!/usr/bin/env python3
"""Fetch HK amenity=parking from OSM Overpass → assets/data/hk_osm_parks.json

ODbL: OpenStreetMap © contributors. Recordo uses as POI skeleton only.
Re-run: python3 scripts/fetch_osm_parking.py
"""
from __future__ import annotations

import json
import math
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "data" / "hk_osm_parks.json"

# Hong Kong SAR-ish bbox
S, W, N, E = 22.15, 113.82, 22.58, 114.50

QUERY = f"""
[out:json][timeout:240];
(
  node["amenity"="parking"]({S},{W},{N},{E});
  way["amenity"="parking"]({S},{W},{N},{E});
  relation["amenity"="parking"]({S},{W},{N},{E});
  node["parking"~"multi-storey|underground|rooftop"]({S},{W},{N},{E});
  way["parking"~"multi-storey|underground|rooftop"]({S},{W},{N},{E});
);
out center tags;
""".strip()

ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]

# Rough district from lat/lng (good enough for list grouping)
def district_of(lat: float, lng: float) -> str:
    # very coarse boxes
    if lng < 113.98:
        return "大嶼山/屯門" if lat > 22.35 else "東涌/機場"
    if lng > 114.24:
        return "將軍澳/西貢" if lat < 22.36 else "沙田/馬鞍山"
    if lat > 22.42:
        return "北區/大埔"
    if lat > 22.36 and lng < 114.14:
        return "荃灣/葵青"
    if lat > 22.36:
        return "沙田/大埔"
    if lat > 22.31 and lng < 114.17:
        return "深水埗/美孚"
    if lat > 22.31 and lng < 114.20:
        return "九龍中"
    if lat > 22.31:
        return "觀塘/九龍灣"
    if lat > 22.28 and lng < 114.16:
        return "中西區"
    if lat > 22.27 and lng < 114.19:
        return "灣仔/銅鑼灣"
    if lng < 114.16:
        return "南區"
    if lat < 22.28:
        return "港島東" if lng > 114.19 else "南區"
    return "九龍"
    # fallback
    return "香港"


def pick_name(tags: dict) -> str:
    for k in (
        "name:zh-Hant",
        "name:zh",
        "name:zh-Hans",
        "name",
        "name:en",
        "alt_name",
        "official_name",
    ):
        v = tags.get(k)
        if v and str(v).strip():
            return str(v).strip()
    # operator + parking type
    op = tags.get("operator") or tags.get("brand")
    ptype = tags.get("parking") or ""
    if op:
        return f"{op} 停車場"
    if ptype == "underground":
        return "地庫停車場"
    if ptype in ("multi-storey", "multistorey"):
        return "多層停車場"
    if ptype == "rooftop":
        return "天台停車場"
    if ptype == "surface":
        return "露天停車場"
    return "停車場"


def height_m(tags: dict) -> float | None:
    for k in ("maxheight", "height"):
        v = tags.get(k)
        if not v:
            continue
        s = str(v).lower().replace("m", "").strip()
        try:
            return float(s)
        except ValueError:
            pass
    return None


def fetch() -> dict:
    data = QUERY.encode("utf-8")
    last_err = None
    for url in ENDPOINTS:
        try:
            req = urllib.request.Request(
                url,
                data=data,
                headers={
                    "Content-Type": "application/x-www-form-urlencoded",
                    "User-Agent": "RecordoHK/1.0 (indie; parking POI skeleton)",
                },
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=300) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:  # noqa: BLE001
            last_err = e
            print(f"endpoint fail {url}: {e}", file=sys.stderr)
    raise SystemExit(f"Overpass failed: {last_err}")


def main() -> None:
    print("Fetching Overpass HK parking…")
    raw = fetch()
    elements = raw.get("elements") or []
    print(f"raw elements: {len(elements)}")

    parks: list[dict] = []
    seen_grid: set[tuple[int, int]] = set()
    seen_ids: set[str] = set()

    for el in elements:
        tags = el.get("tags") or {}
        if tags.get("amenity") not in (None, "parking") and "parking" not in tags:
            # still allow parking=* only
            if tags.get("amenity") and tags.get("amenity") != "parking":
                continue

        et = el.get("type")
        eid = el.get("id")
        oid = f"osm:{et}/{eid}"
        if oid in seen_ids:
            continue

        if "lat" in el and "lon" in el:
            lat, lng = float(el["lat"]), float(el["lon"])
        else:
            c = el.get("center") or {}
            if "lat" not in c:
                continue
            lat, lng = float(c["lat"]), float(c["lon"])

        # ~40m grid dedupe for unnamed clusters
        gy, gx = int(lat * 2500), int(lng * 2500)
        name = pick_name(tags)
        is_generic = name in ("停車場",) or name.startswith("停車場 (")
        if is_generic and (gy, gx) in seen_grid:
            continue
        if not is_generic:
            # also soft-dedupe same name near same grid
            key2 = (name, gy, gx)
            if key2 in seen_ids:  # reuse set with str keys mixed — use parks check
                pass

        seen_ids.add(oid)
        if is_generic:
            seen_grid.add((gy, gx))

        parks.append(
            {
                "id": oid,
                "name": name,
                "district": district_of(lat, lng),
                "lat": round(lat, 6),
                "lng": round(lng, 6),
                "heightM": height_m(tags),
                "source": "osm",
                "osmType": et,
                "parking": tags.get("parking"),
                "access": tags.get("access"),
                "fee": tags.get("fee"),
                "capacity": tags.get("capacity"),
            }
        )

    # Prefer named parks first, then drop near-duplicate named within ~60m
    parks.sort(key=lambda p: (0 if p["name"] != "停車場" else 1, p["name"]))
    final: list[dict] = []
    for p in parks:
        too_close = False
        for q in final:
            # haversine-ish degrees
            dlat = (p["lat"] - q["lat"]) * 111_000
            dlng = (p["lng"] - q["lng"]) * 111_000 * math.cos(math.radians(p["lat"]))
            dist = math.hypot(dlat, dlng)
            sameish = p["name"] == q["name"] or (
                p["name"] == "停車場" or q["name"] == "停車場"
            )
            if dist < 55 and sameish:
                too_close = True
                break
            if dist < 25:
                too_close = True
                break
        if not too_close:
            final.append(p)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "attribution": "© OpenStreetMap contributors (ODbL)",
        "bbox": [S, W, N, E],
        "count": len(final),
        "parks": final,
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    named = sum(1 for p in final if p["name"] != "停車場" and not p["name"].startswith("停車場 ("))
    print(f"wrote {OUT} count={len(final)} named≈{named}")


if __name__ == "__main__":
    main()
