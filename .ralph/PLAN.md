# PORTIX — Plano (backlog priorizado)

Fonte da verdade do que falta. Marque com `[x]` quando feito **com teste/evidência**.
Ajustado à stack real: Flutter + motor Rust (`ureq`/JNI) + Kotlin service. Ver `.ralph/AUDIT.md`.

## P0 — Fundação

- [x] Setup: branch `feat/ui-ux-pro-download-engine`, hook pre-push, push inicial, `MAIN_SHA=305eb58` registrado.
- [x] Baseline: build da `main` **verde** (run de `305eb58`, 2026-11-15).
- [x] `AUDIT.md` completo (UI/UX + motor + CI).
- [ ] CI: `if: github.ref == 'refs/heads/main'` nos 2 passos de publicação na landing (proteção) + dispatch na branch.
- [ ] Motor: núcleo agnóstico de JNI (separação core/ponte) + máquina de estados explícita
      (`Queued→Connecting→Downloading→Verifying→Completed|Failed|Cancelled`) com transições testadas.
- [ ] Motor: erros tipados com códigos estáveis + classificação retentável/fatal; sem `unwrap` em produção.
- [ ] Motor: escrita atômica (`.part` pré-alocado + `fsync` + `rename`) + validação de truncamento
      (`done == Content-Length`) + sanitize de caminho.
- [ ] Motor: detecção de capacidade (`Accept-Ranges`, `ETag`, `Last-Modified`) + retomada com estado
      persistido por download (`.part.meta`) + `If-Range`.
- [ ] Motor: progresso enriquecido (done/total/velocidade EWMA/ETA) com throttle ~100 ms; callback
      JNI/Kotlin/Dart atualizado de forma compatível (mesmo commit nas 3 camadas).
- [ ] Motor: pré-checagem de espaço em disco (`statvfs`) antes de iniciar/retomar.
- [ ] Cargo.toml: remover feature `gzip` do ureq.
- [ ] Testes unitários (estados, backoff, formatação, retomada) — `cargo test` no host.
- [ ] Dart/Kotlin: novos estados e erros mapeados para mensagens localizadas pt/en (sem texto cru do motor).

## P1 — Produto

- [ ] Motor: retry com backoff exponencial + jitter + `Retry-After` (429/503).
- [ ] Motor: segmentação paralela adaptativa (1–8 conexões), segmento mínimo, balanceamento.
- [ ] Motor: limite de velocidade (token bucket) global e por download.
- [ ] Motor: SHA-256 em streaming quando houver hash esperado (estado `Verifying`).
- [ ] Testes de integração com servidor HTTP local (200, 206, 416, queda no meio, resposta lenta,
      ETag mudando, 429 Retry-After, redirects, HTML, truncamento).
- [ ] Kotlin: fila no serviço (N simultâneos configurável), notificação por download, `START_STICKY`
      com retomada, ações na notificação (pausar/cancelar).
- [ ] Kotlin: "somente Wi-Fi" + reação a mudança de rede (retomar quando voltar).
- [ ] Dart: aba/tela de downloads dedicada com filtros (ativos/concluídos/falhos), velocidade, ETA,
      bytes, ações em lote.
- [ ] Dart: estados de UI para offline, sem espaço em disco, permissão negada.
- [ ] Dart: tela de configurações de download (conexões, Wi-Fi only, limite de velocidade).
- [ ] Componentes base aplicados em todas as telas (sem widget "na mão" onde existe primitiva).

## P2 — Polimento

- [ ] Alvos de toque ≥ 48 dp em toda a fila de downloads (hoje 32 dp nos botões do tile).
- [ ] Animações: progresso suave (sem pulos), transições coerentes, haptics sutis revisados.
- [ ] Acessibilidade: Semantics no tile de download, contraste AA em `textTertiary`.
- [ ] Layouts adaptativos (tablet/paisagem) para downloads e detalhes.
- [ ] Ícone monocromático (themed icon) e predictive back.
- [ ] i18n: formatação de bytes/velocidade/ETA por locale (hoje só pt/en strings).
- [ ] `@Preview`/screenshots por tela e estado (claro é N/A — tema único escuro; documentar).
- [ ] README atualizado: seção "Limitações" sincronizada com o motor real + arquitetura do motor.

## Conclusão (Definition of Done)

- [ ] P0 e P1 todos marcados; P2 marcados ou justificados em `DECISIONS.md`.
- [ ] Último commit da branch com `build.yml` verde (confirmado via API).
- [ ] `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` verdes.
- [ ] `git ls-remote origin refs/heads/main` == `MAIN_SHA` (main intacta).
- [ ] README + `PROGRESS.md` com resumo final e nome do artefato.
