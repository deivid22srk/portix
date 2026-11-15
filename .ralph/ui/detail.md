# Detalhe do jogo (+ reports)

## Antes (U1)

- Arquivo monolítico (1808 linhas) — rebuild amplo em interações locais (favoritar/expandir).
- Portas, reports e galeria montados "na mão" — não usam `AppPill`/`InfoChip`/`SectionHeader`
  consistentemente em todos os blocos.
- `Colors.`/`Color(0x…)` no arquivo (regra raw_color do gate) — scrim/overlay fora do tema.
- Hero existe (`heroTag` via router) mas transição de volta não configurada (sem `Hero` no
  destino do GameCard? verificar em `game_media.dart`).
- "Ler mais" expande sem animação de tamanho.
- Landscape: bloco de mídia + título não reorganiza (coluna única esticada).

## Depois (preencher na iteração U1-T)

- (a registrar)
