import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/apk_tools.dart';
import '../../core/github_releases.dart';
import '../../core/providers.dart';
import '../../models/download_task.dart';
import '../../models/game.dart';
import '../../models/game_detail.dart';
import '../downloads/downloads_controller.dart';
import 'file_cleanup.dart';
import 'models.dart';
import 'native_installer.dart';
import 'permissions.dart';
import 'shizuku.dart';

// ============================================================================
// PORTIX — máquina de estados do fluxo "Baixar → instalar".
//
// O reducer é puro (testável) e o controller orquestra os efeitos: resolvedor
// de instalador, pré-aprovação ANTES do download (Android 14+), verificação
// de integridade e instalação (Android ou Shizuku), sem lógica duplicada.
// ============================================================================

/// Fases observáveis pelo CTA da tela de detalhes.
enum InstallPhase {
  /// Nada em andamento para o jogo.
  idle,

  /// Falta "Instalar apps desconhecidos": bottom sheet + tela do sistema.
  needsInstallPermission,

  /// Diálogo de pré-aprovação aberto; nada foi baixado ainda.
  awaitingPreapproval,

  /// Baixando (o download em si usa o fluxo existente: progresso, pausa...).
  downloading,

  /// Verificando checksum, pacote e versão do APK baixado.
  verifying,

  /// Gravando na sessão / instalando.
  installing,

  /// Instalado (ou simulação concluída em desktop/web).
  installed,

  /// Falhou — com mensagem e, quando aplicável, oferta de fallback.
  failed,

  /// Não dá para começar como pedido (ex.: Shizuku escolhido mas parado).
  blocked,
}

/// Estado do fluxo de um jogo.
class FlowState {
  const FlowState({
    this.phase = InstallPhase.idle,
    this.plan,
    this.sessionId,
    this.error,
    this.verdict,
    this.offerAndroidFallback = false,
  });

  const FlowState.idle() : this();

  final InstallPhase phase;
  final InstallPlan? plan;
  final int? sessionId;
  final String? error;

  /// Última decisão de integridade (a UI localiza as mensagens).
  final IntegrityVerdict? verdict;

  /// Sugere "usar o instalador do Android desta vez".
  final bool offerAndroidFallback;

  bool get isBusy =>
      phase == InstallPhase.awaitingPreapproval ||
      phase == InstallPhase.downloading ||
      phase == InstallPhase.verifying ||
      phase == InstallPhase.installing;

  FlowState copyWith({
    InstallPhase? phase,
    InstallPlan? plan,
    int? sessionId,
    String? error,
    IntegrityVerdict? verdict,
    bool? offerAndroidFallback,
    bool clearError = false,
  }) => FlowState(
    phase: phase ?? this.phase,
    plan: plan ?? this.plan,
    sessionId: sessionId ?? this.sessionId,
    error: clearError ? null : (error ?? this.error),
    verdict: verdict ?? this.verdict,
    offerAndroidFallback: offerAndroidFallback ?? this.offerAndroidFallback,
  );
}

// ------------------------------------------------------------------ eventos

sealed class FlowEvent {
  const FlowEvent();
}

/// Usuário tocou em "Baixar" (ou voltou da tela do sistema com permissão).
class FlowBegin extends FlowEvent {
  const FlowBegin(this.plan);
  final InstallPlan plan;
}

/// Rechec da permissão de instalar ao voltar das configurações do sistema.
class FlowPermissionResolved extends FlowEvent {
  const FlowPermissionResolved(this.plan, this.granted);
  final InstallPlan plan;
  final bool granted;
}

/// Evento do instalador nativo (pré-aprovação e instalação).
class FlowPreapproval extends FlowEvent {
  const FlowPreapproval(this.type, {this.sessionId, this.error});
  final String type; // prepared | pending | approved | declined | failed
  final int? sessionId;
  final String? error;
}

class FlowDownloadDone extends FlowEvent {
  const FlowDownloadDone();
}

class FlowDownloadFailed extends FlowEvent {
  const FlowDownloadFailed(this.error);
  final String? error;
}

class FlowVerified extends FlowEvent {
  const FlowVerified(this.verdict);
  final IntegrityVerdict verdict;
}

class FlowInstallFinished extends FlowEvent {
  const FlowInstallFinished(this.ok, {this.error, this.offerFallback = false});
  final bool ok;
  final String? error;

