#!/usr/bin/env python3
"""Ingest TD per-bay meters (msd_1). Does not touch parks or street meters."""

from __future__ import annotations

import csv
import io
import os
import urllib.request

import psycopg

URL = "https://resource.data.one.gov.hk/td/psiparkingspaces/spaceinfo/parkingspaces.csv"


def fetch_rows() -> list[tuple]:
    req = urllib.request.Request(URL, headers={"User-Agent": "recordo-meters/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        text = r.read().decode("utf-8-sig")
    lines = text.splitlines()
    i = 0
    while i < len(lines) and not lines[i].startswith("PoleId"):
        i += 1
    rdr = csv.DictReader(io.StringIO("\n".join(lines[i:])))
    out: list[tuple] = []
    seen: set[str] = set()
    for row in rdr:
        sid = (row.get("ParkingSpaceId") or "").strip()
        if not sid or sid in seen:
            continue
        try:
            lat = float(row["Latitude"])
            lng = float(row["Longitude"])
        except (TypeError, ValueError, KeyError):
            continue
        if abs(lat) < 0.01 or abs(lng) < 0.01:
            continue
        seen.add(sid)
        lpp_raw = (row.get("LPP") or "").strip()
        lpp = int(float(lpp_raw)) if lpp_raw else None
        tu_raw = (row.get("TimeUnit") or "").strip() or "15"
        pu_raw = (row.get("PaymentUnit") or "").strip() or "4"
        try:
            time_unit = int(float(tu_raw))
        except ValueError:
            time_unit = 15
        try:
            payment = float(pu_raw)
        except ValueError:
            payment = 4.0
        out.append(
            (
                sid,
                (row.get("PoleId") or "").strip() or None,
                (row.get("District_tc") or row.get("District") or "").strip(),
                (row.get("SubDistrict_tc") or row.get("SubDistrict") or "").strip(),
                (row.get("Street_tc") or row.get("Street") or "").strip(),
                (row.get("SectionOfStreet_tc") or row.get("SectionOfStreet") or "").strip(),
                lat,
                lng,
                (row.get("VehicleType") or "A").strip() or "A",
                lpp,
                (row.get("OperatingPeriod") or "").strip(),
                time_unit,
                payment,
            )
        )
    return out


def apply_schema(cur) -> None:
    cur.execute(
        """
        create table if not exists public.meter_spaces (
          id text primary key,
          pole_id text,
          district text not null default '',
          sub_district text not null default '',
          street text not null default '',
          section text not null default '',
          lat double precision not null,
          lng double precision not null,
          vehicle_type text not null default 'A',
          lpp int,
          hours_class text not null default '',
          time_unit int not null default 15,
          payment_unit numeric not null default 4,
          updated_at timestamptz not null default now()
        )
        """
    )
    cur.execute(
        "create index if not exists meter_spaces_lat_lng on public.meter_spaces (lat, lng)"
    )
    cur.execute("alter table public.meter_spaces enable row level security")
    cur.execute("drop policy if exists meter_spaces_select_anon on public.meter_spaces")
    cur.execute(
        """
        create policy meter_spaces_select_anon on public.meter_spaces
          for select to anon, authenticated using (true)
        """
    )
    cur.execute(
        """
        create or replace function public.meter_spaces_in_bbox(
          min_lat double precision,
          min_lng double precision,
          max_lat double precision,
          max_lng double precision
        )
        returns jsonb
        language sql
        stable
        security definer
        set search_path = public
        as $$
          select coalesce(
            (
              select jsonb_agg(row_to_json(x))
              from (
                select
                  s.id,
                  s.pole_id as "poleId",
                  s.district,
                  s.sub_district as "subDistrict",
                  s.street,
                  s.section,
                  s.lat,
                  s.lng,
                  s.vehicle_type as "vehicleType",
                  s.lpp,
                  s.hours_class as "hoursClass",
                  s.time_unit as "timeUnit",
                  s.payment_unit as "paymentUnit"
                from public.meter_spaces s
                where s.lat between min_lat and max_lat
                  and s.lng between min_lng and max_lng
                limit 400
              ) x
            ),
            '[]'::jsonb
          );
        $$
        """
    )
    cur.execute(
        """
        grant execute on function public.meter_spaces_in_bbox(
          double precision, double precision, double precision, double precision
        ) to anon, authenticated
        """
    )
    cur.execute("grant select on public.meter_spaces to anon, authenticated")


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
    apply_schema(cur)
    cur.execute("truncate public.meter_spaces")
    cur.executemany(
        """
        insert into public.meter_spaces (
          id, pole_id, district, sub_district, street, section,
          lat, lng, vehicle_type, lpp, hours_class, time_unit, payment_unit
        ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        rows,
    )
    cur.execute("select count(*) from public.meter_spaces")
    print("meter_spaces", cur.fetchone()[0])
    conn.commit()
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
