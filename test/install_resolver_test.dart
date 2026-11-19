import 'package:flutter_test/flutter_test.dart';
import 'package:portix/features/install/models.dart';
import 'package:portix/features/install/shizuku.dart';

// ============================================================================
// Matriz COMPLETA de resolveInstaller (models.dart) — comportamento da spec:
// - automático + Shizuku ativo → ShizukuPlan;
// - automático + Shizuku em outro estado → ShizukuPlan(blocker: motivo);
// - preferência Android → SEMPRE AndroidPlan (estado do Shizuku é ignorado);
// - preferência Shizuku → ShizukuPlan ativo ou com blocker;
// - fallback "fora do Android" (snapshot desktop): AndroidPlan sem
//   permissão e sem pré-aprovação;
// - canInstallApps=false → precisa de permissão e NUNCA usa pré-aprovação
//   (pré-aprovação exige permissão já concedida);
// - pré-aprovação só em Android 14+ (sdkInt >= 34) com pacote conhecido.
//
// Cada caso assere o TIPO EXATO do plano (selado) e os campos do blocker.
// ============================================================================

const String kPkg = 'com.example.game';

void main() {
  InstallerPlanAssertions planOf(InstallPlan plan) =>
      InstallerPlanAssertions(plan);

  group('automático × 4 estados do Shizuku', () {
    test('Shizuku ativo → ShizukuPlan SEM blocker (instalação silenciosa)', () {
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.automatic,
        shizuku: ShizukuStatus.active,
        canInstallApps: true,
        sdkInt: 34,
        expectedPackage: kPkg,
      );
      final InstallerPlanAssertions p = planOf(plan);
      p.expectShizuku(blocker: isNull);
      expect(plan.kind, InstallerKind.shizuku);
      expect(plan.expectedPackage, kPkg);
    });

    test('Shizuku instalado parado → AndroidPlan (automático cai para Android)', () {
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.automatic,
        shizuku: ShizukuStatus.installedStopped,
        canInstallApps: true,
        sdkInt: 34,
        expectedPackage: kPkg,
      );
      // Missão: "Automático: Shizuku ATIVO → Shizuku; senão → Android" — sem
      // blocker: o fallback é silencioso e usa o instalador do Android.
      planOf(plan).expectAndroid(usePreapproval: true, needsInstallPermission: false);
      expect(plan.expectedPackage, kPkg);
    });

    test(
      'Shizuku rodando sem permissão → AndroidPlan (automático cai para Android)',
      () {
        final InstallPlan plan = resolveInstaller(
          choice: InstallerChoice.automatic,
          shizuku: ShizukuStatus.runningNoPermission,
          canInstallApps: true,
          sdkInt: 34,
        );
        planOf(plan).expectAndroid(usePreapproval: false, needsInstallPermission: false);
      },
    );

    test('Shizuku ausente → AndroidPlan (automático cai para Android)', () {
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.automatic,
        shizuku: ShizukuStatus.notInstalled,
        canInstallApps: true,
        sdkInt: 34,
      );
      planOf(plan).expectAndroid(usePreapproval: false, needsInstallPermission: false);
    });
  });

  group('preferência Android × 4 estados do Shizuku', () {
    for (final ShizukuStatus status in ShizukuStatus.values) {
      test('Android pref + Shizuku $status → AndroidPlan ignora o Shizuku', () {
        final InstallPlan plan = resolveInstaller(
          choice: InstallerChoice.android,
          shizuku: status,
          canInstallApps: true,
          sdkInt: 34,
          expectedPackage: kPkg,
        );
        final InstallerPlanAssertions p = planOf(plan);
        p.expectAndroid(needsInstallPermission: false, usePreapproval: true);
        expect(plan.expectedPackage, kPkg);
        expect(plan.kind, InstallerKind.android);
      });
    }

    test(
      'Android pref sem permissão → needsInstallPermission e SEM pré-aprovação',
      () {
        final InstallPlan plan = resolveInstaller(
          choice: InstallerChoice.android,
          shizuku: ShizukuStatus.active,
          canInstallApps: false,
          sdkInt: 35,
          expectedPackage: kPkg,
        );
        planOf(plan).expectAndroid(
          needsInstallPermission: true,
          usePreapproval: false,
        );
      },
    );
  });

  group('preferência Shizuku × 4 estados do Shizuku', () {
    test('ativo → ShizukuPlan sem blocker', () {
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.shizuku,
        shizuku: ShizukuStatus.active,
        canInstallApps: false, // irrelevante para Shizuku
        sdkInt: 0,
        expectedPackage: kPkg,
      );
      planOf(plan).expectShizuku(blocker: isNull);
      expect(plan.kind, InstallerKind.shizuku);
      expect(plan.expectedPackage, kPkg);
    });

    test('installedStopped → ShizukuPlan(blocker: installedStopped)', () {
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.shizuku,
        shizuku: ShizukuStatus.installedStopped,
        canInstallApps: true,
        sdkInt: 34,
      );
      planOf(plan).expectShizuku(blocker: ShizukuStatus.installedStopped);
    });

    test('runningNoPermission → ShizukuPlan(blocker: runningNoPermission)', () {
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.shizuku,
        shizuku: ShizukuStatus.runningNoPermission,
        canInstallApps: true,
        sdkInt: 34,
      );
      planOf(plan).expectShizuku(blocker: ShizukuStatus.runningNoPermission);
    });

    test('notInstalled → ShizukuPlan(blocker: notInstalled)', () {
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.shizuku,
        shizuku: ShizukuStatus.notInstalled,
        canInstallApps: true,
        sdkInt: 34,
      );
      planOf(plan).expectShizuku(blocker: ShizukuStatus.notInstalled);
    });
  });

  group('fora do Android (snapshot desktop — isAndroid=false)', () {
    test(
      'automatic + desktop → AndroidPlan sem permissão e sem pré-aprovação',
      () {
        // O resolvedor não recebe isAndroid: fora do Android o chamador usa
        // PermissionSnapshot.desktop (canInstallApps=true, shizuku
        // notInstalled, sdkInt=0) — o plano resultante é o clássico.
        final InstallPlan plan = resolveInstaller(
          choice: InstallerChoice.automatic,
          shizuku: ShizukuStatus.notInstalled,
          canInstallApps: true,
          sdkInt: 0,
          expectedPackage: kPkg,
        );
        planOf(plan).expectAndroid(
          needsInstallPermission: false,
          usePreapproval: false,
        );
      },
    );

    test('shizuku pref + desktop (notInstalled) → plano bloqueado', () {
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.shizuku,
        shizuku: ShizukuStatus.notInstalled,
        canInstallApps: true,
        sdkInt: 0,
      );
      planOf(plan).expectShizuku(blocker: ShizukuStatus.notInstalled);
    });
  });

  group('canInstallApps=false', () {
    test(
      'automático sem permissão → AndroidPlan pede permissão e nunca pré-aprova',
      () {
        // Mesmo com pacote conhecido e Android 14+, a pré-aprovação exige a
        // permissão de instalar já concedida.
        final InstallPlan plan = resolveInstaller(
          choice: InstallerChoice.automatic,
          shizuku: ShizukuStatus.notInstalled,
          canInstallApps: false,
          sdkInt: 34,
          expectedPackage: kPkg,
        );
        planOf(plan).expectAndroid(
          needsInstallPermission: true,
          usePreapproval: false,
        );
        expect(plan.expectedPackage, kPkg);
      },
    );

    test(
      'automático com permissão e Shizuku parado → AndroidPlan SEM blocker',
      () {
        final InstallPlan plan = resolveInstaller(
          choice: InstallerChoice.automatic,
          shizuku: ShizukuStatus.installedStopped,
          canInstallApps: false,
          sdkInt: 21,
        );
        planOf(plan).expectAndroid(
          needsInstallPermission: true,
          usePreapproval: false,
        );
      },
    );
  });

  group('expectedPackage variando (pré-aprovação Android 14+)', () {
    InstallPlan resolve({String? package = kPkg, int sdkInt = 34}) =>
        resolveInstaller(
          choice: InstallerChoice.automatic,
          shizuku: ShizukuStatus.notInstalled,
          canInstallApps: true,
          sdkInt: sdkInt,
          expectedPackage: package,
        );

    test('pacote + Android 14 → pré-aprovação', () {
      planOf(resolve()).expectAndroid(
        needsInstallPermission: false,
        usePreapproval: true,
      );
    });

    test('pacote + Android 13 (33) → sem pré-aprovação (diálogo no commit)', () {
      planOf(resolve(sdkInt: 33)).expectAndroid(
        needsInstallPermission: false,
        usePreapproval: false,
      );
    });

    test('pacote nulo + Android 14 → sem pré-aprovação', () {
      planOf(resolve(package: null)).expectAndroid(
        needsInstallPermission: false,
        usePreapproval: false,
      );
    });

    test('pacote vazio é tratado como desconhecido → sem pré-aprovação', () {
      planOf(resolve(package: '')).expectAndroid(
        needsInstallPermission: false,
        usePreapproval: false,
      );
    });

    test('pacote é repassado ao plano Android (verificação pós-download)', () {
      expect(resolve().expectedPackage, kPkg);
    });

    test('pacote é repassado ao ShizukuPlan bloqueado', () {
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.shizuku,
        shizuku: ShizukuStatus.installedStopped,
        canInstallApps: true,
        sdkInt: 34,
        expectedPackage: kPkg,
      );
      final ShizukuPlan shizuku = planOf(plan).expectShizuku(
        blocker: ShizukuStatus.installedStopped,
      );
      expect(shizuku.expectedPackage, kPkg);
    });

    test('pacote é repassado ao ShizukuPlan ativo', () {
      final InstallPlan plan = resolveInstaller(
        choice: InstallerChoice.shizuku,
        shizuku: ShizukuStatus.active,
        canInstallApps: true,
        sdkInt: 34,
        expectedPackage: kPkg,
      );
      expect(planOf(plan).expectShizuku(blocker: isNull).expectedPackage, kPkg);
    });
  });

  group('blockedPlanFor — helper da UI', () {
    test('mapeia cada estado para o motivo correto', () {
      expect(
        blockedPlanFor(ShizukuStatus.notInstalled).reason,
        BlockedReason.ausente,
      );
      expect(
        blockedPlanFor(ShizukuStatus.installedStopped).reason,
        BlockedReason.shizukuParado,
      );
      expect(
        blockedPlanFor(ShizukuStatus.runningNoPermission).reason,
        BlockedReason.semPermissao,
      );
      expect(
        blockedPlanFor(ShizukuStatus.active).reason,
        BlockedReason.ausente,
      );
    });

    test(
      'BlockedPlan é AndroidPlan no kind (fluxo só diferencia Android×Shizuku)',
      () {
        expect(
          blockedPlanFor(ShizukuStatus.installedStopped).kind,
          InstallerKind.android,
        );
        expect(
          blockedPlanFor(
            ShizukuStatus.installedStopped,
            expectedPackage: kPkg,
          ).expectedPackage,
          kPkg,
        );
      },
    );
  });

  group('contratos da hierarquia selada', () {
    test('alias InstallerPref = InstallerChoice', () {
      const InstallerPref pref = InstallerChoice.shizuku;
      expect(pref, InstallerChoice.shizuku);
    });

    test('ShizukuPlan.blocker null → plano executável (não bloqueia)', () {
      const InstallPlan plan = ShizukuPlan(expectedPackage: kPkg);
      expect((plan as ShizukuPlan).blocker, isNull);
    });

    test('AndroidPlan expõe os flags que o fluxo consome', () {
      const AndroidPlan plan = AndroidPlan(
        needsInstallPermission: true,
        usePreapproval: false,
        expectedPackage: kPkg,
      );
      expect(plan.needsInstallPermission, isTrue);
      expect(plan.usePreapproval, isFalse);
      expect(plan.kind, InstallerKind.android);
    });
  });
}