  /// Falha com Shizuku indisponível: oferece "usar o Android desta vez" e
  /// preserva o request — tudo atômico dentro do reducer.
  final bool offerFallback;
}

class FlowCancelled extends FlowEvent {
  const FlowCancelled();
}

class FlowReset extends FlowEvent {
  const FlowReset();
}

/// Reducer puro: (estado, evento) → estado. Um único ponto de verdade.
FlowState installFlowReducer(FlowState state, FlowEvent event) {
  switch (event) {
    case FlowBegin(:final plan):
      return switch (plan) {
        ShizukuPlan(:final blocker) when blocker != null => FlowState(
          phase: InstallPhase.blocked,
          plan: plan,
          offerAndroidFallback: true,
        ),
        AndroidPlan(:final needsInstallPermission)
            when needsInstallPermission =>
          FlowState(phase: InstallPhase.needsInstallPermission, plan: plan),
        AndroidPlan(:final usePreapproval) when usePreapproval => FlowState(
          phase: InstallPhase.awaitingPreapproval,
          plan: plan,
        ),
        _ => FlowState(phase: InstallPhase.downloading, plan: plan),
      };

    case FlowPermissionResolved(:final plan, :final granted):
      if (!granted) {
        return FlowState(
          phase: InstallPhase.failed,
          plan: plan,
          error: 'permission-required',
        );
      }
      return installFlowReducer(const FlowState(), FlowBegin(plan));

    case FlowPreapproval(:final type, :final sessionId, :final error):
      return switch (type) {
        'prepared' => state.copyWith(sessionId: sessionId),
        'pending' => state,
        'approved' => state.copyWith(
          phase: InstallPhase.downloading,
          clearError: true,
        ),
        'declined' => const FlowState.idle(),
        _ => FlowState(
          phase: InstallPhase.failed,
          plan: state.plan,
          error: error ?? 'preapproval-failed',
        ),
      };

    case FlowDownloadDone():
      return state.copyWith(phase: InstallPhase.verifying, clearError: true);

    case FlowDownloadFailed(:final error):
      return FlowState(
        phase: InstallPhase.failed,
        plan: state.plan,
        error: error ?? 'download-failed',
      );

    case FlowVerified(:final verdict):
      return switch (verdict) {
        IntegrityVerdict.pass => state.copyWith(
          phase: InstallPhase.installing,
          verdict: verdict,
        ),
        _ => FlowState(
          phase: InstallPhase.failed,
          plan: state.plan,
          verdict: verdict,
        ),
      };

    case FlowInstallFinished(:final ok, :final error, :final offerFallback):
      if (ok) {
        return state.copyWith(phase: InstallPhase.installed, clearError: true);
      }
      return FlowState(
        phase: InstallPhase.failed,
        plan: state.plan,
        error: error ?? 'install-failed',
        offerAndroidFallback: offerFallback,
      );

    case FlowCancelled():
      return const FlowState.idle();

    case FlowReset():
      return const FlowState.idle();
  }
}

// ------------------------------------------------------------------ controller

class _InstallRequest {
  _InstallRequest({
    required this.game,
    required this.url,
    this.port,
    this.releaseTag,
    this.digest,
    this.sizeBytes = 0,
    this.restart = false,
    this.apkPath,
  });

  final Game game;
  final GamePort? port;
  final String url;
  final String? releaseTag;
  final String? digest;
  final int sizeBytes;
  final bool restart;

  /// Caminho de um APK já baixado (reinstalação sem novo download).
  final String? apkPath;
}

/// Falha terminal sem fallback pendente libera o retry imediato.
bool shouldClearRequest(FlowState next) =>
    next.phase == InstallPhase.failed && !next.offerAndroidFallback;

final installFlowProvider =
    NotifierProvider<InstallFlowController, Map<String, FlowState>>(
      InstallFlowController.new,
    );

final installFlowForGameProvider = Provider.family<FlowState, String>(
  (ref, String gameId) =>
      ref.watch(installFlowProvider)[gameId] ?? const FlowState.idle(),
);

