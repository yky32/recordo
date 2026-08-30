#!/usr/bin/env python3
"""Fill meters.lat/lng via HK ALS. Does not touch parks."""

from __future__ import annotations

import os
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

import psycopg

ALS = "https://www.als.gov.hk/lookup?q="


def geocode(district: str, street: str) -> tuple[float, float] | None:
    q = urllib.parse.quote(f"{district} {street}")
    req = urllib.request.Request(
        ALS + q,
        headers={"User-Agent": "recordo-meters/1.0"},
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        xml = r.read()
    root = ET.fromstring(xml)
    sug = root.find("SuggestedAddress")
    if sug is None:
        return None
    geo = sug.find(".//GeospatialInformation")
    if geo is None:
        return None
    lat_el, lng_el = geo.find("Latitude"), geo.find("Longitude")
    if lat_el is None or lng_el is None or lat_el.text is None or lng_el.text is None:
        return None
    try:
        lat, lng = float(lat_el.text), float(lng_el.text)
    except ValueError:
        return None
    if not (22.1 < lat < 22.6 and 113.7 < lng < 114.5):
        return None
    return lat, lng


def main() -> None:
    pw = os.environ["SUPABASE_DB_PASSWORD"]
    conn = psycopg.connect(
        host="aws-0-ap-northeast-1.pooler.supabase.com",
        port=6543,
        dbname="postgres",
        user="postgres.jutuorafntyvukxzehlg",
        password=pw,
        sslmode="require",
    )
    cur = conn.cursor()
    cur.execute(
        "select distinct district, street from meters where lat is null order by 1,2"
    )
    todo = cur.fetchall()
    print("todo", len(todo), flush=True)
    ok = fail = 0
    for i, (district, street) in enumerate(todo, 1):
        try:
            ll = geocode(district, street)
        except Exception as e:
            print("ERR", district, street, e, flush=True)
            ll = None
            time.sleep(0.8)
        if ll is None:
            fail += 1
        else:
            lat, lng = ll
            cur.execute(
                "update meters set lat=%s, lng=%s, updated_at=now() "
                "where district=%s and street=%s",
                (lat, lng, district, street),
            )
            ok += 1
        if i % 25 == 0:
            conn.commit()
            print(f"{i}/{len(todo)} ok={ok} fail={fail}", flush=True)
        time.sleep(0.15)
    cur.execute(
        """
        update meters_meta
        set version = version + 1,
            meter_count = (select count(*) from meters),
            updated_at = now()
        where id = 1
        returning version,
                  (select count(*) from meters where lat is not null)
        """
    )
    print("meta", cur.fetchone(), "ok", ok, "fail", fail, flush=True)
    conn.commit()
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
