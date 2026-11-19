import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_strings.dart';
import '../../../app/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/primitives.dart';
import '../../install/models.dart';
import '../../install/permissions.dart';
import '../../install/shizuku.dart';
import '../../setup/setup_widgets.dart';

// ============================================================================
// PORTIX — corpo da categoria "Instalação e Permissões" (/menu/instalacao).
// Porte do bloco recuperado do menu (_InstallerPrefsBlock + _PermissionsPanel,
// scripts/recovered/menu_page_final.dart) reutilizando os widgets prontos do
// setup (InstallerOptionCard / PermissionCard / StatusPill /
// applyInstallerChoice). Rechec das permissões ao voltar das telas do sistema
// e do Shizuku: AppLifecycleListener(onResume) → permissionsProvider.refresh().
// ============================================================================

/// Rótulo de seção (mesmo estilo do fragmento recuperado).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: context.texts.labelSmall?.copyWith(
        color: context.colors.textTertiary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
      ),
    );
  }
}

class InstallSettingsBody extends ConsumerStatefulWidget {
  const InstallSettingsBody({super.key, required this.l10n});

  final L10n l10n;

  @override
  ConsumerState<InstallSettingsBody> createState() =>
      _InstallSettingsBodyState();
}

class _InstallSettingsBodyState extends ConsumerState<InstallSettingsBody> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Rechec das permissões ao voltar das telas do sistema ("Instalar apps
    // desconhecidos", notificações) e do app do Shizuku (servidor/permissão).
    _lifecycle = AppLifecycleListener(onResume: _onResumed);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResumed() {
    unawaited(ref.read(permissionsProvider.notifier).refresh());
    // Mantém o provider observável do Shizuku coerente (o resolvedor do
    // fluxo de instalação lê `ShizukuService.instance.current`).
    unawaited(ref.read(shizukuStatusProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final PermissionSnapshot? snapshot = ref.watch(permissionsProvider);
    final InstallerChoice choice = ref.watch(installPrefsProvider).choice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionLabel(l10n.installerPrefLabel),
        const SizedBox(height: AppSpacing.md),
        _InstallerPrefsBlock(l10n: l10n, choice: choice, snapshot: snapshot),
        const SizedBox(height: AppSpacing.xl),
        _SectionLabel(l10n.permissionsSection),
        const SizedBox(height: AppSpacing.md),
        _PermissionsPanel(l10n: l10n, snapshot: snapshot),
        const SizedBox(height: AppSpacing.md),
        SectionTile(
          icon: Icons.replay_rounded,
          label: l10n.reviewSetup,
          onTap: () => context.push<Object?>('/setup?review=1'),
        ),
      ],
    );
  }
}

/// Bloco "Instalador preferido": Automático (recomendado) / Android /
/// Shizuku com pílula de estado. Shizuku não instalado = card desabilitado.
/// Escolher Shizuku sem permissão dispara o diálogo do Shizuku na hora
/// (applyInstallerChoice — mesmo comportamento do setup).
class _InstallerPrefsBlock extends ConsumerWidget {
  const _InstallerPrefsBlock({
    required this.l10n,
    required this.choice,
    required this.snapshot,
  });

  final L10n l10n;
  final InstallerChoice choice;
  final PermissionSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ShizukuStatus shizuku =
        snapshot?.shizuku ?? ShizukuService.instance.current;
    final bool shizukuAvailable = shizuku.isInstalledOrRunning;

