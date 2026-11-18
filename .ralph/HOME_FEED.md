# Missão: redesenho da Início + algoritmo de feed (Supabase)

Branch: `feat/inicio-redesign-feed-algoritmo`, criada a partir de
`feat/navbar-header-redesign` (**decisão do usuário**). Motivo: a `main` está
defasada e não tem `AppHeaderSliver`/navegação adaptativa/temas multi-tema, e a
missão manda reutilizar exatamente esses componentes. O PR abre com base em
`feat/navbar-header-redesign`; o alvo final é a `main` depois do merge do PR #2.

---

## Fase 0 — reconhecimento (evidência no código)

### 1. Stack e ativos reutilizáveis

Flutter + Riverpod 3 + go_router 18 + Supabase (RPC via `supabase_flutter`) sobre
o pacote `material_ui`. Reutilizáveis: `AppHeaderSliver`/`AppHeaderBar`,
navegação adaptativa (`AppNavBottomBar`/`Rail`/`Sidebar`), `AppChromeScope`
(inset da chrome), `TabScrollRegistry`/`TabScrollScope` (scroll por aba),
`GameCard`/`GameMedia` (capa procedural), `HeroCarousel`, `SectionHeader`,
chips de plataforma/gênero, `CacheStore` (SharedPreferences), tokens
(`AppRadii`/`AppSpacing`/`AppBreakpoints`/`AppMotion`/`AppContentColors`) e temas
múltiplos via `context.colors`/`context.texts`.

### 2. Seções e queries da Início (antes)

- Cliente: uma chamada `rpc('home_feed', {p_limit: 10})` em
  `lib/data/supabase_catalog_repository.dart:46`; gravada em `cache.home_feed`
  (`:52`) e repintada em `lib/features/home/home_controller.dart:35-41`
  (stale-while-revalidate). Retorno: `trending`, `recent`, `top_rated`, `free`,
  `classics`, `platforms`, `genres`, `stats`.
- Banco (vigente): `public.home_feed(p_limit int default 10)` em
  `supabase/migrations/0018_download_counts.sql:55-142` (reescrita de 0003/0004):

| seção | filtro | ordenação |
|---|---|---|
| trending | — | `visit_count desc, title asc` |
| recent | `released_on is not null` | `released_on desc, title asc` |
| top_rated | `rating_count > 0` | `rating_avg desc, rating_count desc, visit_count desc` |
| free | `is_free` | `visit_count desc, title asc` |
| classics | `year <= 2000` | `visit_count desc, title asc` |

- Sem parâmetro de usuário/sessão/seed/offset/cursor; sem diversidade; sem
  histórico de exibição; sem paginação.

### 3. Causa raiz do "sempre as mesmas coisas"

Três causas somadas (nenhuma resolve sozinha):

1. **Ordenação determinística por métrica acumulada e global** —
   `0018:69,80,91,102,113`. `games.visit_count` é `bigint` monotônico
   (`0001_schema.sql:35`) e **nunca decai**: "o mais popular de sempre" fica
   cravado no topo para todos os usuários, para sempre.
2. **A RPC não recebe identidade alguma** — assinatura só `p_limit int`
   (`0018:55`). Não há `anon_id`/`session_id` no cliente (busca vazia em `lib/`)
   nem tabela de impressões → impossível rotacionar, personalizar ou penalizar
   repetição.
3. **Cache amplifica o determinismo** — `home_controller.dart:35-41` pinta
   `cache.home_feed` em toda abertura e a revalidação devolve o mesmo payload,
   porque o RPC é determinístico. O SWR transforma "feed estável" em "feed
   congelado".

### 4. Schema, RLS, índices, tamanho

- `games` **839**, `ports` **1067**, `platforms` **26** (`README.md:182-188`).
- Sinais disponíveis: `downloads` (`status='done'` → `games.download_count` por
  trigger, `0018:12-34`), `favorites`, `library`, `reviews` (1–5 + `verdict`),
  `games.visit_count`, `games.rating_avg/rating_count`, `released_on`,
  `last_activity_on`, `is_free`, `genre`, `developer`.
