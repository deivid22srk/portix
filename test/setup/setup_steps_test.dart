import 'package:flutter_test/flutter_test.dart';
import 'package:portix/features/install/permissions.dart';
import 'package:portix/features/install/shizuku.dart';
import 'package:portix/features/setup/setup_steps.dart';

// ============================================================================
// Matriz da spec §5 para o stepper do setup — lógica pura:
// 13+/13-, Shizuku instalado ou não, permissões já concedidas e retomada
// por `setup.doneSteps`.
// ============================================================================

PermissionSnapshot _snapshot({
  bool canInstallApps = false,
  bool notificationsGranted = false,
  ShizukuStatus shizuku = ShizukuStatus.notInstalled,
  int sdkInt = 35,
  bool isAndroid = true,
}) {
  return PermissionSnapshot(
    canInstallApps: canInstallApps,
    notificationsGranted: notificationsGranted,
    shizuku: shizuku,
    sdkInt: sdkInt,
    isAndroid: isAndroid,
  );
}

List<SetupStepId> _ids(List<SetupStepState> steps) =>
    steps.map((SetupStepState s) => s.id).toList();

void main() {
  group('setupStepsFor — quais etapas existem', () {
    test('Android 13+ com tudo pendente: lista completa na ordem fixa', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(),
        isAndroid: true,
        sdkInt: 35,
      );
      expect(_ids(steps), <SetupStepId>[
        SetupStepId.welcome,
        SetupStepId.installApps,
        SetupStepId.notifications,
        SetupStepId.installer,
        SetupStepId.done,
      ]);
    });

    test('Android 12-: etapa de notificações não existe', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(sdkInt: 32),
        isAndroid: true,
        sdkInt: 32,
      );
      expect(_ids(steps), isNot(contains(SetupStepId.notifications)));
      expect(_ids(steps).first, SetupStepId.welcome);
      expect(_ids(steps).last, SetupStepId.done);
    });

    test('Shizuku ausente: etapa de Shizuku não existe', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(shizuku: ShizukuStatus.notInstalled),
        isAndroid: true,
        sdkInt: 35,
      );
      expect(_ids(steps), isNot(contains(SetupStepId.shizuku)));
    });

    test('Shizuku instalado (parado): etapa existe e NÃO está concedida', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(shizuku: ShizukuStatus.installedStopped),
        isAndroid: true,
        sdkInt: 35,
      );
      expect(_ids(steps), contains(SetupStepId.shizuku));
      expect(
        steps
            .firstWhere((SetupStepState s) => s.id == SetupStepId.shizuku)
            .granted,
        isFalse,
      );
    });

    test(
      'Shizuku rodando sem permissão: etapa existe e NÃO está concedida',
      () {
        final List<SetupStepState> steps = setupStepsFor(
          snapshot: _snapshot(shizuku: ShizukuStatus.runningNoPermission),
          isAndroid: true,
          sdkInt: 35,
        );
        expect(
          steps
              .firstWhere((SetupStepState s) => s.id == SetupStepId.shizuku)
              .granted,
          isFalse,
        );
      },
    );

    test('Shizuku ativo: etapa marcada como concedida (pula sozinha)', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(shizuku: ShizukuStatus.active),
        isAndroid: true,
        sdkInt: 35,
      );
      expect(
        steps
            .firstWhere((SetupStepState s) => s.id == SetupStepId.shizuku)
            .granted,
        isTrue,
      );
    });

    test('Boas-vindas e instalador nunca nascem concedidas', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(
          canInstallApps: true,
          notificationsGranted: true,
          shizuku: ShizukuStatus.active,
        ),
        isAndroid: true,
        sdkInt: 35,
      );
      expect(
        steps
            .firstWhere((SetupStepState s) => s.id == SetupStepId.welcome)
            .granted,
        isFalse,
      );
      expect(
        steps
            .firstWhere((SetupStepState s) => s.id == SetupStepId.installer)
            .granted,
        isFalse,
      );
      expect(
        steps
            .firstWhere((SetupStepState s) => s.id == SetupStepId.done)
            .granted,
        isFalse,
      );
    });

    test(
      'Fora do Android: permissões marcadas concedidas e sem notificações',
      () {
        final List<SetupStepState> steps = setupStepsFor(
          snapshot: _snapshot(isAndroid: false, sdkInt: 0),
          isAndroid: false,
          sdkInt: 0,
        );
        expect(
          steps
              .firstWhere((SetupStepState s) => s.id == SetupStepId.installApps)
              .granted,
          isTrue,
        );
        expect(_ids(steps), isNot(contains(SetupStepId.notifications)));
        expect(_ids(steps), isNot(contains(SetupStepId.shizuku)));
      },
    );
  });

  group('setupStepsFor — permissões já concedidas', () {
    test('Instalar apps concedido marca a etapa', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(canInstallApps: true),
        isAndroid: true,
        sdkInt: 35,
      );
      expect(
        steps
            .firstWhere((SetupStepState s) => s.id == SetupStepId.installApps)
            .granted,
        isTrue,
      );
    });

    test('Notificações concedidas marcam a etapa (13+)', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(notificationsGranted: true),
        isAndroid: true,
        sdkInt: 33,
      );
      expect(
        steps
            .firstWhere((SetupStepState s) => s.id == SetupStepId.notifications)
            .granted,
        isTrue,
      );
    });
  });

  group('navegação entre etapas pendentes', () {
    test('firstPendingStepIndex começa na primeira não concluída', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(canInstallApps: true),
        isAndroid: true,
        sdkInt: 35,
      );
      // welcome pendente (nunca nasce concedida) → índice 0.
      expect(firstPendingStepIndex(steps, <String>{}), 0);
      // welcome concluído → pula installApps (granted) → notificações (2).
      expect(firstPendingStepIndex(steps, <String>{'welcome'}), 2);
    });

    test('doneIds do processo morto fazem a retomada da etapa certa', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(sdkInt: 32),
        isAndroid: true,
        sdkInt: 32,
      );
      expect(
        firstPendingStepIndex(steps, <String>{'welcome', 'installApps'}),
        2,
      );
    });

    test('nextPendingStepIndex pula concedidas e para na etapa final', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(
          canInstallApps: true,
          notificationsGranted: true,
          shizuku: ShizukuStatus.active,
          sdkInt: 35,
        ),
        isAndroid: true,
        sdkInt: 35,
      );
      // Depois de welcome (0): pula installApps/notifications/shizuku → installer.
      expect(nextPendingStepIndex(steps, 0, <String>{}), 4);
      // Depois de installer: só resta "Pronto" (etapa final).
      expect(nextPendingStepIndex(steps, 4, <String>{'installer'}), 5);
    });

    test('isStepComplete: granted OU id persistido em doneSteps', () {
      const SetupStepState step = SetupStepState(id: SetupStepId.shizuku);
      expect(isStepComplete(step, <String>{}), isFalse);
      expect(isStepComplete(step, <String>{'shizuku'}), isTrue);
      expect(
        isStepComplete(
          const SetupStepState(id: SetupStepId.installApps, granted: true),
          <String>{},
        ),
        isTrue,
      );
    });

    test('com tudo concluído, a retomada cai na etapa final (Pronto)', () {
      final List<SetupStepState> steps = setupStepsFor(
        snapshot: _snapshot(
          canInstallApps: true,
          notificationsGranted: true,
          shizuku: ShizukuStatus.active,
          sdkInt: 35,
        ),
        isAndroid: true,
        sdkInt: 35,
      );
      expect(
        firstPendingStepIndex(steps, <String>{
          'welcome',
          'installApps',
          'notifications',
          'shizuku',
          'installer',
        }),
        steps.length - 1,
      );
    });
  });
}
