import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/env.dart';
import '../../core/theme/tokens.dart';
import '../../models/game.dart';
import '../../models/home_feed.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/glass_header.dart';
import '../../shared/widgets/hero_carousel.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/reveal.dart';
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
      child: GlassHeader(
        title: l10n.navHome,
        child: RefreshIndicator(
          color: context.palette.primary,
          backgroundColor: context.palette.surface,
          onRefresh: () => ref.read(homeFeedProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: <Widget>[
              const _HomeHeader(),
              if (feed == null && async.isLoading)
                const SliverToBoxAdapter(child: HomeSkeleton()),
              if (feed == null && async.hasError)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 380,
                    child: ErrorStateView(
                      message: context.failureText(async.error),
                      retryLabel: l10n.tryAgain,
                      onRetry: () =>
                          ref.read(homeFeedProvider.notifier).refresh(),
                    ),
                  ),
                ),
              if (feed != null) ..._feedSlivers(context, ref, feed),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _feedSlivers(
    BuildContext context,
    WidgetRef ref,
    HomeFeed feed,
  ) {
    final L10n l10n = context.l10n;
    final List<PlatformInfo> platforms = feed.platforms
        .where((PlatformInfo platform) => !platform.isSecondary)
        .toList(growable: false);
    final List<Widget> slivers = <Widget>[];

    if (feed.highlights.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            child: HeroCarousel(games: feed.highlights, tagPrefix: 'home'),
          ),
        ),
      );
    }

    slivers.add(
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
    );

    // Card de apresentação.
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: GlassContainer(
            radius: AppRadii.lg,
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.homeIntroTitle,
                  style: context.texts.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.homeIntroBody,
                  style: context.texts.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SecondaryButton(
                  label: l10n.explore,
                  icon: Icons.explore_rounded,
                  expand: false,
                  onPressed: () => context.go('/explore'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Faixa de plataformas (atalho).
    if (platforms.isNotEmpty) {
      slivers.add(
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      );
      slivers.add(
        SliverToBoxAdapter(child: SectionHeader(title: l10n.sectionPlatforms)),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screen,
              ),
              itemCount: platforms.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: AppSpacing.sm),
              itemBuilder: (BuildContext context, int index) {
                final PlatformInfo platform = platforms[index];
                return AppPill(
                  label: platform.name,
                  dense: true,
                  onTap: () => _browse(context, ref, platform: platform.slug),
                );
              },
            ),
          ),
        ),
      );
    }

    // Explorar por seção (tiles de vidro).
    final List<_BrowseTarget> tiles = _sectionTiles(context, feed);
    if (tiles.isNotEmpty) {
      slivers.add(
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      );
      slivers.add(
        SliverToBoxAdapter(child: SectionHeader(title: l10n.sectionExploreBy)),
      );
      slivers.add(
        ResponsiveCoverGrid(
          mainAxisExtent: 62,
          itemBuilder: (BuildContext context, int index) {
            final _BrowseTarget target = tiles[index];
            return SectionTile(
              icon: target.icon,
              label: target.label,
              onTap: () => _browse(
                context,
                ref,
                platform: target.platform,
                genre: target.genre,
                freeOnly: target.freeOnly,
                sort: target.sort,
              ),
            );
          },
          itemCount: tiles.length,
        ),
      );
    }

    if (feed.recent.isNotEmpty) {
      slivers.add(
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.sectionNews,
            actionLabel: l10n.seeAll,
            onAction: () => context.go('/news'),
          ),
        ),
      );
      slivers.add(
        _GameGrid(
          games: feed.recent.take(6).toList(growable: false),
          prefix: 'home-news',
        ),
      );
    }

    if (feed.topRated.isNotEmpty) {
      slivers.add(
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.sectionTopRated,
            actionLabel: l10n.seeAll,
            onAction: () => _browse(context, ref),
          ),
        ),
      );
      slivers.add(
        _GameGrid(
          games: feed.topRated.take(6).toList(growable: false),
          prefix: 'home-top',
        ),
      );
    }

    if (feed.trending.isNotEmpty) {
      slivers.add(
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.sectionPopular,
            actionLabel: l10n.seeAll,
            onAction: () => _browse(context, ref, sort: 'trending'),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: 236,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screen,
              ),
              itemCount: feed.trending.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (BuildContext context, int index) {
                final Game game = feed.trending[index];
                return GameCard(
                  game: game,
                  width: 150,
                  heroTag: 'home-pop-${game.id}',
                );
              },
            ),
          ),
        ),
      );
    }

    slivers.add(
      SliverToBoxAdapter(child: SizedBox(height: context.bottomChromePadding)),
    );
    return slivers;
  }

  List<_BrowseTarget> _sectionTiles(BuildContext context, HomeFeed feed) {
    final L10n l10n = context.l10n;
    final List<_BrowseTarget> tiles = <_BrowseTarget>[];

    if (feed.free.isNotEmpty) {
      tiles.add(
        _BrowseTarget(
          icon: Icons.bolt_rounded,
          label: l10n.sectionFree,
          freeOnly: true,
        ),
      );
    }
    if (feed.classics.isNotEmpty) {
      tiles.add(
        _BrowseTarget(
          icon: Icons.history_edu_rounded,
          label: l10n.sectionClassics,
          sort: 'year',
        ),
      );
    }
    for (final GenreInfo genre in feed.genres.take(2)) {
      tiles.add(
        _BrowseTarget(
          icon: Icons.category_rounded,
          label: genre.name,
          genre: genre.name,
        ),
      );
    }
    if (tiles.length < 4) {
      final List<PlatformInfo> platforms = feed.platforms
          .where((PlatformInfo platform) => !platform.isSecondary)
          .toList(growable: false);
      if (platforms.isNotEmpty) {
        final PlatformInfo platform = platforms.first;
        tiles.add(
          _BrowseTarget(
            icon: Icons.sports_esports_rounded,
            label: platform.name,
            platform: platform.slug,
          ),
        );
      }
    }
    return tiles.take(4).toList(growable: false);
  }

  void _browse(
    BuildContext context,
    WidgetRef ref, {
    String? platform,
    String? genre,
    bool freeOnly = false,
    String sort = 'trending',
  }) {
    ref
        .read(searchControllerProvider.notifier)
        .browse(
          platform: platform,
          genre: genre,
          freeOnly: freeOnly,
          sort: sort,
        );
    context.go('/explore');
  }
}

class _BrowseTarget {
  const _BrowseTarget({
    required this.icon,
    required this.label,
    this.platform,
    this.genre,
    this.freeOnly = false,
    this.sort = 'trending',
  });

  final IconData icon;
  final String label;
  final String? platform;
  final String? genre;
  final bool freeOnly;
  final String sort;
}

class _GameGrid extends StatelessWidget {
  const _GameGrid({required this.games, required this.prefix});

  final List<Game> games;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return ResponsiveCoverGrid(
      itemBuilder: (BuildContext context, int index) {
        final Game game = games[index];
        // Mesma entrada escalonada das telas irmãs (explore/search/hub).
        return RevealOnMount(
          index: index,
          child: GameCard(game: game, heroTag: '$prefix-${game.id}'),
        );
      },
      itemCount: games.length,
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    return GlassSliverAppBar(
      title: l10n.navHome,
      subtitle: l10n.tagline,
      expandedHeight: 150,
    );
  }
}
