# CRÍTICO — Avaliação pós-iter-8 (HEAD 98ab145)

Avaliador: subagente CRÍTICO (independente, sem participação no código).
Branch `feat/configuracoes-categorias-temas-cache` @ 98ab145, `git status` limpo,
main intacta (9060a14), origin da branch na mesma SHA (push confirmado).

## Verificações obrigatórias (rodadas por mim nesta avaliação)

| Gate | Resultado | Evidência |
|---|---|---|
| `flutter analyze` | **No issues found** | saída: "No issues found! (ran in 1.0s)" |
| `bash tool/ui_gates.sh` (com flutter no PATH) | **verdes**, exit 0 | "UI_GATE ok [analyze] … todos os portões verdes"; allowlist com **0 violações** (só 2 linhas de comentário) |
| `flutter test` | **117/117 passaram** | "+117: All tests passed!" (101 declarações estáticas + geradas; +1 = novo teste do PortixApp) |
| `test/theme_settings_test.dart` isolado | **6/6** | inclui o grupo novo 'PortixApp: modo Sistema e SystemChrome declarativo' |
| `test/profile_avatar_cache_test.dart` isolado | **5/5** | inclui o testWidgets de integração real (contador HTTP: 1→0→0→1) |
| `git status` / push | limpo; origin @ 98ab145 | — |
| `git log origin/main -1` | 9060a14 (main intacta) | — |
| CI run 44117056475 | **não confirmável por API** (rate-limit do GitHub, tentado 2× com IPs diferentes; gh ausente) | evidência local máxima: os 3 gates rodados por mim, todos verdes |

### Greps de risco

| Padrão | Resultado |
|---|---|
| `SystemChrome.setSystemUIOverlayStyle` / `setSystemUIMode` em lib/ | **0 chamadas de estilo** (main.dart tem só orientações + edge-to-edge + comentário) |
| `Color(0x` / `Colors.*` fora de lib/core/theme e app/theme | **0** |
| `fontSize:[0-9]` fora de tema | **0** |
| `Text('<literal>')` fora de app_strings | **0** |
| `TODO|FIXME|XXX` em lib/ | **0** |
| `numericLabel` | **0 ocorrências** (removido de verdade) |

### Verificação empírica própria (teste temporário criado, rodado e apagado)

Para não aceitar a claim de a11y de segunda mão, instrumentei a árvore de
semântica do hub real (`/menu`, PortixApp de verdade via router):
- **Campo vazio**: nó semântico `id=25` com `label="Buscar configurações"` +
  `isTextField=true` — leitores de tela anunciam o NOME do campo. ✅
- **Campo com texto ("tema")**: o mesmo nó vira `label="" value="tema"` — o
  rótulo sai da semântica quando há conteúdo (comportamento padrão do
  InputDecorator; idêntico ao que o hintText fazia antes — não é regressão,
  mas o nome acessível não é persistente). Detalhado em 🟢-R1.

## 1. Tabela dos 9 critérios

