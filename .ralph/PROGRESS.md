# PORTIX — Diário do loop (PROGRESS)

## Contexto fixo

- Repositório: `deivid22srk/portix` · Branch de trabalho: `feat/ui-ux-pro-download-engine`
- **MAIN_SHA**: `305eb584b5dc02ce9d3f6db317ab9319253993b3` (registrado na iteração 1)
- Guard: hook `pre-push` local bloqueia push para main/master; todo push é explícito.
- Stack real: Flutter 3.50 + Riverpod 3 + go_router; motor Rust (`ureq` + JNI) em `native/portix_downloader`;
  Kotlin em `native/android/`; `android/` gerado no CI (`tools/ci/prepare_android.py`).
- Ambiente local: Rust via `source /home/z/my-project/scripts/env.sh`. **Flutter 3.50.0 instalado em
  `/home/z/my-project/tools/flutter`** (`export PATH=/home/z/my-project/tools/flutter/bin:$PATH`) —
  analyze/test/gates rodam localmente. Token: arquivo 600 em `/home/z/my-project/scripts/.gh_token`
  (nunca commitar; **rotacionar ao fim**).

## Loop v2 (UI) — iterações U1–U4 (2026-11-15)

### U-F2 — Fix reportado: aparelho/processador invisíveis nos relatos (`fix(ui)` `057709b`)
- **Sintoma:** na tela de detalhes (e na de relatos) o usuário não via qual
  aparelho/processador gerou o relato de outra pessoa.
- **Root cause:** `CompatReport` já tinha brand/model/soc/gpu/ramGb, mas
  `FeedbackReportRow` espremia as specs na linha do autor (`Expanded` + ellipsis) —
  cortadas em qualquer largura de telefone.
- **Correção:** linha dedicada ao aparelho (ícone memória + SoC em destaque · GPU · RAM);
  autor em linha própria; estrelas/FPS/cargo em `Wrap`; `BadgeChip`/`AdminBadge` com
  ellipsis. Bônus: sweep de overflow expôs e corrigiu **overflow pré-existente de 93px**
  (fonte 200%, 360dp) e ~322px do badge ADMIN.
- **Testes:** `test/ui/report_row_test.dart` — 3 novos; suíte **47/47**; gates verdes.
- **CI:** run `43745474944` (dispatch em `057709b`) — **success**.

### U-F1 — Fix reportado pelo usuário: espaço apagado no campo de busca (`fix(ui)` `a94b6ea`)
- **Sintoma:** na tela de busca, o espaço que o usuário digitava desaparecia (~320ms+RTT
  depois de cada espaço final — a pausa entre palavras dispara o debounce).
- **Root cause:** `SearchController._fetch` gravava a query **trimada** de volta no estado
  ao concluir e o `ref.listen` da SearchPage espelha `state.query` no TextField — o echo
  normalizado reescrevia (e truncava) o texto digitado; em corrida, texto digitado durante
  a busca em voo também era descartado.
- **Correção:** estado carrega a query BRUTA do campo (texto = fonte da verdade enquanto
  se digita); trim só na requisição e em "buscas recentes" (sucesso e erro).
- **Testes:** `test/ui/search_query_test.dart` — 3 novos (regressão widget 'mario ' sobrevive;
  texto em voo preservado; contrato controller estado bruto × requisição trimada), com fake
  de `CatalogRepository`. **Prova:** sem o fix, `Expected 'mario ' / Actual 'mario'`; com o
  fix, verde. Suíte **44/44**; gates verdes; `fake_async ^1.3.1` em dev_dependencies.
- **CI:** run `43743949614` (dispatch em `a94b6ea`) — **success**.

### U4 — AppSnackbar + desfazer (`feat(ui): snackbar com desfazer e AppSnackbar padrão`)
- `lib/shared/widgets/app_snackbar.dart` (posição acima da barra de vidro via token
  `snackbarBottomGap`, ação opcional); remover/cancelar do tile com **Desfazer**;
  `DownloadsController.restore(task)` — concluída volta como done, ativa volta como
  **paused** (nunca retoma sem gesto), id duplicado não regride; `RepaintBoundary` na barra.
- 2 testes de undo; suíte **41/41**; gates verdes. Armadilha: snackbar em animação de
  entrada usa `IgnorePointer` — nos testes, `pumpAndSettle()` antes de tocar a ação.

