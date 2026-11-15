# PORTIX — Decisões de arquitetura e design (com o porquê)

Formato: uma linha de decisão + justificativa curta. Novas dependências só entram com entrada aqui.

## D1 — Manter `ureq` (blocking) em vez de migrar para `tokio` + `reqwest`
O crate é uma `cdylib` de ~3 ABIs com `opt-level = "z"` e LTO; runtime async adicionaria
~1–2 MB por ABI e um executor para um caso de uso de 1–8 transferências concorrentes.
O paralelismo por segmentos será feito com threads (modelo atual já é blocking).
Custo/benefício desfavorável à troca; risco alto para o mesmo resultado.

## D2 — Remover a feature `gzip` do `ureq`
Descompressão automática corrompe a contagem de bytes (`Content-Length` desatualiza),
invalida `Range`/`If-Range` e pode esconder truncamento. APK não deve ser decomprimido.

## D3 — Núcleo agnóstico de plataforma + ponte JNI fina
`core` (estados, HTTP, retomada, escrita) não conhece JNI; `lib.rs` só adapta.
Permite `cargo test` no host sem JVM — pré-requisito para a rede de testes exigida.

## D4 — Erros tipados escritos à mão (sem `thiserror`)
Enum + `Display` manual ≈ 40 linhas, zero dependências novas, códigos estáveis
expostos como constantes para o Dart mapear/localizar. `thiserror` economizaría
poucas linhas e adicionaria proc-macro ao build de 3 ABIs.

## D5 — `libc` como única dependência nova
Necessária para `statvfs` (pré-checagem de espaço em disco) — std não expõe.
`libc` é a base de FFI do ecossistema, sem custo relevante no binário.

## D6 — Servidor HTTP de teste escrito com `std::net` (sem `tiny_http`/`hyper`)
Os cenários de integração (200/206/416, queda no meio, ETag mudando, 429 com
`Retry-After`, redirect, HTML, truncamento) são simples o suficiente para um
`TcpListener` de ~150 linhas no módulo de testes. Zero deps em `[dev-dependencies]`.

## D7 — Fila simulada (non-Android) permanece
Compatibilidade e testabilidade preservadas; o caminho real continua atrás de
`NativeDownloader.isSupported()`. Nenhuma funcionalidade existente é removida.

## D8 — CI: blindar os passos de publicação na landing
`if: github.ref == 'refs/heads/main'` nos dois passos que publicam em
`deivid22srk/portix-landing`. Necessário para dispatchar a branch de trabalho sem
sobrescrever APKs de produção. Jobs da `main` não mudam de comportamento.

## D9 — Contrato JNI/Kotlin/Dart evolui de forma compatível
Eventos novos (estados, velocidade, ETA) entram como campos **aditivos** no mapa do
EventChannel; `DownloadCallback` ganha métodos novos com métodos-ponte mantendo os
antigos funcionando no mesmo commit (Rust+Kotlin+Dart sobem juntos).

## D10 — Identidade visual preservada
Aurora (fundo `#07090E`, ciano→esmeralda, vidro, Poppins) é intocável. Melhorias de
UI reusam tokens/primitivas existentes; nada de tema claro/OLED sem demanda real.
