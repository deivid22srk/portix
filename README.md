# PORTIX

**Seus consoles. No seu bolso.**

PORTIX é uma loja/biblioteca Android de _ports_ de jogos clássicos e modernos.
O catálogo é público, aberto e importado de um JSON real; o app oferece home
curada, busca com filtros, detalhes completos, favoritos, biblioteca e uma fila
de downloads simulada, tudo com Material 3, tema escuro por padrão e pt-BR/en.

> Este repositório é um projeto de estudo. Todos os créditos dos jogos, ports,
> capas e links pertencem aos projetos originais. O PORTIX não hospeda arquivos.

---

## Stack

| Camada | Tecnologia |
| --- | --- |
| UI | Flutter stable (Dart 3), Material 3 |
| Estado | Riverpod 3 (`Notifier`, `AsyncNotifier`, `FutureProvider`) |
| Navegação | go_router 18 (`StatefulShellRoute` + rotas de topo) |
| Backend | Supabase (Postgres + RLS + RPCs jsonb + auth anônima) |
| Cache | `shared_preferences` (stale-while-revalidate) |
| Imagens | `cached_network_image` + placeholder procedural determinístico |
| Tipografia | Space Grotesk (display) e Inter (texto) via `google_fonts` |
| Links | `url_launcher` |

Dependências e versões ficam em [`pubspec.yaml`](pubspec.yaml).

---

## Arquitetura

Organização por feature, com uma camada de dados isolada atrás de repositório:

```
lib/
  app/            # MaterialApp, rotas, tema, textos (L10n pt/en), settings
  core/           # bootstrap, providers globais, cache, formatadores, Env
  data/           # CatalogRepository + implementação Supabase
  models/         # Game, GameDetail, HomeFeed, Collections, DownloadTask...
  features/
    splash/       # splash nativa + gate de bootstrap
    shell/        # MainShell com barra flutuante + 404
    home/         # feed curado + controlador com cache
    search/       # busca, filtros, histórico local e paginação
    details/      # ficha do jogo, ports, requisitos, avaliações
    library/      # biblioteca do usuário
    wishlist/     # lista de desejos
    downloads/    # fila simulada persistida + sync opcional
    collections/  # favoritos/biblioteca com update otimista
    profile/      # aparência, idioma, notificações, dados
  shared/widgets/ # primitivas visuais, capas, skeletons, marca
```

Princípios aplicados:

- **Uma chamada por tela**: `home_feed`, `search_games`, `game_detail`,
  `my_collections` e `catalog_facets` devolvem `jsonb` agregado.
- **Cache primeiro**: a home abre com o último payload bom e revalida em
  segundo plano; erros de rede não apagam conteúdo já exibido.
- **Otimista com rollback**: favoritar/entrar na biblioteca atualiza a UI na
  hora e desfaz se o RPC falhar.
- **Listas leves**: `RepaintBoundary` por card, `memCacheWidth` nas capas,
  imagens com fade curto e skeletons animados por um único controlador.
- **Sem codegen**: textos em uma classe `L10n` tipada e migrações SQL versionadas.

---

## Telas

- **Splash** — marca desenhada em código, bootstrap do Supabase e fallback de
  configuração/erro.
- **Home** — saudação, destaque, plataformas, Em alta, Novos, Clássicos, Grátis,
  gêneros e estatísticas do catálogo.
- **Explorar** — busca com debounce, filtros por plataforma/gênero, grátis,
  arquivos do jogo, ordenação, histórico local e paginação infinita.
- **Detalhes** — capa com parallax, metadados, descrição expansível, requisitos,
  ports (fonte, versão, compatibilidade, notas), avaliações com nota e
  relacionados.
- **Biblioteca** — estatísticas, atalho para desejos e jogos instalados.
- **Wishlist** — favoritos com remoção imediata.
- **Downloads** — fila simulada com progresso, pausa, retomada, remoção e
  persistência entre sessões.
- **Perfil** — tema (sistema/claro/escuro), idioma (pt-BR/en), notificações
  simuladas, recarga do catálogo, limpeza de cache e sobre.

---

## Backend Supabase

- Projeto: **portix**
- Região: **sa-east-1**
- URL e chave anônima **não** ficam no repositório; entram no build via
  `--dart-define` (secrets do GitHub Actions).
- A senha do banco está em `/root/.env.local` (`SUPABASE_DB_PASSWORD`, modo
  600). Nunca é impressa, logada ou versionada.

### Tabelas

`platforms`, `games`, `ports`, `profiles`, `reviews`, `favorites`, `library`,
`downloads`.

### RPCs

