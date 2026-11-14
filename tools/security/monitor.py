#!/usr/bin/env python3
"""Blue Team — lê o canal `breach_signal` sem nunca apagar registros.

Uso:
    SUPA=<token> SUPABASE_PROJECT_REF=<ref> python3 tools/security/monitor.py

Mostra cada sinal (vetor + prova) reportado pelo Atacante. Use a Management API
(credencial privilegiada); o token nunca é impresso.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.supabase.com/v1"


def run_sql(sql: str) -> list[dict]:
    token = os.environ.get("SUPA", "").strip()
    ref = os.environ.get("SUPABASE_PROJECT_REF", "").strip()
    if not token or not ref:
        raise SystemExit("defina SUPA e SUPABASE_PROJECT_REF no ambiente")
    request = urllib.request.Request(
        f"{API}/projects/{ref}/database/query",
        data=json.dumps({"query": sql}).encode("utf-8"),
        method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw.strip() else []
    except urllib.error.HTTPError as error:
        raise SystemExit(f"HTTP {error.code}: {error.read().decode('utf-8', 'replace')[:500]}")


def main() -> None:
    rows = run_sql(
        "select id, created_at, vector, proof, reporter, resolved "
        "from public.breach_signal order by created_at"
    )
    print(f"{len(rows)} sinal(is) em public.breach_signal")
    for row in rows:
        print(json.dumps(row, ensure_ascii=False))


if __name__ == "__main__":
    main()
