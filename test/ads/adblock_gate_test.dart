import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:portix/core/ads/adblock_detector.dart';
import 'package:portix/core/ads/ads_providers.dart';
import 'package:portix/core/ads/ads_sdk.dart';
import 'package:portix/core/providers.dart';
import 'package:portix/features/ads/adblock_gate.dart';

import '../ui/ui_test_helpers.dart';

/// Detector com veredito mutável e checagem segurável (para simular rede
/// lenta durante a verificação do usuário).
class _MutableDetector implements AdblockDetector {
  _MutableDetector(this.verdict);

  AdblockVerdict verdict;
  Completer<void>? hold;
  int calls = 0;

  @override
  Future<AdblockVerdict> detect() async {
    calls++;
    final Completer<void>? pending = hold;
    if (pending != null) {
      await pending.future;
    }
    return verdict;
  }
}

class _SilentSdk implements AdsSdk {
  @override
  Future<void> init({required String gameId, required bool testMode}) async {}

  @override
  Future<void> loadInterstitial() async {}

  @override
  Future<void> loadRewarded() async {}

  @override
  Future<bool> showInterstitial() async => false;

  @override
  Future<bool> showRewarded() async => false;
}

Future<Widget Function(Widget app)> _wrap(_MutableDetector detector) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return (Widget app) => ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      adsSdkProvider.overrideWithValue(_SilentSdk()),
      adblockDetectorProvider.overrideWithValue(detector),
    ],
    child: app,
  );
}

void main() {
  testWidgets(
    'gate bloqueia o app com veredito blocked e libera após verificação',
    (WidgetTester tester) async {
      final _MutableDetector detector = _MutableDetector(
        AdblockVerdict.blocked,
      );
      final wrap = await _wrap(detector);
      await pumpUi(
        tester,
        child: const AdsGate(child: Text('app-visível')),
        wrap: wrap,
      );
      // Sem checagem (idle) e fora do Android: gate é transparente.
      expect(find.text('app-visível'), findsOneWidget);

      // Entra em modo Android e roda a detecção → veredito bloqueado.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final BuildContext context = tester.element(find.text('app-visível'));
      final ProviderContainer container = ProviderScope.containerOf(context);
      await container.read(adblockProvider.notifier).check();
      await tester.pumpAndSettle();

      expect(find.text('Bloqueador de anúncios detectado'), findsOneWidget);
      expect(find.textContaining('O PORTIX é gratuito'), findsOneWidget);
      // O app NÃO está acessível por baixo do diálogo bloqueante.
      expect(find.text('app-visível'), findsNothing);

      // Usuário desligou o bloqueador: verificar de novo libera o app.
      detector.verdict = AdblockVerdict.allowed;
      await tester.tap(find.text('Verificar novamente'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('app-visível'), findsOneWidget);
      expect(find.text('Bloqueador de anúncios detectado'), findsNothing);
    },
  );

  testWidgets(
    'checagem em pano de fundo não pisca barreira; spinner só na verificação manual',
    (WidgetTester tester) async {
      final _MutableDetector detector = _MutableDetector(AdblockVerdict.blocked)
        ..hold = Completer<void>();
      final wrap = await _wrap(detector);
      await pumpUi(
        tester,
        child: const AdsGate(child: Text('app-visível')),
        wrap: wrap,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final BuildContext context = tester.element(find.text('app-visível'));
      final ProviderContainer container = ProviderScope.containerOf(context);

      // Checagem em pano de fundo em andamento: o app segue usável — nada
      // de flash de bloqueio durante o boot.
      unawaited(container.read(adblockProvider.notifier).check());
      await tester.pump();
      expect(find.text('app-visível'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Veredito sai: barreira substitui o app.
      detector.hold!.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Bloqueador de anúncios detectado'), findsOneWidget);
    },
  );
}