### U2 — Poppins embutida (`feat(ui): fonte Poppins embutida em assets`) — commit `5eccecd`
- `google_fonts` removido (D-UI2): Poppins 400/500/600/700 + OFL em `assets/fonts`;
  `Typography.material2021().black` com fontFamily — as 15 variantes já tinham
  tamanho/peso explícitos. Base dos goldens.
- **CI:** run `43739293617` (dispatch no `5eccecd`) — conferir na próxima iteração.
  (O run do U1, `43739064815`, foi **cancelado pela concorrência** — o workflow usa
  `cancel-in-progress` por ref; o run mais recente valida U1+U2 juntos. Comportamento desejado.)

### U3 — Downloads: filtros, lote, grid, movimento, Semantics (`feat(ui): fila de downloads com filtros, animação e acessibilidade`)
- **Filtros** Todos/Ativos/Concluídos/Falhos no Hub (`AppPill` dense) + **Limpar concluídos**
  (só quando existem) + estado vazio do filtro; lógica pura em
  `lib/features/downloads/download_filter.dart` com 4 testes.
- **Tile**: espaçamentos no grid 4/8 (3/5/9→tokens), capa 58×78 → `tileCoverWidth/Height`,
  barra 6→8; corpo por GRUPO de estado com `AnimatedSize`+`AnimatedSwitcher` (conecting→
  downloading não pisca); allowlist `tok_size` e `raw_text` do Hub drenadas (−3 linhas).
- **A11y**: `GradientProgress.semanticLabel` com `Semantics(container: true)` — TalkBack
  anuncia "32%" (teste `find.bySemanticsLabel`); `Pressable` marca `Semantics(button)`.
- Notas de armadilha descobertas: `SemanticsHandle` deve ser descartado DENTRO do corpo do
  teste (verificação do framework roda antes dos tearDowns); Riverpod 3.5 não exporta o tipo
  `Override`; `flutter_test` assume plataforma android (helper sobrescreve p/ linux).
- **Validação local:** analyze limpo · 39/39 testes (31 base + 4 tile + 4 filtro) · gates verdes.

**CI:** U3 run `43740093875` em andamento no momento do push do U4 (concorrência cancela o anterior;
conferir o run mais recente na próxima iteração).

**Próximo passo:** U5 — rebuild com `select` nos ticks + grades adaptativas (U2-R) + goldens
dos estados; depois Detalhe (U1-T).

**Bloqueios:** nenhum.

---
## Loop v2 — iteração U1 (fundação) — commit `edca093`

**Feito (`test(ui): portões de UI, testes de acessibilidade e auditoria das telas`):**
- **Flutter 3.50.0 instalado no sandbox** (SDK intacto verificado por `git status` do próprio SDK).
  Baseline local: `flutter analyze` limpo, `flutter test` 31/31.
- **Auditoria UI completa**: inventário de 14 telas em `.ralph/UI_SCORECARD.md` (11 dimensões,
  média honesta inicial **3,2**; 5 lacunas transversais listadas), `.ralph/UI_PLAN.md`
  (U0/U1/U2 + itens de motor marcados `[congelado]`) e `.ralph/ui/*.md` (8 diagnósticos por tela).
- **`tool/ui_gates.sh`** (raw_color/raw_font/raw_text/tok_size/debug_print/secret/ui_change/
  format-catraca/analyze) com allowlist medida por `--init` (20 arquivos de cor, 3 de fontSize,
  22 de tamanho, 6 de texto) — meta: drenar até o fim do U2.
- **`test/ui/ui_test_helpers.dart`**: `pumpUi` (tema Aurora + pt-BR + dispositivos 360×640/411×891/
  800×1280/paisagem + escala de fonte), `expectMeetsAccessibilityGuidelines` (tap targets 48dp,
  rótulos, contraste AA) e `expectNoOverflow` (6 dispositivos). Notas: `flutter_test` assume
  plataforma android (sobrescrita para linux no helper) e Riverpod 3.5 não exporta o tipo
  `Override` (helper usa closure `wrap`).
- **`test/ui/downloads_tile_test.dart`** (4 testes): conteúdo (bytes/velocidade/ETA/badge),
  erro humanizado sem string crua, guidelines de acessibilidade nos 4 estados, varredura de
  overflow × 6 dispositivos.
