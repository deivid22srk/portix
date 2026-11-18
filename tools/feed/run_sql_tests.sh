#!/usr/bin/env bash
# ============================================================================
# tools/feed/run_sql_tests.sh — valida o algoritmo do feed em um Postgres real.
#
# Aplica TODAS as migrations (o mesmo SQL que vai para produção, em ordem),
# semeia um catálogo com o volume real (839 jogos), roda as assertivas, a
# simulação de 20 aberturas (antes × depois), o EXPLAIN ANALYZE e o teste de
# escala. Falha o build em qualquer erro.
#
# Uso:  PGURL=postgresql://postgres:postgres@localhost:5432/postgres \
#         bash tools/feed/run_sql_tests.sh
# NÃO toca em produção: o Postgres é efêmero, criado pelo serviço do job.
# ============================================================================
set -euo pipefail

PGURL="${PGURL:-postgresql://postgres:postgres@localhost:5432/postgres}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

run_sql() {
  local file="$1"
  echo
  echo "──────────────────────────────────────────────────────────────"
  echo "### $file"
  psql "$PGURL" --no-psqlrc -X -v ON_ERROR_STOP=1 -q -f "$file"
}

run_sql "$ROOT/supabase/tests/00_bootstrap.sql"

for migration in "$ROOT"/supabase/migrations/*.sql; do
  run_sql "$migration"
done

run_sql "$ROOT/supabase/tests/05_testkit.sql"
run_sql "$ROOT/supabase/tests/10_seed.sql"
run_sql "$ROOT/supabase/tests/20_assertions.sql"
run_sql "$ROOT/supabase/tests/30_simulation.sql"
run_sql "$ROOT/supabase/tests/40_explain.sql"
run_sql "$ROOT/supabase/tests/45_explain_scale.sql"

echo
echo "FEED_SQL: migrations aplicadas, assertivas, simulação e EXPLAIN verdes."
