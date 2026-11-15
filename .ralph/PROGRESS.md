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

---
