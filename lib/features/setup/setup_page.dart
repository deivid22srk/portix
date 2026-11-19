import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/primitives.dart';
import '../install/models.dart';
import '../install/permissions.dart';
import '../install/shizuku.dart';
import 'setup_steps.dart';
import 'setup_widgets.dart';

// ============================================================================
// PORTIX — tela de configuração inicial (rota de topo `/setup`, fora do
// MainShell). Stepper com progresso persistido (`setup.doneSteps` +
// `setup.version`), rechecagem ao voltar das telas do sistema
// (AppLifecycleListener → permissionsProvider.refresh() → a etapa concedida
// avança sozinha), "Agora não" sempre disponível e modo revisão
// (`/setup?review=1`), que não grava nada e só fecha.
//
// Sem flash: esta página só é aberta quando o setup está pendente — o
// redirect do routerProvider decide ANTES de construir qualquer página.
// ============================================================================

class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key, this.review = false});

  /// Modo revisão (query `review=1`): não grava versão nem doneSteps;
  /// o botão de sair vira "Fechar" e volta para onde foi aberto.
  final bool review;

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  late final AppLifecycleListener _lifecycle;
  late Set<String> _doneIds;
  int _index = 0;
  bool _indexReady = false;
  bool _finished = false;

  bool get _review => widget.review;

  @override
  void initState() {
    super.initState();
    _doneIds =
        (ref
                    .read(sharedPreferencesProvider)
                    .getStringList(kSetupDoneStepsKey) ??
                const <String>[])
            .toSet();
    // Rechec das permissões ao voltar das telas do sistema (e do Shizuku).
    _lifecycle = AppLifecycleListener(onResume: _onResumed);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResumed() {
    unawaited(ref.read(permissionsProvider.notifier).refresh());
  }

  List<SetupStepState> _stepsFor(PermissionSnapshot? snapshot) {
    final PermissionSnapshot snap = snapshot ?? PermissionSnapshot.desktop;
    return setupStepsFor(
      snapshot: snap,
      isAndroid: snap.isAndroid,
      sdkInt: snap.sdkInt,
    );
  }

  void _onSnapshotChanged(PermissionSnapshot? snapshot) {
    if (!mounted || _finished || snapshot == null) {
      return;
    }
    final List<SetupStepState> steps = _stepsFor(snapshot);
    if (_index >= steps.length) {
      return;
    }
    final SetupStepState step = steps[_index];
    if (step.granted && !_doneIds.contains(step.id.name)) {
      // Rechecagem confirmou o requisito da etapa atual: marca e avança
      // sozinha (ex.: voltou das configurações com a permissão dada).
      _completeAndAdvance(step.id, steps);
    } else {
      setState(() {}); // atualiza pílulas/estados da etapa atual
    }
  }

  void _completeAndAdvance(SetupStepId id, List<SetupStepState> steps) {
    setState(() {
      _doneIds.add(id.name);
      _index = nextPendingStepIndex(steps, _index, _doneIds);
    });
    _persistDoneSteps();
  }

  /// Progresso da etapa gravado a cada avanço: processo morto retoma da
  /// etapa certa (`setup.version` só é gravado ao concluir/sair).
  void _persistDoneSteps() {
    if (_review) {
      return;
    }
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setStringList(kSetupDoneStepsKey, _doneIds.toList()),
    );
  }

  /// Conclui (ou encerra) o setup: grava a versão para o redirect não
  /// trazer o usuário de volta e vai para /home substituindo a rota.
  Future<void> _finish() async {
    if (_finished) {
      return;
    }
    _finished = true;
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    if (!_review) {
      await prefs.setInt(kSetupVersionKey, kSetupVersionValue);
      await prefs.setStringList(kSetupDoneStepsKey, _doneIds.toList());
    }
    if (!mounted) {
      return;
    }
    context.go('/home');
  }

  /// "Agora não" (sempre disponível): no modo normal encerra o setup gravando
  /// a versão (o app nunca fica preso no setup); na revisão apenas fecha.
  Future<void> _onSecondary() async {
    if (_review) {
      if (!mounted) {
        return;
      }
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
      return;
    }
    await _finish();
  }

  void _goBack() {
    if (_index > 0) {
      setState(() => _index -= 1);
    }
  }

  Future<void> _onPrimary() async {
    final PermissionSnapshot? snapshot = ref.read(permissionsProvider);
    final List<SetupStepState> steps = _stepsFor(snapshot);
    if (_index >= steps.length) {
      return;
    }
    final SetupStepState step = steps[_index];
    switch (step.id) {
      case SetupStepId.welcome:
      case SetupStepId.installer:
        _completeAndAdvance(step.id, steps);
      case SetupStepId.installApps:
        if (step.granted) {
          _completeAndAdvance(step.id, steps);
        } else {
          await PortixPermissions.openInstallAppsSettings();
        }
      case SetupStepId.notifications:
        if (step.granted) {
          _completeAndAdvance(step.id, steps);
        } else {
          final bool granted = await PortixPermissions.requestNotifications();
          if (!mounted) {
            return;
          }
          if (granted) {
            _completeAndAdvance(step.id, steps);
          } else {
            unawaited(ref.read(permissionsProvider.notifier).refresh());
          }
        }
      case SetupStepId.shizuku:
        final ShizukuStatus status =
            snapshot?.shizuku ?? ShizukuStatus.notInstalled;
        if (status.isActive) {
          _completeAndAdvance(step.id, steps);
        } else if (status == ShizukuStatus.runningNoPermission) {
          await ShizukuService.instance.requestPermission();
        } else {
          await ShizukuService.instance.openShizuku();
        }
      case SetupStepId.done:
        await _finish();
    }
  }

  String _stepTitle(L10n l10n, SetupStepId id) => switch (id) {
    SetupStepId.welcome => l10n.setupWelcomeTitle,
    SetupStepId.installApps => l10n.setupInstallTitle,
    SetupStepId.notifications => l10n.setupNotificationsTitle,
    SetupStepId.shizuku => l10n.setupShizukuTitle,
    SetupStepId.installer => l10n.setupInstallerTitle,
    SetupStepId.done => l10n.setupDoneTitle,
  };

  String _primaryLabel(
    L10n l10n,
    SetupStepState step,
    PermissionSnapshot? snapshot,
  ) {
    final bool granted = step.granted;
    return switch (step.id) {
      SetupStepId.welcome => l10n.setupStart,
      SetupStepId.installApps =>
        granted ? l10n.continueAction : l10n.setupAllowInstall,
      SetupStepId.notifications =>
        granted ? l10n.continueAction : l10n.setupAllowNotifications,
      SetupStepId.shizuku => _shizukuPrimaryLabel(l10n, snapshot),
      SetupStepId.installer => l10n.continueAction,
      SetupStepId.done => _review ? l10n.close : l10n.setupStart,
    };
  }

  String _shizukuPrimaryLabel(L10n l10n, PermissionSnapshot? snapshot) {
    final ShizukuStatus status =
        snapshot?.shizuku ?? ShizukuStatus.notInstalled;
    if (status.isActive) {
      return l10n.continueAction;
    }
    if (status == ShizukuStatus.runningNoPermission) {
      return l10n.setupShizukuAllow;
    }
    return l10n.setupShizukuOpen;
  }

  // ------------------------------------------------------------ visual

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final PermissionSnapshot? snapshot = ref.watch(permissionsProvider);
    ref.listen<PermissionSnapshot?>(permissionsProvider, (
      PermissionSnapshot? _,
      PermissionSnapshot? next,
    ) {
      _onSnapshotChanged(next);
    });
    final List<SetupStepState> steps = _stepsFor(snapshot);
    if (!_indexReady && snapshot != null) {
      // Retoma da etapa certa (processo morto: doneSteps já persistidos).
      _indexReady = true;
      _index = firstPendingStepIndex(steps, _doneIds);
    }
    final int index = _index.clamp(0, steps.length - 1).toInt();
    final SetupStepState step = steps[index];

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          _goBack();
        }
      },
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(context, l10n, steps, index),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: l10n.setupAnnounce(
                    index + 1,
                    steps.length,
                    _stepTitle(l10n, step.id),
                  ),
                  // Transição sutil entre etapas; zero com reduced motion.
                  child: AnimatedSwitcher(
                    duration: AppMotion.of(context, AppMotion.base),
                    switchInCurve: AppMotion.emphasized,
                    switchOutCurve: AppMotion.out,
                    child: KeyedSubtree(
                      key: ValueKey<SetupStepId>(step.id),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screen,
                          AppSpacing.lg,
                          AppSpacing.screen,
                          AppSpacing.xl,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AppBreakpoints.tablet,
                            ),
                            child: _buildStepBody(
                              context,
                              l10n,
                              snapshot,
                              step,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(top: false, child: _buildFooter(l10n, snapshot, step)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    L10n l10n,
    List<SetupStepState> steps,
    int index,
  ) {
    final double progress = steps.length <= 1 ? 1 : index / (steps.length - 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md,
        AppSpacing.screen,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (index > 0)
                GlassCircleButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: l10n.tooltipBack,
                  onTap: _goBack,
                )
              else
                const SizedBox(width: AppSpacing.circleButton),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.setupTitle,
                  style: context.texts.titleLarge?.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          GradientProgress(
            value: progress,
            height: AppSpacing.xs,
            semanticLabel: l10n.setupStepOf(index + 1, steps.length),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.setupStepOf(index + 1, steps.length),
            style: context.texts.labelMedium?.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    L10n l10n,
    PermissionSnapshot? snapshot,
    SetupStepState step,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md,
        AppSpacing.screen,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PrimaryButton(
            label: _primaryLabel(l10n, step, snapshot),
            onPressed: _onPrimary,
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: _review ? l10n.close : l10n.setupNotNow,
            onPressed: _onSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildStepBody(
    BuildContext context,
    L10n l10n,
    PermissionSnapshot? snapshot,
    SetupStepState step,
  ) {
    switch (step.id) {
      case SetupStepId.welcome:
        return _welcomeBody(l10n);
      case SetupStepId.installApps:
        return _installAppsBody(l10n, step);
      case SetupStepId.notifications:
        return _notificationsBody(l10n, step);
      case SetupStepId.shizuku:
        return _shizukuBody(l10n, snapshot);
      case SetupStepId.installer:
        return _installerBody(context, l10n, snapshot);
      case SetupStepId.done:
        return _doneBody(l10n);
    }
  }

  Widget _stepScaffold({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(child: SetupStepIcon(icon: icon)),
        const SizedBox(height: AppSpacing.xl),
        Text(
          title,
          textAlign: TextAlign.center,
          style: context.texts.headlineSmall?.copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...children,
      ],
    );
  }

  Widget _paragraph(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: context.texts.bodyMedium?.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }

  Widget _welcomeBody(L10n l10n) {
    return _stepScaffold(
      icon: Icons.rocket_launch_rounded,
      title: l10n.setupWelcomeTitle,
      children: <Widget>[
        _paragraph(l10n.setupWelcomeBody1),
        const SizedBox(height: AppSpacing.sm),
        _paragraph(l10n.setupWelcomeBody2),
      ],
    );
  }

  Widget _installAppsBody(L10n l10n, SetupStepState step) {
    final bool granted = step.granted;
    return _stepScaffold(
      icon: Icons.install_mobile_rounded,
      title: l10n.setupInstallTitle,
      children: <Widget>[
        _paragraph(l10n.setupInstallBody),
        const SizedBox(height: AppSpacing.xl),
        PermissionCard(
          icon: Icons.install_mobile_rounded,
          title: l10n.permInstallAppsTitle,
          description: granted
              ? l10n.setupInstallGranted
              : l10n.setupInstallDenied,
          statusLabel: granted ? l10n.statusGranted : l10n.statusNotGranted,
          tone: granted ? StatusTone.ok : StatusTone.pending,
        ),
      ],
    );
  }

  Widget _notificationsBody(L10n l10n, SetupStepState step) {
    final bool granted = step.granted;
    return _stepScaffold(
      icon: Icons.notifications_active_rounded,
      title: l10n.setupNotificationsTitle,
      children: <Widget>[
        _paragraph(l10n.setupNotificationsBody),
        const SizedBox(height: AppSpacing.xl),
        PermissionCard(
          icon: Icons.notifications_active_rounded,
          title: l10n.permNotificationsTitle,
          description: granted
              ? l10n.setupGranted
              : l10n.setupNotificationsDenied,
          statusLabel: granted ? l10n.statusGranted : l10n.statusNotGranted,
          tone: granted ? StatusTone.ok : StatusTone.pending,
        ),
      ],
    );
  }

  Widget _shizukuBody(L10n l10n, PermissionSnapshot? snapshot) {
    final ShizukuStatus status =
        snapshot?.shizuku ?? ShizukuStatus.notInstalled;
    final (String label, StatusTone tone) = switch (status) {
      ShizukuStatus.active => (l10n.statusActive, StatusTone.ok),
      ShizukuStatus.runningNoPermission => (
        l10n.statusNeedsPermission,
        StatusTone.pending,
      ),
      ShizukuStatus.stopped => (l10n.statusStopped, StatusTone.pending),
      ShizukuStatus.notInstalled => (l10n.shizukuMissing, StatusTone.blocked),
    };
    final String description = switch (status) {
      ShizukuStatus.active => l10n.shizukuActive,
      ShizukuStatus.runningNoPermission => l10n.shizukuNeedsPermission,
      ShizukuStatus.stopped => l10n.shizukuStopped,
      ShizukuStatus.notInstalled => l10n.shizukuMissingInfo,
    };
    return _stepScaffold(
      icon: Icons.terminal_rounded,
      title: l10n.setupShizukuTitle,
      children: <Widget>[
        _paragraph(l10n.setupShizukuBody),
        const SizedBox(height: AppSpacing.xl),
        PermissionCard(
          icon: Icons.terminal_rounded,
          title: l10n.permShizukuTitle,
          description: description,
          statusLabel: label,
          tone: tone,
        ),
      ],
    );
  }

  Widget _installerBody(
    BuildContext context,
    L10n l10n,
    PermissionSnapshot? snapshot,
  ) {
    final ShizukuStatus shizuku =
        snapshot?.shizuku ?? ShizukuService.instance.current;
    final bool shizukuAvailable = shizuku.isInstalledOrRunning;
    final InstallerChoice choice = ref.watch(installPrefsProvider).choice;

    void select(InstallerChoice next) {
      applyInstallerChoice(ref, next, shizuku);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.setupInstallerTitle,
          textAlign: TextAlign.center,
          style: context.texts.headlineSmall?.copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _paragraph(l10n.setupInstallerBody),
        const SizedBox(height: AppSpacing.xl),
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

  Widget _doneBody(L10n l10n) {
    return _stepScaffold(
      icon: Icons.celebration_rounded,
      title: l10n.setupDoneTitle,
      children: <Widget>[_paragraph(l10n.tagline)],
    );
  }
}