- RLS ligada em todas as tabelas (`0002`), padrão `*_public_read` (catálogo) ×
  `*_own` (dados de usuário). `0005`/`0008` revogam SELECT direto em
  `profiles`/`reviews` e usam `security definer` + `search_path` fixo nas RPCs
  sensíveis. `0010` limita entrada de busca/perfil.
- Índices existentes: `games_trending_idx(visit_count desc, title)`,
  `games_release_idx(released_on desc nulls last)`, `games_genre_idx`,
  `games_year_idx`, `games_free_idx`, GIN em `platform_slugs`/`title`/`developer`;
  `reviews_game_idx`, `favorites_user_idx`, `library_user_idx`,
  `downloads_user_idx`, `ports_game_idx`, `ports_platform_idx`.
- **Lacunas:** sem índice para `rating_avg desc` (usa `top_rated`), nem para
  `download_count desc`, nem para `last_activity_on desc`; sem índice de
  `downloads(created_at)` para janela de popularidade; **sem tabela de
  impressões**.

### 5-6-9. Medição local: bloqueio e solução

Ambiente sem `psql`, `supabase`, `docker` e sem Flutter (só Dart/Node/Python) —
não dá para rodar `supabase start`, `EXPLAIN ANALYZE`, o script de simulação nem
prints localmente. **Solução:** job `feed-sql` no `build.yml` com serviço
`postgres:16` efêmero que aplica migrations + seed com o volume real e roda
simulação, assertivas e `EXPLAIN ANALYZE`. Evidência real, reproduzível e
anexada ao run; produção intocada.

### 7. `build.yml` × produção

Gatilhos: `push` em `main` + `workflow_dispatch` (push em branch não dispara →
`gh workflow run`). **Não aplica migrations** (nenhum passo supabase/psql) e só
publica na landing em `main`. Migrations em produção são manuais via
`tools/import/apply_sql.py` com token de gestão → **não será executado**. Nenhum
segredo versionado (o único match é o próprio gate em `tool/ui_gates.sh:97`).

### 8-10. Branch, baseline e nota inicial

- Branch criada a partir de `feat/navbar-header-redesign` (decisão do usuário).
- Baseline de lint/testes/build: o CI é a única fonte (rodado a cada iteração).
- Nota inicial (iteração 0) do CRÍTICO: ver seção própria no fim.

---

## Decisões e suposições

1. **Sem materialized view nem `pg_cron`.** Com 839 jogos / 1067 ports, a
   pontuação é calculada on-the-fly (agregação restrita a uma janela de 90 dias
   em `downloads`), o que evita staleness e dispensa agendador. A função
   `purge_feed_impressions` fica disponível para agendamento externo (`pg_cron`
   se existir, ou cron do projeto); a migration **não** assume a extensão.
2. **Penalização de repetição sem vazar histórico:** o cliente envia
   `p_seen uuid[]` (máx. 200 ids, do histórico local). Para usuário autenticado
   soma-se um helper `security definer` que lê **apenas** as impressões do
   próprio `auth.uid()` (sem parâmetro de identidade → sem vazamento). A tabela
   `feed_impressions` é escrita pelo cliente e **não tem SELECT público**.
3. **Identidade de sessão no cliente:** `anon_id` (uuid opaco por instalação, em
   `CacheStore`) + `seed = hash(anon_id|uid, session_epoch)`. Sessão nova após
   ≥30 min em segundo plano ou cold start; pull-to-refresh rotaciona o seed.
4. **Seções adaptadas ao que o app tem:** destaque (hero), para você, em alta,
   novidades, atualizados recentemente, descubra (exploração, com cursor) e por
   categoria. Seção vazia é omitida.
5. **Compatibilidade:** a RPC legada `home_feed` permanece intacta como fallback;
   o cliente passa a usar `get_home_feed` e cai para a legada (e depois para o
   cache) em caso de falha.
