import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  // `GlobalMaterialLocalizations.delegates` já reúne Material, Widgets e
  // Cupertino, então um único delegate cobre os três.
  static const List<LocalizationsDelegate<dynamic>> _delegates =
      GlobalMaterialLocalizations.delegates;

  static const List<Locale> _locales = <Locale>[Locale('pt', 'BR'), Locale('en')];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final AsyncValue<void> bootstrap = ref.watch(supabaseBootstrapProvider);
    final ThemeData light = ref.watch(lightThemeProvider);
    final ThemeData dark = ref.watch(darkThemeProvider);

    if (bootstrap.isLoading) {
      return MaterialApp(
        title: 'PORTIX',
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: settings.themeMode,
        locale: settings.locale,
        supportedLocales: _locales,
        localizationsDelegates: _delegates,
        home: const SplashPage(),
      );
    }

    if (bootstrap.hasError) {
      return MaterialApp(
        title: 'PORTIX',
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: settings.themeMode,
        locale: settings.locale,
        supportedLocales: _locales,
        localizationsDelegates: _delegates,
        home: BootstrapErrorPage(
          error: bootstrap.error ?? const AppFailure(FailureKind.unknown),
        ),
      );
    }

    return MaterialApp.router(
      title: 'PORTIX',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: settings.themeMode,
      themeAnimationDuration: const Duration(milliseconds: 260),
      locale: settings.locale,
      supportedLocales: _locales,
      localizationsDelegates: _delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
