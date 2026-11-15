# PORTIX — Diário do loop (PROGRESS)

## Contexto fixo

- Repositório: `deivid22srk/portix` · Branch de trabalho: `feat/ui-ux-pro-download-engine`
- **MAIN_SHA**: `305eb584b5dc02ce9d3f6db317ab9319253993b3` (registrado na iteração 1)
- Guard: hook `pre-push` local bloqueia push para main/master; todo push é explícito.
- Stack real: Flutter 3.50 + Riverpod 3 + go_router; motor Rust (`ureq` + JNI) em `native/portix_downloader`;
  Kotlin em `native/android/`; `android/` gerado no CI (`tools/ci/prepare_android.py`).
- Ambiente local: Rust instalável via `source /home/z/my-project/scripts/env.sh`
  (`RUSTUP_HOME`/`CARGO_HOME` em `/home/z/my-project/tools`). Flutter NÃO está disponível no sandbox —
  `flutter analyze/test` só no CI. Token: arquivo 600 em `/home/z/my-project/scripts/.gh_token` (nunca commitar; **rotacionar ao fim**).

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