6. **Opt-out:** o app não tem configuração de privacidade hoje. Fica um flag
   local (`privacy.feed_impressions`) lido antes de enviar impressões; default
   ligado. Registrado como suposição.
7. **Simulação no CI com seed sintético de 839 jogos** espelhando o volume real
   (o banco de produção não é acessível a partir deste ambiente, e não deve ser).

---

## Diário de execução — o que o harness do CI pegaria sozinho

Como não há Postgres nem Flutter nesta máquina, o job novo `feed-sql` (Postgres
16 efêmero) e o `flutter analyze` do CI foram o compilador de verdade. Bugs
reais encontrados por eles, em ordem:

1. `round(double precision, integer) does not exist` — `ln(bigint)` devolve
   `double precision` no Postgres; o bloco de popularidade passou a converter
   para `numeric`.
2. `make_interval(days => bigint)` — `%` sobre `row_number()` devolve `bigint`.
3. Slugs fora do padrão `game-NNNN` (jogos semeados pelas migrations 0016/0021)
   quebravam o `split_part(...)::int`; extração passou a ser por regex, e o seed
   limpa o catálogo antes de semear (volume determinístico).
4. `ports_platform_id_fkey` — `generated always as identity` não reinicia no
   delete: os ids vinham 27..52.
5. `RATE_LIMIT_REVIEWS` — o nome do trigger muda entre migrations (0008 →
   `reviews_rate_limit`, 0009 → `r_rate_limit`); o seed desliga via `pg_trigger`.
6. `function round(double precision, integer)` de novo, agora no CTE final.
7. **`permission denied for table favorites` (o mais importante)** — `favorites`,
   `library` e `downloads` têm SELECT só para `authenticated` (privilégio mínimo,
   0005), então a RPC `security invoker` quebrava para **anônimo**, que é a maior
   parte dos usuários. Corrigido com helpers `security definer` que devolvem
   apenas agregados (`feed_popularity`, `feed_user_preferences`).
8. **Top 10 repetindo 90% entre seeds** — com jitter sozinho o topo não rotava.
   Entrou a **banda de relevância** (`band_factor = 4.0`): a seção é montada com
   os melhores `4 × limit` por score e reordenada pelo ruído da seed.
9. Formato do cliente: o portão roda Dart 3.14.0 e o local 3.14.1 quebra
   **cadeias** em colunas diferentes. Padrão eliminado com o helper `mapList`
   (e `MediaQueryData` local em vez de `MediaQuery.of(context).copyWith(...)`).

## CRÍTICO — iteração 0 (linha de base, antes de qualquer mudança)

Evidência: `0018_download_counts.sql:63-116` (ordenção fixa), ausência de
`anon_id`/impressões no cliente, `cache.home_feed` repintado a cada abertura.

| Critério | Peso | Nota |
|---|---|---|
| Algoritmo: variedade e relevância | 20% | 2,0 |
| Beleza visual e hierarquia | 15% | 7,0 |
| Eficiência (queries, latência, render, paginação) | 15% | 6,0 |
| Arquitetura de dados Supabase | 10% | 6,5 |
| Consistência, design system e temas | 10% | 8,0 |
| Usabilidade e descoberta de conteúdo | 10% | 5,0 |
| Estados e feedback | 5% | 6,0 |
| Acessibilidade | 5% | 7,0 |
| Responsividade | 5% | 7,0 |
| Microinterações e microcopy | 5% | 6,5 |
| **Média ponderada** | | **5,4** |

🔴 Ordenação determinística global por contador acumulado: o topo é o mesmo para
todo mundo, sempre (repetição de 100% no top 10 entre aberturas).
🔴 Sem paginação (uma chamada, `limit` único): a descoberta termina no fim da
mesma lista.
🟡 Sem histórico de exibição: impossível penalizar repetição.
🟡 Sem personalização: usuário com histórico recebe o mesmo feed do anônimo.
🟡 `top_rated` ordena por `rating_avg` sem índice.
🟢 Sem impressões: nenhuma telemetria de exposição para calibrar o ranking.
