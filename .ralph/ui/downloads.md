# Downloads (peça central — `lib/features/downloads/`)

## Antes (U1)

- Sem filtros (ativos/concluídos/falhos), sem ações em lote, sem reordenação — fila crua no Hub
  (`hub_page.dart:131-164` lista tudo sempre).
- Espaçamento fora do grid 4/8: `height: 3` (:140), `5` (:157), `9` (:148,198) em `downloads_tile.dart`.
- Troca de estado sem transição (badge/ação pulam; zero `AnimatedSwitcher`).
- Sem `Semantics` no progresso — TalkBack não anuncia percentual; badge só mostra % no estado
  `downloading` (`_statusLabel`).
- Cancelar/remover sem snackbar com desfazer (destructive sem rede de proteção).
- Offline e sem espaço caem em `failed` genérico — mensagem humanizada existe
  (`dlErrDiskFull`/`dlErrNetwork`) mas visual não diferencia estado.
- Tile reconstrói inteira a cada tick (~10/s) — sem `select`/escopo de rebuild; sem `RepaintBoundary`
  na barra animada.
- Capa 58×78 fixa; em telas grandes sobra hierarquia.
- Erro com ícone 15px + texto labelSmall — densidade baixa de leitura em falha (informação crítica).

## Depois (iteração U1 — fundação + correções com evidência de teste)

- Botão "Abrir fonte" 38 → **48dp** (`AppSpacing.secondaryButtonHeight`) — alvo de toque AA
  (verificado por `androidTapTargetGuideline`).
- Linha de ações do estado de falha Row → **Wrap**: um overflow real de 62px (paisagem 891×411
  e fonte 2.0) capturado por `expectNoOverflow` — agora quebra de linha em vez de estourar.
- `textTertiary` 42% → **55% branco**: contraste do ETA 3,9 → 6,0:1 sobre o vidro
  (verificado por `textContrastGuideline`).
- Testes: conteúdo (160 MB / 500 MB · 2,0 MB/s · 3:14 · 32%), erro humanizado sem string crua,
  guidelines nos 4 estados, overflow × 6 dispositivos — `test/ui/downloads_tile_test.dart`.

## Pendente para U1-D (tarefa dedicada)

- Filtros (ativos/concluídos/falhos), ações em lote, reordenação simples.
- Transição de estado com `AnimatedSwitcher`; `Semantics` no progresso; snackbar com desfazer.
- Espaçamentos fora do grid (3, 5, 9) → tokens; escopo de rebuild (`select`) nos ticks.