/// Orquestra o fluxo por jogo: resolve, pede permissão/pré-aprovação, baixa
/// (via DownloadsController existente), verifica e instala.
/// Fonte de eventos nativos do instalador. Provider para o teste injetar um
/// StreamController direto (canal de plataforma não roda no fake-async).
final Provider<Stream<NativeInstallEvent>> installEventsProvider =
    Provider<Stream<NativeInstallEvent>>((Ref ref) => NativeInstaller.events());

class InstallFlowController extends Notifier<Map<String, FlowState>> {
  final Map<String, _InstallRequest> _requests = <String, _InstallRequest>{};

  /// Tentativa atual por jogo (ids monotônicos globais — nunca reutilizados,
  /// então um cancelamento atrasado não envenena a próxima tentativa).
  final Map<String, int> _attempts = <String, int>{};
  int _nextAttemptId = 0;
  StreamSubscription<NativeInstallEvent>? _events;

  @override
  Map<String, FlowState> build() {
    ref.onDispose(() {
      _events?.cancel();
      _events = null;
    });
    if (NativeInstaller.isAndroid) {
      _events = ref.read(installEventsProvider).listen(_onNativeEvent);
      // Sessões órfãs (app morto entre createSession e commit) e APKs
      // deixados para trás são limpos no startup (espec §1).
      unawaited(NativeInstaller.cleanupOrphanSessions());
      unawaited(
        cleanupOrphanApks(
          ref
              .read(downloadsProvider)
              .map((DownloadTask task) => task.apkPath ?? '')
              .toList(),
        ),
      );
    }
    ref.listen(downloadsProvider, _onDownloadsChanged);
    return const <String, FlowState>{};
  }

  FlowState stateFor(String gameId) => state[gameId] ?? const FlowState.idle();

  void _dispatch(String gameId, FlowEvent event) {
    final FlowState current = stateFor(gameId);
    final FlowState next = installFlowReducer(current, event);
    final Map<String, FlowState> nextMap = Map<String, FlowState>.of(state);
    if (next.phase == InstallPhase.idle) {
      nextMap.remove(gameId);
    } else {
      nextMap[gameId] = next;
    }
    state = nextMap;
    // Falha terminal (sem fallback pendente): libera o retry imediato.
    // 'blocked' preserva o request para "usar o Android desta vez".
    if (shouldClearRequest(next)) {
      _requests.remove(gameId);
    }
  }

  // ------------------------------------------------------- início do fluxo

  /// "Baixar vX.Y.Z" (respeita o seletor de versão/asset escolhido).
  /// Guarda de reentrância: duplo toque não cria duas sessões/diálogos.
  Future<void> begin(
    Game game,
    GamePort? port, {
    required String url,
    String? releaseTag,
    String? digest,
    int sizeBytes = 0,
    bool restart = false,
  }) async {
    if (stateFor(game.id).isBusy) {
      return; // Duplo toque durante fluxo ativo: ignora.
    }
    _requests[game.id] = _InstallRequest(
      game: game,
      port: port,
      url: url,
      releaseTag: releaseTag,
      digest: digest,
      sizeBytes: sizeBytes,
      restart: restart,
    );

    // Espaço em disco, antes de qualquer coisa (o staging do instalador
    // pode chegar a ~2x o tamanho do APK).
    if (sizeBytes > 0) {
      final int free = await NativeInstaller.freeBytes();
      if (free >= 0 && free < sizeBytes * 2 + 64 * 1024 * 1024) {
        _dispatch(game.id, const FlowDownloadFailed('low-storage'));
        return;
      }
    }

    final InstallPlan plan = await _resolvePlan(game.id);
    await _afterBegin(game.id, plan);
  }

  /// Reinstala um APK já baixado (tarefa done, app não instalado).
  /// Retorna `false` quando o arquivo não existe mais (chamador recomeça).
  Future<bool> reinstallFromApk(Game game, {required String apkPath}) async {
    if (!apkFileExists(apkPath)) {
      return false;
    }
    if (_requests.containsKey(game.id) || stateFor(game.id).isBusy) {
      return true; // Já existe um fluxo em andamento para este jogo.
    }
    final DownloadTask? task = ref.read(downloadForGameProvider(game.id));
    _requests[game.id] = _InstallRequest(
      game: game,
      port: null,
      url: task?.portUrl ?? '',
      apkPath: apkPath,
    );
    final InstallPlan plan = await _resolvePlan(game.id);
    state = Map<String, FlowState>.of(state)
      ..[game.id] = FlowState(phase: InstallPhase.verifying, plan: plan);
    unawaited(_verifyAndInstall(game.id, apkPath));
    return true;
  }

