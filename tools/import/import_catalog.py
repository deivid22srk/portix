#!/usr/bin/env python3
"""Importa o catálogo de ports (JSON) para o Supabase de forma idempotente.

 - Lê os campos reais do arquivo: games[].ports[] + sourceRows[] (VISITAS).
 - Não contém segredos: usa SUPA e SUPABASE_PROJECT_REF do ambiente.
 - Envia em lotes via Management API (POST /database/query), com upsert.
 - O JSON/ZIP bruto nunca é comitado: use --input apontando para fora do repo.

Uso:
    SUPA=... SUPABASE_PROJECT_REF=... \
      python3 tools/import/import_catalog.py --input /tmp/catalog/napl_android_port_catalog.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import unicodedata
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from datetime import date

API = "https://api.supabase.com/v1"
BATCH = 200

# --------------------------------------------------------------------- helpers
MONTHS = {
    "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11,
    "december": 12,
}


def clean(value) -> str:
    if value is None:
        return ""
    text = str(value).replace("\u00a0", " ").strip()
    return "" if text in {"-", "—", "N/A", "n/a"} else text


def slugify(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text.lower()).strip("-")
    return text or "game"


def parse_date(value: str) -> str | None:
    text = clean(value)
    if not text:
        return None
    iso = re.match(r"^(\d{4})-(\d{2})-(\d{2})", text)
    if iso:
        try:
            return date(int(iso.group(1)), int(iso.group(2)), int(iso.group(3))).isoformat()
        except ValueError:
            return None
    match = re.match(r"^(\d{4})\s*,\s*([A-Za-z]+)\s*(\d{1,2})?", text)
    if match:
        year = int(match.group(1))
        month = MONTHS.get(match.group(2).lower())
        day = int(match.group(3)) if match.group(3) else 1
        if month:
            try:
                return date(year, month, day).isoformat()
            except ValueError:
                return date(year, month, 1).isoformat()
    return None


def parse_year(value: str) -> int | None:
    text = clean(value)
    if not text:
        return None
    match = re.match(r"^(\d{4})", text)
    if not match:
        return None
    year = int(match.group(1))
    return year if 1950 <= year <= 2035 else None


def parse_visits(value) -> int:
    text = clean(value).replace(".", "").replace(",", ".")
    try:
        return max(0, int(float(text)))
    except ValueError:
        return 0


def normalize_url(value: str) -> str | None:
    text = clean(value)
    if not text:
        return None
    text = re.sub(r"^(https?):/+", r"\1://", text)
    text = text.replace(" ", "%20")
    if not re.match(r"^https?://", text):
        return None
    return text


def normalize_works(value: str) -> str | None:
    text = clean(value).lower()
    if not text:
        return None
    if text.startswith("yes") or text == "y":
        return "yes"
    if text.startswith("no"):
        return "no"
    if "test" in text:
        return "untested"
    if "bug" in text:
        return "bug"
    if "kind" in text or "partial" in text:
        return "partial"
    return None


# ---------------------------------------------------------------- plataformas
# slug: (nome curto, nome completo, tipo, ordem)
PLATFORMS: dict[str, tuple[str, str, str, int]] = {
    "n64": ("N64", "Nintendo 64", "console", 10),
    "xbox-360": ("Xbox 360", "XBOX 360", "console", 20),
    "wii": ("Wii", "Nintendo Wii", "console", 30),
    "gamecube": ("GameCube", "Nintendo GameCube", "console", 40),
    "switch": ("Switch", "Nintendo Switch", "console", 50),
    "ps1": ("PS1", "PlayStation", "console", 60),
    "ps2": ("PS2", "PlayStation 2", "console", 70),
    "gba": ("GBA", "Game Boy Advance", "handheld", 80),
    "snes": ("SNES", "Super Nintendo", "console", 90),
    "gbc": ("GBC", "Game Boy Color", "handheld", 100),
    "gb": ("GB", "Game Boy", "handheld", 110),
    "nds": ("DS", "Nintendo DS", "handheld", 120),
    "psp": ("PSP", "PlayStation Portable", "handheld", 130),
    "xbox": ("Xbox", "XBOX", "console", 140),
    "3ds": ("3DS", "Nintendo 3DS", "handheld", 150),
    "wii-u": ("Wii U", "Nintendo Wii U", "console", 160),
    "ps3": ("PS3", "PlayStation 3", "console", 170),
    "ps4": ("PS4", "PlayStation 4", "console", 180),
    "mega-drive": ("Mega Drive", "SEGA Mega Drive / Genesis", "console", 190),
    "nes": ("NES", "Nintendo Entertainment System", "console", 200),
    "switch-2": ("Switch 2", "Nintendo Switch 2", "console", 210),
    "shield": ("Shield", "Nvidia Shield", "console", 220),
    "android": ("Android", "Android (32 to 64 bits)", "mobile", 230),
    "ios": ("iOS", "iOS", "mobile", 240),
    "multi": ("Multi-jogos", "Multi-Game Apps", "multi", 900),
    "others": ("Outros", "Outros / PC", "other", 990),
}

PLATFORM_ALIASES = {
    "sega mega drive / genesis": "mega-drive",
    "nintendo entertainment system": "nes",
    "super nintendo": "snes",
    "nintendo 64": "n64",
    "gamecube": "gamecube",
    "nintendo wii": "wii",
    "nintendo wii u": "wii-u",
    "nintendo switch": "switch",
    "nintendo switch  2": "switch-2",
    "nintendo switch 2": "switch-2",
    "game boy": "gb",
    "game boy color": "gbc",
    "gameboy advance": "gba",
    "nintendo ds": "nds",
    "nintendo 3ds": "3ds",
    "playstation": "ps1",
    "playstation 2": "ps2",
    "playstation 3": "ps3",
    "playstation 4": "ps4",
    "playstation portable": "psp",
    "xbox": "xbox",
    "xbox 360": "xbox-360",
    "nvidia shield": "shield",
    "ios": "ios",
    "android (32 to 64bits)": "android",
    "multi-game apps": "multi",
    "others": "others",
}


def platform_slug(raw: str) -> str:
    key = re.sub(r"\s+", " ", clean(raw)).lower()
    return PLATFORM_ALIASES.get(key, "others")


# ---------------------------------------------------------------- normalização
def build_catalog(payload: dict) -> tuple[list[dict], list[dict], dict]:
    source_rows = payload.get("sourceRows") or []
    games_in = payload.get("games") or []

    raw_ports: list[dict] = []
    for game in games_in:
        for port in game.get("ports") or []:
            raw_ports.append(port)

    # deduplica linhas idênticas (mesmo jogo, plataforma, projeto e URL)
    seen: dict[tuple, dict] = {}
    duplicates = 0
    for port in raw_ports:
        key = (
            clean(port.get("game")).lower(),
            platform_slug(port.get("platform", "")),
            clean(port.get("project")).lower(),
            normalize_url(port.get("url", "")) or "",
        )
        current = seen.get(key)
        if current is None:
            seen[key] = port
            continue
        duplicates += 1
        idx = port.get("sourceRowIndex")
        visits = parse_visits(source_rows[idx].get("VISITAS")) if isinstance(idx, int) and idx < len(source_rows) else 0
        cur_idx = current.get("sourceRowIndex")
        cur_visits = parse_visits(source_rows[cur_idx].get("VISITAS")) if isinstance(cur_idx, int) and cur_idx < len(source_rows) else 0
        if visits > cur_visits:
            seen[key] = port

    ports_dedup = list(seen.values())

    # agrupa ports por jogo (slug único)
    used_slugs: set[str] = set()
    games_out: list[dict] = []
    ports_out: list[dict] = []
    dropped_no_name = 0

    for game in games_in:
        name = clean(game.get("name"))
        if not name:
            dropped_no_name += 1
            continue
        base = slugify(clean(game.get("slug")) or name)
        slug = base
        suffix = 2
        while slug in used_slugs:
            slug = f"{base}-{suffix}"
            suffix += 1
        used_slugs.add(slug)

        own = [p for p in ports_dedup if clean(p.get("game")).lower() == name.lower()]
        own.sort(key=lambda p: (-parse_visits((source_rows[p["sourceRowIndex"]].get("VISITAS")
                                              if isinstance(p.get("sourceRowIndex"), int)
                                              and p["sourceRowIndex"] < len(source_rows) else ""))))

        descriptions = [clean(p.get("description")) for p in own if clean(p.get("description"))]
        developers = [clean(p.get("developer")) for p in own if clean(p.get("developer"))]
        genres = [clean(p.get("genre")) for p in own if clean(p.get("genre"))]
        covers = [normalize_url(p.get("coverUrl", "")) for p in own]
        covers = [c for c in covers if c]
        years = [parse_year(p.get("year")) for p in own]
        years = [y for y in years if y]

        games_out.append({
            "slug": slug,
            "title": name,
            "year": parse_year(game.get("year")) or (min(years) if years else None),
            "genre": (Counter(genres).most_common(1)[0][0] if genres else clean(game.get("genre")) or None),
            "description": max(descriptions, key=len) if descriptions else clean(game.get("description")),
            "cover_url": covers[0] if covers else None,
            "developer": (Counter(developers).most_common(1)[0][0] if developers else clean(game.get("developer")) or None),
        })

        for index, port in enumerate(own):
            row_index = port.get("sourceRowIndex")
            source = source_rows[row_index] if isinstance(row_index, int) and row_index < len(source_rows) else {}
            needs_raw = clean(port.get("needsGameFiles"))
            needs = bool(needs_raw) and needs_raw.lower() not in {"no", "nao", "não"}
            visits = parse_visits(source.get("VISITAS"))
            ports_out.append({
                "game_slug": slug,
                "port_key": f"row-{row_index}" if isinstance(row_index, int) else f"{slug}-{index}",
                "platform_slug": platform_slug(port.get("platform", "")),
                "project": clean(port.get("project")) or None,
                "source": clean(port.get("link")) or None,
                "url": normalize_url(port.get("url", "")),
                "data_url": normalize_url(port.get("dataUrl", "")),
                "developer": clean(port.get("developer")) or None,
                "version": clean(port.get("version")) or None,
                "last_update": parse_date(port.get("lastUpdate", "")),
                "date_added": parse_date(port.get("dateAdded", "")),
                "needs_game_files": needs,
                "needs_game_files_note": needs_raw if needs and needs_raw.lower() != "yes" else None,
                "works": normalize_works(port.get("works", "")),
                "controller_support": clean(port.get("controllerSupport")) or None,
                "notes": clean(port.get("notes")) or None,
                "visits": visits,
                "sort_index": index,
            })

    games_out.sort(key=lambda g: g["slug"])
    ports_out.sort(key=lambda p: p["port_key"])

    stats = {
        "sourceGames": len(games_in),
        "sourcePorts": len(raw_ports),
        "games": len(games_out),
        "ports": len(ports_out),
        "platforms": len(PLATFORMS),
        "duplicatesRemoved": duplicates,
        "droppedNoName": dropped_no_name,
        "portsWithoutUrl": sum(1 for p in ports_out if not p["url"]),
        "gamesWithoutCover": sum(1 for g in games_out if not g["cover_url"]),
        "gamesWithoutGenre": sum(1 for g in games_out if not g["genre"]),
    }
    return games_out, ports_out, stats


# ---------------------------------------------------------------- Management API
def run_sql(sql: str) -> dict:
    token = os.environ.get("SUPA", "").strip()
    ref = os.environ.get("SUPABASE_PROJECT_REF", "").strip()
    if not token or not ref:
        raise SystemExit("defina SUPA e SUPABASE_PROJECT_REF no ambiente")
    req = urllib.request.Request(
        f"{API}/projects/{ref}/database/query",
        data=json.dumps({"query": sql}).encode("utf-8"),
        method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"HTTP {exc.code}:\n{body[:3000]}") from exc


def json_literal(payload) -> str:
    text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    if "$catalog$" in text:
        raise SystemExit("payload contém o delimitador $catalog$; ajuste o delimitador")
    return f"$catalog${text}$catalog$"


def chunked(items: list, size: int = BATCH):
    for start in range(0, len(items), size):
        yield items[start:start + size]


def upsert_platforms() -> None:
    rows = [
        {"slug": slug, "name": name, "full_name": full, "kind": kind, "sort_order": order}
        for slug, (name, full, kind, order) in PLATFORMS.items()
    ]
    run_sql(
        """
        insert into public.platforms (slug, name, full_name, kind, sort_order)
        select x.slug, x.name, x.full_name, x.kind, x.sort_order
        from jsonb_to_recordset(%s::jsonb) as x(
          slug text, name text, full_name text, kind text, sort_order smallint
        )
        on conflict (slug) do update
          set name = excluded.name,
              full_name = excluded.full_name,
              kind = excluded.kind,
              sort_order = excluded.sort_order;
        """ % json_literal(rows)
    )


def upsert_games(games: list[dict]) -> None:
    for batch in chunked(games):
        run_sql(
            """
            insert into public.games (slug, title, year, genre, description, cover_url, developer)
            select x.slug, x.title, x.year, x.genre, coalesce(x.description, ''),
                   x.cover_url, x.developer
            from jsonb_to_recordset(%s::jsonb) as x(
              slug text, title text, year smallint, genre text,
              description text, cover_url text, developer text
            )
            on conflict (slug) do update
              set title = excluded.title,
                  year = coalesce(excluded.year, public.games.year),
                  genre = coalesce(excluded.genre, public.games.genre),
                  description = case when excluded.description <> '' then excluded.description
                                     else public.games.description end,
                  cover_url = coalesce(excluded.cover_url, public.games.cover_url),
                  developer = coalesce(excluded.developer, public.games.developer);
            """ % json_literal(batch)
        )


def upsert_ports(ports: list[dict]) -> None:
    for batch in chunked(ports):
        run_sql(
            """
            insert into public.ports (port_key, game_id, platform_id, project, source, url,
              data_url, developer, version, last_update, date_added, needs_game_files,
              needs_game_files_note, works, controller_support, notes, visits, sort_index)
            select x.port_key, g.id, pl.id, x.project, x.source, x.url, x.data_url,
                   x.developer, x.version, x.last_update::date, x.date_added::date,
                   x.needs_game_files, x.needs_game_files_note, x.works,
                   x.controller_support, x.notes, x.visits, x.sort_index
            from jsonb_to_recordset(%s::jsonb) as x(
              game_slug text, port_key text, platform_slug text, project text, source text,
              url text, data_url text, developer text, version text, last_update text,
              date_added text, needs_game_files boolean, needs_game_files_note text,
              works text, controller_support text, notes text, visits int, sort_index int
            )
            join public.games g on g.slug = x.game_slug
            join public.platforms pl on pl.slug = x.platform_slug
            on conflict (port_key) do update
              set game_id = excluded.game_id,
                  platform_id = excluded.platform_id,
                  project = excluded.project,
                  source = excluded.source,
                  url = excluded.url,
                  data_url = excluded.data_url,
                  developer = excluded.developer,
                  version = excluded.version,
                  last_update = excluded.last_update,
                  date_added = excluded.date_added,
                  needs_game_files = excluded.needs_game_files,
                  needs_game_files_note = excluded.needs_game_files_note,
                  works = excluded.works,
                  controller_support = excluded.controller_support,
                  notes = excluded.notes,
                  visits = excluded.visits,
                  sort_index = excluded.sort_index;
            """ % json_literal(batch)
        )


def refresh_aggregates() -> None:
    run_sql(
        """
        with agg as (
          select po.game_id,
                 count(*)::int as port_count,
                 coalesce(sum(po.visits), 0)::bigint as visit_count,
                 bool_or(coalesce(po.source, '') ilike 'free%%'
                         or coalesce(po.source, '') ilike 'mirror%%') as is_free,
                 bool_or(po.needs_game_files) as needs_rom,
                 min(po.date_added) as released_on,
                 max(po.last_update) as last_activity_on,
                 array_agg(distinct pl.slug) as slugs,
                 array_agg(distinct pl.name) as names
          from public.ports po
          join public.platforms pl on pl.id = po.platform_id
          group by po.game_id
        )
        update public.games g
           set port_count = agg.port_count,
               visit_count = agg.visit_count,
               is_free = agg.is_free,
               needs_rom = agg.needs_rom,
               released_on = agg.released_on,
               last_activity_on = agg.last_activity_on,
               platform_slugs = agg.slugs,
               platforms = agg.names
          from agg
         where agg.game_id = g.id;
        """
    )


def verify(expected_games: int, expected_ports: int) -> dict:
    result = run_sql(
        """
        select (select count(*) from public.games) as games,
               (select count(*) from public.ports) as ports,
               (select count(*) from public.platforms) as platforms,
               (select count(*) from public.games where port_count = 0) as games_without_ports;
        """
    )
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="caminho do JSON bruto (fora do repositório)")
    parser.add_argument("--dry-run", action="store_true", help="apenas normaliza e mostra o relatório")
    parser.add_argument("--report", default=None, help="grava o relatório JSON neste caminho")
    args = parser.parse_args()

    with open(args.input, "r", encoding="utf-8") as handle:
        payload = json.load(handle)

    games, ports, stats = build_catalog(payload)
    print(json.dumps(stats, indent=2, ensure_ascii=False))

    if args.report:
        with open(args.report, "w", encoding="utf-8") as handle:
            json.dump(stats, handle, indent=2, ensure_ascii=False)

    if args.dry_run:
        return

    upsert_platforms()
    print(f"plataformas: {len(PLATFORMS)}")
    upsert_games(games)
    print(f"jogos: {len(games)}")
    upsert_ports(ports)
    print(f"ports: {len(ports)}")
    refresh_aggregates()
    print("agregados recalculados")

    db = verify(len(games), len(ports))
    print("banco:", json.dumps(db, ensure_ascii=False))
    first = db[0] if isinstance(db, list) and db else db
    if isinstance(first, dict):
        assert int(first["games"]) == len(games), "contagem de jogos divergente"
        assert int(first["ports"]) == len(ports), "contagem de ports divergente"
    print("validação OK")


if __name__ == "__main__":
    main()
