# Splash + BootstrapError + NotFound + Shell (transversais)

## Antes (U1)

- Splash: logo estático sem brand moment (animação curta de entrada); tempo mínimo artificial
  indefinido — pode piscar.
- BootstrapError (`app.dart:48-61`): só mensagem + tema; sem botão "Tentar de novo" e sem
  detalhe técnico colapsável para suporte.
- NotFound: sem ação de volta clara além do app bar; ilustração mínima.
- Shell: FAB de busca 68 (token `searchFab`) — bom; `AppSpacing.circleButton: 46` < 48dp
  (tokens.dart:86) — regra de alvo de toque.
- Troca de abas sem transição/`NavigationBar` M3 nativa (GlassNavBar custom) — decisão de marca;
  garantir feedback haptic + `Semantics(selected)` nos itens.

## Depois (preencher nas iterações U1-S / U1-V / U2-P)

- (a registrar)
