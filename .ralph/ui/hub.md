# Hub (favoritos / instalados / downloads)

## Antes (U1)

- Troca de segmento sem indicador animado (`SegmentedControl` pinta sem transição de largura).
- `SizedBox(height: 360)` mágico para empty states (:136, :180) — fora do grid.
- Grade fixa `crossAxisCount: 2` (:201) — em tablet/janela larga deveria escalar (3–4 colunas).
- Contadores nos rótulos dos segmentos ('Favoritos · 3') misturam dado e label — sem accessible
  label separado.
- EmptyState dos segmentos reutiliza ação "Explorar" — ok, mas sem retry quando a falha é de rede
  (collectionsProvider.error não tratado: `async.value ?? empty` esconde erro :35).
- RefreshIndicator com cores do tema — ok; sem haptic ao concluir refresh.

## Depois (iteração U3)

- Fila de downloads com **filtros Todos/Ativos/Concluídos/Falhos** (`AppPill`, dense) +
  ação **Limpar concluídos** (aparece só quando há concluídos); estado vazio do filtro com
  `EmptyState` dedicado (`filterEmptyTitle/Body`).
- Lógica de filtro extraída e testada: `lib/features/downloads/download_filter.dart` +
  `test/ui/download_filter_test.dart` (4 testes).
- `SizedBox(height: 360)` → `AppSpacing.emptyStateViewport`; `height: 6` → `AppSpacing.sm`.
- Rótulos "Seção · N" via `l10n.segmentCount` — separador no dicionário de i18n.
- `Pressable` ganhou `Semantics(button)` — chips/pílulas agora existem para o TalkBack.

## Pendente para U4+

- Reordenação da fila; ações em lote adicionais; animação na troca de segmento.
- Erro de `collectionsProvider` tratado (hoje `async.value ?? empty` esconde falha de rede).
