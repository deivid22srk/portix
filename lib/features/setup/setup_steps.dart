import 'package:flutter/foundation.dart';

import '../install/permissions.dart';
import '../install/shizuku.dart';

// ============================================================================
// PORTIX — lógica PURA do stepper do setup inicial (sem widgets): decide
// quais etapas existem para um snapshot de permissões e quais já estão
// satisfeitas. Toda decisão é coberta por testes puros (matriz da spec §5):
// - notificações só existem no Android 13+ (sdkInt >= 33);
// - Shizuku só entra quando instalado (status != notInstalled);
// - etapa já concedida é marcada como granted (a tela marca/pula sozinha).
// Os ids persistidos em `setup.doneSteps` são os nomes de [SetupStepId].
// ============================================================================

/// Ids das etapas do setup, na ordem de exibição.
enum SetupStepId {
  welcome,
  installApps,
  notifications,
  shizuku,
  installer,
  done,
}

/// Uma etapa do setup com o estado derivado do snapshot.
@immutable
class SetupStepState {
  const SetupStepState({required this.id, this.granted = false});

  final SetupStepId id;

  /// Requisito da etapa já satisfeito no aparelho — a tela marca como
  /// concluída e pula sem interação do usuário.
  final bool granted;

  @override
  String toString() => 'SetupStepState(${id.name}, granted: $granted)';
}

/// Android 13 (Tiramisu) — primeira versão com POST_NOTIFICATIONS.
const int kNotificationsSdk = 33;

// Chaves de persistência do setup (SharedPreferences — spec §2).
const String kSetupVersionKey = 'setup.version';
const String kSetupDoneStepsKey = 'setup.doneSteps';

/// Versão do setup gravada ao concluir; ausente = setup pendente.
const int kSetupVersionValue = 1;

/// Etapas aplicáveis ao snapshot, na ordem fixa do fluxo:
/// boas-vindas → instalar apps → notificações (13+) → Shizuku (instalado) →
/// instalador preferido → pronto.
///
/// [isAndroid]/[sdkInt] vêm explícitos para o teste puro não depender de
/// plataforma; no app passe `snapshot.isAndroid`/`snapshot.sdkInt`.
List<SetupStepState> setupStepsFor({
  required PermissionSnapshot snapshot,
  required bool isAndroid,
  required int sdkInt,
}) {
  final ShizukuStatus shizuku = snapshot.shizuku;
  return <SetupStepState>[
    // Boas-vindas nunca nasce concedida: o usuário fecha com "Começar".
    const SetupStepState(id: SetupStepId.welcome),
    SetupStepState(
      id: SetupStepId.installApps,
      granted: snapshot.canInstallApps || !isAndroid,
    ),
    if (sdkInt >= kNotificationsSdk)
      SetupStepState(
        id: SetupStepId.notifications,
        granted: snapshot.notificationsGranted || !isAndroid,
      ),
    if (shizuku != ShizukuStatus.notInstalled)
      SetupStepState(id: SetupStepId.shizuku, granted: shizuku.isActive),
    const SetupStepState(id: SetupStepId.installer),
    const SetupStepState(id: SetupStepId.done),
  ];
}

/// Etapa concluída = requisito concedido agora OU marcada pelo usuário antes
/// (ids persistidos em `setup.doneSteps`).
bool isStepComplete(SetupStepState step, Set<String> doneIds) =>
    step.granted || doneIds.contains(step.id.name);

/// Primeira etapa pendente (concedida ou já concluída não conta). Se todas
/// estão prontas, cai na etapa final ("Pronto").
int firstPendingStepIndex(List<SetupStepState> steps, Set<String> doneIds) {
  for (int i = 0; i < steps.length; i++) {
    if (!isStepComplete(steps[i], doneIds)) {
      return i;
    }
  }
  return steps.length - 1;
}

/// Próxima etapa pendente depois de [fromIndex] — pula as concedidas em
/// tempo real (ex.: usuário concedeu notificações e volta de uma etapa
/// anterior). Sem pendente, fica na etapa final.
int nextPendingStepIndex(
  List<SetupStepState> steps,
  int fromIndex,
  Set<String> doneIds,
) {
  for (int i = fromIndex + 1; i < steps.length; i++) {
    if (!isStepComplete(steps[i], doneIds)) {
      return i;
    }
  }
  return steps.length - 1;
}