- **Correções de UI com evidência do teste**: botão "Abrir fonte" 38→48dp (alvo de toque);
  linha de ações da falha Row→Wrap (overflow real de 62px em paisagem/fonte 2.0);
  `textTertiary` 42%→55% branco (contraste 3,9→6,0:1, AA) — tokens.dart comentado.
- **CI**: `build.yml` da branch ganha "Portões de UI" (`tool/ui_gates.sh --skip-analyze`)
  + `fetch-depth: 0` (regra `ui_change`). Jobs de release/main intocados.
- **Validação local:** analyze limpo · `dart format` nos arquivos tocados · **35/35 testes** ·
  gates verdes.

**CI:** run `43739064815` (cancelado pela concorrência, ver U2 acima) — validação coberta pelo run do U2.

**Próximo passo (histórico):** U0-D (design system: fonte Poppins embutida em assets + ThemeExtension) ou,
se o CI vermelhar, corrigir primeiro. Depois U1-D (Downloads: filtros/lote/animação/Semantics).

**Bloqueios:** nenhum.

---
## Loop v1 (motor) — histórico

## Iteração 1 — Setup + auditoria (2026-11-15)

**Feito:**
- Clone, `git fetch --all --prune`, branch criada e publicada com `git push -u origin feat/ui-ux-pro-download-engine`.
- Hook `pre-push` local (bloqueia main/master) ativado.
- Reconhecimento completo: README, `pubspec.yaml`, `Cargo.toml`, `build.yml`, `admin-app.yml`,
  `native/portix_downloader/src/lib.rs` (213 linhas), `native/android/**` (4 arquivos Kotlin + res),
  caminho Dart (`native_downloader.dart`, `downloads_controller.dart`, `downloads_tile.dart`,
  `download_task.dart`, tokens/primitivas/tema/estados, `analysis_options.yaml`, testes).
- Baseline CI: **último run na main = success** (commit `305eb58`, workflow "Build APK").
  API de Actions consultada com o token; runs anteriores: `0f220db` success, `efa493d` failure (já corrigido na main).
- `.ralph/AUDIT.md` (UI/UX + motor + CI), `.ralph/PLAN.md` (backlog P0/P1/P2), `.ralph/DECISIONS.md` (D1–D10).
- Descoberta crítica de CI: `build.yml` publica na landing em qualquer ref → blindagem obrigatória antes de dispatch (tarefa P0).

**CI:** nenhum run da branch ainda (gatilho atual: push só para `main`; `workflow_dispatch` disponível — usar após D8).

**Próximo passo:** iteração 2 → blindar `build.yml` (D8) + dispatch na branch; depois motor (núcleo/estados/erros).

**Bloqueios:** nenhum.

## Iteração 2 — CI acionável na branch (2026-11-15)

**Feito:**
- `build.yml`: `if: github.ref == 'refs/heads/main'` nos 2 passos de publicação na landing
  (`4a91c30`). Jobs da `main` intocados; branch não pode mais sobrescrever APKs de produção.
- `workflow_dispatch` na branch: run **43731447123 → success** (analyze+test+scaffold+Rust+APK).
  CI da branch é acionável e o guard funciona.

**CI:** run 43731447123 (success). **Próximo passo:** motor fatia 1 (núcleo/estados/erros/escrita atômica).

## Iteração 3 — Motor fatia 1: núcleo correto e seguro (2026-11-15)

**Feito (`feat(download): núcleo com máquina de estados, erros tipados e escrita atômica`):**
- Crate dividido: `engine/` agnóstico (`error`, `state`, `progress`, `fsutil`, `http`, `transfer`)
  + ponte JNI fina em `lib.rs`. Contrato JNI **preservado** (`onProgress`/`onComplete`); mensagem de
  erro agora é `"<code>|<detalhe>"` com códigos estáveis (Dart mapeia/localiza na iteração de contrato).
- Estados com transições validadas; erros tipados com `is_retryable()` (base do retry P1).
- Escrita atômica: `.part` pré-alocado → `fsync` → validação (magic PK, truncamento) → `rename`.
  Destino final nunca mais recebe arquivo corrompido; APK bom anterior sobrevive a tentativa falha
  (bug antigo: `remove_file(dest)` em erro).
- Pré-checagem de espaço (`statvfs` + margem 1 MiB), sanitize de caminho (anti-traversal),
  cancelamento cooperativo a cada buffer, `gzip` removido do ureq, locks tolerantes a poisoning,
  falha de callback não aborta mais o download.
