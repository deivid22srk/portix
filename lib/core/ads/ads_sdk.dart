import 'dart:async';

import 'package:unity_ads_plugin/unity_ads_plugin.dart';

import 'ads_config.dart';

/// Falha de contrato do SDK de anúncios (init/load/show).
class AdsSdkException implements Exception {
  const AdsSdkException(this.message);

  final String message;

  @override
  String toString() => 'AdsSdkException($message)';
}

/// Contrato mínimo que o PORTIX usa do Unity Ads. Existir como interface
/// permite testar pacing/estados sem canal nativo (fakes nos testes).
abstract interface class AdsSdk {
  /// Inicializa o SDK; lança [AdsSdkException] quando falha (inclusive
  /// quando o próprio Unity detecta bloqueador: adBlockerDetected).
  Future<void> init({required String gameId, required bool testMode});

  /// Pede fill para o interstitial. Falha (noFill/rede) não é fatal.
  Future<void> loadInterstitial();

  /// Pede fill para o recompensado. Falha (noFill/rede) não é fatal.
  Future<void> loadRewarded();

  /// Exibe o interstitial. `true` = exibido (completo ou pulado).
  Future<bool> showInterstitial();

  /// Exibe o recompensado. `true` SOMENTE se assistido até o fim — pular
  /// não gera recompensa.
  Future<bool> showRewarded();
}

/// Implementação real sobre o plugin `unity_ads_plugin` (canal Android).
class UnityAdsSdk implements AdsSdk {
  @override
  Future<void> init({required String gameId, required bool testMode}) {
    final Completer<void> done = Completer<void>();
    UnityAds.init(
      gameId: gameId,
      testMode: testMode,
      // Builds de CI/scaffold rodam em emuladores do Test Lab: sem anúncios.
      firebaseTestLabMode: FirebaseTestLabMode.disableAds,
      onComplete: () {
        if (!done.isCompleted) {
          done.complete();
        }
      },
      onFailed: (UnityAdsInitializationError error, String message) {
        if (!done.isCompleted) {
          done.completeError(AdsSdkException('${error.name}: $message'));
        }
      },
    );
    return done.future;
  }

  @override
  Future<void> loadInterstitial() => _load(AdsConfig.interstitialPlacement);

  @override
  Future<void> loadRewarded() => _load(AdsConfig.rewardedPlacement);

  @override
  Future<bool> showInterstitial() => _show(AdsConfig.interstitialPlacement);

  @override
  Future<bool> showRewarded() async {
    final Completer<bool> done = Completer<bool>();
    UnityAds.showVideoAd(
      placementId: AdsConfig.rewardedPlacement,
      onStart: (_) {},
      onClick: (_) {},
      // Pular recompensado não gera recompensa — contrato do placement.
      onSkipped: (_) {
        if (!done.isCompleted) {
          done.complete(false);
        }
      },
      onComplete: (_) {
        if (!done.isCompleted) {
          done.complete(true);
        }
      },
      onFailed: (String _, UnityAdsShowError error, String message) {
        if (!done.isCompleted) {
          done.complete(false);
        }
      },
    );
    return done.future;
  }

  Future<void> _load(String placementId) {
    final Completer<void> done = Completer<void>();
    UnityAds.load(
      placementId: placementId,
      onComplete: (String _) {
        if (!done.isCompleted) {
          done.complete();
        }
      },
      onFailed: (String _, UnityAdsLoadError error, String message) {
        if (!done.isCompleted) {
          done.completeError(AdsSdkException('${error.name}: $message'));
        }
      },
    );
    return done.future;
  }

  Future<bool> _show(String placementId) {
    final Completer<bool> done = Completer<bool>();
    UnityAds.showVideoAd(
      placementId: placementId,
      onStart: (_) {},
      onClick: (_) {},
      // Interstitial pulado continua sendo exibição (receita parcial).
      onSkipped: (_) {
        if (!done.isCompleted) {
          done.complete(true);
        }
      },
      onComplete: (_) {
        if (!done.isCompleted) {
          done.complete(true);
        }
      },
      onFailed: (String _, UnityAdsShowError error, String message) {
        if (!done.isCompleted) {
          done.complete(false);
        }
      },
    );
    return done.future;
  }
}
