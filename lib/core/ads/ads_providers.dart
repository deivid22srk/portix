import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';
import 'adblock_detector.dart';
import 'ads_config.dart';
import 'ads_sdk.dart';

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

// ----------------------------------------------------------------- SDK/probes

/// SDK real; nos testes sobrescreva com um fake (sem canal nativo).
final adsSdkProvider = Provider<AdsSdk>((ref) => UnityAdsSdk());

/// Detector real; nos testes sobrescreva com fake de veredito fixo.
final adblockDetectorProvider = Provider<AdblockDetector>(
  (ref) => const AdblockDetector(),
);

/// Relógio injetável (testes de cooldown sem `fake_async`).
final adsClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// ------------------------------------------------------------------ ads state

enum AdsPhase { disabled, initializing, ready, failed }

class AdsState {
  const AdsState({
    required this.phase,
    this.interstitialReady = false,
    this.rewardedReady = false,
  });

  const AdsState.disabled() : this(phase: AdsPhase.disabled);
  const AdsState.initializing() : this(phase: AdsPhase.initializing);
  const AdsState.ready({
    bool interstitialReady = false,
    bool rewardedReady = false,
  }) : this(
         phase: AdsPhase.ready,
         interstitialReady: interstitialReady,
         rewardedReady: rewardedReady,
       );

  final AdsPhase phase;
  final bool interstitialReady;
  final bool rewardedReady;

  AdsState copyWith({
    AdsPhase? phase,
    bool? interstitialReady,
    bool? rewardedReady,
  }) => AdsState(
    phase: phase ?? this.phase,
    interstitialReady: interstitialReady ?? this.interstitialReady,
    rewardedReady: rewardedReady ?? this.rewardedReady,
  );
}

final adsProvider = NotifierProvider<AdsController, AdsState>(
  AdsController.new,
);

/// Ciclo de vida da monetização: init lazy (só Android), pré-carga dos
/// placements e o PACING do interstitial — exibir na conclusão de download,
/// nunca nas primeiras sessões e com cooldown mínimo. Anúncio não é
/// punição: é o que mantém o app gratuito.
class AdsController extends Notifier<AdsState> {
  static const String _sessionsKey = 'ads.sessions';
  static const String _lastInterstitialKey = 'ads.lastInterstitialAt';

  bool _started = false;

  @override
  AdsState build() {
    ref.onDispose(() => _started = false);
    return const AdsState.disabled();
  }

  /// Chame uma vez por sessão (AdsGate). Em desktop/dev fica desligado.
  Future<void> ensureStarted() async {
    if (_started || !_isAndroid) {
      return;
    }
    _started = true;
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    final int sessions = (prefs.getInt(_sessionsKey) ?? 0) + 1;
    unawaited(prefs.setInt(_sessionsKey, sessions));

    state = const AdsState.initializing();
    try {
      await ref
          .read(adsSdkProvider)
          .init(
            gameId: AdsConfig.androidGameId,
            // Anúncios de teste em debug; o build de CI (release) serve
            // anúncios reais. Firebase Test Lab desliga por conta própria.
            testMode: kDebugMode,
          );
    } on Object {
      // Init falhou (rede, bloqueador): o gate de bloqueador decide o que
      // mostrar a partir do veredito de DNS; sem SDK não há receita, mas o
      // app continua usável se a rede estiver sã.
      state = const AdsState(phase: AdsPhase.failed);
      unawaited(ref.read(adblockProvider.notifier).check());
      return;
    }
    state = const AdsState(phase: AdsPhase.ready);
    unawaited(ref.read(adblockProvider.notifier).check());
    await _reloadPlacements();
  }

  /// Gancho de pacing: um download concluiu — avalia e, se couber, exibe.
  Future<void> onDownloadCompleted() async {
    if (!_isAndroid || state.phase != AdsPhase.ready) {
      return;
    }
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    final int sessions = prefs.getInt(_sessionsKey) ?? 1;
    if (sessions <= AdsConfig.skipFirstSessions) {
      // Primeiras sessões sem anúncio: o usuário precisa se apegar antes.
      return;
    }
    final DateTime now = ref.read(adsClockProvider)();
    final int? lastMs = prefs.getInt(_lastInterstitialKey);
    if (lastMs != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
            AdsConfig.interstitialCooldown) {
      return;
    }
    await prefs.setInt(_lastInterstitialKey, now.millisecondsSinceEpoch);
    final bool shown = await _showSafe(
      ref.read(adsSdkProvider).showInterstitial(),
    );
    if (shown) {
      unawaited(_reloadPlacements());
    }
  }

  /// Recompensado voluntário ("Apoie o PORTIX" no menu). `true` = assistiu
  /// até o fim; pular ou indisponível devolve `false` sem prometer nada.
  Future<bool> showRewardedSupport() async {
    if (!_isAndroid || state.phase != AdsPhase.ready || !state.rewardedReady) {
      return false;
    }
    final bool watched = await _showSafe(
      ref.read(adsSdkProvider).showRewarded(),
    );
    unawaited(_reloadPlacements());
    return watched;
  }

  Future<void> _reloadPlacements() async {
    final AdsSdk sdk = ref.read(adsSdkProvider);
    final bool interstitial = await _loadSafe(sdk.loadInterstitial());
    final bool rewarded = await _loadSafe(sdk.loadRewarded());
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      interstitialReady: interstitial,
      rewardedReady: rewarded,
    );
  }

  Future<bool> _loadSafe(Future<void> future) async {
    try {
      await future;
      return true;
    } on Object {
      return false; // noFill/rede — não é fatal, tenta de novo depois.
    }
  }

  Future<bool> _showSafe(Future<bool> future) async {
    try {
      return await future;
    } on Object {
      return false;
    }
  }
}

// --------------------------------------------------------------- adblock gate

enum AdblockPhase { idle, checking, ok, blocked }

class AdblockState {
  const AdblockState({required this.phase, this.userInitiated = false});

  final AdblockPhase phase;

  /// `true` quando a checagem veio do botão do diálogo (mostra spinner).
  final bool userInitiated;
}

final adblockProvider = NotifierProvider<AdblockController, AdblockState>(
  AdblockController.new,
);

/// Detecta bloqueador de anúncios (DNS) e decide o estado do gate.
class AdblockController extends Notifier<AdblockState> {
  @override
  AdblockState build() => const AdblockState(phase: AdblockPhase.idle);

  Future<void> check({bool userInitiated = false}) async {
    if (!_isAndroid) {
      return;
    }
    state = AdblockState(
      phase: AdblockPhase.checking,
      userInitiated: userInitiated,
    );
    final AdblockVerdict verdict = await ref
        .read(adblockDetectorProvider)
        .detect();
    switch (verdict) {
      case AdblockVerdict.blocked:
        state = AdblockState(
          phase: AdblockPhase.blocked,
          userInitiated: userInitiated,
        );
      case AdblockVerdict.allowed:
      case AdblockVerdict.offline:
        // Offline NÃO bloqueia (falso positivo puniria quem está sem rede);
        // a checagem roda de novo no próximo início do app.
        state = const AdblockState(phase: AdblockPhase.ok);
    }
  }
}
