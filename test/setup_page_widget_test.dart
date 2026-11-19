import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:portix/app/theme.dart';
import 'package:portix/core/providers.dart';
import 'package:portix/features/install/permissions.dart';
import 'package:portix/features/install/shizuku.dart';
import 'package:portix/features/setup/setup_page.dart';
import 'package:portix/features/setup/setup_steps.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// SetupPage como widget completo (rota /setup real com go_router):
// - varredura de overflow em 375/768/1440 com textScale 2.0 em TODAS as
//   etapas (mesma técnica de test/ui/ui_test_helpers.dart, com os tamanhos
//   exigidos pela tarefa);
// - modo revisão não grava nada;
// - "Agora não" grava setup.version e vai para /home;
// - etapa de permissão avança sozinha quando o snapshot muda para granted
//   (o canal portix/permissions devolve um novo snapshot e a rechecagem
//   revalida o permissionsProvider — como no AppLifecycleListener.onResume).
//
// Plataforma: android de verdade (canal mockado) — é o caminho de produção,
// com snapshot vindo de portix/permissions e não do fallback desktop.
// ============================================================================

const String kHomeProbe = 'PORTIX_HOME';

/// Snapshot controlado pelo teste — a resposta do canal portix/permissions.
class _Snapshot {
  bool canInstallApps = false;
  bool notificationsGranted = false;
  String shizuku = 'installedStopped';
  int sdkInt = 35;

  Map<String, Object?> toMap() => <String, Object?>{
    'canInstallApps': canInstallApps,
    'notificationsGranted': notificationsGranted,
    'shizuku': shizuku,
    'sdkInt': sdkInt,
    'freeBytes': 1 << 30,
  };
}

void _clearInstallChannels() {
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final MethodChannel channel in <MethodChannel>[
    const MethodChannel('portix/permissions'),
    const MethodChannel('portix/shizuku'),
    const MethodChannel('portix/shizuku/events'),
  ]) {
    messenger.setMockMethodCallHandler(channel, null);
  }
}