- Progresso: EWMA + ETA + throttle 100 ms no núcleo (exposição no contrato vem depois).
- **Validação local:** `cargo fmt --check` ok, `clippy -D warnings` ok, `cargo test` 28/28
  (18 unitários + 10 de integração com servidor HTTP local em `std::net`), `cargo build --release` ok.

**CI:** dispatch pendente para esta fatia (será acionado no push; conferir na próxima iteração).

**Próximo passo:** iteração 4 → retomada real (probe de Range, `.part.meta`, `If-Range`) + cenários
de teste 206/416/ETag/429/redirect/queda no meio.

**Bloqueios:** nenhum.

## Iteração 4 — Motor fatia 2: retomada real (2026-11-15)

**Feito (`feat(download): retomada real com Range, If-Range e estado persistido`):**
- `engine/resume.rs`: `.part.meta` atomicamente persistido (tmp+rename) com URL, ETag,
  Last-Modified, total e done; `can_resume` exige validador (sem ETag/Last-Modified →
  recomeço do zero — nunca concatena arquivos possivelmente diferentes).
- `attempt()` com `Range: bytes=<done>-<fim>` + `If-Range`; Content-Range validado contra a meta;
  200-em-resposta-à-retomada ou 416 → limpa e recomeça do zero (1 vez). Espaço em disco verificado
  contra o que **falta** (não o total).
- Cancelamento (pausa) e quedas de rede **preservam** `.part`+`.meta`; erros fatais de conteúdo
  (NotAnApk) limpam. Magic APK validado **do arquivo** (na retomada a stream começa no meio).
- Cenários novos de integração: retomada 206 completa o arquivo; ETag mudou → arquivo novo
  (não concatenação); 416 → recomeço; sem validador → sem Range; meta corrompida → fresh;
  redirect 302; cancelamento no meio preserva progresso e retoma.
- Nota: notificações de retomada no Kotlin/Dart (botão retomar de verdade) chegam na iteração de
  contrato/fila — o motor já está pronto para retomar em nova chamada `startDownload`.
- **Validação local:** fmt ok, clippy -D warnings ok, 39/39 testes (22 unit + 17 integração), release ok.

**CI:** dispatch do run após este commit; conferir resultado na próxima iteração.

**Próximo passo:** iteração 5 → retry com backoff exponencial + jitter + `Retry-After`
(classificação retentável já existe).

**Bloqueios:** nenhum.

## Iteração 5 — Motor fatia 3: retry automático (2026-11-15)

**Feito (`feat(download): retry com backoff, jitter e Retry-After`):**
- `engine/retry.rs`: `RetryPolicy` (4 tentativas, base 500 ms, teto 8 s, jitter 0,5) +
  `effective_delay` (`Retry-After` vence o backoff quando maior) + `sleep_interruptible`
  (cancela em ≤100 ms) + PRNG xorshift64* semeado por relógio (zero dependências).
- `download()` virou orquestrador de retries; `download_once` mantém retomada + recomeço seguro;
  cada retry aproveita o `.part.meta` do disco automaticamente. JNI não muda.
- 5 cenários de integração novos: retry após queda (retoma sozinho e conclui com 2 requests),
  retry após 500, 429 com `Retry-After: 1` respeitado (≥950 ms), 404 sem retry, cancel durante o
  backoff aborta rápido. 6 testes unitários (backoff cresce/teto, RNG determinístico, Retry-After,
  sleep interrompível).
- Correção de suíte: o `Content-Range` do mock estava malformado (espaço em vez de `/`) e os
  testes de retomada passavam via fallback seguro; com o formato certo, o caminho 206 real é
  exercitado (o parse rígido do motor pegou a malformação — bom sinal).
- **Validação local:** fmt ok, clippy -D warnings ok, 49/49 testes (27 unit + 22 integração).

**CI:** run da fatia 2 (`43733494095`) em andamento; novo dispatch após este commit.

**Próximo passo:** iteração 6 → contrato enriquecido JNI/Kotlin/Dart (estados, velocidade, ETA,
mensagens de erro localizadas) — fatia vertical nas 3 camadas.

**Bloqueios:** nenhum.

## Iterações 6+7 — Contrato rico ponta a ponta (Rust → Kotlin → Dart) (2026-11-15)

**Feito (`feat(download): contrato rico de estados, velocidade e ETA nas 3 camadas`):**
- Rust: ponte JNI emite `onState(código estável 0–5)` e `onStats(done,total,speed,eta)` a ~10/s;
  `RefCell` para dividir o `JNIEnv` entre os dois callbacks (mesma thread, chamadas sequenciais).
