# Camada de dados do GitHub (ficha de versões e desenvolvedor)

Um único serviço concentra todas as chamadas ao GitHub: `lib/core/github_service.dart`
(`GitHubApi` + providers Riverpod). Nenhuma tela fala com a API direto.

## Endpoints usados (todos anônimos, sem token)

| Endpoint | Uso | Cadência |
|---|---|---|
| `GET /repos/{owner}/{repo}/releases?per_page=20` | Seletor de versões, "Novidades", detecção de atualização | 1 requisição por tela (com cache) |
| `GET /users/{owner}` | Card do desenvolvedor (nome, foto, bio, Organization) | 1 requisição por tela (com cache) |

## Estratégia de cache (meta: reabrir = 0 downloads)

1. **Memória** (instância viva do app): TTL de 5 minutos. Reabrir a tela
   dentro do TTL = **0 requisições** (comprovado por teste: 3 aberturas =
   1 chamada HTTP; perfil 5x = 1 chamada).
2. **Disco** (`CacheStore`/SharedPreferences): payload + ETag + timestamp.
   Sobrevive a reinício do app e serve dados **stale** quando offline.
3. **Requisições condicionais**: o ETag da última resposta vai em
   `If-None-Match`; um `304` devolve o cache com 0 bytes na rede e a UI
   não pisca nem recarrega.

## Limites da API e degradação

- Sem autenticação o limite é **60 requisições/hora por IP**.
- `403` com `x-ratelimit-remaining: 0` (ou body "rate limit") e `429` são
  mapeados para `GitHubErrorKind.rateLimit` → a UI mostra estado dedicado
  ("Limite do GitHub atingido") com botão Tentar de novo.
- Se existe cache (memória ou disco), ele é servido **em vez** de tela vazia.
- Erros de rede (`SocketException`, `ClientException`, timeout 12s) →
  `GitHubErrorKind.offline` → mesmo comportamento stale.
- `404` (repo privado/movido/removido) → `GitHubErrorKind.notFound` →
  estado "Repositório indisponível". Para usuários, 404 é caso normal e
  devolve `null` (fallback com iniciais).
- **Nenhum token/secrets no app** — todas as chamadas são anônimas.

## Sugestão registrada (não implementada sem aprovação)

Se o limite de 60/h se tornar problema em produção, a opção é um
**proxy próprio** (ex.: Cloudflare Worker / função serverless) que:
1. Faz cache por `owner/repo` no CDN (TTL curto + ETag passthrough);
2. Opcionalmente usa um token de servidor (60 → 5.000/h) sem expor nada
   ao cliente;
3. Mantém o contrato `GitHubApi` inalterado (troca só a `baseUrl`).
Esta implementação não adiciona proxy nem token — decisão conservadora.
