# Diálogos, sheets e snackbars

## Antes (U1)

- Sem componente padrão: `UpdateDialog` (dialog manual), `FilterSheet`/`CompatReportSheet`
  (sheets manuais com raio/insets próprios), `StarPicker` inline.
- Snackbars: `SnackBar` cru com cores do scheme — sem estilo do tema (fundo, radius, ação) nem
  padrão com desfazer.
- Handle de arrasto ausente; alturas máximas inconsistentes; bottom inset tratado pontualmente
  (`systemBottomInset` em alguns, esquecido em outros).
- Dialogs sem `barrierLabel` acessível.

## Depois (preencher na iteração U1-V)

- (a registrar)
