import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

// Tokens visuais do PORTIX. Nada de ThemeExtension: cores resolvidas por
// brilho, o que mantém o tema leve e imune a mudanças de API de componente.
class AppPalette {
  const AppPalette({
    required this.dark,
    required this.bg,
    required this.bgSoft,
    required this.surface,
    required this.surfaceHigh,
    required this.line,
    required this.text,
    required this.muted,
    required this.primary,
    required this.secondary,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final bool dark;
  final Color bg;
  final Color bgSoft;
  final Color surface;
  final Color surfaceHigh;
  final Color line;
  final Color text;
  final Color muted;
  final Color primary;
  final Color secondary;
  final Color success;
  final Color warning;
  final Color danger;

  static const Color violet = Color(0xFF8B5CFF);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color mint = Color(0xFF34D399);
  static const Color amber = Color(0xFFFFC857);
  static const Color rose = Color(0xFFFF5C8A);

  static const AppPalette dark = AppPalette(
    dark: true,
    bg: Color(0xFF06060C),
    bgSoft: Color(0xFF0B0C15),
    surface: Color(0xFF101220),
    surfaceHigh: Color(0xFF191C2C),
    line: Color(0x1FFFFFFF),
    text: Color(0xFFF4F5FB),
    muted: Color(0xFF9AA1B8),
    primary: violet,
    secondary: cyan,
    success: mint,
    warning: amber,
    danger: rose,
  );

  static const AppPalette light = AppPalette(
    dark: false,
    bg: Color(0xFFF4F5FA),
    bgSoft: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEDEFF7),
    line: Color(0x140F1227),
    text: Color(0xFF11131F),
    muted: Color(0xFF5E6479),
    primary: Color(0xFF6D45F5),
    secondary: Color(0xFF0891B2),
    success: Color(0xFF0F9D6E),
    warning: Color(0xFFB7791F),
    danger: Color(0xFFD63A5F),
  );

  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  LinearGradient get brand => const LinearGradient(
        colors: <Color>[violet, cyan],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get brandSoft => LinearGradient(
        colors: <Color>[
          violet.withValues(alpha: dark ? 0.26 : 0.14),
          cyan.withValues(alpha: dark ? 0.12 : 0.08),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get cardGradient => LinearGradient(
        colors: <Color>[
          surfaceHigh.withValues(alpha: dark ? 0.9 : 1),
          surface.withValues(alpha: dark ? 0.7 : 1),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get scrim => LinearGradient(
        colors: <Color>[
          Colors.transparent,
          bg.withValues(alpha: 0.35),
          bg.withValues(alpha: 0.92),
          bg,
        ],
        stops: const <double>[0, 0.46, 0.82, 1],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => AppPalette.of(Theme.of(this).brightness);
  TextTheme get texts => Theme.of(this).textTheme;
  ColorScheme get scheme => Theme.of(this).colorScheme;
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(AppPalette.dark);

  static ThemeData light() => _build(AppPalette.light);

  static ThemeData _build(AppPalette p) {
    final TextTheme display = GoogleFonts.spaceGroteskTextTheme();
    final TextTheme base = GoogleFonts.interTextTheme();
    final TextTheme textTheme = base.copyWith(
      displayLarge: display.displayLarge,
      displayMedium: display.displayMedium,
      displaySmall: display.displaySmall,
      headlineLarge: display.headlineLarge,
      headlineMedium: display.headlineMedium,
      headlineSmall: display.headlineSmall,
      titleLarge: display.titleLarge,
      titleMedium: display.titleMedium,
    );

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.violet,
      brightness: p.dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: p.primary,
      secondary: p.secondary,
      surface: p.surface,
      onSurface: p.text,
      error: p.danger,
      outline: p.line,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      textTheme: textTheme.apply(bodyColor: p.text, displayColor: p.text),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }
}

// Temas resolvidos uma única vez por sessão: o MaterialApp apenas troca a
// referência, sem reconstruir a tipografia a cada mudança de estado.
final darkThemeProvider = Provider<ThemeData>((ref) => AppTheme.dark());

final lightThemeProvider = Provider<ThemeData>((ref) => AppTheme.light());
