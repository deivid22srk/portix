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

## D-UI1 — Tema único escuro (marca Aurora) no loop v2
O scorecard avalia contraste no tema suportado (escuro). Um tema claro contradiria a
identidade "vidro escuro" preservada pela missão; se o humano pedir, vira backlog próprio.

## D-UI2 — `google_fonts` removido; Poppins embutida em `assets/fonts` (U2)
Motivos: (1) google_fonts busca a fonte em runtime — primeiro boot sem cache troca a
tipografia depois de aberto (ruim para "perfeito"); (2) goldens de teste ficam
indeterminísticos com fetch de rede; (3) menos dependência = menos superfície no CI.
4 pesos (400/500/600/700) cobrem toda a escala do tema; licença OFL incluída.
`Typography.material2021().black` substitui o TextTheme base do GoogleFonts — todas as
15 variantes já eram sobrescritas com tamanho/peso explícitos em `AppTheme.dark()`.

## D-UI3 — Portões de UI tolerantes com allowlist drenável (U1)
`tool/ui_gates.sh` varre lib/ inteira, mas a allowlist (`tool/ui_gates_allowlist.txt`)
absorve o legado medido (58 entradas na U1). Regras novas arquivos entram por `--init`.
Ao reconstruir uma tela, as linhas dela saem da allowlist NO MESMO commit — o portão
aperta sozinho com o tempo, sem quebrar o CI de mudanças alheias.
