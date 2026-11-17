# PORTIX — Missão UI/UX iterativa (ux/melhorias-iterativas)

## Protocolo e suposições registradas

- Branch: `ux/melhorias-iterativas`, criada a partir de `feat/ui-ux-pro-download-engine`
  (8d93f18) — SUPOSIÇÃO CONSERVADORA: a main (9060a14) não tem o motor v2 nem os
  fixes de UI reportados pelo usuário; basear na branch de trabalho evita perder tudo.
  O PR final para main trará o consolidado.
- build.yml roda só em push para `main` + `workflow_dispatch` → cada iteração é
  validada via dispatch na branch (curl, sem gh CLI; RUN_ID via lista de runs).
- Papéis: CRIADOR = agente principal (contexto do projeto/skills); CRÍTICO =
  subagente independente (agent-ff1a073c-443b-4837-bfae-9d707659fc7e, resume entre
  iterações para comparar séries).
- Evidências: testes widget em 411/800/1440px, texto 2.0, semântica (SemanticsFlags),
  contrastes calculados (iter 0), ui_gates no CI.
- NOTA ambiental: dart format do SDK 3.50 re-extraído quer reformatar ~38-55
  arquivos do projeto (estilo antigo no repo). Reformatação global FOI DESCARTADA
  nas iterações 1-3 para manter commits atômicos; o working tree carrega essa
  formatação pendente unstaged. Resolver deliberadamente numa iteração de
  "drenagem" (formatter + allowlist juntos).

## Série de notas (CRÍTICO)

| Iter | Commit | Média | Δ | CI run | Resumo |
|---|---|---|---|---|---|
| 0 | 8d93f18 | **6,6** | — | (linha de base, analyze+63?52/52) | 5 🔴 (responsividade zero, clamp 1.35, AppToggle/StarPicker cegos, 16 botões sem rótulo), 8 🟡 |
| 1 | a81c03f | **7,5** | +0,9 | 44079614868 success | ResponsiveCoverGrid 2/3/5/6 col + teto 1200px nas 6 grades; clamp 1.0-2.0; AppToggle/StarPicker Semantics; tooltip OBRIGATÓRIO (24/24); circleButton 48; 11 testes |
| 2 | 1f8a582 | **7,8** | +0,3 | 44082947068 success | AppContentMax em 7 telas; snackbars 8/8 no padrão; limpar histórico confirm+undo; sign-out confirm; RevealOnMount home; alturas colapsadas; navbar selected |
| 3 | c3e16a1 | **7,9** | +0,1 | 44084688722 success | showAppConfirm (vidro) nos 2 AlertDialog cru; filtro único no Explore; chips 48/48; 3 testes (undo/confirm). NOTA: o CRÍTICO errou a soma da iter 2 (publicou 8,2; real 7,8) |

Critérios iter 3: hierarquia 7,5 · consistência 8,0 · usabilidade 7,5 · a11y 8,5 ·
responsividade 9,0 · estados 7,5 · microinterações 7,5 · performance 8,0 · microcopy 7,5.

## Pendências para a iteração 4 (TOP3 do CRÍTICO)

1. **Drenar allowlist 48→0** (20 tok_size + 20 raw_color + 5 raw_font + 5 raw_text
   em ~20 arquivos; meta própria do arquivo é "vazia no fim do U2") + tamanhos
   mágicos (47 SizedBox / 19 EdgeInsets fora da escala 4/8; fontSize 10/9;
   SegmentedControl vertical: 9). Estratégia sugerida: drenar raw_text e raw_font
   primeiro; tok_size junto com a decisão sobre a reformatação global pendente.
2. **Sweep de overflow texto 2.0 nas 7 telas não-grade** (menu, detail ×2, news,
   user_profile, auth, profile_edit) — única lacuna de a11y sem teste.
3. **Microcopy/microinterações**: '— PORTIX —' ×2 (search:480, explore:310),
   wordmark duplo no splash (splash_page.dart:26-33), "(simulado)"
   (app_strings.dart:236), flutter_animate morto (pubspec.yaml:22), transição de
   segmento do Hub (hub_page.dart:105-106), chrome full-bleed (_TopBar detail
   :751-762), snackbar gap fixo 96px em rotas sem navbar, acoplamento de locale
   em confirm_flow_test.dart.

## Estado da branch

- Topo: c3e16a1 (iter 3) — push feito, CI verde, suíte 66/66.
- working tree: ~38 arquivos com reformatação unstaged (ver nota ambiental) —
  NÃO commitar junto com feature; decidir na drenagem.
- Guard: branch única; main intacta (do dono) em 9060a14.
- Veredito atual: CONTINUAR (meta: ≥9,5 com nada <9, zero 🔴/🟡, 2 avaliações
  consecutivas, build verde; máx 10 iterações).
