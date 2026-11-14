import 'package:material_ui/material_ui.dart';

// ============================================================================
// PORTIX — design tokens ("Aurora")
// Único ponto de verdade para cores, raios, espaçamentos, durações e sombras.
// Nenhuma tela deve declarar cor/tamanho solto: use estes tokens.
// ============================================================================

/// Cores da identidade Aurora. Tema único (escuro).
class AppColors {
  const AppColors._();

  /// Fundo base das telas.
  static const Color bg = Color(0xFF07090E);

  /// Fundo de sheets e áreas elevadas.
  static const Color bgElevated = Color(0xFF0D1017);

  /// Preenchimento de vidro padrão (branco 6%).
  static const Color glass = Color(0x0FFFFFFF);

  /// Vidro reforçado: item selecionado, pressionado, botões circulares (branco 10%).
  static const Color glassStrong = Color(0x1AFFFFFF);

  /// Borda fina de todo elemento de vidro (branco 12%).
  static const Color glassBorder = Color(0x1FFFFFFF);

  static const Color textPrimary = Color(0xFFF4F6FA);
  static const Color textSecondary = Color(0x9EFFFFFF); // branco 62%
  static const Color textTertiary = Color(0x6BFFFFFF); // branco 42%

  /// Destaque principal (ciano).
  static const Color accent = Color(0xFF22D3EE);

  /// Segundo tom do gradiente de destaque (esmeralda).
  static const Color accentAlt = Color(0xFF34D399);

  /// Texto/ícone sobre o gradiente de destaque.
  static const Color onAccent = Color(0xFF031317);

  static const Color favorite = Color(0xFFFB7185);
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);

  /// Gradiente do botão principal e da barra de progresso.
  static const LinearGradient accentGradient = LinearGradient(
    colors: <Color>[accent, accentAlt],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

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
  static const double circleButton = 46;
  static const double searchFab = 68;
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

/// Sombras suaves reutilizadas pelos elementos de vidro.
class AppShadows {
  const AppShadows._();

  static const List<BoxShadow> glass = <BoxShadow>[
    BoxShadow(
      color: Color(0x59000000),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];

  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x8C000000),
      blurRadius: 32,
      offset: Offset(0, 16),
    ),
  ];
}
