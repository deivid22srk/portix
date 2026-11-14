import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/env.dart';
import '../../models/collections.dart';
import '../../models/download_task.dart';
import '../../models/game.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/states.dart';
import '../collections/collections_controller.dart';
import '../downloads/downloads_controller.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    final AsyncValue<Collections> async = ref.watch(collectionsProvider);
    final Collections collections = async.value ?? Collections.empty;
    final int completedDownloads = ref
        .watch(downloadsProvider)
        .where((DownloadTask task) => task.isDone)
        .length;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: p.primary,
        backgroundColor: p.surface,
        onRefresh: () => ref.read(collectionsProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            l10n.libraryTitle,
                            style: context.texts.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ),
                        IconGlassButton(
                          icon: Icons.search_rounded,
                          tooltip: l10n.searchTitle,
                          onTap: () => context.go('/search'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.anonymousHint,
                      style: context.texts.bodySmall?.copyWith(
                        color: p.muted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    GlassPanel(
                      radius: 20,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _LibraryStat(
                              value: collections.library.length.toString(),
                              label: l10n.libraryTitle,
                              color: p.primary,
                            ),
                          ),
                          _StatDivider(color: p.line),
                          Expanded(
                            child: _LibraryStat(
                              value: collections.favorites.length.toString(),
                              label: l10n.wishlistTitle,
                              color: p.danger,
                            ),
                          ),
                          _StatDivider(color: p.line),
                          Expanded(
                            child: _LibraryStat(
                              value: completedDownloads.toString(),
                              label: l10n.statusDone,
                              color: p.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Pressable(
                      onTap: () => context.push<Object?>('/wishlist'),
                      child: GlassPanel(
                        radius: 18,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 13,
                        ),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: p.danger.withValues(alpha: 0.14),
                              ),
                              child: Icon(
                                Icons.favorite_rounded,
                                size: 17,
                                color: p.danger,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                l10n.wishlistTitle,
                                style: context.texts.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              collections.favorites.length.toString(),
                              style: context.texts.labelMedium?.copyWith(
                                color: p.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: p.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SectionHeader(
                      title: l10n.libraryTitle,
                    ),
                  ],
                ),
              ),
            ),
            if (async.isLoading && !async.hasValue)
              const SliverToBoxAdapter(child: SearchSkeleton()),
            if (async.hasError && !async.hasValue)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 360,
                  child: ErrorStateView(
                    message: context.failureText(async.error),
                    retryLabel: l10n.tryAgain,
                    onRetry: () =>
                        ref.read(collectionsProvider.notifier).refresh(),
                  ),
                ),
              ),
            if (async.hasValue && collections.library.isEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 380,
                  child: EmptyState(
                    icon: Icons.video_library_outlined,
                    title: l10n.libraryEmpty,
                    body: l10n.libraryEmptyBody,
                    actionLabel: l10n.explore,
                    onAction: () => context.go('/search'),
                  ),
                ),
              ),
            if (collections.library.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 130),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
                      final Game game = collections.library[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GameRow(
                          game: game,
                          onTap: () =>
                              context.push<Object?>('/game/${game.slug}'),
                          trailing: BadgeChip(
                            label: l10n.installedLabel,
                            color: p.success,
                            icon: Icons.check_rounded,
                          ),
                        ),
                      );
                    },
                    childCount: collections.library.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryStat extends StatelessWidget {
  const _LibraryStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: context.texts.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
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

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 30,
        color: color,
      );
}
