import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/core/apk_tools.dart';
import 'package:portix/core/providers.dart';
import 'package:portix/features/downloads/downloads_controller.dart';
import 'package:portix/features/install/install_flow.dart';
import 'package:portix/features/install/models.dart';
import 'package:portix/features/install/native_installer.dart';
import 'package:portix/features/install/shizuku.dart';
import 'package:portix/models/download_task.dart';
import 'package:portix/models/game.dart';
import 'package:portix/models/game_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// Fluxo "Baixar → instalar" sem device: o nativo é simulado com
// setMockMethodCallHandler nos canais portix/permissions, portix/install,
// portix/install/events, portix/shizuku e portix/apk; o download usa um
// DownloadsController de gravação (nada de motor real, nada de sleep).
//
// Os eventos nativos chegam pelo MESMO caminho de produção: o handler do
// canal de eventos é mockado para o 'listen' e cada evento é entregue via
// handlePlatformMessage (envelope de sucesso do codec do EventChannel) —
// exatamente como o Kotlin posta no EventSink.
//
// Plataforma: debugDefaultTargetPlatformOverride = android faz os módulos de
// instalação falarem com os canais (fallback simulado é cobrido pelos outros
// testes do repo). Reseta em tearDown junto com os handlers.
// ============================================================================

const String kGameId = 'g1';
const String kLabel = 'Spore';
const String kPkg = 'com.example.game';
const String kDigest = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const String kUrl =
    'https://github.com/owner/repo/releases/download/v1/game.apk';

const Game kGame = Game(
  id: kGameId,
  slug: 'spore',
  title: 'Spore',
  genre: 'Sandbox',
  platforms: <String>['Android'], // coverUrl nulo: prepare não busca ícone
);

/// Snapshot de permissões controlado pelo teste (respostas do canal
/// portix/permissions e dos demais métodos simulados).
class _Nativo {
  bool canInstallApps = true;
  bool notificationsGranted = true;
  ShizukuStatus shizuku = ShizukuStatus.notInstalled;
  int sdkInt = 34;

  /// Resposta de portix/install freeBytes (2 GiB por padrão).
  int freeBytes = 2 * 1024 * 1024 * 1024;

  /// Resposta de portix/install prepare (sessão criada).
  bool prepareOk = true;

  /// Resposta de portix/install sha256 (null = fail-closed do canal).
  String? sha256;

  /// Resposta de portix/apk inspect (leitura do APK baixado).
  Map<String, Object?>? inspect;

  /// Resposta de portix/apk installed (app já instalado).
  Map<String, Object?>? installed;

  Map<String, Object?> get snapshotMap => <String, Object?>{
    'canInstallApps': canInstallApps,
    'notificationsGranted': notificationsGranted,
    'shizuku': shizuku.name,
    'sdkInt': sdkInt,
    'freeBytes': freeBytes,
  };
}

class _Call {
  const _Call(this.channel, this.method, this.arguments);
  final String channel;
  final String method;
  final Object? arguments;

  Object? arg(String name) => (arguments as Map?)?[name];
}

/// DownloadsController de gravação: registra start/cancel e permite ao teste
/// mover a tarefa (downloading → done/failed) como o motor real faria.
class RecordingDownloads extends DownloadsController {
  List<DownloadTask> tasks = <DownloadTask>[];
  final List<String> startedUrls = <String>[];
  final List<String> cancelledIds = <String>[];

  @override
  List<DownloadTask> build() => tasks;

  void _replace(List<DownloadTask> next) {
    tasks = next;
    state = next;
  }

  @override
  void start(
    Game game, {
    GamePort? port,
    String? urlOverride,
    String? releaseTag,
    bool restart = false,
  }) {
    startedUrls.add(urlOverride ?? '');
    _replace(<DownloadTask>[
      DownloadTask(
        gameId: game.id,
        title: game.title,
        slug: game.slug,
        portUrl: urlOverride,
        releaseTag: releaseTag,
        status: DownloadStatus.downloading,
        progress: 0.05,
        startedAt: DateTime.now(),
      ),
      ...tasks.where((DownloadTask t) => t.gameId != game.id),
    ]);
  }

  @override
  void cancel(String gameId) {
    cancelledIds.add(gameId);
    _replace(tasks.where((DownloadTask t) => t.gameId != gameId).toList());
  }

  /// Download concluído (como o evento nativo faria).
  void finishWithApk(String gameId, {required String path}) {
    _apply(
      gameId,
      (DownloadTask t) => t.copyWith(
        status: DownloadStatus.done,
        progress: 1,
        apkPath: path,
        packageName: kPkg,
        versionCode: 5,
      ),
    );
  }

  void failDownload(String gameId, [String error = 'network']) {
    _apply(
      gameId,
      (DownloadTask t) =>
          t.copyWith(status: DownloadStatus.failed, error: error),
    );
  }