  Future<InstallPlan> _resolvePlan(
    String gameId, {
    InstallerChoice? overrideChoice,
  }) async {
    final InstallerChoice choice =
        overrideChoice ?? ref.read(installPrefsProvider).choice;
    final ShizukuStatus shizuku = ShizukuService.instance.current;
    bool canInstallApps = true;
    int sdkInt = 0;
    final PermissionSnapshot? snapshot = await PortixPermissions.snapshot();
    if (snapshot != null) {
      canInstallApps = snapshot.canInstallApps;
      sdkInt = snapshot.sdkInt;
    }
    final _InstallRequest? request = _requests[gameId];
    // Pacote esperado: da tarefa atual ou do cache por port (lido do APK de
    // downloads anteriores) — habilita pré-aprovação antes do download.
    final String? expectedPackage =
        ref.read(downloadForGameProvider(gameId))?.packageName ??
        (request == null ? null : lookupKnownPackage(ref, request.url));
    return resolveInstaller(
      choice: choice,
      shizuku: shizuku,
      canInstallApps: canInstallApps,
      sdkInt: sdkInt,
      expectedPackage: expectedPackage,
    );
  }

  Future<void> _afterBegin(String gameId, InstallPlan plan) async {
    if (!_requests.containsKey(gameId)) {
      return; // Fluxo cancelado durante os awaits do resolve.
    }
    _dispatch(gameId, FlowBegin(plan));
    final FlowState current = stateFor(gameId);
    switch (current.phase) {
      case InstallPhase.needsInstallPermission:
        // A UI (tela de detalhes) mostra o bottom sheet e abre o sistema.
        break;
      case InstallPhase.awaitingPreapproval:
        await _requestPreapproval(gameId, plan);
      case InstallPhase.downloading:
        await _startDownload(gameId);
      default:
        break;
    }
  }

  /// Chamado quando o usuário volta da tela do sistema de permissões.
  Future<void> onPermissionResume(String gameId) async {
    if (stateFor(gameId).phase != InstallPhase.needsInstallPermission) {
      return;
    }
    final PermissionSnapshot? snapshot = await PortixPermissions.snapshot();
    // Rechec após o await: o estado pode ter mudado enquanto voltávamos.
    if (stateFor(gameId).phase != InstallPhase.needsInstallPermission) {
      return;
    }
    final bool granted = snapshot?.canInstallApps ?? false;
    if (granted) {
      final InstallPlan plan = await _resolvePlan(gameId);
      _dispatch(gameId, FlowPermissionResolved(plan, true));
      await _afterBegin(gameId, plan);
    } else {
      // Negada: falha clara (o pedido continua nas Configurações) e o
      // request é liberado — o próximo toque reabre o sheet.
      final FlowState current = stateFor(gameId);
      final InstallPlan plan =
          current.plan ??
          const AndroidPlan(
            needsInstallPermission: true,
            usePreapproval: false,
          );
      _dispatch(gameId, FlowPermissionResolved(plan, false));
    }
  }

  /// "Usar o instalador do Android desta vez" (Shizuku bloqueado). Passa
  /// pelo resolvedor de novo, mantendo pacote esperado e pré-aprovação.
  Future<void> useAndroidThisTime(String gameId) async {
    if (!_requests.containsKey(gameId)) {
      return;
    }
    final InstallPlan plan = await _resolvePlan(
      gameId,
      overrideChoice: InstallerChoice.android,
    );
    await _afterBegin(gameId, plan);
  }

  /// Reseta o fluxo somente se a fase [phase] persistir (sheet dispensado
  /// sem ação). Usado pela UI para o próximo toque reabrir o sheet.
  Future<void> resetIfPending(String gameId, InstallPhase phase) async {
    if (stateFor(gameId).phase == phase) {
      await cancel(gameId);
    }
  }

