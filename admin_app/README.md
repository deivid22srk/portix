# PORTIX ADM — app separado

Segundo app Flutter, **independente** do PORTIX: painel de administração com
estatísticas e hierarquia de ADMs. Não compartilha código com o app principal.

- Login por e-mail/senha (Supabase Auth).
- **Estatísticas** do catálogo e da comunidade (RPC `admin_stats`).
- **ADMs**: o ADM raiz (`psvstore01@gmail.com`, promovido automaticamente no
  primeiro login) concede/revoga acesso e define permissões
  (`view_stats`, `moderate_reviews`, `manage_games`, `manage_users`).
- Quem tem `moderate_reviews` pode apagar avaliações e aparece com o selo
  **ADM** nos relatos do PORTIX.

## Build

O APK é gerado pelo workflow [`admin-app.yml`](../.github/workflows/admin-app.yml)
(artefato `portix-admin-apk`). A URL e a chave anônima entram por
`--dart-define` a partir dos mesmos secrets do repositório; sem elas o app abre
uma tela para configurar o projeto manualmente.

## Rodar localmente

```bash
cd admin_app
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=SUA-CHAVE
```

Nenhuma chave de serviço/gestão é usada — apenas a anon key pública.
