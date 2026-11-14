import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../app/settings.dart';
import '../../core/auth.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../models/collections.dart';
import '../../models/download_task.dart';
import '../../models/profile.dart';
import '../../shared/widgets/admin_crown.dart';
import '../../shared/widgets/app_mark.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/primitives.dart';
import '../collections/collections_controller.dart';
import '../downloads/downloads_controller.dart';
import '../home/home_controller.dart';
import '../profile/profile_controller.dart';

class MenuPage extends ConsumerWidget {
  const MenuPage({super.key});

  void _snack(BuildContext context, String message) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.bgElevated,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
      ),
    );
  }

  Future<void> _reload(BuildContext context, WidgetRef ref) async {
    ref.invalidate(homeFeedProvider);
    ref.invalidate(catalogFacetsProvider);
    ref.invalidate(collectionsProvider);
    await ref.read(homeFeedProvider.notifier).refresh();
    if (!context.mounted) {
      return;
    }
    _snack(context, context.l10n.catalogReloaded);
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    await ref.read(cacheStoreProvider).clearAll();
    ref.invalidate(homeFeedProvider);
    if (!context.mounted) {
      return;
    }
    _snack(context, context.l10n.cacheCleared);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;
    final AppSettings settings = ref.watch(settingsProvider);
    final AccountState account = ref.watch(accountProvider);
    final UserProfile profile = ref.watch(profileProvider).value ??
        UserProfile(id: account.id ?? '', displayName: account.displayName);
    final String? adminLevel = ref.watch(adminLevelProvider).value;
    final Collections collections = ref.watch(collectionsProvider).value ?? Collections.empty;
    final int downloads = ref
        .watch(downloadsProvider)
        .where((DownloadTask task) => task.isDone)
        .length;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.lg,
                AppSpacing.screen,
                context.bottomChromePadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.menuTitle,
                    style: context.texts.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  GlassContainer(
                    radius: AppRadii.lg,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 62,
                          height: 62,
                          child: GameCover(
                            imageUrl: profile.coverUrl,
                            title: profile.displayName,
                            memWidth: 180,
                            borderRadius: AppRadii.md,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                profile.displayName,
                                style: context.texts.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (adminLevel != null) ...<Widget>[
                                const SizedBox(height: 4),
                                AdminBadge(level: adminLevel),
                              ],
                              const SizedBox(height: 3),
                              Row(
                                children: <Widget>[
                                  Icon(
                                    account.isSignedIn
                                        ? Icons.verified_rounded
                                        : Icons.lock_rounded,
                                    size: 12,
                                    color: account.isSignedIn
                                        ? AppColors.accent
                                        : AppColors.success,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      account.isSignedIn
                                          ? l10n.accountSection
                                          : l10n.guestLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.texts.labelSmall?.copyWith(
                                        color: account.isSignedIn
                                            ? AppColors.accent
                                            : AppColors.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (account.isSignedIn)
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: SecondaryButton(
                            label: l10n.editProfile,
                            icon: Icons.edit_rounded,
                            onPressed: () => context.push<Object?>('/profile/edit'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        SecondaryButton(
                          label: l10n.signOut,
                          icon: Icons.logout_rounded,
                          expand: false,
                          onPressed: () => ref.read(accountProvider.notifier).signOut(),
                        ),
                      ],
                    )
                  else
                    PrimaryButton(
                      label: '${l10n.signIn} / ${l10n.signUp}',
                      icon: Icons.login_rounded,
                      onPressed: () => context.push<Object?>('/auth'),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  GlassContainer(
                    radius: AppRadii.lg,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.lg,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _MenuStat(value: collections.favorites.length.toString(), label: l10n.hubFavorites),
                        ),
                        const _MenuDivider(),
                        Expanded(
                          child: _MenuStat(value: collections.library.length.toString(), label: l10n.hubInstalled),
                        ),
                        const _MenuDivider(),
                        Expanded(child: _MenuStat(value: downloads.toString(), label: l10n.hubDownloads)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _SectionLabel(l10n.activity),
                  const SizedBox(height: AppSpacing.md),
                  SectionTile(
                    icon: Icons.layers_rounded,
                    label: l10n.hubTitle,
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                    onTap: () => context.go('/hub'),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _SectionLabel(l10n.appearanceSection),
                  const SizedBox(height: AppSpacing.md),
                  GlassContainer(
                    radius: AppRadii.lg,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.language,
                          style: context.texts.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SegmentedControl<String>(
                          items: const <SegmentItem<String>>[
                            SegmentItem<String>(value: 'pt', label: 'Português (BR)'),
                            SegmentItem<String>(value: 'en', label: 'English'),
                          ],
                          value: settings.locale.languageCode,
                          onChanged: (String code) => ref
                              .read(settingsProvider.notifier)
                              .setLocale(code == 'en' ? const Locale('en') : const Locale('pt', 'BR')),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    l10n.notifications,
                                    style: context.texts.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l10n.notificationsHint,
                                    style: context.texts.labelSmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            AppToggle(
                              value: settings.notifications,
                              onChanged: (bool value) =>
                                  ref.read(settingsProvider.notifier).setNotifications(value),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _SectionLabel(l10n.dataSection),
                  const SizedBox(height: AppSpacing.md),
                  SectionTile(
                    icon: Icons.sync_rounded,
                    label: l10n.reloadCatalog,
                    onTap: () => _reload(context, ref),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SectionTile(
                    icon: Icons.cleaning_services_rounded,
                    label: l10n.clearCache,
                    onTap: () => _clearCache(context, ref),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _SectionLabel(l10n.about),
                  const SizedBox(height: AppSpacing.md),
                  GlassContainer(
                    radius: AppRadii.lg,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const PortixMark(size: 44),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    l10n.appName,
                                    style: context.texts.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  Text(
                                    l10n.tagline,
                                    style: context.texts.labelSmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'v1.0.0',
                              style: context.texts.labelSmall?.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          l10n.dataSource,
                          style: context.texts.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: <Widget>[
                            const Icon(Icons.code_rounded, size: 14, color: AppColors.accent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                l10n.madeWith,
                                style: context.texts.labelSmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuStat extends StatelessWidget {
  const _MenuStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: context.texts.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 1,
      height: 30,
      child: ColoredBox(color: AppColors.glassBorder),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: context.texts.labelSmall?.copyWith(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
      ),
    );
  }
}