  /// Cancelamento em qualquer ponto: abandona a sessão e a tarefa.
  Future<void> cancel(String gameId) async {
    final FlowState current = stateFor(gameId);
    final int? sessionId = current.sessionId;
    if (sessionId != null) {
      unawaited(NativeInstaller.abandon(sessionId));
    } else if (current.phase == InstallPhase.awaitingPreapproval) {
      // Prepare em andamento (ícone/sessão): impede o diálogo de aparecer.
      // O attemptId evita envenenar a próxima tentativa do mesmo jogo.
      final int? attemptId = _attempts[gameId];
      if (attemptId != null) {
        unawaited(NativeInstaller.cancelPrepare(gameId, attemptId: attemptId));
      }
    }
    if (current.isBusy) {
      ref.read(downloadsProvider.notifier).cancel(gameId);
    }
    _requests.remove(gameId);
    // _attempts é mantido: o attemptId cancelado não pode ser reusado.
    _dispatch(gameId, const FlowCancelled());
  }

  // --------------------------------------------------- pré-aprovação (34+)

  Future<void> _requestPreapproval(String gameId, InstallPlan plan) async {
    final _InstallRequest? request = _requests[gameId];
    // O cancelamento pode ter corrido durante os awaits do begin: não pede
    // pré-aprovação para um fluxo que o usuário já cancelou.
    if (request == null ||
        stateFor(gameId).phase != InstallPhase.awaitingPreapproval) {
      return;
    }
    final String? expectedPackage = plan is AndroidPlan
        ? plan.expectedPackage
        : null;
    if (expectedPackage == null || expectedPackage.isEmpty) {
      // Sem pacote conhecido não existe pré-aprovação: cai para o clássico,
      // mas com o plano registrado para o download ser rastreado.
      const InstallPlan legacy = AndroidPlan(
        needsInstallPermission: false,
        usePreapproval: false,
      );
      _dispatch(gameId, const FlowBegin(legacy));
      await _startDownload(gameId);
      return;
    }
    final int attemptId = _nextAttemptId++;
    _attempts[gameId] = attemptId;
    final bool ok = await NativeInstaller.prepare(
      key: gameId,
      attemptId: attemptId,
      packageName: expectedPackage,
      label: request.game.title,
      iconUrl: request.game.coverUrl,
      sizeBytes: request.sizeBytes,
    );
    if (!ok) {
      // D20: prepare indisponível (API <34, sessão negada, storage do
      // sistema) NÃO é falha terminal — degrada sozinho para o fluxo
      // clássico (1 único diálogo no commit) e continua o download.
      const InstallPlan legacy = AndroidPlan(
        needsInstallPermission: false,
        usePreapproval: false,
      );
      _dispatch(gameId, const FlowBegin(legacy));
      await _startDownload(gameId);
    }
  }

  // -------------------------------------------------------------- download

  Future<void> _startDownload(String gameId) async {
    final _InstallRequest? request = _requests[gameId];
    if (request == null) {
      // Self-heal: request já limpo (cancel em corrida) — não deixa o CTA
      // travado em "Baixando…" sem tarefa.
      _dispatch(gameId, const FlowCancelled());
      return;
    }
    ref
        .read(downloadsProvider.notifier)
        .start(
          request.game,
          port: request.port,
          urlOverride: request.url,
          releaseTag: request.releaseTag,
          restart: request.restart,
        );
  }

  void _onDownloadsChanged(
    List<DownloadTask>? previous,
    List<DownloadTask> next,
  ) {
    // Snapshot: dispatch substitui o mapa inteiro.
    for (final MapEntry<String, FlowState> entry in state.entries.toList(
      growable: false,
    )) {
      final String gameId = entry.key;
      final FlowState flow = entry.value;
      if (flow.phase != InstallPhase.downloading) {
        continue;
      }
      DownloadTask? task;
      for (final DownloadTask item in next) {
        if (item.gameId == gameId) {
          task = item;
          break;
        }
      }
      if (task == null) {
        // Sessão pré-aprovada não serve mais: abandona.
        final int? sessionId = flow.sessionId;
        if (sessionId != null) {
          unawaited(NativeInstaller.abandon(sessionId));
        }
        _dispatch(gameId, const FlowCancelled());
      } else if (task.status == DownloadStatus.done) {
        _dispatch(gameId, const FlowDownloadDone());
        unawaited(_verifyAndInstall(gameId, task.apkPath));
      } else if (task.status == DownloadStatus.failed) {
        // Sessão pré-aprovada não serve mais: abandona.
        final int? sessionId = flow.sessionId;
        if (sessionId != null) {
          unawaited(NativeInstaller.abandon(sessionId));
        }
        _dispatch(gameId, FlowDownloadFailed(task.error));
      }
    }
  }