    void select(InstallerChoice next) {
      applyInstallerChoice(ref, next, shizuku);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InstallerOptionCard(
          choice: InstallerChoice.automatic,
          title: l10n.installerAutomatic,
          description: l10n.installerAutomaticHint,
          selected: choice == InstallerChoice.automatic,
          enabled: true,
          status: StatusPill(label: l10n.recommended),
          onTap: () => select(InstallerChoice.automatic),
        ),
        const SizedBox(height: AppSpacing.md),
        InstallerOptionCard(
          choice: InstallerChoice.android,
          title: l10n.installerAndroid,
          description: l10n.installerAndroidHint,
          selected: choice == InstallerChoice.android,
          enabled: true,
          onTap: () => select(InstallerChoice.android),
        ),
        const SizedBox(height: AppSpacing.md),
        InstallerOptionCard(
          choice: InstallerChoice.shizuku,
          title: l10n.installerShizuku,
          description: shizukuAvailable
              ? l10n.installerShizukuHint
              : l10n.installerShizukuUnavailable,
          selected: choice == InstallerChoice.shizuku,
          enabled: shizukuAvailable,
          status: shizukuAvailable
              ? StatusPill(
                  label: switch (shizuku) {
                    ShizukuStatus.active => l10n.statusActive,
                    ShizukuStatus.runningNoPermission =>
                      l10n.statusNeedsPermission,
                    _ => l10n.statusStopped,
                  },
                  tone: shizuku.isActive ? StatusTone.ok : StatusTone.pending,
                )
              : null,
          onTap: shizukuAvailable
              ? () => select(InstallerChoice.shizuku)
              : null,
        ),
      ],
    );
  }
}

/// Painel de permissões (porte de _PermissionsPanel): status e ação de cada
/// linha. Ações: abrir a tela do sistema (instalar apps), pedir notificações
/// e abrir/permitir pelo app do Shizuku.
class _PermissionsPanel extends ConsumerWidget {
  const _PermissionsPanel({required this.l10n, required this.snapshot});

  final L10n l10n;
  final PermissionSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ShizukuStatus shizuku =
        snapshot?.shizuku ?? ShizukuService.instance.current;
    final bool notificationsRelevant = (snapshot?.sdkInt ?? 0) >= 33;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PermissionCard(
          icon: Icons.install_mobile_rounded,
          title: l10n.permInstallAppsTitle,
          description: l10n.permInstallAppsDesc,
          statusLabel: (snapshot?.canInstallApps ?? true)
              ? l10n.statusGranted
              : l10n.statusNotGranted,
          tone: (snapshot?.canInstallApps ?? true)
              ? StatusTone.ok
              : StatusTone.pending,
          actionLabel: (snapshot?.canInstallApps ?? true)
              ? null
              : l10n.actionOpenSettings,
          onAction: (snapshot?.canInstallApps ?? true)
              ? null
              : () => unawaited(PortixPermissions.openInstallAppsSettings()),
        ),
        if (notificationsRelevant) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          PermissionCard(
            icon: Icons.notifications_active_rounded,
            title: l10n.permNotificationsTitle,
            description: l10n.permNotificationsDesc,
            statusLabel: (snapshot?.notificationsGranted ?? true)
                ? l10n.statusGranted
                : l10n.statusNotGranted,
            tone: (snapshot?.notificationsGranted ?? true)
                ? StatusTone.ok
                : StatusTone.pending,
            actionLabel: (snapshot?.notificationsGranted ?? true)
                ? null
                : l10n.actionGrant,
            onAction: (snapshot?.notificationsGranted ?? true)
                ? null
                : () => unawaited(PortixPermissions.requestNotifications()),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        PermissionCard(
          icon: Icons.terminal_rounded,
          title: l10n.permShizukuTitle,
          description: shizuku.isInstalledOrRunning
              ? l10n.permShizukuDesc
              : l10n.shizukuMissingInfo,
          statusLabel: switch (shizuku) {
            ShizukuStatus.active => l10n.statusActive,
            ShizukuStatus.runningNoPermission => l10n.statusNeedsPermission,
            ShizukuStatus.stopped => l10n.statusStopped,
            _ => l10n.shizukuMissing,
          },
          tone: switch (shizuku) {
            ShizukuStatus.active => StatusTone.ok,
            ShizukuStatus.runningNoPermission => StatusTone.pending,
            ShizukuStatus.stopped => StatusTone.pending,
            _ => StatusTone.blocked,
          },
          actionLabel: switch (shizuku) {
            ShizukuStatus.runningNoPermission => l10n.setupShizukuAllow,
            ShizukuStatus.stopped => l10n.actionOpenShizuku,
            _ => null,
          },
          onAction: switch (shizuku) {
            ShizukuStatus.runningNoPermission => () => unawaited(
              ShizukuService.instance.requestPermission(),
            ),
            ShizukuStatus.stopped => () => unawaited(
              ShizukuService.instance.openShizuku(),
            ),
            _ => null,
          },
        ),
      ],
    );
  }
}
