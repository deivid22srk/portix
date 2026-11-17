import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/formatters.dart';
import '../../core/env.dart';
import '../../core/github_releases.dart';
import '../../core/github_service.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/states.dart';

/// Seletor das 3 releases mais recentes do repo do port.
/// Mobile: lista de cards. Larguras maiores: controle segmentado + card do
/// detalhe da versão selecionada. Estados: skeleton, rate limit, offline,
/// erro, vazio e "sem APK" (versão desabilitada com explicação).
class VersionSelector extends ConsumerWidget {
  const VersionSelector({
    super.key,
    required this.repoId,
    required this.selectedTag,
    required this.installedTag,
    required this.onSelected,
  });

  /// Identificador "owner/repo" do port no GitHub.
  final String repoId;

  /// Tag atualmente selecionada (null = mais recente com APK).
  final String? selectedTag;

  /// Tag da versão que o usuário já tem instalada (badge "Instalada").
  final String? installedTag;

  final ValueChanged<GithubRelease> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;
    final AsyncValue<List<GithubRelease>> async =
        ref.watch(repoReleasesProvider(repoId));

    if (async.isLoading && !async.hasValue) {
      return const _VersionSkeleton();
    }

    final List<GithubRelease>? data = async.value;
    if (data == null) {
      final Object? error = async.error;
      return _ErrorCard(
        rateLimit: error is GitHubApiException && error.kind == GitHubErrorKind.rateLimit,
        offline: error is GitHubApiException && error.kind == GitHubErrorKind.offline,
        message: context.failureText(error),
        onRetry: () => ref.invalidate(repoReleasesProvider(repoId)),
      );
    }

