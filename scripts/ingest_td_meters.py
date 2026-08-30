#!/usr/bin/env python3
"""Ingest TD metered-parking CSVs into public.meters. Does not touch parks."""

from __future__ import annotations

import csv
import io
import json
import os
import urllib.request

import psycopg

URLS = [
    "https://www.td.gov.hk/datagovhk_td/metered-parking-spaces/resources/tc/hki_parking_spaces_chi.csv",
    "https://www.td.gov.hk/datagovhk_td/metered-parking-spaces/resources/tc/kln_parking_spaces_chi.csv",
    "https://www.td.gov.hk/datagovhk_td/metered-parking-spaces/resources/tc/nt_parking_spaces_chi.csv",
]

# TD dataspec: A/B/D/H/Q…  → bands. Amount is territory-wide $4 / 15 min (cars).
HOURS = {
    "A": [("mon-sat", "08:00", "24:00")],
    "B": [("mon-sat", "08:00", "20:00")],
    "D": [("mon-sat", "08:00", "24:00"), ("sun-ph", "10:00", "22:00")],
    "E": [("daily", "07:00", "20:00")],
    "F": [("daily", "08:00", "21:00")],
    "G": [("daily", "07:00", "19:00")],
    "H": [("daily", "08:00", "20:00")],
    "J": [("daily", "08:00", "24:00")],
    "N": [("daily", "19:00", "24:00")],
    "P": [("mon-sat", "08:00", "20:00")],
    "Q": [("mon-sat", "08:00", "20:00"), ("sun-ph", "10:00", "22:00")],
    "S": [
        ("mon-fri", "17:00", "24:00"),
        ("sat", "08:00", "24:00"),
        ("sun-ph", "10:00", "22:00"),
    ],
    "T": [
        ("mon-fri", "17:30", "24:00"),
        ("sat", "08:00", "24:00"),
        ("sun-ph", "10:00", "22:00"),
    ],
}


def hours_key(raw: str) -> str:
    s = (raw or "").strip().upper()
    for prefix in ("7", "4", "3"):
        if s.startswith(prefix) and len(s) > 1:
            s = s[1:]
            break
    return s[:1] if s else "?"


def tariff_for(cls: str) -> dict:
    bands = [
        {
            "days": days,
            "kind": "peak",
            "start": start,
            "end": end,
            "amount": 4,
        }
        for days, start, end in HOURS.get(cls, [("daily", "08:00", "24:00")])
    ]
    return {
        "unitMinutes": 15,
        "currency": "HKD",
        "sourceName": "運輸署",
        "hoursClass": cls,
        "bands": bands,
    }


def fetch_rows() -> list[dict]:
    ua = {"User-Agent": "recordo-meters/1.0"}
    out: list[dict] = []
    seen: set[str] = set()
    for url in URLS:
        req = urllib.request.Request(url, headers=ua)
        with urllib.request.urlopen(req, timeout=30) as r:
            text = r.read().decode("utf-8-sig")
        reader = csv.reader(io.StringIO(text))
        header = next(reader, None)
        if not header:
            continue
        for row in reader:
            if len(row) < 6:
                continue
            district, street, raw_cls = row[0].strip(), row[1].strip(), row[2].strip()
            if not district or not street:
                continue
            cls = hours_key(raw_cls)
            mid = f"td:{district}:{street}"
            if mid in seen:
                continue
            seen.add(mid)

            def n(i: int) -> int:
                try:
                    return int(float(row[i] or 0))
                except ValueError:
                    return 0

            out.append(
                {
                    "id": mid,
                    "district": district,
                    "street": street,
                    "hours_class": cls,
                    "spaces_car": n(3),
                    "spaces_goods": n(4),
                    "spaces_bus": n(5),
                    "tariff": tariff_for(cls),
                }
            )
    return out


def main() -> None:
    pw = os.environ["SUPABASE_DB_PASSWORD"]
    rows = fetch_rows()
    conn = psycopg.connect(
        host="aws-0-ap-northeast-1.pooler.supabase.com",
        port=6543,
        dbname="postgres",
        user="postgres.jutuorafntyvukxzehlg",
        password=pw,
        sslmode="require",
    )
    cur = conn.cursor()
    cur.execute("truncate public.meters")
    payload = [
        (
            row["id"],
            row["district"],
            row["street"],
            row["hours_class"],
            row["spaces_car"],
            row["spaces_goods"],
            row["spaces_bus"],
            json.dumps(row["tariff"], ensure_ascii=False),
        )
        for row in rows
    ]
    cur.executemany(
        """
        insert into public.meters (
          id, district, street, hours_class,
          spaces_car, spaces_goods, spaces_bus, tariff, source
        ) values (%s,%s,%s,%s,%s,%s,%s,%s::jsonb,'td')
        """,
        payload,
    )
    cur.execute(
        """
        update public.meters_meta
        set version = version + 1,
            meter_count = (select count(*) from public.meters),
            updated_at = now()
        where id = 1
        returning version, meter_count
        """
    )
    print("meta", cur.fetchone(), "rows", len(rows))
    conn.commit()
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
