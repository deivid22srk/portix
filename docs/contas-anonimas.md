# Contas anônimas: causa, correção e limpeza

## O que estava acontecendo

`lib/core/providers.dart` chamava `signInAnonymously()` no boot de **toda
instalação**. No Supabase isso cria uma linha em `auth.users` **sem e-mail** por
instalação/reinstalação — o banco acumulava contas que ninguém criou, e o
usuário "tinha conta" sem ter se cadastrado.

## O que mudou

1. **A sessão anônima automática foi removida.** O app agora abre como
   **visitante**: navega o catálogo, busca, vê detalhes, recebe o feed (que já
   funciona sem conta, com `anon_id` local para impressões) e pode se cadastrar
   quando quiser.
2. **Ações que exigem conta avisam em vez de falhar**: favoritar, entrar na
   biblioteca, avaliar e editar perfil mostram o convite para entrar (com ação
   direta para a tela de login) — algumas já tinham essa guarda; favoritar e
   biblioteca passaram a ter.
3. **Leituras toleram visitante**: `fetchCollections` devolve coleção vazia e os
   toggles devolvem `false` sem sessão, em vez de estourar erro de rede.

## Limpar o passivo

`supabase/migrations/0024_purge_anonymous_accounts.sql` traz duas funções
(`security definer`, revogadas de `anon`/`authenticated`):

```sql
-- 1) SEMPRE comece pelo dry-run: ele só relata (padrão).
select public.purge_anonymous_accounts();
-- → {"dry_run": true, "candidates": N, "oldest": ..., "newest": ..., "sample": [...]}

-- 2) confira a amostra e o volume; então execute em lotes.
select public.purge_anonymous_accounts(false, 5000);   -- apaga até 5000
select public.purge_anonymous_accounts(false, 5000);   -- repita até "remaining": 0
```

O critério é conservador — apaga **somente** conta que:

- não tem e-mail (nem vazio/espaços), **e**
- está marcada como anônima (`is_anonymous` ou `raw_app_meta_data.provider =
  'anonymous'`), **e**
- **não** tem nenhuma identidade com e-mail.

Ou seja: conta real nunca é tocada, e uma conta anônima que depois vinculou
e-mail também não. As FKs são `on delete cascade`, então perfil, favoritos,
biblioteca, downloads, avaliações e impressões daquela conta saem junto.

**É irreversível.** Rode o dry-run, confira `candidates` e `sample`, e só então
execute. Em produção, aplique a migration e rode pelo SQL editor do Supabase (ou
`tools/import/apply_sql.py`, com o token de gestão) — a função exige privilégio
de dono/service_role de propósito.

## Como isso é testado

`supabase/tests/50_purge_accounts.sql` (roda no job `feed-sql` do CI) monta seis
contas — três anônimas, uma anônima que vinculou e-mail, uma sem e-mail mas com
identidade de e-mail e uma real — e prova que: o dry-run não apaga, o lote é
respeitado, só as três anônimas somem, as demais ficam, os dados em cascata
saem e o cliente (`authenticated`) não executa nem lista.
