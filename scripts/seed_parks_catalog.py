#!/usr/bin/env python3
"""Upsert OSM + curated seed parks into public.parks, then bump catalog_meta.

Auth (first match):
  SUPABASE_ACCESS_TOKEN + SUPABASE_URL  → Management API SQL
  DATABASE_URL                          → psql

Used by GitHub Actions after `supabase db push`. Idempotent.
"""
from __future__ import annotations

import json
import os
import re
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OSM_JSON = ROOT / "assets" / "data" / "hk_osm_parks.json"
SEED_DART = ROOT / "lib" / "features" / "parks" / "hk_seed_parks.dart"
ENV_FILE = ROOT / ".env.supabase"

KIND = {
    "underground": "地庫",
    "multi-storey": "多層",
    "multistorey": "多層",
    "multi_storey": "多層",
    "rooftop": "天台",
    "surface": "露天",
}
_PRETTY_RE = re.compile(
    r"^(.*?)(?:\s*[\(（]\s*(underground|multi-storey|multistorey|multi_storey|rooftop|surface)\s*[\)）])\s*$",
    re.I,
)
_SEED_LINE = re.compile(r"Park\((.*)\)\s*,?\s*$")
_SEED_KV = re.compile(
    r"(id|name|district|lat|lng|hourlyHkd|dailyHkd|nightHkd|heightM|ugcConfirms)\s*:\s*('(?:\\'|[^'])*'|-?[0-9.]+)"
)
_CTX = ssl.create_default_context()


def load_dotenv() -> None:
    if not ENV_FILE.exists():
        return
    for raw in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k = k.strip()
        v = v.strip().strip("'").strip('"')
        if k and k not in os.environ:
            os.environ[k] = v


def pretty_park_name(raw: str) -> str:
    s = (raw or "").strip()
    m = _PRETTY_RE.match(s)
    if not m:
        return s
    kind = KIND[m.group(2).lower()]
    base = m.group(1).strip()
    if (
        not base
        or base == "停車場"
        or base.lower() == "parking"
        or base.lower() == "car park"
    ):
        return f"{kind}停車場"
    return f"{base}（{kind}）"


def project_ref(url: str) -> str:
    host = url.replace("https://", "").replace("http://", "").split("/")[0]
    return host.split(".supabase.co")[0]


def sql_str(v: object) -> str:
    if v is None:
        return "null"
    return "'" + str(v).replace("'", "''") + "'"


def sql_num(v: object) -> str:
    if v is None or v == "":
        return "null"
    return repr(float(v))


def sql_int(v: object) -> str:
    if v is None or v == "":
        return "0"
    return str(int(v))


def parse_seed_dart(path: Path) -> list[dict]:
    out: list[dict] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line.startswith("Park("):
            continue
        m = _SEED_LINE.search(line)
        if not m:
            continue
        rec: dict = {}
        for km in _SEED_KV.finditer(m.group(1)):
            key, val = km.group(1), km.group(2)
            if val.startswith("'"):
                rec[key] = val[1:-1]
            elif "." in val:
                rec[key] = float(val)
            else:
                rec[key] = int(val) if key == "ugcConfirms" else float(val)
        if "id" in rec and "lat" in rec and "lng" in rec:
            rec.setdefault("name", "停車場")
            rec.setdefault("district", "香港")
            rec.setdefault("source", "seed")
            out.append(rec)
    return out


def load_osm() -> list[dict]:
    data = json.loads(OSM_JSON.read_text(encoding="utf-8"))
    parks = data.get("parks") if isinstance(data, dict) else data
    out = []
    for raw in parks or []:
        m = dict(raw)
        out.append(
            {
                "id": m.get("id") or "osm-unknown",
                "name": pretty_park_name(m.get("name") or "停車場"),
                "district": m.get("district") or "香港",
                "lat": float(m["lat"]),
                "lng": float(m["lng"]),
                "heightM": float(m["heightM"]) if m.get("heightM") is not None else None,
                "source": "osm",
            }
        )
    return out


def approx_m2(a: dict, b: dict) -> float:
    d_lat = (float(a["lat"]) - float(b["lat"])) * 111000
    d_lng = (float(a["lng"]) - float(b["lng"])) * 111000 * 0.92
    return d_lat * d_lat + d_lng * d_lng


def merge_seed_over_osm(osm: list[dict], seeds: list[dict]) -> list[dict]:
    used: set[int] = set()
    out: list[dict] = []
    threshold = 90 * 90
    for s in seeds:
        best_i, best_d = -1, 1e18
        for i, o in enumerate(osm):
            if i in used:
                continue
            d = approx_m2(s, o)
            if d < best_d:
                best_d, best_i = d, i
        if best_i >= 0 and best_d < threshold:
            used.add(best_i)
            o = osm[best_i]
            out.append(
                {
                    "id": o["id"],
                    "name": s.get("name") or o["name"],
                    "district": s.get("district") or o["district"],
                    "lat": o["lat"],
                    "lng": o["lng"],
                    "heightM": s.get("heightM") if s.get("heightM") is not None else o.get("heightM"),
                    "hourlyHkd": s.get("hourlyHkd"),
                    "dailyHkd": s.get("dailyHkd"),
                    "nightHkd": s.get("nightHkd"),
                    "ugcConfirms": int(s.get("ugcConfirms") or 0),
                    "source": "seed+osm",
                }
            )
        else:
            rec = dict(s)
            rec["source"] = "seed"
            rec["name"] = pretty_park_name(str(rec.get("name") or "停車場"))
            out.append(rec)
    for i, o in enumerate(osm):
        if i not in used:
            out.append(o)
    return out


