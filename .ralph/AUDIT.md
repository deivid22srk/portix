# PORTIX — Auditoria inicial (iteração 1)

> Data: 2026-11-15 · Branch: `feat/ui-ux-pro-download-engine` · Baseline: `main` = `305eb58` (CI **verde**)
>
> Stack real confirmada (diferente da hipótese inicial de Compose): **Flutter 3.50/Dart** (Material 3 via
> `material_ui`, Riverpod 3, go_router 18, Supabase) + **motor de download em Rust** (`native/portix_downloader`,
> **ureq 2.10** blocking + rustls, JNI 0.21) exposto a **Kotlin** (`native/android/`) e consumido via
> MethodChannel/EventChannel. O `android/` não é versionado: o CI gera o scaffold (`tools/ci/prepare_android.py`).

## 1. O que está bom e deve ser preservado

- **Design system "Aurora"** real e centralizado: tokens completos em `lib/core/theme/tokens.dart`
  (cores, raios, espaçamentos, motion, sombras) e ~23 primitivas em `lib/shared/widgets/primitives.dart`
  (`GlassContainer`, `PrimaryButton`, `GlassCircleButton`, `GradientProgress`, `SegmentedControl`, …).
  Regra seguida de "nenhuma cor solta nas telas".
- **Tipografia** hierarquizada em `lib/app/theme.dart` (Poppins, escala com tracking negativo),
  `ColorScheme.fromSeed` com override da marca.
- **Identidade da marca**: nome PORTIX, ciano `#22D3EE` → esmeralda `#34D399`, vidro escuro. Não tocar.
- **L10n tipado** (`L10n` pt-BR/en, sem codegen) e formatadores centrais (`lib/core/formatters.dart`).
- **UI de downloads funcional**: tile com capa, badge de status, progresso, pausar/retomar/cancelar,
  abrir fonte; persistência em `shared_preferences` + sync opcional com a tabela `downloads`.
- **Cache-first e otimismo com rollback** nas coleções; skeletons com um único controlador de shimmer.
- **Motor Rust**: `catch_unwind` na fronteira JNI, cancelamento cooperativo no loop de leitura,
  buffer de 64 KiB (memória constante), timeouts configurados, validação de `Content-Type`
  e do *magic* `PK\x03\x04`, agente com rustls (sem OpenSSL no Android).
- **CI completa**: analyze + test + scaffold Android + ícone/splash + Rust/NDK para 3 ABIs +
  APK split-per-abi + artefato `portix-apk`. `main` está verde.

## 2. Motor de download — falhas e riscos (caminho completo)

### Críticos (P0)

| # | Problema | Evidência | Consequência |
| --- | --- | --- | --- |
| R1 | **Sem escrita atômica**: grava direto no destino final (`File::create(dest)`, lib.rs:105) e sem `fsync` | `transfer()` | Crash/kill no meio deixa **APK corrompido com nome final**; o app pode oferecer instalação de arquivo truncado |
| R2 | **Sem validação de truncamento**: fim da stream (`read == 0`) encerra como sucesso mesmo com `done < Content-Length` | lib.rs:120-135, 140-142 | Conexão caindo "de graça" conclui APK truncado (o magic `PK` está no início, não pega truncamento no meio) |
| R3 | **Sem retomada**: qualquer erro/cancelamento **apaga o arquivo** (lib.rs:116, 163) e recomeça do zero; sem `Range`, `If-Range`, `ETag`, `Last-Modified` | `run_download()` | "Pausar" no Dart chama `cancel` nativo (downloads_controller.dart:223-235) = **cancelar disfarçado**; rede instável = recomeçar do zero |
| R4 | **Erros como strings ad-hoc** (`"http: {e}"`, `"read: {e}"`) sem classificação retentável/fatal e sem código estável | `transfer()` | Dart mostra erro cru em inglês/técnico, não localizável, sem retry automático |
| R5 | **Feature `gzip` do ureq** (Cargo.toml:14): descompressão automática quebra `Content-Length`/`Range` | Cargo.toml | Retomada e contagem de bytes ficam erradas quando o servidor comprime |
| R6 | **Sem pré-checagem de espaço em disco** nem sanitização de caminho | `transfer()` | Download falha no meio com erro genérico; risco de path traversal se o destino vier de fora |
| R7 | **Sem máquina de estados explícita** (só `onProgress`/`onComplete`) | JNI callback | UI não consegue distinguir conectando/baixando/verificando; estados novos impossíveis |
| R8 | **Zero testes** no crate | — | Refatorar sem rede de proteção |