  void _apply(String gameId, DownloadTask Function(DownloadTask) transform) {
    final int index = tasks.indexWhere((DownloadTask t) => t.gameId == gameId);
    if (index < 0) {
      return;
    }
    final List<DownloadTask> next = List<DownloadTask>.of(tasks);
    next[index] = transform(next[index]);
    _replace(next);
  }
}

/// Aparelho simulado: canais mockados + container Riverpod.
class _Harness {
  final _Nativo nativo = _Nativo();
  final List<_Call> installCalls = <_Call>[];
  final List<_Call> permissionCalls = <_Call>[];
  final List<_Call> shizukuCalls = <_Call>[];
  final List<_Call> apkCalls = <_Call>[];
  late final SharedPreferences prefs;
  late final RecordingDownloads downloads;
  late final StreamController<NativeInstallEvent> events;
  late final ProviderContainer container;

  Future<void> init({
    Map<String, Object> prefsSeed = const <String, Object>{},
  }) async {
    // O resolvedor/instalador consultam defaultTargetPlatform: sem este
    // override os testes rodam como desktop e os mocks nunca são chamados.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues(prefsSeed);
    prefs = await SharedPreferences.getInstance();
    downloads = RecordingDownloads();
    // events criado logo abaixo, antes do container;
    _registerChannels();
    events = StreamController<NativeInstallEvent>.broadcast();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        downloadsProvider.overrideWith(() => downloads),
        installEventsProvider.overrideWithValue(events.stream),
      ],
    );
    // Constrói o InstallFlowController: assina portix/install/events e roda
    // a limpeza de sessões órfãs (mesma inicialização do app).
    container.read(installFlowProvider);
    await settle();
  }

  Future<void> tearDown() async {
    container.dispose();
    await events.close();
    debugDefaultTargetPlatformOverride = null;
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final MethodChannel channel in <MethodChannel>[
      const MethodChannel('portix/install'),
      const MethodChannel('portix/permissions'),
      const MethodChannel('portix/shizuku'),
      const MethodChannel('portix/apk'),
      const MethodChannel('portix/install/events'),
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    // Reseta o singleton do Shizuku (estado pode ter sido mutado no teste).
    await ShizukuService.instance.refresh();
  }

  void _registerChannels() {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(const MethodChannel('portix/install'), (
      MethodCall call,
    ) async {
      installCalls.add(_Call('portix/install', call.method, call.arguments));
      switch (call.method) {
        case 'freeBytes':
          return nativo.freeBytes;
        case 'sha256':
          return nativo.sha256;
        case 'prepare':
          return nativo.prepareOk;
        default:
          return null; // commitPrepared/commitFresh/abandon/cancelPrepare/cleanup
      }
    });

    messenger.setMockMethodCallHandler(
      const MethodChannel('portix/permissions'),
      (MethodCall call) async {
        permissionCalls.add(
          _Call('portix/permissions', call.method, call.arguments),
        );
        if (call.method == 'snapshot') {
          return nativo.snapshotMap;
        }
        return null; // openInstallAppsSettings / requestNotifications
      },
    );

    messenger.setMockMethodCallHandler(const MethodChannel('portix/shizuku'), (
      MethodCall call,
    ) async {
      shizukuCalls.add(_Call('portix/shizuku', call.method, call.arguments));
      if (call.method == 'status') {
        return nativo.shizuku.name;
      }
      return null; // requestPermission / openShizuku / install
    });

    messenger.setMockMethodCallHandler(const MethodChannel('portix/apk'), (
      MethodCall call,
    ) async {
      apkCalls.add(_Call('portix/apk', call.method, call.arguments));
      if (call.method == 'inspect') {
        return nativo.inspect;
      }
      if (call.method == 'installed') {
        return nativo.installed;
      }
      return false;
    });

    // EventChannel: o 'listen' do receiveBroadcastStream precisa responder
    // (sem handler o stream não registra o listener de eventos).
    messenger.setMockMethodCallHandler(
      const MethodChannel('portix/install/events'),
      (MethodCall call) async => null,
    );
  }

  // ------------------------------------------------------------ utilidades

  Future<void> settle() async {
    // Drena os microtasks em cascata (canal → reducer). Microtasks correm no
    // fake-async do testWidgets; Future.delayed NÃO (timer nunca dispara sem
    // pump) — era a causa do 'did not complete'.
    for (int i = 0; i < 12; i++) {
      await Future<void>.microtask(() {});
    }
  }

  /// Entrega um evento do instalador nativo direto no stream sobreposto
  /// (o mesmo contrato do canal, sem o plumbing de plataforma).
  Future<void> pushInstallEvent(Map<String, Object?> event) async {
    events.add(
      NativeInstallEvent.fromMap(<Object?, Object?>{
        'type': event['type'],
        'key': event['key'],
        'sessionId': event['sessionId'],
        'error': event['error'],
      }),
    );
    await settle();
  }

  List<_Call> calls(String channel, String method) => <_Call>[
    ...installCalls,
    ...permissionCalls,
    ...shizukuCalls,
    ...apkCalls,
  ].where((_Call c) => c.channel == channel && c.method == method).toList();

  List<_Call> get prepares => calls('portix/install', 'prepare');
  List<_Call> get abandons => calls('portix/install', 'abandon');

  FlowState flow([String gameId = kGameId]) =>
      container.read(installFlowForGameProvider(gameId));

  InstallPhase get phase => flow().phase;

  Future<void> begin({String? url = kUrl, String? digest, int sizeBytes = 0}) =>
      container
          .read(installFlowProvider.notifier)
          .begin(
            kGame,
            null,
            url: url ?? '',
            digest: digest,
            sizeBytes: sizeBytes,
          );

  /// Alinha o singleton do Shizuku com o valor do teste (o resolvedor lê
  /// `ShizukuService.instance.current` sincronamente).
  Future<void> syncShizuku() => ShizukuService.instance.refresh();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  });

  // ---------------------------------------------------------------- reducer
  group('installFlowReducer (puro)', () {
    const AndroidPlan preapproval = AndroidPlan(
      needsInstallPermission: false,
      usePreapproval: true,
      expectedPackage: kPkg,
    );

    test(
      'FlowBegin: Shizuku bloqueado → fase blocked + oferta de fallback',
      () {
        final FlowState next = installFlowReducer(
          const FlowState.idle(),
          const FlowBegin(
            ShizukuPlan(
              blocker: ShizukuStatus.installedStopped,
              expectedPackage: kPkg,
            ),
          ),
        );
        expect(next.phase, InstallPhase.blocked);
        expect(next.offerAndroidFallback, isTrue);
        expect(next.plan, isA<ShizukuPlan>());
      },
    );

    test('FlowBegin: falta permissão → needsInstallPermission', () {
      final FlowState next = installFlowReducer(
        const FlowState.idle(),
        const FlowBegin(
          AndroidPlan(needsInstallPermission: true, usePreapproval: false),
        ),
      );
      expect(next.phase, InstallPhase.needsInstallPermission);
      expect(next.isBusy, isFalse);
    });

    test('FlowBegin: pré-aprovação → awaitingPreapproval (busy)', () {
      final FlowState next = installFlowReducer(
        const FlowState.idle(),
        const FlowBegin(preapproval),
      );
      expect(next.phase, InstallPhase.awaitingPreapproval);
      expect(next.isBusy, isTrue);
    });

    test('FlowBegin: Android clássico e Shizuku ativo → downloading', () {
      expect(
        installFlowReducer(
          const FlowState.idle(),
          const FlowBegin(
            AndroidPlan(needsInstallPermission: false, usePreapproval: false),
          ),
        ).phase,
        InstallPhase.downloading,
      );
      expect(
        installFlowReducer(
          const FlowState.idle(),
          const FlowBegin(ShizukuPlan(expectedPackage: kPkg)),
        ).phase,
        InstallPhase.downloading,
      );
    });

    test('FlowPreapproval: prepared grava sessionId sem mudar fase', () {
      final FlowState state = installFlowReducer(
        const FlowState(
          phase: InstallPhase.awaitingPreapproval,
          plan: preapproval,
        ),
        const FlowPreapproval('prepared', sessionId: 42),
      );
      expect(state.phase, InstallPhase.awaitingPreapproval);
      expect(state.sessionId, 42);
      // 'pending' não muda nada.
      expect(
        installFlowReducer(state, const FlowPreapproval('pending')).sessionId,
        42,
      );
    });

    test('FlowPreapproval: approved → downloading; declined → idle', () {
      const FlowState state = FlowState(
        phase: InstallPhase.awaitingPreapproval,
        plan: preapproval,
        sessionId: 42,
      );
      expect(
        installFlowReducer(state, const FlowPreapproval('approved')).phase,
        InstallPhase.downloading,
      );
      final FlowState declined = installFlowReducer(
        state,
        const FlowPreapproval('declined'),
      );
      expect(declined.phase, InstallPhase.idle);
      expect(declined.plan, isNull);
    });

    test('FlowPreapproval: falha → failed com erro preservado', () {
      final FlowState next = installFlowReducer(
        const FlowState(
          phase: InstallPhase.awaitingPreapproval,
          plan: preapproval,
        ),
        const FlowPreapproval('preapprovalFailed', error: 'boom'),
      );
      expect(next.phase, InstallPhase.failed);
      expect(next.error, 'boom');
    });

    test('FlowDownloadDone → verifying (limpa erro)', () {
      const FlowState state = FlowState(
        phase: InstallPhase.downloading,
        plan: preapproval,
        error: 'antigo',
      );
      final FlowState next = installFlowReducer(
        state,
        const FlowDownloadDone(),
      );
      expect(next.phase, InstallPhase.verifying);
      expect(next.error, isNull);
    });

    test('FlowDownloadFailed → failed com plano e erro', () {
      const FlowState state = FlowState(
        phase: InstallPhase.downloading,
        plan: preapproval,
      );
      final FlowState next = installFlowReducer(
        state,
        const FlowDownloadFailed('socket'),
      );
      expect(next.phase, InstallPhase.failed);
      expect(next.error, 'socket');
      expect(next.plan, preapproval);
      expect(
        installFlowReducer(state, const FlowDownloadFailed(null)).error,
        'download-failed',
      );
    });

    test(
      'FlowVerified: pass → installing; divergente → failed com veredito',
      () {
        const FlowState state = FlowState(
          phase: InstallPhase.verifying,
          plan: preapproval,
        );
        expect(
          installFlowReducer(
            state,
            const FlowVerified(IntegrityVerdict.pass),
          ).phase,
          InstallPhase.installing,
        );
        final FlowState bad = installFlowReducer(
          state,
          const FlowVerified(IntegrityVerdict.digestMismatch),
        );
        expect(bad.phase, InstallPhase.failed);
        expect(bad.verdict, IntegrityVerdict.digestMismatch);
        expect(bad.plan, preapproval);
      },
    );

    test(
      'FlowInstallFinished: ok → installed; falha preserva offerFallback',
      () {
        const FlowState state = FlowState(
          phase: InstallPhase.installing,
          plan: preapproval,
        );
        expect(
          installFlowReducer(state, const FlowInstallFinished(true)).phase,
          InstallPhase.installed,
        );
        final FlowState failed = installFlowReducer(
          state,
          const FlowInstallFinished(
            false,
            error: 'shizuku-unavailable',
            offerFallback: true,
          ),
        );
        expect(failed.phase, InstallPhase.failed);
        expect(failed.error, 'shizuku-unavailable');
        expect(failed.offerAndroidFallback, isTrue);
        expect(failed.plan, preapproval);
      },
    );

    test('FlowCancelled e FlowReset → idle completo', () {
      const FlowState state = FlowState(
        phase: InstallPhase.installing,
        plan: preapproval,
        sessionId: 9,
        error: 'x',
      );
      for (final FlowEvent event in const <FlowEvent>[
        FlowCancelled(),
        FlowReset(),
      ]) {
        final FlowState next = installFlowReducer(state, event);
        expect(next.phase, InstallPhase.idle);
        expect(next.sessionId, isNull);
        expect(next.error, isNull);
      }
    });

    test('FlowPermissionResolved: granted re-começa; denied → failed', () {
      final FlowState granted = installFlowReducer(
        const FlowState(
          phase: InstallPhase.needsInstallPermission,
          plan: preapproval,
        ),
        const FlowPermissionResolved(preapproval, true),
      );
      expect(granted.phase, InstallPhase.awaitingPreapproval);
      final FlowState denied = installFlowReducer(
        const FlowState(
          phase: InstallPhase.needsInstallPermission,
          plan: preapproval,
        ),
        const FlowPermissionResolved(preapproval, false),
      );
      expect(denied.phase, InstallPhase.failed);
      expect(denied.error, 'permission-required');
    });

    test(
      'shouldClearRequest: falha terminal libera retry; fallback/bloqueio preservam',
      () {
        expect(
          shouldClearRequest(
            const FlowState(phase: InstallPhase.failed, error: 'x'),
          ),
          isTrue,
        );
        expect(
          shouldClearRequest(
            const FlowState(
              phase: InstallPhase.failed,
              offerAndroidFallback: true,
            ),
          ),
          isFalse,
        );
        expect(
          shouldClearRequest(
            const FlowState(
              phase: InstallPhase.blocked,
              offerAndroidFallback: true,
            ),
          ),
          isFalse,
        );
      },
    );
  });

  // ------------------------------------------------------------- controller
  group('InstallFlowController (canais simulados)', () {
    late _Harness h;

    setUp(() {
      h = _Harness();
    });
    tearDown(() => h.tearDown());

    Directory? tmpDir;
    File apk() {
      final Directory dir = Directory.systemTemp.createTempSync(
        'portix_flow_test',
      );
      tmpDir = dir;
      return File('${dir.path}${Platform.pathSeparator}portix-$kGameId.apk')
        ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    }

    tearDown(() {
      try {
        tmpDir?.deleteSync(recursive: true);
      } on Object {
        // best-effort
      }
    });

    testWidgets(
      '(a) pré-aprovação aprovada: awaitingPreapproval→downloading→verifying→'
      'installing→installed, APK apagado e pacote memorizado',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
              'other/port': 'com.other',
            }),
          },
        );
        h.nativo.sha256 = kDigest;
        h.nativo.inspect = <String, Object?>{
          'packageName': kPkg,
          'versionCode': 5,
        };
        h.nativo.installed = <String, Object?>{
          'packageName': kPkg,
          'versionCode': 5,
        };
        final File file = apk();

        final List<InstallPhase> fases = <InstallPhase>[];
        await h.begin(digest: kDigest, sizeBytes: 50 * 1024 * 1024);
        fases.add(h.phase);
        expect(h.prepares, hasLength(1));
        expect(h.prepares.single.arg('packageName'), kPkg);
        expect(h.prepares.single.arg('attemptId'), 0);
        expect(
          h.downloads.startedUrls,
          isEmpty,
        ); // nada baixado antes da aprovação

        await h.pushInstallEvent(<String, Object?>{
          'type': 'prepared',
          'key': kGameId,
          'sessionId': 42,
        });
        fases.add(h.phase);
        expect(h.flow().sessionId, 42);

        await h.pushInstallEvent(<String, Object?>{
          'type': 'preapprovalApproved',
          'key': kGameId,
        });
        fases.add(h.phase);
        await h.settle();
        expect(h.downloads.startedUrls, <String>[
          kUrl,
        ]); // download único, pós-aprovação

        h.downloads.finishWithApk(kGameId, path: file.path);
        // O dispatch do download é síncrono: verifying é observável aqui.
        expect(h.phase, InstallPhase.verifying);
        fases.add(h.phase);
        await h.settle();
        fases.add(h.phase);
        expect(h.flow().verdict, IntegrityVerdict.pass);

        await h.pushInstallEvent(<String, Object?>{
          'type': 'installDone',
          'key': kGameId,
        });
        fases.add(h.phase);

        expect(fases, <InstallPhase>[
          InstallPhase.awaitingPreapproval,
          InstallPhase.awaitingPreapproval,
          InstallPhase.downloading,
          InstallPhase.verifying,
          InstallPhase.installing,
          InstallPhase.installed,
        ]);
        // commitPrepared usa a SESSÃO pré-aprovada (não commitFresh).
        final List<_Call> commits = h.calls('portix/install', 'commitPrepared');
        expect(commits, hasLength(1));
        expect(commits.single.arg('sessionId'), 42);
        expect(commits.single.arg('path'), file.path);
        expect(h.calls('portix/install', 'commitFresh'), isEmpty);
        // APK confirmado → apagado do armazenamento privado.
        expect(
          file.existsSync(),
          isFalse,
          reason: 'APK deve ser apagado pós-instalação',
        );
        // Cache de pacote: merge preservou a entrada de OUTRO port.
        final Map<Object?, Object?> cache =
            jsonDecode(h.prefs.getString('install.packages')!)
                as Map<Object?, Object?>;
        final Map<Object?, Object?> entry =
            cache['owner/repo'] as Map<Object?, Object?>;
        expect(entry['p'], kPkg);
        expect(entry['l'], kLabel);
        final Map<Object?, Object?> other =
            cache['other/port'] as Map<Object?, Object?>;
        expect(other['p'], 'com.other');
      },
    );

    testWidgets(
      '(b) pré-aprovação RECUSADA: nenhum download iniciado e fase volta a idle',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
            }),
          },
        );

        await h.begin();
        expect(h.phase, InstallPhase.awaitingPreapproval);

        await h.pushInstallEvent(<String, Object?>{
          'type': 'prepared',
          'key': kGameId,
          'sessionId': 42,
        });
        await h.pushInstallEvent(<String, Object?>{
          'type': 'preapprovalDeclined',
          'key': kGameId,
        });

        expect(h.phase, InstallPhase.idle);
        expect(h.container.read(installFlowProvider), isNot(contains(kGameId)));
        expect(
          h.downloads.startedUrls,
          isEmpty,
          reason:
              'recusa ANTES do download: portix/downloader start não pode '
              'ter sido invocado',
        );
      },
    );

    testWidgets(
      '(c) download falha → failed; retry recomeça o download (guarda não engole)',
      (WidgetTester tester) async {
        await h.init(); // sem pacote conhecido → downloading direto

        await h.begin();
        expect(h.phase, InstallPhase.downloading);
        expect(h.downloads.startedUrls, hasLength(1));

        h.downloads.failDownload(kGameId, 'network');
        await h.settle();
        expect(h.phase, InstallPhase.failed);
        expect(h.flow().error, 'network');

        // Lição 4: a guarda não pode engolir o retry após falha terminal.
        await h.begin();
        expect(h.phase, InstallPhase.downloading);
        expect(h.downloads.startedUrls, hasLength(2));
      },
    );

    testWidgets(
      '(d) digest divergente → failed com erro de integridade e APK apagado',
      (WidgetTester tester) async {
        await h.init();
        final File file = apk();
        h.nativo.sha256 = 'deadbeef'; // != kDigest

        await h.begin(digest: kDigest);
        expect(h.phase, InstallPhase.downloading);
        h.downloads.finishWithApk(kGameId, path: file.path);
        expect(h.phase, InstallPhase.verifying);
        await h.settle();

        expect(h.phase, InstallPhase.failed);
        expect(h.flow().verdict, IntegrityVerdict.digestMismatch);
        expect(
          file.existsSync(),
          isFalse,
          reason: 'APK divergente é descartado',
        );
        expect(h.calls('portix/install', 'commitPrepared'), isEmpty);
        expect(h.calls('portix/install', 'commitFresh'), isEmpty);
        expect(h.downloads.startedUrls, hasLength(1));
      },
    );

    testWidgets(
      '(e) cancelamento: sessão abandonada no canal e tarefa cancelada',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
            }),
          },
        );

        await h.begin();
        await h.pushInstallEvent(<String, Object?>{
          'type': 'prepared',
          'key': kGameId,
          'sessionId': 42,
        });

        await h.container.read(installFlowProvider.notifier).cancel(kGameId);

        expect(h.phase, InstallPhase.idle);
        final List<_Call> abandons = h.abandons;
        expect(abandons, hasLength(1), reason: 'abandon(sessionId) no canal');
        expect(abandons.single.arg('sessionId'), 42);
        expect(h.downloads.cancelledIds, contains(kGameId));
      },
    );

    testWidgets(
      '(f) attemptId antigo: cancelamento invalida callbacks e ids nunca reusa',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
            }),
          },
        );

        // Tentativa 0: cancelada durante o prepare (sem sessionId).
        await h.begin();
        expect(h.prepares.single.arg('attemptId'), 0);
        await h.container.read(installFlowProvider.notifier).cancel(kGameId);
        final List<_Call> cancels = h.calls('portix/install', 'cancelPrepare');
        expect(cancels, hasLength(1));
        expect(cancels.single.arg('attemptId'), 0);
        expect(h.phase, InstallPhase.idle);

        // Callbacks VELHOS chegam depois do cancelamento: não mudam o estado.
        await h.pushInstallEvent(<String, Object?>{
          'type': 'prepared',
          'key': kGameId,
          'sessionId': 99,
        });
        await h.pushInstallEvent(<String, Object?>{
          'type': 'preapprovalApproved',
          'key': kGameId,
        });
        expect(h.phase, InstallPhase.idle);
        expect(h.downloads.startedUrls, isEmpty);

        // Tentativa seguinte usa attemptId monotônico (0 nunca é reutilizado).
        await h.begin();
        expect(h.prepares, hasLength(2));
        expect(h.prepares.last.arg('attemptId'), 1);
        expect(h.phase, InstallPhase.awaitingPreapproval);
      },
    );

    testWidgets('(g) Shizuku preferido sem estar ativo → blocked; '
        '"usar Android desta vez" troca o plano de forma atômica', (
      WidgetTester tester,
    ) async {
      await h.init(
        prefsSeed: <String, Object>{
          'install.installer': 'shizuku',
          'install.packages': jsonEncode(<String, Object?>{
            'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
          }),
        },
      );
      h.nativo.shizuku = ShizukuStatus.installedStopped;
      await h.syncShizuku();

      await h.begin();
      final FlowState blocked = h.flow();
      expect(blocked.phase, InstallPhase.blocked);
      expect(blocked.offerAndroidFallback, isTrue);
      expect(blocked.plan, isA<ShizukuPlan>());
      expect(
        (blocked.plan as ShizukuPlan).blocker,
        ShizukuStatus.installedStopped,
      );
      expect(h.downloads.startedUrls, isEmpty);
      expect(h.prepares, isEmpty);

      // Fallback do sheet: re-resolve com Android mantendo o pacote.
      await h.container
          .read(installFlowProvider.notifier)
          .useAndroidThisTime(kGameId);
      final FlowState fallback = h.flow();
      expect(fallback.plan, isA<AndroidPlan>());
      expect(
        (fallback.plan as AndroidPlan).usePreapproval,
        isTrue,
        reason: 'pacote conhecido + Android 14+: pré-aprovação preservada',
      );
      expect(fallback.phase, InstallPhase.awaitingPreapproval);
      expect(fallback.offerAndroidFallback, isFalse);
      expect(h.prepares, hasLength(1));
    });

    testWidgets(
      'rechec de permissão: volta da tela do sistema concedida avança; '
      'negada falha sem travar',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
            }),
          },
        );
        h.nativo.canInstallApps = false;

        await h.begin();
        expect(h.phase, InstallPhase.needsInstallPermission);
        expect(h.downloads.startedUrls, isEmpty);

        // Usuário negou voltando do sistema.
        await h.container
            .read(installFlowProvider.notifier)
            .onPermissionResume(kGameId);
        expect(h.phase, InstallPhase.failed);
        expect(h.flow().error, 'permission-required');

        // Falha terminal liberou o request: novo toque reabre o fluxo.
        await h.begin();
        expect(h.phase, InstallPhase.needsInstallPermission);

        // Agora concedeu: rechec avança sozinho para a pré-aprovação.
        h.nativo.canInstallApps = true;
        await h.container
            .read(installFlowProvider.notifier)
            .onPermissionResume(kGameId);
        expect(h.phase, InstallPhase.awaitingPreapproval);
        expect(h.prepares, hasLength(1));
        expect(h.downloads.startedUrls, isEmpty); // só baixa após o 'approved'
      },
    );

    testWidgets(
      'Shizuku ativo: instala via canal portix/shizuku e PERMITE downgrade '
      '(D37/D39);rechec no momento da instalação',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.installer': 'shizuku',
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
            }),
          },
        );
        h.nativo.shizuku = ShizukuStatus.active;
        await h.syncShizuku();
        final File file = apk();
        h.nativo.inspect = <String, Object?>{
          'packageName': kPkg,
          'versionCode': 3, // APK mais antiga que a instalada
        };
        h.nativo.installed = <String, Object?>{
          'packageName': kPkg,
          'versionCode': 5,
        };

        await h.begin();
        expect(h.phase, InstallPhase.downloading);
        h.downloads.finishWithApk(kGameId, path: file.path);
        await h.settle();

        // Downgrade não bloqueia no caminho Shizuku (allowDowngrade).
        expect(h.flow().verdict, IntegrityVerdict.pass);
        final List<_Call> installs = h.calls('portix/shizuku', 'install');
        expect(installs, hasLength(1));
        expect(installs.single.arg('key'), kGameId);
        expect(installs.single.arg('path'), file.path);
        expect(installs.single.arg('expectedPackage'), kPkg);
        expect(h.calls('portix/install', 'commitFresh'), isEmpty);

        await h.pushInstallEvent(<String, Object?>{
          'type': 'installDone',
          'key': kGameId,
        });
        expect(h.phase, InstallPhase.installed);
        expect(file.existsSync(), isFalse);
      },
    );

    testWidgets(
      'downgrade com instalador do Android é bloqueado e descarta o APK',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
            }),
          },
        );
        h.nativo.sdkInt = 33; // sem pré-aprovação: downloading direto
        final File file = apk();
        h.nativo.inspect = <String, Object?>{
          'packageName': kPkg,
          'versionCode': 3,
        };
        h.nativo.installed = <String, Object?>{
          'packageName': kPkg,
          'versionCode': 5,
        };

        await h.begin(digest: null);
        h.downloads.finishWithApk(kGameId, path: file.path);
        await h.settle();

        expect(h.phase, InstallPhase.failed);
        expect(h.flow().verdict, IntegrityVerdict.downgradeBlocked);
        expect(file.existsSync(), isFalse);
        expect(h.calls('portix/shizuku', 'install'), isEmpty);
      },
    );

    testWidgets(
      'Shizuku morre entre o download e a instalação → falha clara com fallback '
      'preservado e "usar Android desta vez" funciona',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.installer': 'shizuku',
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
            }),
          },
        );
        h.nativo.shizuku = ShizukuStatus.active;
        await h.syncShizuku();
        final File file = apk();
        h.nativo.inspect = <String, Object?>{
          'packageName': kPkg,
          'versionCode': 5,
        };

        await h.begin();
        expect(h.phase, InstallPhase.downloading);
        h.downloads.finishWithApk(kGameId, path: file.path);

        // O servidor cai ANTES do _runInstall rechecar.
        h.nativo.shizuku = ShizukuStatus.runningNoPermission;
        await h.settle();

        final FlowState failed = h.flow();
        expect(failed.phase, InstallPhase.failed);
        expect(failed.error, 'shizuku-unavailable');
        expect(failed.offerAndroidFallback, isTrue);
        expect(h.calls('portix/shizuku', 'install'), isEmpty);

        // Fallback atômico: request preservado (offerFallback=true).
        await h.container
            .read(installFlowProvider.notifier)
            .useAndroidThisTime(kGameId);
        expect(h.flow().plan, isA<AndroidPlan>());
        expect(h.phase, InstallPhase.awaitingPreapproval);
      },
    );

    testWidgets(
      'prepare falha (Android < 34 ou sessão negada) → degrada para o fluxo '
      'clássico e baixa (fallback commitFresh acontece sozinho — D20)',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
            }),
          },
        );
        h.nativo.prepareOk = false;

        await h.begin();
        expect(h.phase, InstallPhase.downloading);
        expect(h.flow().error, isNull);
        expect(h.downloads.startedUrls, <String>[kUrl]);
        expect(h.prepares, hasLength(1));
      },
    );

    testWidgets(
      'preapprovalFailed VIA EVENTO (framework nega o recurso) → degrada e '
      'baixa (o prepare respondeu true; D20 cobre o par reply+evento)',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
            }),
          },
        );

        await h.begin();
        expect(h.phase, InstallPhase.awaitingPreapproval);
        expect(h.downloads.startedUrls, isEmpty);

        // O framework responde o broadcast com PRE_APPROVAL_NOT_AVAILABLE:
        // o evento chega DEPOIS do reply true (corrida real do Kotlin).
        await h.pushInstallEvent(<String, Object?>{
          'type': 'preapprovalFailed',
          'key': kGameId,
          'error': 'shizuku-unavailable-not-applicable',
        });

        expect(h.phase, InstallPhase.downloading);
        expect(h.downloads.startedUrls, <String>[kUrl]);
        // Nada foi baixado antes: o degrade acontece ANTES do _startDownload.
        expect(h.prepares, hasLength(1));
      },
    );

    testWidgets(
      'preapprovalFailed em fase avançada (downloading) é ignorado — não mata '
      'um download em curso',
      (WidgetTester tester) async {
        await h.init(
          prefsSeed: <String, Object>{
            'install.packages': jsonEncode(<String, Object?>{
              'owner/repo': <String, String>{'p': kPkg, 'l': kLabel},
            }),
          },
        );

        await h.begin();
        await h.pushInstallEvent(<String, Object?>{
          'type': 'prepared',
          'key': kGameId,
          'sessionId': 7,
        });
        await h.pushInstallEvent(<String, Object?>{
          'type': 'preapprovalApproved',
          'key': kGameId,
        });
        expect(h.phase, InstallPhase.downloading);

        await h.pushInstallEvent(<String, Object?>{
          'type': 'preapprovalFailed',
          'key': kGameId,
          'error': 'atrasado',
        });
        expect(h.phase, InstallPhase.downloading);
        expect(h.downloads.startedUrls, hasLength(1));
      },
    );

    testWidgets(
      'espaço em disco insuficiente → failed antes de qualquer download',
      (WidgetTester tester) async {
        await h.init();
        h.nativo.freeBytes = 100 * 1024 * 1024; // 100 MB livres

        await h.begin(sizeBytes: 300 * 1024 * 1024);
        expect(h.phase, InstallPhase.failed);
        expect(h.flow().error, 'low-storage');
        expect(h.downloads.startedUrls, isEmpty);
        expect(h.prepares, isEmpty);
      },
    );

    testWidgets(
      'duplo toque durante o fluxo não cria segunda sessão/download',
      (WidgetTester tester) async {
        await h.init();
        await h.begin();
        expect(h.phase, InstallPhase.downloading);
        await h.begin(); // guard de reentrância
        expect(h.downloads.startedUrls, hasLength(1));
        expect(h.container.read(installFlowProvider), contains(kGameId));
      },
    );

    testWidgets('reinstalação de APK existente vai direto para verifying e usa '
        'commitFresh (diálogo único no commit)', (WidgetTester tester) async {
      await h.init();
      final File file = apk();
      h.nativo.inspect = <String, Object?>{
        'packageName': kPkg,
        'versionCode': 5,
      };
      h.nativo.installed = <String, Object?>{
        'packageName': kPkg,
        'versionCode': 5,
      };

      expect(
        await h.container
            .read(installFlowProvider.notifier)
            .reinstallFromApk(kGame, apkPath: file.path),
        isTrue,
      );
      await h.settle();

      expect(h.phase, InstallPhase.installing);
      final List<_Call> fresh = h.calls('portix/install', 'commitFresh');
      expect(fresh, hasLength(1));
      expect(fresh.single.arg('path'), file.path);
      expect(
        h.prepares,
        isEmpty,
        reason: 'reinstalação não pede pré-aprovação',
      );

      await h.pushInstallEvent(<String, Object?>{
        'type': 'installDone',
        'key': kGameId,
      });
      expect(h.phase, InstallPhase.installed);
    });

    testWidgets('reinstalação com arquivo inexistente devolve false', (
      WidgetTester tester,
    ) async {
      await h.init();
      expect(
        await h.container
            .read(installFlowProvider.notifier)
            .reinstallFromApk(kGame, apkPath: '/caminho/inexistente.apk'),
        isFalse,
      );
      expect(h.phase, InstallPhase.idle);
    });
  });
}
