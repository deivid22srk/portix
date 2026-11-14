# Segurança (Blue Team)

Canal do jogo: `public.breach_signal` (insert-only para os clientes de baixo
privilégio; leitura própria). **Nunca apagar registros** desse histórico.

Monitorar:

```bash
export SUPA="<management-token>"
export SUPABASE_PROJECT_REF="<ref>"
python3 tools/security/monitor.py
```

## Auditoria inicial (0005_security_hardening.sql)

| # | Achado | Risco | Correção |
| - | ------ | ----- | -------- |
| 1 | `anon`/`authenticated` com INSERT/UPDATE/DELETE/**TRUNCATE**/REFERENCES/TRIGGER em todas as tabelas (ACL padrão) | TRUNCATE ignora RLS; superfície excessiva | `REVOKE ALL` por tabela e re-concessão mínima por role |
| 2 | `EXECUTE` de todas as funções de `public` para `PUBLIC` | funções (incl. SECURITY DEFINER) expostas | `REVOKE EXECUTE ... FROM public, anon, authenticated` + grants explícitos |
| 3 | `compat_reports` com SELECT público | vazava `user_id`/nota de todos | leitura direta revogada de `anon`; agregado via `compat_summary` (SECURITY DEFINER) |
| 4 | `SECURITY DEFINER` com `search_path=public` | risco de hijack de search_path | `search_path = ''` + nomes totalmente qualificados |
| 5 | Não existia `breach_signal` | sem canal do jogo | tabela criada com RLS (insert/select own) |

## Sinais do Atacante (histórico em `breach_signal`, nunca apagado)

| Sinal | Vetor | Correção |
| ----- | ----- | -------- |
| 1 (probe) | insert no canal | canal validado; nada a corrigir |
| 2 (probe) | insert autenticado no canal | integridade de `reporter` (0007) |
| 3 | `compat_public_read` `USING(true)` valia para `authenticated` | 0006: policy pública removida; leitura só do dono; agregado via `compat_summary` |
| 4 | `profiles`/`reviews` com SELECT público listavam PII | 0008: leitura direta revogada; `game_detail` vira definer e entrega reviews+autor |
| 5 | cadastro anônimo sem limite | 0008: rate limit por usuário (triggers) + constraints únicas |
| 6 | `created_at` gravável pelo cliente → bypass do rate limit por retrodatação | 0009: triggers `a_*` carimbam `created_at`/`updated_at` no servidor antes do rate limit |

Migrations: `0005_security_hardening`, `0006_fix_compat_read`,
`0007_breach_signal_integrity`, `0008_privacy_and_rate_limit`,
`0009_server_timestamps`, `0010_input_hardening`.

Extras proativos (0010): termo de busca limitado a 120 caracteres e
`display_name` limitado a 80.

### Verificação (anon e sessão anônima)

- `INSERT/TRUNCATE` em `games`: negado.
- `SELECT` direto em `compat_reports`: negado (401).
- `EXECUTE` de `toggle_favorite` por `anon`: negado.
- `INSERT` em `breach_signal`: permitido; `UPDATE/DELETE`: negado.
- App preservado: `home_feed`, `game_detail`, `search_games`, `catalog_facets`,
  `news_feed`, `games_by_platform` (anon) e `my_collections`,
  `submit_compat_report`, `compat_summary` (sessão anônima) retornam 200.

## Privilégios finais (anon)

`SELECT` em `games`, `platforms`, `ports`, `profiles`, `reviews`, `game_cards`;
`INSERT, SELECT` em `breach_signal`. Nada de DML no catálogo, nada de acesso a
`favorites`/`library`/`downloads`/`compat_reports`.

## Pendências conhecidas (aceitas por design)

- Cadastro anônimo habilitado (necessário ao app; cada instalação vira um usuário
  `authenticated`). Sem captcha/rate-limit próprio.
- `reviews` e `profiles` com leitura pública (conteúdo público do catálogo).