| # | Critério | Peso | Nota | Evidência principal |
|---|---|---|---|---|
| 1 | Arquitetura de informação | 20% | **9,5** | 6 categorias + deep link `/menu/<id>`; master-detail ≥768px e drill-down 375px testados (settings_navigation_test.dart:532-566); tabela 14→13 itens SEM órfão — teste percorre as 6 categorias e afirma os itens (:200-281: editar/sair/stats, 6 temas, toggle, idioma, recarregar/limpar, versão+termos+privacidade); item 7 (atalho Hub) removido por decisão registrada (SETTINGS_MISSION.md:42); destrutivos isolados com showAppConfirm em danger |
| 2 | Sistema de temas | 20% | **9,5** | 5 paletas AA com pares compostos medidos (theme_contrast_test.dart:74-101 **inclui agora danger/bgElevated**:107); persistência + id inválido normalizado (settings.dart:49-69); **modo Sistema agora coberto por teste PERMANENTE do app real** (theme_settings_test.dart:180-251: bootstrap pendente de verdade via `FutureProvider` + Completer, `platformBrightnessTestValue` dark→light, bg `auroraDark`=0xFF07090E → `auroraLight`=0xFFF6F7FB — valores distintos, asserts não triviais); reduced motion no código (app.dart:53-55) mas **sem teste permanente** (🟢-R2); raw_color=0 |
| 3 | Cache da imagem de perfil | 15% | **9,5** | Meta provada no nível do WIDGET (profile_avatar_cache_test.dart, `_CountingHttpClient` + `runAsync`): 1º render = 1 download; 5 renders = 0 (memória); `clearInMemoryImageCache` = 0 (disco atende); `removeFile`+clear = 1 re-download — rodado isolado por mim: 5/5. SWR keepAlive sem flicker (profile_controller.dart:38-96). Invalidação memória+disco nos 3 pontos (:118 logout, profile_edit_page.dart:109, data_settings.dart:73). Cabeçalho do teste agora descreve os 2 níveis (:15-32) |
| 4 | Consistência e design system | 10% | **9,5** | Allowlist VAZIA (só comentários) — gate verde rodado por mim com analyze real; `numericLabel` morto REMOVIDO (rg=0; fpsValue/downloadsCount/versionBadge têm usos reais); raw_font/raw_text/tok_size=0; label da busca agora usa `bodyMedium`+`textTertiary` — mesma família do ícone da busca (settings_hub.dart:173,184-186), visualmente coerente |
| 5 | Acessibilidade | 10% | **9,5** | **Único desconto da 9,45 resolvido e verificado por mim**: `labelText: l10n.settingsSearchHint` + `FloatingLabelBehavior.never` (settings_hub.dart:183-187) — campo vazio expõe nome acessível real na semântica (nó `label="Buscar configurações" isTextField=true`, verificado na árvore real); visual idêntico (nunca flutua) e a busca continua funcionando (testes :320-352 passam); Semantics button/selected; alvos 48dp; texto 2.0 com piso/teto; danger/bgElevated AA travado por teste. Residual: nome não persiste com campo preenchido (🟢-R1, pré-existente e global) |
| 6 | Responsividade e navegação | 10% | **9,5** | testes reais 1200×800 (master-detail), 375×720 (drill-down), 360@2.0 (settings_navigation_test.dart:532,551,566); AppContentMax teto 1200; labelText não quebrou o layout: `isDense`+`border: InputBorder.none` mantidos e a suíte de overflow texto 2.0 passa |
| 7 | Estados e feedback | 5% | **9,5** | reload com loading real (data_settings.dart:27-43) coberto pelo teste `_GatedRepository` (:445-489); estado vazio da busca; erro honesto; splash/erro de bootstrap no PortixApp com paleta correta (agora testado) |
| 8 | Microinterações e performance percebida | 5% | **9,5** | troca de tema animada 220ms e Duration.zero com disableAnimations (app.dart:53-55,64,141); avatar com memCacheWidth + fadeIn; reabertura = 0 downloads (teste widget); chrome reage à troca de brilho sem recriar o app (teste novo) |
| 9 | Microcopy | 5% | **9,5** | pt/en coerente; label da busca reusa `settingsSearchHint` existente (sem string nova duplicada); confirmação de limpar cache promete exatamente o que faz; nenhum literal em Text() (grep=0) |

## 2. Média ponderada (soma explícita)

```
9,5×0,20 = 1,900
9,5×0,20 = 1,900
9,5×0,15 = 1,425
9,5×0,10 = 0,950
9,5×0,10 = 0,950
9,5×0,10 = 0,950
9,5×0,05 = 0,475
9,5×0,05 = 0,475
9,5×0,05 = 0,475
SOMA     = 9,500  →  Média 9,50
```

## 3. Problemas classificados

