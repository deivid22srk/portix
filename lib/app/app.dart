import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/env.dart';
import '../core/providers.dart';
import '../core/theme/tokens.dart';
import '../features/splash/splash_page.dart';
import 'router.dart';
import 'settings.dart';
import 'theme.dart';

// Raiz do app. O bootstrap do Supabase acontece antes de qualquer rota ser
// construída: assim nenhuma tela tenta usar o client sem configuração.
class PortixApp extends ConsumerWidget {
  const PortixApp({super.key});

  // `GlobalMaterialLocalizations.delegates` reúne Material, Widgets e Cupertino.
  static const List<LocalizationsDelegate<dynamic>> _delegates =
      GlobalMaterialLocalizations.delegates;

  static const List<Locale> _locales = <Locale>[
    Locale('pt', 'BR'),
    Locale('en'),
  ];

  /// Escala de texto do sistema: piso 1.0 (nunca rebaixa o pedido do usuário)
  /// e teto 2.0 — WCAG 1.4.4 exige redimensionamento de 200%. O layout deve
  /// sobreviver ao teto (as grades/limites de largura já são elásticas).
  Widget _withTextScale(Widget? child) => MediaQuery.withClampedTextScaling(
    minScaleFactor: 1.0,
    maxScaleFactor: 2.0,
    child: child ?? const SizedBox.shrink(),
  );

  /// Monte o MaterialApp uma única vez — as variantes com router e as de
  /// boot/erro (home) compartilham a mesma configuração de tema/localização.
  Widget _app({
    required ThemeData theme,
    required ThemeData darkTheme,
    required ThemeMode mode,
    required AppSettings settings,
    Widget? home,
    GoRouter? router,
  }) {
    if (router != null) {
      return MaterialApp.router(
        title: 'PORTIX',
        debugShowCheckedModeBanner: false,
        theme: theme,
        darkTheme: darkTheme,
        themeMode: mode,
        // Troca de tema animada e sutil (ver setThemeId).
        themeAnimationDuration: AppMotion.base,
        themeAnimationCurve: AppMotion.emphasized,
        locale: settings.locale,
        supportedLocales: _locales,
        localizationsDelegates: _delegates,
        builder: (BuildContext context, Widget? child) => _withTextScale(child),
        routerConfig: router,
      );
    }
    return MaterialApp(
      title: 'PORTIX',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: mode,
      themeAnimationDuration: AppMotion.base,
      themeAnimationCurve: AppMotion.emphasized,
      locale: settings.locale,
      supportedLocales: _locales,
      localizationsDelegates: _delegates,
      builder: (BuildContext context, Widget? child) => _withTextScale(child),
      home: home,
    );
  }

  /// Aplica os ícones das barras do sistema conforme a paleta resolvida
  /// (operação idempotente — pode ser chamada a cada mudança de tema).
  void _applySystemChrome(AppColorsTheme colors) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: AppContentColors.transparent,
        statusBarIconBrightness: colors.isDark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: colors.isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: AppContentColors.transparent,
        systemNavigationBarIconBrightness: colors.isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final AsyncValue<void> bootstrap = ref.watch(supabaseBootstrapProvider);
    final AppThemePair pair = appThemePairFor(settings.themeId);
    final ThemeMode mode = themeModeFor(settings.themeId);
    final ThemeData lightTheme = AppTheme.build(pair.light);
    final ThemeData darkTheme = AppTheme.build(pair.dark);

    // Ícones das barras do sistema seguem o tema resolvido. O listener cobre
    // a troca; o apply direto cobre o primeiro frame (operação idempotente).
    ref.listen<AppSettings>(settingsProvider, (_, AppSettings next) {
      final AppThemePair pairNext = appThemePairFor(next.themeId);
      final AppColorsTheme colors = switch (themeModeFor(next.themeId)) {
        // No modo Sistema a paleta escuro é o design de referência do app.
        ThemeMode.light => pairNext.light,
        ThemeMode.dark || ThemeMode.system => pairNext.dark,
      };
      _applySystemChrome(colors);
    });
    final Brightness resolved = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => View.of(
        context,
      ).platformDispatcher.platformBrightness,
    };
    final AppColorsTheme colors = resolved == Brightness.light
        ? pair.light
        : pair.dark;
    _applySystemChrome(colors);

    if (bootstrap.isLoading) {
      return _app(
        theme: lightTheme,
        darkTheme: darkTheme,
        mode: mode,
        settings: settings,
        home: const SplashPage(),
      );
    }

    if (bootstrap.hasError) {
      return _app(
        theme: lightTheme,
        darkTheme: darkTheme,
        mode: mode,
        settings: settings,
        home: BootstrapErrorPage(
          error: bootstrap.error ?? const AppFailure(FailureKind.unknown),
        ),
      );
    }

    return _app(
      theme: lightTheme,
      darkTheme: darkTheme,
      mode: mode,
      settings: settings,
      router: ref.watch(routerProvider),
    );
  }
}
