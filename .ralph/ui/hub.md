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

## Depois (preencher na iteração U1-H)

- (a registrar)