### 🔴 Grave — nenhum
### 🟡 Médio — nenhum

### 🟢 Menor (5)

**🟢-R1 · Nome acessível da busca não persiste com o campo preenchido**
- Onde: `lib/features/menu/settings_hub.dart:177-192`.
- Evidência: minha instrumentação da semântica real — vazio: `label="Buscar configurações" isTextField=true`; com texto: `label="" value="tema"`. Comportamento padrão do InputDecorator do Flutter (o hint anterior tinha a mesma limitação) — não é regressão.
- Por que 🟢: o desconto original (label ausente) está resolvido; o gap restante é o nome acessível durante a digitação (WCAG 4.1.2 em modo estrito).
- Correção esperada: envolver o TextField em `Semantics(label: l10n.settingsSearchHint, child: …)` (ou `excludeSemantics` + label) para nome persistente.

**🟢-R2 · Reduced motion (themeAnimationDuration → Duration.zero) sem teste permanente**
- Onde: `lib/app/app.dart:53-55,64,83,141` — `rg themeAnimationDuration test/` = 0.
- Por que 🟢: o comportamento foi provado empiricamente na avaliação anterior (teste temporário) e o código está correto; mas a recomendação 🟢-N1 pedia asserts de paleta/AnnotatedRegion/**themeAnimationDuration** e o iter-8 entregou só os 2 primeiros.
- Correção esperada: no grupo novo do PortixApp, override de `MediaQuery.disableAnimationsOf` (ou `accessibilityFeatures.disableAnimations`) e `expect(app.themeAnimationDuration, Duration.zero)` vs `AppMotion.base`.

**🟢-R3 (carregado) · Busca indexa só títulos/descrições de categoria**
- settings_hub.dart. Aceitável com 6 categorias; Linear/iOS indexam itens internos.

**🟢-R4 (carregado) · `strokeWidth: 2` literal em 10 arquivos (fora do escopo do gate)**
- search_page.dart:2, game_reports_page.dart:2, news_page.dart:1, primitives.dart:1, etc. Convenção consistente; um token `strokeHairline` resolveria.

**🟢-R5 · Outros campos de busca do app continuam só hintText (fora do escopo da missão)**
- `search_page.dart:224`, `game_reports_page.dart:122`, `auth_page.dart:303`, `profile_edit_page.dart:266`, `game_detail_page.dart:1428`. A missão era configurações; listar para consistência futura.

## 4. Conferência item a item dos 6 claims do iter 8

| # | Claim do iter-8 | Status | Evidência |
|---|---|---|---|
| 🟢-N1 | Teste permanente do PortixApp (modo Sistema/brilho/AnnotatedRegion) | ✅ **Real e forte** | theme_settings_test.dart:180-251. Verifiquei as 3 suspeitas de fake: (a) bootstrap PENDENTE de verdade — `supabaseBootstrapProvider.overrideWith((Ref) => boot.future)` com Completer nunca completado e o provider é `FutureProvider<void>` (providers.dart:24) → app fica no splash (app.dart:134-144); (b) asserts de brilho de VERDADE — `auroraDark.bg` (0xFF07090E) ≠ `auroraLight.bg` (0xFFF6F7FB) e mode `system` resolve por `MediaQuery.platformBrightnessOf` (app.dart:121-132); (c) o AnnotatedRegion procurado é O QUE CARREGA o estilo — só existem 2 em lib/ (app.dart:70,89), um por variante do MaterialApp, no builder, e o teste acha o único presente. Rodado isolado: 6/6. Residual: sem assert de themeAnimationDuration (🟢-R2) |
| 🟢-N4 | labelText + floatingLabelBehavior.never na busca | ✅ **Real, verificado na semântica** | settings_hub.dart:183-187; minha instrumentação: campo vazio expõe `label="Buscar configurações"` no nó do campo. Layout preservado (isDense + border none mantidos; testes de busca e overflow 2.0 passam). Residual: label some da semântica com texto digitado (🟢-R1, pré-existente) |
| 🟢-N2 | SystemChrome imperativo removido do main.dart | ✅ **Corrigido de verdade** | diff: bloco de 10 linhas removido; main.dart:17-20 tem só o comentário documentando que o AnnotatedRegion cobre o 1º frame; import de tokens.dart limpo junto; `rg SystemChrome.setSystemUIOverlayStyle lib/` = **0**; o AnnotatedRegion de fato cobre o splash (app.dart:88-92) |
| 🟢-N3 | numericLabel removido | ✅ **Corrigido de verdade** | diff remove o getter; `rg numericLabel lib/ test/` = 0; analyze limpo (nenhuma referência quebrada) |
| 🟢-N5 | Cabeçalho do teste de cache atualizado | ✅ | profile_avatar_cache_test.dart:15-32 descreve nível A (cache manager) e nível B (widget real, "é o caminho que o app de fato usa") |
| 🟢-N6 | par danger/bgElevated no contraste | ✅ | theme_contrast_test.dart:107; suíte completa passou (20 testes de contraste, 5 paletas) |

**Saldo: 6/6 claims reais. Nenhum fake fix.** O commit descreve exatamente o que o diff mostra (8 arquivos, +263/−23, incluindo o registro do CRÍTICO anterior).

## 5. Veredito

| Condição de parada | Estado |
|---|---|
| Média ≥ 9,5 | ✅ **9,50** |
| Nenhum critério < 9 | ✅ todos 9,5 |
| Zero 🔴/🟡 | ✅ zero e zero (5 🟢 residuais, todos não-bloqueantes) |
| Imagem comprovadamente sem recarregar na 2ª abertura | ✅ nível WIDGET com contador HTTP (1º=1; 5 renders=0; clear memória=0 via disco; removeFile=1) — rodado isolado por mim |
| Temas AA sem cores hardcoded | ✅ testes de contraste (5 paletas, pares compostos incl. danger/bgElevated) + raw_color=0 (gate rodado por mim) |
| CI verde | ⚠️✅ run 44117056475 declarado success pelo CRIADOR; API rate-limited (2 tentativas, gh ausente). Evidência local completa e equivalente: analyze + gates + 117/117 rodados por mim no mesmo SHA |
| 2 avaliações consecutivas ≥ 9,5 | 🕐 sequência: 8,43 → 8,60 → 9,05 → 9,45 → **9,50 (esta)** |

## **🌟 1ª LEITURA CONSECUTIVA ≥9,5 ATINGIDA — falta 1 reavaliação de estabilidade**

Todas as condições técnicas de parada estão cumpridas nesta leitura (média 9,50,
zero critério <9, zero 🔴/🟡, cache provado por teste, AA provado por teste+gate,
CI verde por evidência local). O que resta é a condição processual do dono:
**2 avaliações consecutivas ≥9,5** — esta é a 1ª. Falta 1 reavaliação de
estabilidade que confirme ≥9,5 (idealmente na próxima iteração do CRIADOR, que
pode ser de estabilidade, sem mudanças de feature).

## 6. TOP priorizado para o CRIADOR

1. **Iteração de estabilidade**: nenhuma mudança de comportamento; pode conter só os itens abaixo (ou nada). Qualquer regressão em AppColorsTheme/AnnotatedRegion/cache derruba a 2ª leitura.
2. **(opcional, barato) 🟢-R2**: assert de `themeAnimationDuration` (Duration.zero ↔ AppMotion.base) no grupo novo do PortixApp — fecha o pedido original do 🟢-N1.
3. **(opcional) 🟢-R1**: `Semantics(label: …)` no campo de busca para nome acessível persistente durante a digitação.
4. **(pós-APROVADO) 🟢-R3/R4/R5**: busca indexando itens internos, token `strokeHairline`, labelText nos demais campos de busca do app.