/// Infla o app real com a rota /setup e os canais de permissão mockados.
Future<(_Snapshot, ProviderContainer)> _pumpSetup(
  WidgetTester tester, {
  Map<String, Object> prefsSeed = const <String, Object>{},
  String initialLocation = '/setup',
  Size size = const Size(375, 812),
  double textScale = 1.0,
  _Snapshot? snapshot,
}) async {
  SharedPreferences.setMockInitialValues(prefsSeed);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);

  final _Snapshot snap = snapshot ?? _Snapshot();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('portix/permissions'),
    (MethodCall call) async {
      if (call.method == 'snapshot') {
        return snap.toMap();
      }
      return null; // openInstallAppsSettings / requestNotifications
    },
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('portix/shizuku'),
    (MethodCall call) async {
      if (call.method == 'status') {
        return snap.shizuku;
      }
      return null; // requestPermission / openShizuku
    },
  );
  // EventChannel do Shizuku: o ShizukuStatusNotifier assina no build.
  messenger.setMockMethodCallHandler(
    const MethodChannel('portix/shizuku/events'),
    (MethodCall call) async => null,
  );
  addTearDown(_clearInstallChannels);

  final GoRouter router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/setup',
        builder: (BuildContext context, GoRouterState state) => SetupPage(
          review: state.uri.queryParameters['review'] == '1',
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (BuildContext context, GoRouterState state) => const Scaffold(
          body: Center(child: Text(kHomeProbe)),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark(),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const <Locale>[Locale('pt', 'BR'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (snap, container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  });

  tearDown(() async {
    _clearInstallChannels();
    // Reseta o singleton do Shizuku (a tela pode ter mutado via refresh):
    // com plataforma fora do Android, refresh() devolve notInstalled.
    debugDefaultTargetPlatformOverride = null;
    await ShizukuService.instance.refresh();
  });

  group('varredura de overflow', () {
    testWidgets(
      '375 / 768 / 1440 com textScale 2.0: nenhuma etapa estoura layout',
      (WidgetTester tester) async {
        const List<Size> sizes = <Size>[
          Size(375, 812),
          Size(768, 1024),
          Size(1440, 900),
        ];
        // doneSteps que levam a página a CADA etapa do stepper (6 etapas).
        const List<List<String>> seeds = <List<String>>[
          <String>[],
          <String>['welcome'],
          <String>['welcome', 'installApps'],
          <String>['welcome', 'installApps', 'notifications'],
          <String>['welcome', 'installApps', 'notifications', 'shizuku'],
          <String>[
            'welcome',
            'installApps',
            'notifications',
            'shizuku',
            'installer',
          ],
        ];

        final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
        final List<String> combos = <String>[];
        final FlutterExceptionHandler? previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) => errors.add(details);
        try {
          final _Snapshot snap = _Snapshot();
          for (final List<String> seed in seeds) {
            for (final Size size in sizes) {
              final int before = errors.length;
              combos.add('seed=${seed.join('/')} size=${size.width}');
              await _pumpSetup(
                tester,
                prefsSeed: <String, Object>{'setup.doneSteps': seed},
                size: size,
                textScale: 2.0,
                snapshot: snap,
              );
              await tester.pumpAndSettle();
              if (errors.length > before) {
                // Diagnóstico: Rows suspeitas na combinação que falhou.
                for (final FlutterErrorDetails e in errors.skip(before)) {
                  // ignore: avoid_print
                  debugPrint('OVERFLOW NA COMBO: ${combos.last}');
                  // ignore: avoid_print
                  debugPrint(
                    'DETALHE: ${e.exception.toString().split("\n").take(6).join(" | ")}',
                  );
                }
              }
            }
          }
        } finally {
          FlutterError.onError = previous;
        }

        final List<String> overflows = errors
            .map((FlutterErrorDetails e) => e.exception.toString())
            .where(
              (String message) =>
                  message.contains('RenderFlex') || message.contains('overflowed'),
            )
            .toList();
        expect(
          overflows,
          isEmpty,
          reason: 'Overflow em alguma combinação de 375/768/1440 × textScale 2.0',
        );
      },
    );
  });

  group('modo revisão', () {
    testWidgets('não grava setup.version nem setup.doneSteps; sai por /home', (
      WidgetTester tester,
    ) async {
      final (_, ProviderContainer container) = await _pumpSetup(
        tester,
        initialLocation: '/setup?review=1',
      );

      // Botão de sair vira "Fechar".
      expect(find.text('Fechar'), findsOneWidget);
      expect(find.text('Agora não'), findsNothing);

      // Avança uma etapa: em revisão o progresso NÃO é persistido.
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();
      expect(find.text('Permitir instalar apps'), findsOneWidget);

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();

      expect(find.text(kHomeProbe), findsOneWidget);
      final SharedPreferences prefs = container.read(sharedPreferencesProvider);
      expect(prefs.get(kSetupVersionKey), isNull);
      expect(prefs.getStringList(kSetupDoneStepsKey), isNull);
    });
  });

  group('"Agora não"', () {
    testWidgets('grava setup.version e vai para /home substituindo a rota', (
      WidgetTester tester,
    ) async {
      final (_, ProviderContainer container) = await _pumpSetup(tester);

      await tester.tap(find.text('Agora não'));
      await tester.pumpAndSettle();

      expect(find.text(kHomeProbe), findsOneWidget);
      expect(find.text('Configuração inicial'), findsNothing);
      final SharedPreferences prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getInt(kSetupVersionKey), 1);
      expect(prefs.get(kSetupVersionKey), isNotNull);
    });
  });

  group('rechec de permissão avança sozinha', () {
    testWidgets(
      'snapshot muda para granted → etapa de instalar apps marca e avança',
      (WidgetTester tester) async {
        final _Snapshot snap = _Snapshot(); // canInstallApps=false
        final (_, ProviderContainer container) = await _pumpSetup(
          tester,
          // Processo morto retomado: welcome já concluído.
          prefsSeed: <String, Object>{
            'setup.doneSteps': <String>['welcome'],
          },
          snapshot: snap,
        );

        // Está na etapa "Instalar apps desconhecidos" (botão de concessão).
        expect(find.text('Permitir instalar apps'), findsOneWidget);
        expect(find.text('Não concedido'), findsOneWidget);

        // Usuário concede lá fora e volta: o refresh revalida o snapshot
        // (mesmo caminho do AppLifecycleListener.onResume).
        snap.canInstallApps = true;
        await container.read(permissionsProvider.notifier).refresh();
        await tester.pumpAndSettle();

        // Avançou SOZINHO para Notificações e gravou o progresso.
        expect(find.text('Permitir notificações'), findsOneWidget);
        expect(find.text('Permitir instalar apps'), findsNothing);
        final SharedPreferences prefs = container.read(sharedPreferencesProvider);
        expect(prefs.getStringList(kSetupDoneStepsKey), contains('installApps'));
      },
    );

    testWidgets(
      'sem mudança de permissão a etapa NÃO avança sozinha',
      (WidgetTester tester) async {
        final _Snapshot snap = _Snapshot();
        final (_, ProviderContainer container) = await _pumpSetup(
          tester,
          prefsSeed: <String, Object>{
            'setup.doneSteps': <String>['welcome'],
          },
          snapshot: snap,
        );

        await container.read(permissionsProvider.notifier).refresh();
        await tester.pumpAndSettle();

        expect(find.text('Permitir instalar apps'), findsOneWidget);
        final SharedPreferences prefs = container.read(sharedPreferencesProvider);
        expect(prefs.getStringList(kSetupDoneStepsKey), <String>['welcome']);
      },
    );
  });
}
