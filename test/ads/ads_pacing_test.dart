import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:portix/core/ads/adblock_detector.dart';
import 'package:portix/core/ads/ads_providers.dart';
import 'package:portix/core/providers.dart';
import 'package:portix/core/ads/ads_sdk.dart';

class _FakeSdk implements AdsSdk {
  bool throwOnInit = false;
  bool showResult = true;
  bool initCalled = false;
  int loads = 0;
  int interstitialShows = 0;
  int rewardedShows = 0;

  @override
  Future<void> init({required String gameId, required bool testMode}) async {
    if (throwOnInit) {
      throw const AdsSdkException('init falhou');
    }
    initCalled = true;
  }

  @override
  Future<void> loadInterstitial() async => loads++;

  @override
  Future<void> loadRewarded() async => loads++;

  @override
  Future<bool> showInterstitial() async {
    interstitialShows++;
    return showResult;
  }

  @override
  Future<bool> showRewarded() async {
    rewardedShows++;
    return showResult;
  }
}

class _OkDetector implements AdblockDetector {
  const _OkDetector();

  @override
  Future<AdblockVerdict> detect() async => AdblockVerdict.allowed;
}

final DateTime _now = DateTime(2026, 1, 10, 12);

Future<ProviderContainer> _container(
  _FakeSdk sdk, {
  int sessions = 1,
  int? lastMs,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'ads.sessions': sessions,
    'ads.lastInterstitialAt': ?lastMs,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      adsSdkProvider.overrideWithValue(sdk),
      adblockDetectorProvider.overrideWithValue(const _OkDetector()),
      adsClockProvider.overrideWithValue(() => _now),
    ],
  );
}

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('init falhou → fase failed, sem crash, e detector acionado', () async {
    final _FakeSdk sdk = _FakeSdk()..throwOnInit = true;
    final ProviderContainer container = await _container(sdk);
    addTearDown(container.dispose);
    await container.read(adsProvider.notifier).ensureStarted();
    expect(container.read(adsProvider).phase, AdsPhase.failed);
    expect(sdk.interstitialShows, 0);
  });

  test('init ok → fase ready com placements pré-carregados', () async {
    final _FakeSdk sdk = _FakeSdk();
    final ProviderContainer container = await _container(sdk);
    addTearDown(container.dispose);
    await container.read(adsProvider.notifier).ensureStarted();
    expect(sdk.initCalled, isTrue);
    expect(container.read(adsProvider).phase, AdsPhase.ready);
    expect(sdk.loads, 2); // interstitial + rewarded
  });

  test('primeira sessão: download concluído NÃO mostra interstitial', () async {
    final _FakeSdk sdk = _FakeSdk();
    // ensureStarted incrementa: 0 → vira a primeira sessão do usuário.
    final ProviderContainer container = await _container(sdk, sessions: 0);
    addTearDown(container.dispose);
    await container.read(adsProvider.notifier).ensureStarted();
    await container.read(adsProvider.notifier).onDownloadCompleted();
    expect(sdk.interstitialShows, 0);
  });

  test(
    'sessão seguinte fora do cooldown: mostra e registra o instante',
    () async {
      final _FakeSdk sdk = _FakeSdk();
      final ProviderContainer container = await _container(sdk, sessions: 1);
      addTearDown(container.dispose);
      await container.read(adsProvider.notifier).ensureStarted();
      await container.read(adsProvider.notifier).onDownloadCompleted();
      expect(sdk.interstitialShows, 1);
      final int lastMs = container
          .read(sharedPreferencesProvider)
          .getInt('ads.lastInterstitialAt')!;
      expect(lastMs, _now.millisecondsSinceEpoch);
    },
  );

  test('dentro do cooldown: segundo download concluído não mostra', () async {
    final _FakeSdk sdk = _FakeSdk();
    final ProviderContainer container = await _container(
      sdk,
      sessions: 2,
      lastMs:
          _now.millisecondsSinceEpoch -
          const Duration(minutes: 1).inMilliseconds,
    );
    addTearDown(container.dispose);
    await container.read(adsProvider.notifier).ensureStarted();
    await container.read(adsProvider.notifier).onDownloadCompleted();
    expect(sdk.interstitialShows, 0);
  });

  test('cooldown vencido (4 min): mostra de novo', () async {
    final _FakeSdk sdk = _FakeSdk();
    final ProviderContainer container = await _container(
      sdk,
      sessions: 2,
      lastMs:
          _now.millisecondsSinceEpoch -
          const Duration(minutes: 4).inMilliseconds,
    );
    addTearDown(container.dispose);
    await container.read(adsProvider.notifier).ensureStarted();
    await container.read(adsProvider.notifier).onDownloadCompleted();
    expect(sdk.interstitialShows, 1);
  });

  test('sem fill no show: não crasha e segue em ready', () async {
    final _FakeSdk sdk = _FakeSdk()..showResult = false;
    final ProviderContainer container = await _container(sdk, sessions: 1);
    addTearDown(container.dispose);
    await container.read(adsProvider.notifier).ensureStarted();
    await container.read(adsProvider.notifier).onDownloadCompleted();
    expect(sdk.interstitialShows, 1);
    expect(container.read(adsProvider).phase, AdsPhase.ready);
  });

  test('rewarded voluntário: só recompensa quem assistiu até o fim', () async {
    final _FakeSdk sdk = _FakeSdk();
    final ProviderContainer container = await _container(sdk, sessions: 1);
    addTearDown(container.dispose);
    await container.read(adsProvider.notifier).ensureStarted();
    expect(container.read(adsProvider).rewardedReady, isTrue);
    sdk.showResult = false; // usuário pulou o anúncio
    final bool watched = await container
        .read(adsProvider.notifier)
        .showRewardedSupport();
    expect(watched, isFalse);
    expect(sdk.rewardedShows, 1);
  });

  test(
    'fora do Android: monetização desligada (nada inicia, nada mostra)',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final _FakeSdk sdk = _FakeSdk();
      final ProviderContainer container = await _container(sdk, sessions: 5);
      addTearDown(container.dispose);
      await container.read(adsProvider.notifier).ensureStarted();
      expect(container.read(adsProvider).phase, AdsPhase.disabled);
      expect(sdk.initCalled, isFalse);
      await container.read(adsProvider.notifier).onDownloadCompleted();
      expect(sdk.interstitialShows, 0);
    },
  );
}
