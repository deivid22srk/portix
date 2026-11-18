# Algoritmo do feed da Início

Documento de referência de `supabase/migrations/0023_home_feed_algorithm.sql`.
Fórmula, pesos, como ajustar e como testar.

## Por que ele existe (causa raiz)

A Início antiga (`home_feed`, 0018) devolvia cinco listas com ordenação
determinística sobre métricas **acumuladas e globais**:

```sql
-- trending / free / classics
order by visit_count desc, title asc
```

`games.visit_count` é um `bigint` monotônico e **nunca decai**. Resultado: os
mesmos jogos no topo para todos os usuários, para sempre. A RPC também não
recebia identidade alguma (só `p_limit`), não havia histórico de exibição e o
cache do cliente repintava o mesmo payload em toda abertura. Três causas somadas:
**ranking determinístico global + métrica que só cresce + cache sem rotação**.

## O que o feed faz agora

RPC `public.get_home_feed(p_seed, p_limit, p_seen, p_cursor, p_sections)`.

### Pontuação por item

```
base      = w_pop * popularidade
          + w_fresh * frescor
          + w_quality * qualidade
          + w_affinity * afinidade

penalizado = max(base - w_rep * repetição, 0)

score      = penalizado * (1 + explore * (2 * ruído - 1))
```

Além do ruído, cada seção (menos `discover`) usa uma **banda de relevância**:
toma os melhores `band_factor × limit` itens por score e os reordena pelo ruído
da seed. O usuário continua vendo o topo do ranking; o que muda entre sessões é
*quem do topo* aparece — sem isso, o jitter sozinho rotacionava pouco o top 10.

O **ruído é multiplicativo** de propósito: ele reordena itens de mérito
parecido, mas não deixa um jogo fraco pular na frente de um forte (isso é o que
diferencia exploração controlada de aleatoriedade pura).

| Componente | Como é calculado |
|---|---|
| popularidade | `0,60 · d/(1+d)` downloads recentes **com decaimento** (meia-vida 7 dias) `+ 0,25 · log(1+download_count) + 0,15 · log(1+visit_count)`, tudo normalizado por `x/(1+x)` |
| frescor | `0,65 · exp(−idade_desde_release/21) + 0,35 · exp(−idade_desde_atividade/10)` |
| qualidade | `0,70 · média_bayesiana/5 + 0,30 · conversão/(1+conversão)`, com média bayesiana `(Σnotas + C·m)/(n + C)`, `C = 5`, `m = 3,5` — evita "5,0 com 1 voto" |
| afinidade | `0,55 · share_gênero + 0,45 · share_desenvolvedor`, sobre os jogos que o usuário favoritou, guardou na biblioteca ou baixou |
| repetição | `0,75` se está em `p_seen` (histórico local enviado pelo cliente); senão `exp(−idade/3)` sobre as impressões do próprio `auth.uid()` (janela 30 dias) |
| ruído | `hashtextextended(game_id, hashtextextended(seed, 0))` normalizado em `[0,1)` — determinístico |

### Pesos (fonte única: `public.feed_weights()`)

| Chave | Valor | Papel |
|---|---|---|
| `popularity` | 1,00 | peso do bloco de popularidade |
| `freshness` | 0,55 | peso do frescor |
| `quality` | 0,45 | peso da qualidade |
| `affinity` | 0,60 | peso da afinidade |
| `explore` | 0,45 | **amplitude do jitter** de exploração (±45%) |
| `repetition` | 0,90 | peso da penalidade de repetição |
| `popularity_window_days` | 35 | janela de downloads (~5 meias-vidas) |
| `download_half_life_days` | 7 | meia-vida do download |
| `release_half_life_days` | 21 | meia-vida do lançamento |
| `activity_half_life_days` | 10 | meia-vida da atualização |
| `seen_half_life_days` | 3 | meia-vida da impressão |
| `rating_prior_count` / `_mean` | 5 / 3,5 | prior da média bayesiana |
| `explore_min_share` | 0,25 | cota mínima de itens fora da zona de conforto |
| `band_factor` | 4,0 | a seção é montada com os melhores `4 × limit` itens por score e reordenada pelo ruído da seed (relevância garantida pela faixa; rotação garantida pela seed) — `discover` fica em 1,0 porque a paginação por cursor exige ordem estável |
| `max_per_developer` | 2 | teto por seção |
| `max_per_genre` | 3 | teto por seção |
| `max_familiar_share` | 0,60 | teto de itens "familiares" por seção |