def row_sql(p: dict) -> str:
    return (
        "("
        f"{sql_str(p['id'])}, {sql_str(p.get('name') or '停車場')}, "
        f"{sql_str(p.get('district') or '香港')}, "
        f"{sql_num(p['lat'])}, {sql_num(p['lng'])}, "
        f"{sql_num(p.get('heightM'))}, "
        f"{sql_num(p.get('hourlyHkd'))}, {sql_num(p.get('dailyHkd'))}, "
        f"{sql_num(p.get('nightHkd'))}, "
        f"{sql_int(p.get('ugcConfirms') or 0)}, "
        f"{sql_str(p.get('source') or 'osm')}"
        ")"
    )


UPSERT_TAIL = """
on conflict (id) do update set
  name = excluded.name,
  district = excluded.district,
  lat = excluded.lat,
  lng = excluded.lng,
  height_m = coalesce(public.parks.height_m, excluded.height_m),
  source = case
    when public.parks.source like 'ugc%' then public.parks.source
    else excluded.source
  end,
  hourly_hkd = coalesce(public.parks.hourly_hkd, excluded.hourly_hkd),
  daily_hkd = coalesce(public.parks.daily_hkd, excluded.daily_hkd),
  night_hkd = coalesce(public.parks.night_hkd, excluded.night_hkd),
  ugc_confirms = public.parks.ugc_confirms,
  updated_at = now()
""".strip()


def batch_sql(rows: list[dict]) -> str:
    values = ",\n".join(row_sql(p) for p in rows)
    return f"""
select set_config('recordo.skip_catalog_bump', 'on', true);
insert into public.parks (
  id, name, district, lat, lng, height_m,
  hourly_hkd, daily_hkd, night_hkd, ugc_confirms, source
) values
{values}
{UPSERT_TAIL};
""".strip()


def run_sql_management(token: str, ref: str, sql: str) -> None:
    body = json.dumps({"query": sql}).encode("utf-8")
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{ref}/database/query",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, context=_CTX, timeout=120) as resp:
            resp.read()
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Management API {e.code}: {err[:800]}") from e


def run_sql_psql(database_url: str, sql: str) -> None:
    r = subprocess.run(
        ["psql", database_url, "-v", "ON_ERROR_STOP=1", "-c", sql],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        raise SystemExit(f"psql failed:\n{r.stderr or r.stdout}")


def run_sql(sql: str) -> None:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    url = os.environ.get("SUPABASE_URL", "").strip()
    db = os.environ.get("DATABASE_URL", "").strip()
    if token and url:
        run_sql_management(token, project_ref(url), sql)
        return
    if db:
        run_sql_psql(db, sql)
        return
    raise SystemExit(
        "Need SUPABASE_ACCESS_TOKEN + SUPABASE_URL, or DATABASE_URL"
    )


def main() -> int:
    load_dotenv()
    assert pretty_park_name("停車場 (underground)") == "地庫停車場"
    assert pretty_park_name("停車場 (multi-storey)") == "多層停車場"

    if not OSM_JSON.exists():
        raise SystemExit(f"missing {OSM_JSON}")
    osm = load_osm()
    seeds = parse_seed_dart(SEED_DART) if SEED_DART.exists() else []
    merged = merge_seed_over_osm(osm, seeds)
    print(f"seed catalog: osm={len(osm)} seed={len(seeds)} merged={len(merged)}")

    batch = 80
    for i in range(0, len(merged), batch):
        chunk = merged[i : i + batch]
        run_sql(batch_sql(chunk))
        print(f"  upserted {min(i + batch, len(merged))}/{len(merged)}")
        time.sleep(0.05)

    run_sql(
        """
select set_config('recordo.skip_catalog_bump', 'on', true);
update public.parks p set
  hourly_hkd = v.hourly_hkd,
  daily_hkd = v.daily_hkd,
  night_hkd = v.night_hkd,
  price_note = coalesce(nullif(v.price_note, ''), p.price_note),
  ugc_confirms = v.ugc_confirms,
  price_updated_at = v.price_updated_at,
  updated_at = now()
from public.park_prices v
where p.id = v.park_id;

insert into public.catalog_meta (id, version, park_count, updated_at)
values (1, 1, (select count(*)::int from public.parks), now())
on conflict (id) do update set
  version = public.catalog_meta.version + 1,
  park_count = (select count(*)::int from public.parks),
  updated_at = now();
"""
    )
    print("catalog_meta bumped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
