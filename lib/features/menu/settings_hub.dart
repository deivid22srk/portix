import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/theme/tokens.dart';
import 'settings_categories.dart';
import 'settings_profile_header.dart';
import '../../shared/widgets/primitives.dart';

/// Hub de configurações: título + perfil resumido + lista de categorias.
/// Usado no /menu e como coluna esquerda do master-detail (≥768px).
class SettingsHub extends ConsumerWidget {
  const SettingsHub({super.key, this.selectedId});

  /// Categoria destacada quando a página abre em master-detail.
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.screen,
            right: AppSpacing.screen,
            top: AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.settingsTitle,
                style: context.texts.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.settingsSubtitle,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: SettingsProfileHeader(selectedId: selectedId),
        ),
        const SizedBox(height: AppSpacing.xl),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screen,
              0,
              AppSpacing.screen,
              context.bottomChromePadding,
            ),
            itemCount: kSettingsCategories.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (BuildContext context, int index) {
              final SettingsCategory category = kSettingsCategories[index];
              return SettingsCategoryCard(
                category: category,
                selected: selectedId == category.id,
                onTap: () => context.go('/menu/${category.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Card de categoria: ícone em vidro com brilho da marca, título,
/// descrição curta e chevron. Alvo de toque ≥ 48dp, Semantics de botão.
class SettingsCategoryCard extends ConsumerWidget {
  const SettingsCategoryCard({
    super.key,
    required this.category,
    required this.onTap,
    this.selected = false,
  });

  final SettingsCategory category;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;

    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.base,
          curve: AppMotion.emphasized,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected ? context.colors.glassStrong : context.colors.glass,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: selected
                  ? context.colors.accent
                  : context.colors.glassBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: AppSpacing.circleButton,
                height: AppSpacing.circleButton,
                decoration: BoxDecoration(
                  gradient: context.colors.brandSoft,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(
                  category.icon,
                  size: 22,
                  color: context.colors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      category.title(l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? context.colors.accent
                            : context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      category.description(l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall?.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