  // --------------------------------------------- verificação + instalação

  Future<void> _verifyAndInstall(String gameId, String? path) async {
    final _InstallRequest? request = _requests[gameId];
    if (request == null || path == null || path.isEmpty) {
      if (!NativeInstaller.isAndroid) {
        // Simulação desktop/web: download 'done' não tem arquivo nativo.
        _dispatch(gameId, const FlowInstallFinished(true));
        _requests.remove(gameId);
        return;
      }
      _dispatch(gameId, const FlowInstallFinished(false, error: 'no-apk'));
      return;
    }
    final FlowState flow = stateFor(gameId);
    final InstallPlan plan =
        flow.plan ??
        const AndroidPlan(needsInstallPermission: false, usePreapproval: false);
    final bool allowDowngrade = plan.kind == InstallerKind.shizuku;
    final String? expectedPackage = switch (plan) {
      AndroidPlan(:final expectedPackage) => expectedPackage,
      ShizukuPlan(:final expectedPackage) => expectedPackage,
      // BlockedPlan nunca chega aqui (o reducer bloqueia antes), mas a
      // hierarquia selada exige o caso para exaustividade.
      BlockedPlan() => null,
    };

    // Integridade: checksum (quando o GitHub fornece digest) + pacote.
    // Digest esperado sem digest calculado = indefinido: descarta (seguro).
    // Na simulação desktop/web não há canal nativo: digest é omitido.
    final bool canHash = NativeInstaller.isAndroid;
    String? actualDigest;
    if (canHash && request.digest != null && request.digest!.isNotEmpty) {
      actualDigest = await NativeInstaller.sha256(path);
      if (actualDigest == null) {
        _deleteQuietly(path);
        _dispatch(gameId, const FlowVerified(IntegrityVerdict.digestMismatch));
        return;
      }
    }
    final String? expectedDigest = canHash ? request.digest : null;
    final ApkSummary? apk = await ApkTools.inspect(path);
    ApkSummary? installed;
    if (expectedPackage != null && expectedPackage.isNotEmpty) {
      installed = await ApkTools.installed(expectedPackage);
    }
    final IntegrityVerdict verdict = verifyDownloadedApk(
      expectedDigest: expectedDigest,
      actualDigest: actualDigest,
      expectedPackage: expectedPackage,
      actualPackage: apk?.packageName,
      allowDowngrade: allowDowngrade,
      installedVersionCode: installed?.versionCode,
      apkVersionCode: apk?.versionCode,
    );
    // Memoriza o pacote por port SÓ quando a integridade PASSOU —
    // APK adulterado (digest/pacote divergente) não pode envenenar o
    // cache e pré-aprovar o pacote errado na próxima tentativa.
    if (apk != null &&
        apk.packageName.isNotEmpty &&
        verdict == IntegrityVerdict.pass) {
      rememberKnownPackage(ref, request.url, apk.packageName);
    }
    if (verdict != IntegrityVerdict.pass) {
      _deleteQuietly(path);
      _dispatch(gameId, FlowVerified(verdict));
      return;
    }
    _dispatch(gameId, const FlowVerified(IntegrityVerdict.pass));

    await _runInstall(gameId, plan, path);
  }

  Future<void> _runInstall(String gameId, InstallPlan plan, String path) async {
    switch (plan.kind) {
      case InstallerKind.shizuku:
        // Rechec no momento da instalação: nunca usar estado velho.
        final ShizukuStatus status = await ShizukuService.instance.refresh();
        if (!status.isActive) {
          // Atômico: failed + fallback preserva o request para o sheet.
          _dispatch(
            gameId,
            const FlowInstallFinished(
              false,
              error: 'shizuku-unavailable',
              offerFallback: true,
            ),
          );
          return;
        }
        await safeInvoke<Map<Object?, Object?>>(() async {
          final Object? result = await const MethodChannel('portix/shizuku')
              .invokeMethod<Object?>('install', <String, Object?>{
                'key': gameId,
                'path': path,
                'expectedPackage': plan is ShizukuPlan
                    ? plan.expectedPackage
                    : null,
              });
          return result as Map<Object?, Object?>?;
        });
      case InstallerKind.android:
        final FlowState flow = stateFor(gameId);
        final int? sessionId = flow.sessionId;
        if (sessionId != null) {
          await NativeInstaller.commitPrepared(
            key: gameId,
            sessionId: sessionId,
            path: path,
            expectedPackage: plan is AndroidPlan ? plan.expectedPackage : null,
          );
        } else if (!NativeInstaller.isAndroid) {
          // Simulação em desktop/web: considera instalado.
          _dispatch(gameId, const FlowInstallFinished(true));
        } else {
          await NativeInstaller.commitFresh(key: gameId, path: path);
        }
    }
  }