### Importantes (P1)

- Sem **retry** com backoff/jitter/`Retry-After`; erros transientes (timeout, reset, 5xx) falham de vez.
- Sem **segmentação paralela** (1–8 conexões) nem balanceamento entre segmentos.
- Progresso a cada **350 ms sem velocidade/ETA** (lib.rs:131) — a UI não tem dados para exibir.
- **Sem fila no nativo**: `DownloadService` trata 1 download por vez (`currentId`/`currentHandle` estáticos,
  `NOTIFICATION_ID` fixo), `START_NOT_STICKY` — morte do processo perde o download.
- Sem **limite de velocidade**, sem **SHA-256** quando houver hash, sem limite de redirecionamentos explícito.
- `unwrap()` em locks (`registry()`, `next_id()`) em caminho de produção (pânico por poisoning cruza a fronteira).
- `emit_progress` com erro **aborta o download** (lib.rs:132 via `?`) — falha de callback ≠ falha de rede.
- Kotlin: sem ações na notificação (pausar/cancelar), sem "somente Wi-Fi", sem reação a mudança de rede.

## 3. UI/UX — dívidas por área

### Tela de downloads (Meu Hub → segmento Downloads; `downloads_tile.dart`)
- Sem **velocidade, ETA, bytes baixados/total** (o motor não envia; o modelo `DownloadTask` não tem campos).
- Sem **filtros** (ativos/concluídos/falhos), sem **ações em lote**, sem reordenação de fila.
- Erro exibe a string crua do motor (`task.error`) — sem tradução, sem "como resolver", sem botão **tentar de novo**.
- Falha de download **apaga o progresso visível** (motor apaga o arquivo; a tarefa fica em `failed` com progresso congelado).
- `GlassCircleButton` de 32 dp nos controles (tokens pedem 46; alvo de toque < 48 dp → acessibilidade).
- Estados `connecting`/`verifying` inexistentes — a barra fica parada nesses períodos.

### Estados globais
- Offline, sem espaço em disco e permissão negada **não têm tratamento específico** na fila.
- Non-Android mantém fila **simulada** (progresso fake +2,8%/420 ms e "concluído" sem arquivo) —
  fallback aceitável e documentado, mas deve continuar claramente separado do caminho real.

### Notificação (Android)
- Sem ações (pausar/cancelar), apenas percentual; ícone do sistema `stat_sys_download` (genérico).

### Consistência/docs
- README contraditório: seção "Limitações" diz "Downloads simulados" enquanto existe o motor nativo
  (e a tabela de stack cita Space Grotesk/Inter, mas o tema usa **Poppins**). Atualizar.
- `analysis_options.yaml` desliga regras `const` — oportunidade de revisão, não bloqueio.

## 4. CI/CD — riscos

- **`build.yml` publica APKs na landing (`deivid22srk/portix-landing`) em QUALQUER ref** — os dois passos
  "Publicar … na landing" não têm `if: github.ref == 'refs/heads/main'`. Um `workflow_dispatch` na branch de
  trabalho **sobrescreveria os APKs de produção**. Blindagem obrigatória antes de dispatchar (só na branch).
- Gatilhos: `push` → só `main`; `workflow_dispatch` disponível (usar com `--ref` da branch).
- Artefato para o humano: **portix-apk** (3 ABIs).

## 5. Decisão de abordagem para o motor

Separar **núcleo agnóstico** (HTTP, estados, retomada, escrita — testável no host com `cargo test`)
da **ponta JNI fina** (que só adapta). Detalhes e justificativas em `.ralph/DECISIONS.md`.
