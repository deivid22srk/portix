import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/env.dart';
import '../../core/formatters.dart';
import '../../models/game.dart';
import '../../models/home_feed.dart';
import '../../shared/widgets/app_mark.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/states.dart';
import '../search/search_controller.dart';
import 'home_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;
    final AsyncValue<HomeFeed> async = ref.watch(homeFeedProvider);
    final HomeFeed? feed = async.value;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: context.palette.primary,
        backgroundColor: context.palette.surface,
        onRefresh: () async {
          await ref.read(homeFeedProvider.notifier).refresh();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: <Widget>[
            const SliverToBoxAdapter(child: _HomeHeader()),
            if (feed == null && async.isLoading)
              const SliverToBoxAdapter(child: HomeSkeleton()),
            if (feed == null && async.hasError)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 380,
                  child: ErrorStateView(
                    message: context.failureText(async.error),
                    retryLabel: l10n.tryAgain,
                    onRetry: () => ref.read(homeFeedProvider.notifier).refresh(),
                  ),
                ),
              ),
            if (feed != null) ..._feedSlivers(context, ref, feed, async.hasError),
          ],
        ),
      ),
    );
  }

  List<Widget> _feedSlivers(
    BuildContext context,
    WidgetRef ref,
    HomeFeed feed,
    bool stale,
  ) {
    final L10n l10n = context.l10n;
    final List<PlatformInfo> platforms = feed.platforms
        .where((PlatformInfo platform) => !platform.isSecondary)
        .toList(growable: false);
    final SliverToBoxAdapter gap = const SliverToBoxAdapter(
      child: SizedBox(height: 28),
    );

    return <Widget>[
      if (stale)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _OfflineBanner(
              onRetry: () => ref.read(homeFeedProvider.notifier).refresh(),
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 22)),
      if (feed.trending.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _FeaturedCard(
              game: feed.trending.first,
              onTap: () => context.push<Object?>(
                '/game/${feed.trending.first.slug}',
                extra: 'home-featured-${feed.trending.first.id}',
              ),
            ),
          ),
        ),
      if (platforms.isNotEmpty) ...<Widget>[
        gap,
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.sectionPlatforms,
            actionLabel: l10n.seeAll,
            onAction: () => _openSearch(context, ref),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: platforms.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: 8),
              itemBuilder: (BuildContext context, int index) {
                final PlatformInfo platform = platforms[index];
                return AppPill(
                  label: platform.name,
                  dense: true,
                  onTap: () => _openSearch(
                    context,
                    ref,
                    platform: platform.slug,
                  ),
                );
              },
            ),
          ),
        ),
      ],
      if (feed.trending.isNotEmpty) ...<Widget>[
        gap,
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.sectionTrending,
            actionLabel: l10n.seeAll,
            onAction: () => _openSearch(context, ref, sort: 'trending'),
          ),
        ),
        SliverToBoxAdapter(
          child: _GameRail(games: feed.trending, tagPrefix: 'home-trending'),
        ),
      ],
      if (feed.recent.isNotEmpty) ...<Widget>[
        gap,
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.sectionRecent,
            actionLabel: l10n.seeAll,
            onAction: () => _openSearch(context, ref, sort: 'recent'),
          ),
        ),
        SliverToBoxAdapter(
          child: _GameRail(games: feed.recent, tagPrefix: 'home-recent'),
        ),
      ],
      if (feed.classics.isNotEmpty) ...<Widget>[
        gap,
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.sectionClassics,
            actionLabel: l10n.seeAll,
            onAction: () => _openSearch(context, ref, sort: 'year'),
          ),
        ),
        SliverToBoxAdapter(
          child: _GameRail(games: feed.classics, tagPrefix: 'home-classics'),
        ),
      ],
      if (feed.free.isNotEmpty) ...<Widget>[
        gap,
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.sectionFree,
            actionLabel: l10n.seeAll,
            onAction: () => _openSearch(context, ref, freeOnly: true),
          ),
        ),
        SliverToBoxAdapter(
          child: _GameRail(games: feed.free, tagPrefix: 'home-free'),
        ),
      ],
      if (feed.genres.isNotEmpty) ...<Widget>[
        gap,
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.sectionGenres,
            actionLabel: l10n.seeAll,
            onAction: () => _openSearch(context, ref),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final GenreInfo genre in feed.genres.take(10))
                  AppPill(
                    label: genre.name,
                    dense: true,
                    onTap: () => _openSearch(
                      context,
                      ref,
                      genre: genre.name,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      gap,
      SliverToBoxAdapter(child: _StatsPanel(stats: feed.stats)),
      const SliverToBoxAdapter(child: SizedBox(height: 130)),
    ];
  }

  void _openSearch(
    BuildContext context,
    WidgetRef ref, {
    String? platform,
    String? genre,
    bool freeOnly = false,
    String sort = 'trending',
  }) {
    ref.read(searchControllerProvider.notifier).browse(
          platform: platform,
          genre: genre,
          freeOnly: freeOnly,
          sort: sort,
        );
    context.go('/search');
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: p.brandSoft,
                  border: Border.all(color: p.line),
                ),
                child: const Center(child: PortixMark(size: 30, glow: false)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      greetingFor(DateTime.now(), en: l10n.isEn),
                      style: context.texts.bodySmall?.copyWith(color: p.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.appName,
                      style: context.texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.4,
                      ),
                    ),
                  ],
                ),
              ),
              IconGlassButton(
                icon: Icons.favorite_rounded,
                tooltip: l10n.wishlistTitle,
                onTap: () => context.push<Object?>('/wishlist'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            l10n.homeTitle,
            style: context.texts.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.9,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.homeSubtitle,
            style: context.texts.bodyMedium?.copyWith(
              color: p.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Pressable(
            onTap: () => context.go('/search'),
            child: GlassPanel(
              radius: 17,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search_rounded, size: 20, color: p.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.searchShort,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium?.copyWith(color: p.muted),
                    ),
                  ),
                  Icon(Icons.tune_rounded, size: 18, color: p.secondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.game, required this.onTap});

  final Game game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final String meta = <String>[
      if (game.year != null) game.year.toString(),
      if (game.primaryPlatform.isNotEmpty) game.primaryPlatform,
      if (game.portCount > 0) context.l10n.portCount(game.portCount),
    ].join(' · ');

    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: SizedBox(
        height: 286,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Hero(
                tag: 'home-featured-${game.id}',
                child: GameCover(
                  imageUrl: game.coverUrl,
                  title: game.title,
                  memWidth: 900,
                  borderRadius: 0,
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0x33000000),
                      Color(0x00000000),
                      Color(0xCC000000),
                    ],
                    stops: <double>[0, 0.42, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.bolt_rounded, size: 14, color: p.warning),
                      const SizedBox(width: 4),
                      Text(
                        context.l10n.sectionTrending.toUpperCase(),
                        style: context.texts.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      game.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.06,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        if (game.hasRating) ...<Widget>[
                          Icon(Icons.star_rounded, size: 15, color: p.warning),
                          const SizedBox(width: 3),
                          Text(
                            formatRating(game.rating),
                            style: context.texts.labelMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.74),
                            ),
                          ),
                        ),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: p.brand,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 19,
                            color: Colors.white,
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
    );
  }
}

