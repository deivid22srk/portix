import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/core/providers.dart';
import 'package:portix/features/install/install_flow.dart';
import 'package:portix/features/install/shizuku.dart';
import 'package:portix/features/install/models.dart';
import 'package:portix/features/setup/setup_steps.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// Persistência do fluxo de instalação e do setup (SharedPreferences):
// - `install.installer` (InstallPrefsController.setChoice → string na prefs;
//   recriar o controller restaura a escolha);
// - `setup.version` / `setup.doneSteps` (gravar/ler — contrato do redirect do
//   router e da retomada do processo morto);
// - `install.packages` (cache owner/repo → packageName: rememberKnownPackage /
//   lookupKnownPackage / packageCacheKey).
// ============================================================================

const String kGithubUrl =
    'https://github.com/owner/repo/releases/download/v1/game.apk';
const String kForeignUrl = 'https://exemplo.org/downloads/game.apk';

/// Expõe o [Ref] real do Riverpod para os helpers que o pedem
/// (rememberKnownPackage / lookupKnownPackage).
final Provider<Ref> kRefProvider = Provider<Ref>((Ref ref) => ref);

class _Ctx {
  _Ctx._(this.prefs, this.container, this.ref);

  final SharedPreferences prefs;
  final ProviderContainer container;
  final Ref ref;

  void dispose() => container.dispose();
}

Future<_Ctx> _ctx({Map<String, Object> seed = const <String, Object>{}}) async {
  SharedPreferences.setMockInitialValues(seed);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  final Ref ref = container.read(kRefProvider);
  return _Ctx._(prefs, container, ref);
}