    final List<GithubRelease> sorted = visibleReleases(data);
    if (sorted.isEmpty) {
      return GlassContainer(
        radius: AppRadii.lg,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          children: <Widget>[
            const Icon(Icons.inventory_2_rounded, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.noReleases, style: context.texts.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    l10n.noReleasesBody,
                    style: context.texts.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final List<GithubRelease> shown = sorted.take(3).toList(growable: false);
    // Padrão conservador: a versão pré-selecionada é a mais nova COM apk.
    final GithubRelease defaultRelease = sorted.firstWhere(
      (GithubRelease release) => release.hasApk,
      orElse: () => sorted.first,
    );
    final String effectiveTag = selectedTag ?? defaultRelease.tag;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool segmented = constraints.maxWidth >= 480;
        if (segmented) {
          return _SegmentedVersions(
            releases: shown,
            effectiveTag: effectiveTag,
            installedTag: installedTag,
            onSelected: onSelected,
          );
        }
        return Column(
          children: <Widget>[
            for (int index = 0; index < shown.length; index += 1) ...<Widget>[
              VersionCard(
                release: shown[index],
                isLatest: index == 0,
                selected: shown[index].tag == effectiveTag,
                installed: shown[index].tag == installedTag,
                onTap: shown[index].hasApk ? () => onSelected(shown[index]) : null,
              ),
              if (index < shown.length - 1) const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

/// Card de uma versão (mobile e sheet).
class VersionCard extends StatelessWidget {
  const VersionCard({
    super.key,
    required this.release,
    required this.isLatest,
    required this.selected,
    required this.installed,
    this.onTap,
  });

  final GithubRelease release;
  final bool isLatest;
  final bool selected;
  final bool installed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final bool enabled = onTap != null;
    final ApkAsset? asset = preferredApkAsset(release.assets);

    final String date = release.publishedAt == null
        ? l10n.notInformed
        : '${relativeDay(release.publishedAt, en: l10n.isEn)} · '
            '${formatDate(release.publishedAt, en: l10n.isEn)}';
    final String meta = asset == null
        ? l10n.noCompatibleApk
        : <String>[
            formatBytes(asset.sizeBytes),
            if (release.downloadCount > 0) compactNumber(release.downloadCount),
            if (release.assets.length > 1) '${release.assets.length} APK',
          ].join(' · ');

    final Color border = selected
        ? AppColors.accent.withValues(alpha: 0.55)
        : AppColors.glassBorder;
    final Color fill = selected
        ? AppColors.accent.withValues(alpha: 0.10)
        : AppColors.glass;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: l10n.chooseVersionTitle(release.tag),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.out,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            color: fill,
            border: Border.all(color: border),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            release.tag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: enabled ? null : AppColors.textTertiary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _Badges(
                          release: release,
                          isLatest: isLatest,
                          installed: installed,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall?.copyWith(
                        color: asset == null ? AppColors.warning : AppColors.textSecondary,
                      ),
                    ),
                    if (asset == null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        l10n.noCompatibleApkBody,
                        style: context.texts.bodySmall?.copyWith(color: AppColors.warning),
                      ),
                    ],
                  ],
                ),
              ),
              if (enabled) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: selected ? AppColors.accent : AppColors.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Badges extends StatelessWidget {
  const _Badges({required this.release, required this.isLatest, required this.installed});

  final GithubRelease release;
  final bool isLatest;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // "Mais recente" e "Instalada" coexistem (podem ser a mesma versão).
        if (isLatest && !release.prerelease)
          BadgeChip(label: l10n.latestBadge, color: AppColors.accent),
        if (release.prerelease) ...<Widget>[
          const SizedBox(width: 6),
          BadgeChip(label: l10n.betaBadge, color: AppColors.warning),
        ],
        if (installed) ...<Widget>[
          const SizedBox(width: 6),
          BadgeChip(label: l10n.installedBadge, color: AppColors.accentAlt),
        ],
      ],
    );
  }
}

/// Variante segmentada para telas largas.
class _SegmentedVersions extends StatelessWidget {
  const _SegmentedVersions({
    required this.releases,
    required this.effectiveTag,
    required this.installedTag,
    required this.onSelected,
  });

  final List<GithubRelease> releases;
  final String effectiveTag;
  final String? installedTag;
  final ValueChanged<GithubRelease> onSelected;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final GithubRelease selected = releases.firstWhere(
      (GithubRelease release) => release.tag == effectiveTag,
      orElse: () => releases.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SegmentedControl<int>(
          value: releases.indexWhere(
            (GithubRelease release) => release.tag == effectiveTag,
          ),
          items: <SegmentItem<int>>[
            for (int index = 0; index < releases.length; index += 1)
              SegmentItem<int>(
                value: index,
                label: releases[index].tag,
              ),
          ],
          onChanged: (int index) {
            final GithubRelease release = releases[index];
            if (release.hasApk) {
              onSelected(release);
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        VersionCard(
          release: selected,
          isLatest: selected.tag == releases.first.tag,
          selected: true,
          installed: selected.tag == installedTag,
          onTap: selected.hasApk ? () => onSelected(selected) : null,
        ),
        Text(
          l10n.versionsSubtitle,
          style: context.texts.labelSmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

/// Skeleton da seção enquanto a lista carrega.
class _VersionSkeleton extends StatelessWidget {
  const _VersionSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Column(
        children: <Widget>[
          for (int index = 0; index < 3; index += 1) ...<Widget>[
            const SkeletonBox(width: double.infinity, height: 64, radius: AppRadii.md),
            if (index < 2) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet para escolher entre vários APKs da mesma release.
class ApkPickerSheet extends StatelessWidget {
  const ApkPickerSheet({super.key, required this.assets});

  final List<ApkAsset> assets;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.vertical(top: AppRadii.sheet),
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.chooseApk,
                style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final ApkAsset asset in assets)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SecondaryButton(
                    label: asset.sizeBytes > 0
                        ? '${asset.name} · ${formatBytes(asset.sizeBytes)}'
                        : asset.name,
                    icon: Icons.android_rounded,
                    onPressed: () => Navigator.of(context).pop(asset),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Erro da seção de versões (rate limit / offline / outro).
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.rateLimit,
    required this.offline,
    required this.message,
    required this.onRetry,
  });

  final bool rateLimit;
  final bool offline;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final String title = rateLimit ? l10n.rateLimitTitle : l10n.errorGeneric;
    final String body = rateLimit
        ? l10n.rateLimitBody
        : offline
            ? l10n.githubOfflineBody
            : message;
    return GlassContainer(
      radius: AppRadii.lg,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                rateLimit
                    ? Icons.hourglass_top_rounded
                    : offline
                        ? Icons.cloud_off_rounded
                        : Icons.error_outline_rounded,
                color: rateLimit || offline ? AppColors.warning : AppColors.danger,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(title, style: context.texts.titleSmall)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: context.texts.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: l10n.tryAgain,
            icon: Icons.refresh_rounded,
            height: 44,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