  // -------------------------------------------------------------- eventos

  void _onNativeEvent(NativeInstallEvent event) {
    final String gameId = event.key;
    if (gameId.isEmpty ||
        (!_requests.containsKey(gameId) && !state.containsKey(gameId))) {
      return;
    }
    switch (event.type) {
      case 'prepared':
        _dispatch(
          gameId,
          FlowPreapproval('prepared', sessionId: event.sessionId),
        );
      case 'preapprovalPending' ||
          'userActionPending' ||
          'writing' ||
          'committing':
        break; // Estados transitórios; o CTA já mostra "instalando".
      case 'preapprovalApproved':
        _dispatch(gameId, const FlowPreapproval('approved'));
        unawaited(_startDownload(gameId));
      case 'preapprovalDeclined':
        _dispatch(gameId, const FlowPreapproval('declined'));
        _requests.remove(gameId);
      case 'installDone':
        unawaited(_onInstallSuccess(gameId));
      case 'installFailed' || 'failed' || 'preapprovalFailed':
        final String flowError = event.error ?? 'install-failed';
        _dispatch(
          gameId,
          FlowInstallFinished(
            false,
            error: flowError,
            // Corrida Shizuku (morte entre o rechec Dart e o Kotlin): o
            // token do bridge indica indisponibilidade → fallback Android.
            offerFallback: flowError.startsWith('shizuku-unavailable'),
          ),
        );
      default:
        break;
    }
  }

  Future<void> _onInstallSuccess(String gameId) async {
    final DownloadTask? task = ref.read(downloadForGameProvider(gameId));
    // Confirma a instalação antes de apagar o APK do armazenamento privado.
    final String? path = task?.apkPath;
    final String? pkg = task?.packageName;
    ApkSummary? installed;
    if (pkg != null && pkg.isNotEmpty) {
      installed = await ApkTools.installed(pkg);
    }
    if (installed != null || pkg == null || pkg.isEmpty) {
      _deleteQuietly(path);
    }
    _dispatch(gameId, const FlowInstallFinished(true));
    _requests.remove(gameId);
  }

  void _deleteQuietly(String? path) {
    if (path == null || path.isEmpty) {
      return;
    }
    deleteFileQuietly(path);
  }
}

// ------------------------------------------------------------ cache de pacotes

const String _kPackageCacheKey = 'install.packages';

/// Chave estável por port: `owner/repo` quando GitHub, senão a própria URL.
String packageCacheKey(String url) {
  final GithubRepo? repo = githubRepoOf(url);
  if (repo != null) {
    return '${repo.owner}/${repo.repo}';
  }
  return url;
}

/// Lê o pacote memorizado de um port (habilita pré-aprovação pré-download).
String? lookupKnownPackage(Ref ref, String url) {
  try {
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    final String? raw = prefs.getString(_kPackageCacheKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    final Object? value = decoded[packageCacheKey(url)];
    final String text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  } on Object {
    return null;
  }
}

/// Memoriza o pacote de um port (lido do próprio APK baixado).
void rememberKnownPackage(Ref ref, String url, String packageName) {
  if (url.isEmpty || packageName.isEmpty) {
    return;
  }
  try {
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    final Map<String, String> cache = <String, String>{};
    final String? raw = prefs.getString(_kPackageCacheKey);
    if (raw != null && raw.isNotEmpty) {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach(
          (Object? key, Object? value) =>
              cache[key.toString()] = value.toString(),
        );
      }
    }
    cache[packageCacheKey(url)] = packageName;
    unawaited(prefs.setString(_kPackageCacheKey, jsonEncode(cache)));
  } on Object {
    // Cache é otimização: falhar não pode quebrar o fluxo.
  }
}