| RPC | Papel |
| --- | --- |
| `home_feed(p_limit)` | seções da home + facetas + estatísticas |
| `search_games(...)` | busca textual + filtros + ordenação + total |
| `game_detail(p_slug)` | jogo, ports, reviews e relacionados |
| `catalog_facets()` | plataformas e gêneros para filtros |
| `games_by_platform(...)` | listagem por plataforma (reserva) |
| `my_collections()` | favoritos, biblioteca e downloads do usuário |
| `toggle_favorite(uuid)` | alterna favorito e devolve o novo estado |
| `toggle_library(uuid)` | alterna biblioteca e devolve o novo estado |

### RLS

- Catálogo (`games`, `ports`, `platforms`): leitura pública, escrita bloqueada.
- `favorites`, `library`, `downloads`: cada usuário lê/escreve apenas as
  próprias linhas (`auth.uid()`).
- `reviews`: leitura pública e escrita apenas do próprio usuário.
- `profiles`: leitura pública, escrita do próprio perfil.
- Auth anônima habilitada: cada instalação recebe um usuário anônimo estável
  para sincronizar favoritos/biblioteca.

As migrações idempotentes estão em `supabase/migrations/`:

1. `0001_schema.sql` — tabelas, extensões, índices, triggers e grants.
2. `0002_policies.sql` — RLS.
3. `0003_rpc.sql` — views, funções e grants.

---

## Catálogo

Fonte: JSON público de ports Android (campos reais: `games[].ports[]`,
`sourceRows[].VISITAS`). O ZIP/JSON bruto **não** é versionado.

Importação idempotente (usa a Management API somente no provisionamento; o token
`SUPA` vem do ambiente e nunca é commitado):

```bash
export SUPA="<token-de-gestão>"
export SUPABASE_PROJECT_REF="<ref-do-projeto>"
python3 tools/import/apply_sql.py supabase/migrations/*.sql
python3 tools/import/import_catalog.py \
  --input /tmp/catalog/napl_android_port_catalog.json
```

Resultado da carga:

- **839 jogos** importados
- **1.067 ports** importados
- **26 plataformas** (25 + “Multi-Game Apps”)
- **0 registros descartados** / **0 duplicados**
- 10 ports sem URL (mantidos; instalação desabilitada)
- 69 jogos sem capa (placeholder procedural)
- 72 jogos sem gênero

Popularidade usa `VISITAS` das linhas de origem; grátis/ROM vêm dos campos
normalizados do catálogo.

---

## Rodando localmente

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=SUA-CHAVE-ANONIMA
```

Sem as duas defines o app abre uma tela de configuração explicando o que falta.
Nenhuma chave de serviço/gestão é usada no aplicativo.

## Build no CI

O workflow [`.github/workflows/build.yml`](.github/workflows/build.yml) roda a
cada push em `main` (e manualmente):

1. checkout + JDK 17 + Flutter stable com cache;
2. `flutter pub get`, `flutter analyze`, `flutter test`;
3. gera o scaffold `android/` com `flutter create`;
4. aplica manifest release, R8/shrink, ProGuard e `-Xmx4G`;
5. gera ícone adaptativo e splash com `flutter_launcher_icons` e
   `flutter_native_splash`;
6. compila `flutter build apk --release --split-per-abi` com as defines;
7. publica os APKs no artefato **portix-apk**.

Secrets necessários no repositório:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

> A pasta `android/` não é versionada de propósito: o template é sempre gerado
> pela versão stable do CI, reduzindo drifting de Gradle/AGP.

---

## Limitações conhecidas

- **Downloads simulados**: não há APK/arquivo real; a fila avança em memória,
  persiste em `shared_preferences` e sincroniza status com a tabela `downloads`.
  O botão “Abrir fonte” usa o link original do port.
- **Sem autenticação social**: a sessão é anônima por instalação. Limpar dados
  do app cria outra identidade.
- **Sem preços, prints ou contagem de downloads**: o catálogo de origem não
  fornece esses campos; a UI foi adaptada aos dados reais.
- **Capas externas**: algumas URLs do LaunchBox podem falhar; o app cai no
  placeholder procedural com iniciais.
- **Avaliações**: qualquer sessão anônima pode avaliar; não há moderação.
- **Fontes via runtime**: `google_fonts` baixa na primeira execução e usa cache
  local depois. Sem internet, o sistema aplica a fonte de fallback.
- **Assinatura**: o template do CI assina com a chave de debug (instalável, mas
  não adequada para loja). Para produção, configure um keystore.

---

## Segurança

- `SUPA` (Management API) foi usado apenas no provisionamento e **nunca** entra
  no app, no repositório ou nos logs.
- Apenas URL + chave anônima pública vão para o build.
- RLS ativo em todas as tabelas de usuário; catálogo somente leitura.
- `.env*`, JSON bruto, ZIPs e keystores estão no `.gitignore`.