/// Drena os microtasks das escritas `unawaited` das prefs (nada de sleep).
Future<void> _flush() async {
  for (int i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('install.installer — escolha do instalador', () {
    test('default é automático quando a chave não existe', () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);

      expect(c.prefs.getString('install.installer'), isNull);
      expect(
        c.container.read(installPrefsProvider).choice,
        InstallerChoice.automatic,
      );
    });

    test('setChoice grava a string imediatamente na prefs', () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);

      c.container
          .read(installPrefsProvider.notifier)
          .setChoice(InstallerChoice.shizuku);
      expect(
        c.container.read(installPrefsProvider).choice,
        InstallerChoice.shizuku,
      );
      await _flush();
      expect(c.prefs.getString('install.installer'), 'shizuku');

      c.container
          .read(installPrefsProvider.notifier)
          .setChoice(InstallerChoice.android);
      await _flush();
      expect(c.prefs.getString('install.installer'), 'android');
    });

    test('recriar o controller (novo container) restaura a escolha gravada', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final ProviderContainer primeiro = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      primeiro
          .read(installPrefsProvider.notifier)
          .setChoice(InstallerChoice.shizuku);
      await _flush();
      primeiro.dispose();

      // "Reinício do processo": o controller novo relê a MESMA prefs.
      final ProviderContainer segundo = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(segundo.dispose);
      expect(
        segundo.read(installPrefsProvider).choice,
        InstallerChoice.shizuku,
        reason: 'estado restaurado de install.installer',
      );
    });

    test('valor desconhecido gravado na prefs cai no automático (decode seguro)',
        () async {
      final _Ctx c = await _ctx(seed: <String, Object>{'install.installer': 'root'});
      addTearDown(c.dispose);
      expect(
        c.container.read(installPrefsProvider).choice,
        InstallerChoice.automatic,
      );
    });

    test('ciclo completo volta ao automático e persiste', () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);
      final InstallPrefsController controller =
          c.container.read(installPrefsProvider.notifier);

      controller.setChoice(InstallerChoice.shizuku);
      controller.setChoice(InstallerChoice.android);
      controller.setChoice(InstallerChoice.automatic);
      await _flush();

      expect(
        c.container.read(installPrefsProvider).choice,
        InstallerChoice.automatic,
      );
      expect(c.prefs.getString('install.installer'), 'automatic');
    });
  });

  group('setup.version e setup.doneSteps', () {
    test('constantes do contrato', () {
      expect(kSetupVersionKey, 'setup.version');
      expect(kSetupDoneStepsKey, 'setup.doneSteps');
      expect(kSetupVersionValue, 1);
    });

    test('conclusão grava int 1 + lista de ids e leitura confere (round-trip)',
        () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);

      // Mesmas escritas de SetupPage._finish().
      await c.prefs.setInt(kSetupVersionKey, kSetupVersionValue);
      await c.prefs.setStringList(kSetupDoneStepsKey, <String>[
        'welcome',
        'installApps',
        'installer',
      ]);

      expect(c.prefs.getInt(kSetupVersionKey), 1);
      // O redirect usa prefs.get(): int OU string contam como versão gravada.
      expect(c.prefs.get(kSetupVersionKey), isNotNull);
      expect(c.prefs.getStringList(kSetupDoneStepsKey), <String>[
        'welcome',
        'installApps',
        'installer',
      ]);
    });

    test('processo morto retoma: valores pré-gravados reaparecem em prefs novas',
        () async {
      final _Ctx c = await _ctx(seed: <String, Object>{
        'setup.version': 1,
        'setup.doneSteps': <String>['welcome'],
      });
      addTearDown(c.dispose);

      expect(c.prefs.getInt(kSetupVersionKey), 1);
      expect(c.prefs.getStringList(kSetupDoneStepsKey), <String>['welcome']);
    });

    test('setup pendente = versão ausente (redirect levaria ao /setup)', () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);

      expect(c.prefs.get(kSetupVersionKey), isNull);
      expect(c.prefs.getStringList(kSetupDoneStepsKey), isNull);

      await c.prefs.setInt(kSetupVersionKey, kSetupVersionValue);
      expect(c.prefs.get(kSetupVersionKey), isNotNull);
    });
  });

  group('install.packages — cache de pacote por port', () {
    test('packageCacheKey: GitHub vira owner/repo; URL estranha vira a própria URL',
        () {
      expect(packageCacheKey(kGithubUrl), 'owner/repo');
      expect(packageCacheKey(kForeignUrl), kForeignUrl);
    });

    test('rememberKnownPackage grava e lookupKnownPackage lê (round-trip)', () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);

      rememberKnownPackage(c.ref, kGithubUrl, 'com.example.game');
      await _flush();

      final Map<Object?, Object?> cached =
          jsonDecode(c.prefs.getString('install.packages')!) as Map<Object?, Object?>;
      expect(cached['owner/repo'], 'com.example.game');
      expect(lookupKnownPackage(c.ref, kGithubUrl), 'com.example.game');
    });

    test('porta sem GitHub memoriza pela URL completa', () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);

      rememberKnownPackage(c.ref, kForeignUrl, 'org.exemplo.jogo');
      await _flush();

      expect(lookupKnownPackage(c.ref, kForeignUrl), 'org.exemplo.jogo');
      expect(lookupKnownPackage(c.ref, kGithubUrl), isNull);
    });

    test('novos remembers preservam as entradas anteriores (merge)', () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);

      rememberKnownPackage(c.ref, kGithubUrl, 'com.example.game');
      await _flush();
      rememberKnownPackage(c.ref, kForeignUrl, 'org.exemplo.jogo');
      await _flush();

      final Map<Object?, Object?> cached =
          jsonDecode(c.prefs.getString('install.packages')!) as Map<Object?, Object?>;
      expect(cached, <Object?, Object?>{
        'owner/repo': 'com.example.game',
        kForeignUrl: 'org.exemplo.jogo',
      });
    });

    test('atualizar o pacote do mesmo port sobrescreve a entrada', () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);

      rememberKnownPackage(c.ref, kGithubUrl, 'com.antigo.jogo');
      await _flush();
      rememberKnownPackage(c.ref, kGithubUrl, 'com.novo.jogo');
      await _flush();

      expect(lookupKnownPackage(c.ref, kGithubUrl), 'com.novo.jogo');
    });

    test('chave inexistente e cache vazio devolvem null', () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);
      expect(lookupKnownPackage(c.ref, kGithubUrl), isNull);
    });

    test(
      'cache corrompido é fail-safe: lookup null e remember não grava (no-op)',
      () async {
        final _Ctx c = await _ctx(
          seed: <String, Object>{'install.packages': 'isto não é json'},
        );
        addTearDown(c.dispose);

        expect(lookupKnownPackage(c.ref, kGithubUrl), isNull);

        // rememberKnownPackage falha ao decodificar o lixo e desiste em
        // silêncio (cache é otimização — nunca quebra o fluxo).
        rememberKnownPackage(c.ref, kGithubUrl, 'com.example.game');
        await _flush();
        expect(c.prefs.getString('install.packages'), 'isto não é json');
        expect(lookupKnownPackage(c.ref, kGithubUrl), isNull);
      },
    );

    test('argumentos vazios são ignorados (no-op seguro)', () async {
      final _Ctx c = await _ctx();
      addTearDown(c.dispose);

      rememberKnownPackage(c.ref, '', 'com.example.game');
      rememberKnownPackage(c.ref, kGithubUrl, '');
      await _flush();
      expect(c.prefs.getString('install.packages'), isNull);
    });

    test('cache alimenta o plano: expectedPackage habilita pré-aprovação', () async {
      final _Ctx c = await _ctx(seed: <String, Object>{
        'install.packages':
            jsonEncode(<String, String>{'owner/repo': 'com.example.game'}),
      });
      addTearDown(c.dispose);

      final String? known = lookupKnownPackage(c.ref, kGithubUrl);
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.automatic,
        shizuku: ShizukuStatus.notInstalled,
        canInstallApps: true,
        sdkInt: 34,
        expectedPackage: known,
      );
      expect(plan, isA<AndroidPlan>());
      expect((plan as AndroidPlan).usePreapproval, isTrue);
      expect(plan.expectedPackage, 'com.example.game');
    });
  });
}
