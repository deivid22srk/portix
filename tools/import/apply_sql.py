#!/usr/bin/env python3
"""Aplica migrations SQL no projeto Supabase via Management API.

Uso:
    SUPA=<token> SUPABASE_PROJECT_REF=<ref> python3 tools/import/apply_sql.py supabase/migrations/*.sql

Nunca contém segredos: o token vem do ambiente.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.supabase.com/v1"


def _request(path: str, method: str, payload: dict) -> dict:
    token = os.environ.get("SUPA", "").strip()
    if not token:
        raise SystemExit("SUPA não definido no ambiente.")
    req = urllib.request.Request(
        API + path,
        data=json.dumps(payload).encode("utf-8"),
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"HTTP {exc.code} em {path}:\n{body[:2000]}") from exc


def run_sql(sql: str) -> dict:
    ref = os.environ.get("SUPABASE_PROJECT_REF", "").strip()
    if not ref:
        raise SystemExit("SUPABASE_PROJECT_REF não definido no ambiente.")
    return _request(f"/projects/{ref}/database/query", "POST", {"query": sql})


def main() -> None:
    paths = sys.argv[1:]
    if not paths:
        raise SystemExit("informe ao menos um arquivo .sql")
    for path in paths:
        with open(path, "r", encoding="utf-8") as handle:
            sql = handle.read()
        run_sql(sql)
        print(f"ok: {path} ({len(sql)} bytes)")


if __name__ == "__main__":
    main()
