# Missão: ficha técnica de dispositivos via API pública — diário final

**Branch:** `feat/ficha-tecnica-dispositivos` (baseada em `feat/configuracoes-categorias-temas-cache` 26dbc56)
**Status:** APROVADA — CI verde (run 44132467003), suíte 137/137, analyze 0 issues, portões de UI OK.

## Pedido

"Implemente uma API pública grátis no app para ver toda a especificação do dispositivo.
Nos relatos da comunidade, o usuário clica no nome do dispositivo e vai para uma nova
tela com toda a ficha técnica. Se tiver imagem na API, exibir de forma organizada."

## FASE 0 — seleção da API (evidências via curl ao vivo)

Candidatos testados: `phones-specs-api.vercel.app` (DEPLOYMENT_NOT_FOUND),
`api-mobilespecs.azharimm.dev` e `phone-specs-api-2.azharimm.dev` (DNS morto),
`gsmarena-api.vercel.app`/`api-gsmarena.vercel.app` (mortas), `specs.fldtrace.com`
(DNS morto). Viva e estável: **`https://phone-specs-api.vercel.app`** (phone-specs-api
do azharimm, dados GSMArena, sem chave, MIT-ish unofficial, repo atualizado 2026).

- `/brands` → 127 marcas (20 KB) — **OK**
- `/brands/{slug}?page=N` → 50 aparelhos/página, last_page 5–16 nas grandes — **OK**
- `/{phone_slug}` → ficha completa: thumbnail + `phone_images[]` + fatos rápidos +
  `specifications[{title, specs[{key, val[]}]}]` — **OK** (iPhone 12 Pro Max validado)
- `/search?query=` → **QUEBRADO na instância** (Puppeteer/Chrome ausente no deploy)

## Causa raiz da busca e solução

Sem `/search`, o fluxo "tocou no nome → ficha técnica" foi resolvido com busca em
duas camadas no repositório: (1) endpoint direto quando a instância o consertar
(flag de saúde por sessão); (2) fallback determinístico por marca — resolve a marca
no texto com apelidos (Poco/Redmi→Xiaomi, Galaxy→Samsung, iPhone/iPad→Apple,
Pixel→Google, Moto→Motorola, ROG/Zenfone→Asus), baixa as páginas da marca em
paralelo (concorrência 6, cap 20 páginas) e pontua nomes normalizados
(exato 100 / prefixo 80 / contém 60 / palavras 60/10·palavra). Tudo cacheado em
memória por sessão: re-busca da mesma marca e reabertura de ficha = 0 requisições.

## Entrega (commit 9235f55)

- `lib/features/device_specs/`: modelos tolerantes (parsing.dart), cliente HTTP com
  timeout/AppFailure (rede/servidor/404), repositório com caches, providers Riverpod.
- Tela de busca: campo com debounce 450 ms, skeletons, estados de erro/vazio
  localizados, resultado único → abre a ficha direto (fluxo do relato).
- Tela da ficha: imagem principal, galeria oficial em carrossel (CachedNetworkImage,
  memCacheWidth), visão geral (lançamento/dimensões/sistema/armazenamento), grupos de
  especificações com vocabulário traduzido (Tela, Plataforma, Câmeras, Bateria...)
  e crédito "Dados da ficha técnica: GSMArena".
- Relatos: `_DeviceLink` no `FeedbackReportRow` (nome accent + chevron, rotas
  `/specs/search?q=`) e ação "Ver ficha técnica" no `CompatReportSheet`.
- Rotas `/specs/search` e `/specs/:slug` com transição de expansão; strings novas no
  L10n pt/en; ZERO dependências novas.
- Testes: parse (fixture + tolerante + vocabulário), repositório mockado (fallback,
  apelidos, paginação, cache de ficha, AppFailure.network), telas e navegação
  completa (linha → busca → ficha; sheet → ação; auto-nav resultado único).
- Sonda extra (não commitada) parseou JSONs REAIS capturados: OK.

## Incidente de CI — 3 runs falhos antes do verde

Falha determinística no runner (`profile_avatar_cache_test`, Expected 2/Actual 1)
em teste pré-existente da missão de cache; local passava 15/15 (mesma Flutter
3.50.0). Causa raiz lida no código do `flutter_cache_manager` 3.5: o
`WebHelper._memCache` mantém o `BehaviorSubject` por URL até `subject.close()`
completar — o que depende do descarte do completer da imagem antiga; em runners
lentos, chamadas posteriores recebem **replay de FileInfo velho** (arquivo já
removido) e o re-download nunca acontece. `getSingleFile` não contorna (usa o
mesmo caminho). Fix (8da5006): invalidação continua real via `removeFile`, e o
re-download é medido com `downloadFile(force: true)` (público, ignora o cache de
streams); o render final segue provando o disco atendendo sem rede. Mesma
evidência, sem corrida. 4º dispatch: verde ponta a ponta.

## Lição

Ao depender de biblioteca com estado interno global (singletons de cache), a
evidência de teste precisa usar caminhos com semântica await determinística
(`force:`) em vez de depender de drenagem assíncrona em runners lentos.

## Pós-entrega — recuperação do trabalho perdido na branch de detalhes (2026-11-17)
O dono reportou que `feat/detalhes-jogo-versoes-desenvolvedor` "perdeu tudo" da
`feat/ficha-tecnica-dispositivos`. Diagnóstico: a branch de detalhes partiu da
`main` (9060a14) e ficou sem os 45 commits da ficha — nada foi apagado no
remoto; os commits sempre estiveram intactos na branch de origem.
Recuperação por merge (15aad8e) + drenagem dos portões de UI (e1b9fa1):
analyze limpo, 195/195 testes, portões verdes, CI verde
(run 44168045461, commit e1b9fa1). Decisões em DECISIONS.md D-DET5.
