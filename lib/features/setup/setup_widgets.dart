import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/theme/tokens.dart';
import '../install/models.dart';
import '../install/shizuku.dart';
import '../../shared/widgets/primitives.dart';

// ============================================================================
// PORTIX — widgets do setup inicial e da categoria "Instalação" das
// configurações. Portados dos fragmentos recuperados (_InstallerPrefsBlock /
// _PermissionsPanel) usando só tokens (AppSpacing/AppRadii/AppMotion,
// context.colors/context.texts) — cores semânticas vêm do tema (success/
// warning/danger/accent), nunca hardcoded.
// ============================================================================

/// Tom semântico de um status. As cores são resolvidas pelo TEMA no build:
/// ok → success, pending → warning, blocked → danger, neutral → accent.
enum StatusTone { ok, pending, blocked, neutral }

/// Pílula de status (Concedido / Não concedido / Ativo / Parado…).
/// Nunca é alvo de toque: é sempre informativa, dentro de um card.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
  });

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (tone) {
      StatusTone.ok => context.colors.success,
      StatusTone.pending => context.colors.warning,
      StatusTone.blocked => context.colors.danger,
      StatusTone.neutral => context.colors.accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.compact,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: AppSpacing.xs,
            height: AppSpacing.xs,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: AppSpacing.xxs),
          // Flexible + ellipsis: em textScale 2.0 o rótulo não pode derrubar
          // o layout (requisito da missão: fonte ampliada sem cortar botões).
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ícone grande da etapa: vidro com disco em gradiente de destaque.
class SetupStepIcon extends StatelessWidget {
  const SetupStepIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: AppRadii.md,
      padding: const EdgeInsets.all(AppSpacing.md),
      shadow: <BoxShadow>[
        BoxShadow(
          color: context.colors.accent.withValues(alpha: 0.25),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: context.colors.accentGradient,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Icon(
          icon,
          size: AppSpacing.xxxl,
          color: context.colors.onAccent,
        ),
      ),
    );
  }
}

/// Cartão de permissão/estado: ícone, título, pílula de status, corpo e
/// (opcionalmente) botão primário + secundário ("Agora não"). Usado no setup
/// e no painel de permissões das configurações.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.statusLabel,
    this.tone = StatusTone.neutral,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String description;
  final String statusLabel;
  final StatusTone tone;

  /// Ação primária do cartão (ex.: "Abrir configurações"). Nula = sem botão.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Ação secundária do cartão (ex.: "Agora não").
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final bool hasActions = actionLabel != null || secondaryLabel != null;
    return GlassContainer(
      radius: AppRadii.lg,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.glassStrong,
                  border: Border.all(color: context.colors.glassBorder),
                ),
                child: Icon(
                  icon,
                  size: AppSpacing.navIconSize,
                  color: context.colors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: context.texts.titleSmall?.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    StatusPill(label: statusLabel, tone: tone),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            description,
            style: context.texts.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          if (hasActions) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            if (actionLabel != null && secondaryLabel != null)
              Row(
                children: <Widget>[
                  Expanded(
                    child: PrimaryButton(
                      label: actionLabel!,
                      onPressed: onAction,
                      height: AppSpacing.secondaryButtonHeight,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: SecondaryButton(
                      label: secondaryLabel!,
                      onPressed: onSecondary,
                    ),
                  ),
                ],
              )
            else if (actionLabel != null)
              PrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                height: AppSpacing.secondaryButtonHeight,
              )
            else
              SecondaryButton(label: secondaryLabel!, onPressed: onSecondary),
          ],
        ],
      ),
    );
  }
}

/// Cartão-rádio do instalador preferido (Automático / Android / Shizuku).
/// Alvo de toque ≥48px (conteúdo com folga de padding do vidro).
class InstallerOptionCard extends StatelessWidget {
  const InstallerOptionCard({
    super.key,
    required this.choice,
    required this.title,
    required this.description,
    required this.selected,
    this.enabled = true,
    this.status,
    this.onTap,
  });

  final InstallerChoice choice;
  final String title;
  final String description;
  final bool selected;

  /// `false` desabilita (ex.: Shizuku não instalado) e esmaece o texto.
  final bool enabled;

  /// Pílula opcional no canto (status do Shizuku, "Recomendado").
  final StatusPill? status;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: AppRadii.lg,
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: selected ? context.colors.accent.withValues(alpha: 0.10) : null,
      borderColor: selected
          ? context.colors.accent.withValues(alpha: 0.45)
          : null,
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.circleButton),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _radioDot(context),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: context.texts.titleSmall?.copyWith(
                      color: enabled
                          ? context.colors.textPrimary
                          : context.colors.textTertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // Pill na própria linha: como filho lateral do Row o pill
                  // era ilimitado e, em textScale 2.0 com rótulo longo,
                  // derrubava o layout (18px de overflow em 375px).
                  if (status != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    status!,
                  ],
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    description,
                    style: context.texts.bodySmall?.copyWith(
                      color: enabled
                          ? context.colors.textSecondary
                          : context.colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _radioDot(BuildContext context) {
    final Color tone = selected
        ? context.colors.accent
        : context.colors.textTertiary;
    return Container(
      width: AppSpacing.lg,
      height: AppSpacing.lg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? tone : AppContentColors.transparent,
        border: Border.all(color: tone, width: AppSpacing.hairline),
      ),
      child: selected
          ? Center(
              child: Container(
                width: AppSpacing.xs,
                height: AppSpacing.xs,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.onAccent,
                ),
              ),
            )
          : null,
    );
  }
}

/// Porta do `select()` do fragmento _InstallerPrefsBlock: grava a escolha
/// (`install.installer`) e, ao escolher Shizuku rodando SEM permissão,
/// dispara o diálogo de permissão do Shizuku na hora.
void applyInstallerChoice(
  WidgetRef ref,
  InstallerChoice next,
  ShizukuStatus shizuku,
) {
  ref.read(installPrefsProvider.notifier).setChoice(next);
  if (next == InstallerChoice.shizuku &&
      shizuku == ShizukuStatus.runningNoPermission) {
    unawaited(ShizukuService.instance.requestPermission());
  }
}