- Kotlin: `DownloadCallback` ganha `onStats`/`onState` com constantes documentadas;
  `DownloadService` propõe ao EventChannel os status `connecting`/`downloading`/`verifying` + `speed`/`eta`;
  `onProgress` legado (notificação a ~3/s) preservado.
- Dart: `NativeDownloadEvent` parseia `speed`/`eta`; `DownloadStatus` ganha `connecting`/`verifying`
  (transientes, não persistidos); `DownloadTask` ganha `speedBps/etaSecs/doneBytes/totalBytes`;
  tile mostra `X de Y · velocidade` e “restam m:ss”, botão **tentar de novo** no falho
  (usa a retomada do motor), erros viram texto humano pt/en via `downloadErrorLabel` —
  nunca mais string crua do motor; alvos de toque 32 → 48 dp.
- Formatadores novos: `formatBytes`, `formatSpeed`, `formatEta` (+ testes).
- **Validação:** Rust fmt/clippy/test 49/49 local; Dart/Kotlin dependem do CI (flutter não há no sandbox).

**CI:** dispatch após este commit; conferir na próxima iteração.

**Próximo passo:** iteração 8 → corrigir o que o CI apontar; depois fila no serviço Kotlin
(N simultâneos) + notificação com ações, ou segmentação paralela no motor.

**Bloqueios:** nenhum.

## Iteração 8 — Motor fatia 4: segmentação paralela (2026-11-15)

**Feito (`feat(download): segmentação paralela com probe e retomada v2`):**
- `engine/segments.rs`: plano de chunks com oversubscription (2× conexões, chunk mínimo 1 MiB,
  ≥8 MiB para paralelizar) — balanceamento por fila, sem coordenação em pleno voo.
- `engine/parallel.rs`: probe `Range: bytes=0-0` (206 → capacidade+validadores; 200 → fallback
  single-stream), workers com `Range`+`If-Range` por chunk, escrita em intervalos disjuntos do
  `.part`, agregador via mpsc (progresso EWMA/ETA + meta v2 a cada ~1 MiB), abort coordenado.
- `engine/resume.rs` v2: `segments` por chunk no `.meta` (`segI=start,end,pos`),
  `can_resume_parallel`, compatível com meta v1.
- `download_once` orquestra: v2 paralelo → v1 single → fresh (probe → paralelo/single).
- CI do contrato rico (e8f7cb2): **success** — Dart/Kotlin validados no build.
- **Validação local:** fmt ok, clippy -D warnings ok, **57/57 testes** (32 unit + 25 integração,
  incluindo: paralelo monta arquivo correto, servidor sem Range → single-stream, chunk cai no
  meio → retomada v2 conclui), release ok.

**CI:** dispatch após este commit.

**Próximo passo:** iteração 9 → corrigir CI se vermelho; depois fila no serviço Kotlin
(N simultâneos + notificação com ações) ou limite de velocidade.

**Bloqueios:** nenhum.

## Iteração 9 — docs + CI da fatia paralela (2026-11-15)

**Feito:**
- README: arquitetura do motor documentada (núcleo agnóstico, escrita atômica,
  retomada, paralelismo com probe, retry, erros tipados, progresso rico) e seção
  "Limitações" sincronizada com a realidade (downloads reais no Android; tipografia Poppins).
- CI da fatia paralela: run `43735568342` → **success** (analyze + test + scaffold +
  Rust/NDK 3 ABIs + APK). `3c6803d` no topo da branch.

## Estado do loop para a próxima sessão

**P0: 100% concluído.** P1: falta fila no serviço Kotlin (N simultâneos), notificação
com ações, limite de velocidade (expor na UI), tela de downloads dedicada com filtros/lote,
estados offline/espaço/permissão. P2: restam animações/adaptativo/i18n por locale/previews.
SHA-256: N/A enquanto o catálogo não publicar hashes (justificado em DECISIONS quando surgir).

**Como retomar:** rode o mesmo prompt; o agente deve ler este arquivo, `PLAN.md`,
`git log --oneline -15` e continuar da maior prioridade aberta. `main` permanece intacta
(MAIN_SHA `305eb58` confere). Branch: `feat/ui-ux-pro-download-engine`.

**Bloqueios:** nenhum.

---