/// Ajudante de asserção com tipo exato: falha se o resolvedor devolver um
/// tipo de plano diferente do esperado (matriz da spec não pode "vazar").
class InstallerPlanAssertions {
  InstallerPlanAssertions(this.plan);

  final InstallPlan plan;

  ShizukuPlan expectShizuku({Object? blocker = _unset}) {
    expect(plan, isA<ShizukuPlan>(), reason: 'esperava ShizukuPlan: $plan');
    final ShizukuPlan shizuku = plan as ShizukuPlan;
    if (!identical(blocker, _unset)) {
      if (blocker == null) {
        expect(shizuku.blocker, isNull, reason: 'blocker devia ser nulo');
      } else {
        expect(shizuku.blocker, blocker, reason: 'blocker divergente');
      }
    }
    return shizuku;
  }

  AndroidPlan expectAndroid({
    required bool needsInstallPermission,
    required bool usePreapproval,
  }) {
    expect(plan, isA<AndroidPlan>(), reason: 'esperava AndroidPlan: $plan');
    final AndroidPlan android = plan as AndroidPlan;
    expect(
      android.needsInstallPermission,
      needsInstallPermission,
      reason: 'needsInstallPermission divergente',
    );
    expect(
      android.usePreapproval,
      usePreapproval,
      reason: 'usePreapproval divergente',
    );
    return android;
  }
}

const Object _unset = Object();
