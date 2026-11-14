# PORTIX · Painel ADM (app separado)

App **separado** (HTML/CSS/JS, sem build) para administrar o PORTIX. Não faz
parte do APK e não compartilha código com o app mobile.

- Publicado no GitHub Pages: `https://deivid22srk.github.io/portix/`
- Login por e-mail/senha (Supabase Auth).
- Estatísticas do catálogo e da comunidade (RPC `admin_stats`).
- Hierarquia de ADMs (RPCs `admin_*`), com o **ADM raiz** `psvstore01@gmail.com`
  promovido automaticamente no primeiro login.

## Níveis e permissões

| Nível | O que pode |
| --- | --- |
| `root` | tudo; concede/revoga ADMs e define permissões |
| `admin` | o que as permissões concedidas permitirem |
| `moderator` | idem, tipicamente `moderate_reviews` |

Permissões: `view_stats`, `moderate_reviews`, `manage_games`, `manage_users`.
Quem tem `moderate_reviews` pode apagar avaliações (policy no banco), e o selo
**ADM** aparece ao lado do nome nos relatos do app principal.

## Primeiro acesso

1. Crie a conta do ADM raiz dentro do PORTIX (e-mail `psvstore01@gmail.com`) ou
   pelo próprio painel (mesmo projeto).
2. Abra o painel, informe `SUPABASE_URL` + `SUPABASE_ANON_KEY` e entre. O root é
   promovido automaticamente e passa a enxergar a aba **Administradores**.
3. Para dar acesso a outra pessoa: ela precisa ter conta criada no PORTIX; depois
   use “Conceder acesso” com o e-mail e as permissões.

## Rodar localmente

```bash
cd admin
python3 -m http.server 8080
# abra http://localhost:8080
```

A URL e a chave anônima ficam apenas no `localStorage` do navegador — nada de
segredos no repositório.
