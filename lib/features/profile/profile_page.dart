import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_strings.dart';
import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/download_task.dart';
import '../../shared/widgets/app_mark.dart';
import '../../shared/widgets/primitives.dart';
import '../collections/collections_controller.dart';
import '../downloads/downloads_controller.dart';
import '../home/home_controller.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  void _snack(BuildContext context, String message) {
    final AppPalette p = context.palette;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceHigh,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    final AppSettings settings = ref.watch(settingsProvider);
    final Collections collections =
        ref.watch(collectionsProvider).value ?? Collections.empty;
    final int downloads =
        ref.watch(downloadsProvider).where((DownloadTask task) => task.isDone).length;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.profileTitle,
                    style: context.texts.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 18),
                  GlassPanel(
                    radius: 24,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: p.brandSoft,
                            border: Border.all(color: p.line),
                          ),
                          child: const Center(
                            child: PortixMark(size: 38, glow: false),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                l10n.player,
                                style: context.texts.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.lock_rounded,
                                    size: 12,
                                    color: p.success,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      l10n.anonymousSession,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.texts.labelSmall?.copyWith(
                                        color: p.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.anonymousHint,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.bodySmall?.copyWith(
                                  color: p.muted,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    radius: 20,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _ProfileStat(
                            value: collections.favorites.length.toString(),
                            label: l10n.wishlistTitle,
                          ),
                        ),
                        _Divider(color: p.line),
                        Expanded(
                          child: _ProfileStat(
                            value: collections.library.length.toString(),
                            label: l10n.libraryTitle,
                          ),
                        ),
                        _Divider(color: p.line),
                        Expanded(
                          child: _ProfileStat(
                            value: downloads.toString(),
                            label: l10n.completedDownloads,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SectionLabel(l10n.settingsSection),
                  const SizedBox(height: 10),
                  GlassPanel(
                    radius: 20,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.appearance,
                          style: context.texts.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedControl<ThemeMode>(
                          items: <SegmentItem<ThemeMode>>[
                            SegmentItem<ThemeMode>(
                              value: ThemeMode.system,
                              label: l10n.themeSystem,
                            ),
                            SegmentItem<ThemeMode>(
                              value: ThemeMode.light,
                              label: l10n.themeLight,
                            ),
                            SegmentItem<ThemeMode>(
                              value: ThemeMode.dark,
                              label: l10n.themeDark,
                            ),
                          ],
                          value: settings.themeMode,
                          onChanged: (ThemeMode mode) =>
                              ref.read(settingsProvider.notifier).setThemeMode(mode),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          l10n.language,
                          style: context.texts.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedControl<String>(
                          items: <SegmentItem<String>>[
                            const SegmentItem<String>(
                              value: 'pt',
                              label: 'Português (BR)',
                            ),
                            const SegmentItem<String>(
                              value: 'en',
                              label: 'English',
                            ),
                          ],
                          value: settings.locale.languageCode,
                          onChanged: (String code) =>
                              ref.read(settingsProvider.notifier).setLocale(
                                    code == 'en'
                                        ? const Locale('en')
                                        : const Locale('pt', 'BR'),
                                  ),
                        ),
                        const SizedBox(height: 16),
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
                                      color: p.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            AppToggle(
                              value: settings.notifications,
                              onChanged: (bool value) => ref
                                  .read(settingsProvider.notifier)
                                  .setNotifications(value),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SectionLabel(l10n.dataSection),
                  const SizedBox(height: 10),
                  _ActionTile(
                    icon: Icons.sync_rounded,
                    title: l10n.reloadCatalog,
                    onTap: () => unawaited(_reload(context, ref)),
                  ),
                  const SizedBox(height: 8),
                  _ActionTile(
                    icon: Icons.cleaning_services_rounded,
                    title: l10n.clearCache,
                    onTap: () => unawaited(_clearCache(context, ref)),
                  ),
                  const SizedBox(height: 28),
                  _SectionLabel(l10n.about),
                  const SizedBox(height: 10),
                  GlassPanel(
                    radius: 22,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const PortixMark(size: 44),
                            const SizedBox(width: 12),
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
                                      color: p.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'v1.0.0',
                              style: context.texts.labelSmall?.copyWith(
                                color: p.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          l10n.dataSource,
                          style: context.texts.bodySmall?.copyWith(
                            color: p.muted,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.code_rounded,
                              size: 14,
                              color: p.secondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                l10n.madeWith,
                                style: context.texts.labelSmall?.copyWith(
                                  color: p.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 130),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

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
            color: context.palette.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.labelSmall?.copyWith(
            color: context.palette.muted,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 30,
        color: color,
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: context.texts.labelSmall?.copyWith(
        color: context.palette.muted,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Pressable(
      onTap: onTap,
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: p.primary.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 18, color: p.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
          ],
        ),
      ),
    );
  }
}
