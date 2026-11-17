# Login (Auth) + Perfil (editar/público)

## Antes (U1)

- Formulário sem validação por campo com mensagem inline (erros em snackbar genérico).
- Botão de entrar sem estado de carregamento dedicado (spinner dentro do botão? verificar —
  hoje desabilita sem feedback claro).
- Campos sem `textInputAction`/autofill hints (email/senha) — UX de teclado imperfeita.
- Avatar/picker manual; perfil público: stats em `_MenuStat`-like duplicado.
- `Colors.`/`Color(0x…)` presentes nos 3 arquivos (regra raw_color).

## Depois (preencher na iteração U1-C)

- (a registrar)
