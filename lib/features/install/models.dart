import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers.dart';
import 'shizuku.dart';

// ============================================================================
// PORTIX — plano de instalação: a preferência do usuário (`install.installer`)
// cruzada com o estado real do Shizuku produz o plano que o fluxo executa.
// `resolveInstaller` é puro e coberto por testes (matriz completa da spec).
// ============================================================================

/// Instaladores selecionáveis pelo usuário (persistido em `install.installer`).
enum InstallerChoice { automatic, android, shizuku }

/// Alias da spec §1 — o mesmo enum com o nome usado na documentação.
typedef InstallerPref = InstallerChoice;

/// Motivo pelo qual uma escolha Shizuku não pode seguir agora.
enum BlockedReason {
  /// App instalado, servidor parado.
  shizukuParado,

  /// Servidor rodando, PORTIX sem permissão.
  semPermissao,

  /// App não instalado.
  ausente,
}

/// Tipo de instalador efetivo (o fluxo só diferencia Android × Shizuku).
enum InstallerKind { android, shizuku }

/// Plano resolvido para uma instalação.
sealed class InstallPlan {
  const InstallPlan({this.expectedPackage});

  /// Pacote esperado do APK (cache `install.packages` ou tarefa atual).
  /// Habilita pré-aprovação ANTES do download (Android 14+) e a verificação
  /// de pacote depois do download.
  final String? expectedPackage;

  InstallerKind get kind => switch (this) {
    ShizukuPlan() => InstallerKind.shizuku,
    // BlockedPlan nunca chega ao executor (só é construído por
    // [blockedPlanFor] para a UI); trata como Android por exaustividade.
    AndroidPlan() || BlockedPlan() => InstallerKind.android,
  };
}

/// Instala pelo PackageInstaller/intent do Android (com diálogo).
class AndroidPlan extends InstallPlan {
  const AndroidPlan({
    required this.needsInstallPermission,
    required this.usePreapproval,
    super.expectedPackage,
  });

  /// Falta "Instalar apps desconhecidos" — abre a tela do sistema antes.
  final bool needsInstallPermission;

  /// Android 14+ com pacote conhecido: pré-aprovação antes do download
  /// (nenhum diálogo depois do APK baixado).
  final bool usePreapproval;
}

/// Instala pelo binder do Shizuku (sem diálogo).
class ShizukuPlan extends InstallPlan {
  const ShizukuPlan({this.blocker, super.expectedPackage});

  /// Não-nulo quando o Shizuku está escolhido mas indisponível agora — o
  /// reducer entra em `blocked` com oferta "usar o Android desta vez".
  final ShizukuStatus? blocker;
}

/// Plano bloqueado (uso na UI — ex.: cartão Shizuku desabilitado). O fluxo de
/// instalação usa [ShizukuPlan.blocker] para manter o fallback atômico.
class BlockedPlan extends InstallPlan {
  const BlockedPlan({required this.reason, super.expectedPackage});

  final BlockedReason reason;
}

/// Converte um estado Shizuku em plano bloqueado explícito (helper da UI).
BlockedPlan blockedPlanFor(ShizukuStatus status, {String? expectedPackage}) {
  return BlockedPlan(
    reason: switch (status) {
      ShizukuStatus.notInstalled => BlockedReason.ausente,
      ShizukuStatus.installedStopped => BlockedReason.shizukuParado,
      ShizukuStatus.runningNoPermission => BlockedReason.semPermissao,
      ShizukuStatus.active => BlockedReason.ausente,
    },
    expectedPackage: expectedPackage,
  );
}

/// Matriz de decisão (pura — coberta por testes):
/// - automático + Shizuku ativo → Shizuku;
/// - automático + outro → Android (com permissão/pré-aprovação conforme o caso);
/// - preferência Android → sempre Android (Shizuku ignorado);
/// - preferência Shizuku + ativo → Shizuku;
/// - preferência Shizuku + outro estado → ShizukuPlan(blocker: motivo).
InstallPlan resolveInstaller({
  required InstallerChoice choice,
  required ShizukuStatus shizuku,
  required bool canInstallApps,
  required int sdkInt,
  String? expectedPackage,
}) {
  final bool hasPackage = expectedPackage != null && expectedPackage.isNotEmpty;
  if (choice == InstallerChoice.shizuku ||
      (choice == InstallerChoice.automatic && shizuku.isActive)) {
    if (shizuku.isActive) {
      return ShizukuPlan(expectedPackage: expectedPackage);
    }
    return ShizukuPlan(blocker: shizuku, expectedPackage: expectedPackage);
  }
  final bool needsPermission = !canInstallApps;
  final bool preapproval = sdkInt >= 34 && hasPackage && !needsPermission;
  return AndroidPlan(
    needsInstallPermission: needsPermission,
    usePreapproval: preapproval,
    expectedPackage: expectedPackage,
  );
}

// ---------------------------------------------------------------- preferência

/// Estado persistido do instalador preferido.
class InstallPrefsState {
  const InstallPrefsState({this.choice = InstallerChoice.automatic});

  final InstallerChoice choice;
}

class InstallPrefsController extends Notifier<InstallPrefsState> {
  static const String _key = 'install.installer';

  @override
  InstallPrefsState build() {
    final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
    return InstallPrefsState(choice: _decode(prefs.getString(_key)));
  }

  /// Troca o instalador preferido e persiste imediatamente (a escolha vale
  /// para o próximo toque em "Baixar").
  void setChoice(InstallerChoice next) {
    state = InstallPrefsState(choice: next);
    unawaited(ref.read(sharedPreferencesProvider).setString(_key, next.name));
  }

  static InstallerChoice _decode(String? raw) {
    for (final InstallerChoice choice in InstallerChoice.values) {
      if (choice.name == raw) {
        return choice;
      }
    }
    return InstallerChoice.automatic;
  }
}

final installPrefsProvider =
    NotifierProvider<InstallPrefsController, InstallPrefsState>(
      InstallPrefsController.new,
    );
