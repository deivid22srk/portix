import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme/tokens.dart';

// ============================================================================
// Tema do PORTIX — escuro único, montado a partir dos tokens "Aurora".
// `AppPalette` expõe apelidos curtos (bg/text/muted/primary...) para o restante
// do código, sempre derivados de AppColors. Nada de cor solta nas telas.
// ============================================================================
class AppPalette {
  const AppPalette();

  // ---- apelidos curtos ----
  Color get bg => AppColors.bg;
  Color get bgSoft => AppColors.bgElevated;
  Color get surface => AppColors.glassStrong;
  Color get surfaceHigh => AppColors.glass;
  Color get line => AppColors.glassBorder;
  Color get text => AppColors.textPrimary;
  Color get muted => AppColors.textSecondary;
  Color get faint => AppColors.textTertiary;
  Color get primary => AppColors.accent;
  Color get secondary => AppColors.accentAlt;
  Color get danger => AppColors.danger;
  Color get success => AppColors.success;
  Color get warning => AppColors.warning;
  Color get favorite => AppColors.favorite;
  Color get onAccent => AppColors.onAccent;
  bool get dark => true;

  LinearGradient get brand => AppColors.accentGradient;

  LinearGradient get brandSoft => LinearGradient(
        colors: <Color>[
          AppColors.accent.withValues(alpha: 0.22),
          AppColors.accentAlt.withValues(alpha: 0.08),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get cardGradient => const LinearGradient(
        colors: <Color>[AppColors.glass, Color(0x0AFFFFFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Escurecimento sobre capas para legibilidade de texto.
  LinearGradient get coverScrim => const LinearGradient(
        colors: <Color>[
          Colors.transparent,
          Color(0x00000000),
          Color(0xA6000000),
          Color(0xD9000000),
        ],
        stops: <double>[0, 0.5, 0.82, 1],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  /// Transição do topo da tela de detalhes para o fundo.
  LinearGradient get scrim => LinearGradient(
        colors: <Color>[
          Colors.transparent,
          AppColors.bg.withValues(alpha: 0.55),
          AppColors.bg.withValues(alpha: 0.94),
          AppColors.bg,
        ],
        stops: const <double>[0, 0.42, 0.78, 1],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  static const AppPalette darkPalette = AppPalette();

  static AppPalette of(Brightness brightness) => darkPalette;
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => AppPalette.darkPalette;
  TextTheme get texts => Theme.of(this).textTheme;
  ColorScheme get scheme => Theme.of(this).colorScheme;
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final TextTheme base = GoogleFonts.poppinsTextTheme();
    final TextTheme textTheme = base.copyWith(
      // Títulos de tela grandes (~34–40).
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        height: 1.05,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        height: 1.06,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.08,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.1,
      ),
      // Título grande do jogo nos detalhes.
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
      bodySmall: base.bodySmall?.copyWith(fontSize: 13, height: 1.4),
      labelLarge: base.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600),
    );

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accentAlt,
      surface: AppColors.bg,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      outline: AppColors.glassBorder,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      textTheme: textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }
}

// Tema resolvido uma única vez por sessão.
final darkThemeProvider = Provider<ThemeData>((ref) => AppTheme.dark());
