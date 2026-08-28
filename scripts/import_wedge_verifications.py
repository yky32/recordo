#!/usr/bin/env python3
"""Import gate-checked wedge prices into public.parks (Phase A).

Reads `data/wedge_verification_queue.json`:
- append gate observations to `verified`
- run this script to promote them in Supabase

Each verified row requires:
  parkId, observedAt (YYYY-MM-DD), source (gate|operator),
  and at least one of hourlyHkd / dailyHkd / nightHkd / priceNote.

Never increments ugc_confirms.
"""
from __future__ import annotations

import json
import os
import ssl
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QUEUE = ROOT / "data" / "wedge_verification_queue.json"
ENV_FILE = ROOT / ".env.supabase"
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


def sql_str(v: object) -> str:
    if v is None:
        return "null"
    return "'" + str(v).replace("'", "''") + "'"


def sql_num(v: object) -> str:
    if v is None or v == "":
        return "null"
    return repr(float(v))


def project_ref(url: str) -> str:
    host = url.replace("https://", "").replace("http://", "").split("/")[0]
    return host.split(".supabase.co")[0]


def run_sql(sql: str) -> None:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    url = os.environ.get("SUPABASE_URL", "").strip()
    db = os.environ.get("DATABASE_URL", "").strip()
    if token and url:
        body = json.dumps({"query": sql}).encode("utf-8")
        req = urllib.request.Request(
            f"https://api.supabase.com/v1/projects/{project_ref(url)}/database/query",
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
        return
    if db:
        r = subprocess.run(
            ["psql", db, "-v", "ON_ERROR_STOP=1", "-c", sql],
            capture_output=True,
            text=True,
        )
        if r.returncode != 0:
            raise SystemExit(f"psql failed:\n{r.stderr or r.stdout}")
        return
    raise SystemExit("Need SUPABASE_ACCESS_TOKEN + SUPABASE_URL, or DATABASE_URL")


def fail(msg: str) -> None:
    raise SystemExit(msg)


def validate(entry: dict) -> None:
    if not entry.get("parkId"):
        fail("verified row missing parkId")
    if not entry.get("observedAt"):
        fail(f"{entry.get('parkId')}: missing observedAt")
    src = (entry.get("source") or "").strip().lower()
    if src not in {"gate", "operator"}:
        fail(f"{entry.get('parkId')}: source must be gate or operator")
    has_fee = any(
        entry.get(k) is not None
        for k in ("hourlyHkd", "dailyHkd", "nightHkd", "priceNote")
    )
    if not has_fee:
        fail(f"{entry.get('parkId')}: need hourly/daily/night/note")


def update_sql(entry: dict) -> str:
    pid = entry["parkId"]
    src = entry["source"].strip().lower()
    note = entry.get("priceNote")
    return f"""
update public.parks set
  hourly_hkd = {sql_num(entry.get('hourlyHkd'))},
  daily_hkd = {sql_num(entry.get('dailyHkd'))},
  night_hkd = {sql_num(entry.get('nightHkd'))},
  price_note = coalesce({sql_str(note)}, price_note),
  price_verification_status = 'verified',
  price_verified_at = {sql_str(entry['observedAt'])}::timestamptz,
  price_provenance = {sql_str(src)},
  ugc_confirms = 0,
  updated_at = now()
where id = {sql_str(pid)};
""".strip()


def main() -> int:
    load_dotenv()
    if not QUEUE.exists():
        fail(f"missing {QUEUE}")
    data = json.loads(QUEUE.read_text(encoding="utf-8"))
    verified = data.get("verified") or []
    if not verified:
        print("No verified rows in queue — add gate data to verified[] first.")
        return 0

    stmts = []
    for row in verified:
        validate(row)
        stmts.append(update_sql(row))

    stmts.append(
        "update public.catalog_meta set version = version + 1, updated_at = now() where id = 1;"
    )
    run_sql("\n".join(stmts))
    print(f"Applied {len(verified)} verified wedge price(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