class _GameRail extends StatelessWidget {
  const _GameRail({required this.games, required this.tagPrefix});

  final List<Game> games;
  final String tagPrefix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 268,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: games.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 14),
        itemBuilder: (BuildContext context, int index) {
          final Game game = games[index];
          return GameCard(
            game: game,
            width: 146,
            heroTag: '$tagPrefix-${game.id}',
          );
        },
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.stats});

  final CatalogStats stats;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassPanel(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatBlock(
                    value: stats.games.toString(),
                    label: l10n.gameCount(stats.games),
                  ),
                ),
                _StatDivider(color: p.line),
                Expanded(
                  child: _StatBlock(
                    value: stats.ports.toString(),
                    label: l10n.portCount(stats.ports),
                  ),
                ),
                _StatDivider(color: p.line),
                Expanded(
                  child: _StatBlock(
                    value: stats.platforms.toString(),
                    label: l10n.platformCount(stats.platforms),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.auto_awesome_rounded, size: 13, color: p.secondary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l10n.catalogStatsHint,
                    textAlign: TextAlign.center,
                    style: context.texts.labelSmall?.copyWith(color: p.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Column(
      children: <Widget>[
        Text(
          value,
          style: context.texts.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.labelSmall?.copyWith(color: p.muted),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 30, color: color);
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Pressable(
      onTap: onRetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: p.warning.withValues(alpha: 0.10),
          border: Border.all(color: p.warning.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_off_rounded, size: 16, color: p.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.errorNetwork,
                maxLines: 2,
                style: context.texts.bodySmall?.copyWith(height: 1.35),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.refresh_rounded, size: 17, color: p.warning),
          ],
        ),
      ),
    );
  }
}
