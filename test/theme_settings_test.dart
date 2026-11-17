import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:portix/app/settings.dart';
import 'package:portix/app/theme.dart';
import 'package:portix/core/providers.dart';
import 'package:portix/core/theme/tokens.dart';
import 'package:portix/core/theme/themes.dart';
import 'package:portix/shared/widgets/theme_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// Sistema de temas: persistência, aplicação no primeiro frame (sem flash) e
// troca instantânea pelo seletor.
// ============================================================================

/// MaterialApp que resolve o tema pelos settings — mesmo caminho do PortixApp.
class _ThemeHost extends ConsumerWidget {
  const _ThemeHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String themeId = ref.watch(
      settingsProvider.select((AppSettings s) => s.themeId),
    );
    final AppThemePair pair = appThemePairFor(themeId);
    return MaterialApp(
      theme: AppTheme.build(pair.light),
      darkTheme: AppTheme.build(pair.dark),
      themeMode: themeModeFor(themeId),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const <Locale>[Locale('pt', 'BR'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const Scaffold(body: ThemeSelector()),
    );
  }
}

Future<ProviderContainer> _container({
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final SharedPreferences instance = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(instance)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('persistência do tema', () {
    test(
      'setThemeId grava no SharedPreferences e sobrevive ao reinício',
      () async {
        final ProviderContainer container = await _container();
        addTearDown(container.dispose);

        expect(container.read(settingsProvider).themeId, kThemeDark);
        container.read(settingsProvider.notifier).setThemeId(kThemeOcean);

        final SharedPreferences prefs = container.read(
          sharedPreferencesProvider,
        );
        expect(prefs.getString('settings.themeId'), kThemeOcean);

        // Reinício: o armazenamento persiste e um novo boot lê o valor salvo.
        final ProviderContainer restarted = await _container(
          prefs: <String, Object>{
            'settings.themeId': prefs.getString('settings.themeId')!,
          },
        );
        addTearDown(restarted.dispose);
        expect(restarted.read(settingsProvider).themeId, kThemeOcean);
      },
    );

    test('id inválido cai no tema padrão (escuro Aurora)', () async {
      final ProviderContainer container = await _container(
        prefs: <String, Object>{'settings.themeId': 'hack'},
      );
      addTearDown(container.dispose);
      expect(container.read(settingsProvider).themeId, kThemeDark);
      expect(appThemePairFor('hack').dark, auroraDark);
    });
  });

  group('aplicação sem flash', () {
    testWidgets('primeiro frame já usa a paleta persistida', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await _container(
        prefs: <String, Object>{'settings.themeId': kThemeOcean},
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _ThemeHost(),
        ),
      );
      await tester.pump();

      final BuildContext ctx = tester.element(find.byType(Scaffold));
      final AppColorsTheme colors = Theme.of(ctx).extension<AppColorsTheme>()!;
      expect(colors.bg, oceano.bg);
      expect(Theme.of(ctx).scaffoldBackgroundColor, oceano.bg);
    });
  });

  group('seletor de temas', () {
    testWidgets('toque em Oceano troca o ThemeData imediatamente', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _ThemeHost(),
        ),
      );
      await tester.pump();

      final BuildContext ctx = tester.element(find.byType(Scaffold));
      expect(Theme.of(ctx).extension<AppColorsTheme>()!.bg, auroraDark.bg);

      await tester.tap(find.text('Oceano'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).themeId, kThemeOcean);
      final BuildContext after = tester.element(find.byType(Scaffold));
      expect(Theme.of(after).extension<AppColorsTheme>()!.bg, oceano.bg);
    });

    testWidgets(
      'card selecionado expõe Semantics selected e todos os temas têm botão',
      (WidgetTester tester) async {
        final ProviderContainer container = await _container();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const _ThemeHost(),
          ),
        );
        await tester.pumpAndSettle();

        // 6 opções: Sistema, Claro, Escuro, Midnight, Oceano, Floresta.
        final List<String> names = <String>[
          'Sistema',
          'Claro',
          'Escuro',
          'Midnight',
          'Oceano',
          'Floresta',
        ];
        for (final String name in names) {
          expect(find.text(name), findsOneWidget, reason: 'tema $name visível');
        }
        // Botões semânticos com estado selecionado.
        final Finder options = find.ancestor(
          of: find.text('Escuro'),
          matching: find.byWidgetPredicate(
            (Widget w) => w is Semantics && w.properties.selected != null,
          ),
        );
        expect(options, findsWidgets);
      },
    );
  });
}
