import 'package:material_ui/material_ui.dart';

export 'themes.dart';

// ============================================================================
// PORTIX — design tokens ("Aurora")
// Único ponto de verdade para raios, espaçamentos, durações, breakpoints e
// SOMBRAS. Cores de tema ficam em themes.dart (AppColorsTheme); cores de
// CONTEÚDO (scrims sobre mídia, marca) ficam aqui — são invariantes de tema.
// Nenhuma tela deve declarar cor/tamanho solto: use estes tokens.
// ============================================================================

/// Raios de canto.
class AppRadii {
  const AppRadii._();

  static const double sm = 12;
  static const double md = 20;
  static const double lg = 24;
  static const double pill = 999;
  static const Radius sheet = Radius.circular(28);
}

/// Escala de espaçamento e medidas de layout.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Margem lateral padrão das telas.
  static const double screen = 16;

  /// Espaço entre cards de grade.
  static const double gridGap = 12;

  /// Botões.
  static const double primaryButtonHeight = 52;
  static const double secondaryButtonHeight = 48;
  // 48px: alvo mínimo de toque WCAG 2.2 AA (2.5.8) — antes 46.
  static const double circleButton = 48;
  static const double searchFab = 68;

  /// Capa compacta na linha de download (proporção ~3:4 de pôster).
  static const double tileCoverWidth = 58;
  static const double tileCoverHeight = 78;

  /// Altura reservada do estado vazio dentro do viewport do Hub.
  static const double emptyStateViewport = 360;

  /// Folga da snackbar flutuante acima da barra de navegação de vidro.
  static const double snackbarBottomGap = 96;
}

/// Durações e curvas de animação.
class AppMotion {
  const AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 300);
  static const Duration indicator = Duration(milliseconds: 250);

  /// Intervalo do autoplay do carrossel de destaques.
  static const Duration autoplay = Duration(seconds: 5);

  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve out = Curves.easeOutCubic;
}

/// Breakpoints responsivos (mobile-first). Grades de capas ganham colunas
/// conforme a largura; acima de `contentMax` o conteúdo é centralizado com
/// teto de largura para não esticar capas 3:4 em monitores.
class AppBreakpoints {
  const AppBreakpoints._();

  /// Tablet / paisagem baixa.
  static const double tablet = 600;

  /// Desktop estreito.
  static const double desktop = 1024;

  /// Telas largas.
  static const double wide = 1440;

  /// Teto de largura do conteúdo de grades em telas largas.
  static const double contentMax = 1200;

  /// Colunas da grade de capas 3:4 conforme a largura disponível.
  static int coverColumns(double width) {
    if (width >= wide) {
      return 6;
    }
    if (width >= desktop) {
      return 5;
    }
    if (width >= tablet) {
      return 3;
    }
    return 2;
  }
}

/// Cores de CONTEÚDO — aparecem sobre mídia (capa, foto, vídeo) e não mudam
/// com o tema: legibilidade sobre imagem é sempre a mesma.
class AppContentColors {
  const AppContentColors._();

  /// Ausência de cor (scrims que começam transparentes).
  static const Color transparent = Color(0x00000000);

  /// Texto/ícone sobre mídia (capa, notícia, vídeo).
  static const Color onMedia = Color(0xFFFFFFFF);

  /// Scrim preto puro — use com `withValues(alpha: …)` para cada caso.
  static const Color scrim = Color(0xFF000000);

  /// Scrim padrão do rodapé de card (gradiente de título).
  static const Color scrimSoft = Color(0x22000000);

  /// Scrim forte de rodapé de card.
  static const Color scrimStrong = Color(0xD9000000);
}

/// Cores da MARCA (logo PORTIX) — invariantes de tema: a identidade não muda
/// com a aparência escolhida.
class AppBrandColors {
  const AppBrandColors._();

  /// Céu claro do gradiente de brilho do logo.
  static const Color skyLight = Color(0xFFCFFAFE);
}
