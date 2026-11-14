import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/env.dart';
import '../core/providers.dart';
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

  static const List<Locale> _locales = <Locale>[Locale('pt', 'BR'), Locale('en')];

  /// Limita a escala de fonte do sistema para o layout não quebrar.
  Widget _withTextScale(Widget? child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.9,
        maxScaleFactor: 1.35,
        child: child ?? const SizedBox.shrink(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final AsyncValue<void> bootstrap = ref.watch(supabaseBootstrapProvider);
    final ThemeData theme = ref.watch(darkThemeProvider);

    if (bootstrap.isLoading) {
      return MaterialApp(
        title: 'PORTIX',
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: settings.locale,
        supportedLocales: _locales,
        localizationsDelegates: _delegates,
        builder: (BuildContext context, Widget? child) => _withTextScale(child),
        home: const SplashPage(),
      );
    }

    if (bootstrap.hasError) {
      return MaterialApp(
        title: 'PORTIX',
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: settings.locale,
        supportedLocales: _locales,
        localizationsDelegates: _delegates,
        builder: (BuildContext context, Widget? child) => _withTextScale(child),
        home: BootstrapErrorPage(
          error: bootstrap.error ?? const AppFailure(FailureKind.unknown),
        ),
      );
    }

    return MaterialApp.router(
      title: 'PORTIX',
      debugShowCheckedModeBanner: false,
      theme: theme,
      themeAnimationDuration: const Duration(milliseconds: 240),
      locale: settings.locale,
      supportedLocales: _locales,
      localizationsDelegates: _delegates,
      builder: (BuildContext context, Widget? child) => _withTextScale(child),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