**Como ajustar:** altere `public.feed_weights()` (uma migration nova) e rode a
simulação no CI. Os limiares medidos estão em `supabase/tests/30_simulation.sql`;
o efeito de cada mudança aparece no relatório do job `feed-sql`.

### Seções

`featured` (hero, 6), `for_you` (só com histórico), `trending`,
`new_releases`, `recently_updated`, `discover` (exploração, **paginada**),
`category:<gênero>` (2 gêneros com mais jogos). Seção vazia é omitida.

### Regras de diversidade

Em `feed_diversify` (função pura, testável): ≤2 por desenvolvedor, ≤3 por
gênero, ≤60% de itens familiares por seção e **nenhum item repetido entre
seções** (`p_used` acumulado).

### Sessão, seed e estabilidade

`seed = hash(anon_id|uid, janela_de_30_min)`, calculada no cliente
(`lib/core/session.dart`). Mesma sessão ⇒ mesma ordem (o feed não "pula"
sozinho). Sessão nova (cold start ou ≥30 min em segundo plano) ou
pull-to-refresh ⇒ seed nova ⇒ outro feed. Há assertiva para os dois lados:
estabilidade com a mesma seed e variação entre seeds.

### Paginação

Keyset em `(score, id)` na seção `discover`, com o cursor devolvido por seção.
Nunca `offset`, então não há item repetido entre páginas (assertiva cobre).

### Impressões

`feed_impressions(id, user_id, anon_id, game_id, section, session_id, seen_at)`,
retenção de 30 dias via `purge_feed_impressions(days)` (agende com `pg_cron` se
o projeto tiver, ou cron externo — a migration **não** assume a extensão). O
cliente envia no máximo 50 por chamada e 5.000 por chave/dia, só quando o card
ficou realmente visível. A tabela **não tem SELECT** para o cliente.

## Segurança

- `get_home_feed`, `feed_candidates`, `feed_diversify` e `feed_projection` → `immutable`, sem acesso a tabela +
  `search_path` fixo; leem sob RLS.
- `feed_seen_recent()` → `security definer` **justificado**: a tabela de
  impressões não tem SELECT público; a função lê apenas `auth.uid()` e não
  aceita identidade como parâmetro, então não expõe histórico alheio.
- `record_feed_impressions()` → `security definer` com validação de dono, teto
  de volume e `search_path` vazio.
- `purge_feed_impressions()` → revogada de `public/anon/authenticated`.
- Nenhuma `service_role` key no app; nenhum secret versionado.

## Performance

- Índices novos: `games_rating_idx`, `games_download_idx`, `games_activity_idx`,
  `downloads_recent_idx` e `downloads_game_recent_idx` (parciais em
  `status='done'`), além dos três de `feed_impressions`.
- Sem materialized view nem `pg_cron`: com 839 jogos a agregação em memória é
  mais barata e sempre fresca. Se o catálogo crescer uma ordem de grandeza, o
  próximo passo é uma MV de popularidade decaída com refresh agendado.
- Evidência: `supabase/tests/40_explain.sql` (volume real) e
  `supabase/tests/45_explain_scale.sql` (2M de downloads + 250k impressões,
  exigindo índice no caminho quente e latência abaixo da meta).

## Como testar

```bash
# local (exige um Postgres descartável; NUNCA aponte para produção)
PGURL=postgresql://postgres:postgres@localhost:5432/postgres \
  bash tools/feed/run_sql_tests.sh
```

O script aplica **todas** as migrations em ordem, semeia 839 jogos, roda as
assertivas (`20_assertions.sql`), a simulação de 20 aberturas antes × depois
(`30_simulation.sql`), o `EXPLAIN ANALYZE` (`40_explain.sql`) e o teste de
escala (`45_explain_scale.sql`). No CI isso roda no job `feed-sql`.
