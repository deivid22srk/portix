import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/env.dart';
import '../../core/theme/tokens.dart';
import '../../models/game.dart';
import '../../models/home_feed.dart';
import '../../models/search.dart';
import '../../shared/widgets/filter_sheet.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/glass_header.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/reveal.dart';
import '../../shared/widgets/states.dart';
import '../home/home_controller.dart';
import '../search/search_controller.dart';

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        ref.read(searchControllerProvider.notifier).ensureLoaded();
      }
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _openFilters(SearchState state, CatalogFacets facets) async {
    final SearchFilters? result = await showFilterSheet(
      context,
      initial: state.filters,
      facets: facets,
    );
    if (result == null || !mounted) {
      return;
    }
    ref.read(searchControllerProvider.notifier).applyFilters(result);
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final SearchState state = ref.watch(searchControllerProvider);
    final CatalogFacets facets =
        ref.watch(catalogFacetsProvider).value ?? const CatalogFacets();

    return SafeArea(
      bottom: false,
      child: GlassHeader(
        title: l10n.exploreTitle,
        child: RefreshIndicator(
          color: context.palette.primary,
          backgroundColor: context.palette.surface,
          onRefresh: () =>
              ref.read(searchControllerProvider.notifier).refresh(),
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: <Widget>[
              GlassSliverAppBar(
                title: l10n.exploreTitle,
                subtitle:
                    state.status == SearchStatus.loading && state.items.isEmpty
                    ? l10n.loading
                    : l10n.resultsCount(state.total),
                expandedHeight: 140,
                actions: <Widget>[
                  GlassCircleButton(
                    icon: Icons.tune_rounded,
                    active: state.filters.activeCount > 0,
                    tooltip: l10n.filters,
                    badge: _FilterBadge(count: state.filters.activeCount),
                    onTap: () => _openFilters(state, facets),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                ],
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screen,
                    ),
                    children: <Widget>[
                      AppPill(
                        label: l10n.all,
                        dense: true,
                        selected:
                            state.filters.platform == null &&
                            !state.filters.freeOnly,
                        onTap: () => ref
                            .read(searchControllerProvider.notifier)
                            .applyFilters(
                              state.filters.copyWith(
                                clearPlatform: true,
                                freeOnly: false,
                              ),
                            ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AppPill(
                        label: l10n.filterFree,
                        dense: true,
                        selected: state.filters.freeOnly,
                        onTap: () => ref
                            .read(searchControllerProvider.notifier)
                            .applyFilters(
                              state.filters.copyWith(
                                freeOnly: !state.filters.freeOnly,
                              ),
                            ),
                      ),
                      for (final PlatformInfo platform in facets.platforms.take(
                        10,
                      )) ...<Widget>[
                        const SizedBox(width: AppSpacing.sm),
                        AppPill(
                          label: platform.name,
                          dense: true,
                          selected: state.filters.platform == platform.slug,
                          onTap: () => ref
                              .read(searchControllerProvider.notifier)
                              .applyFilters(
                                state.filters.platform == platform.slug
                                    ? state.filters.copyWith(
                                        clearPlatform: true,
                                      )
                                    : state.filters.copyWith(
                                        platform: platform.slug,
                                      ),
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              if (state.isInitialLoading)
                const SliverToBoxAdapter(child: SearchSkeleton()),
              if (state.status == SearchStatus.error && state.items.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 380,
                    child: ErrorStateView(
                      message: context.failureText(state.error),
                      retryLabel: l10n.tryAgain,
                      onRetry: () =>
                          ref.read(searchControllerProvider.notifier).refresh(),
                    ),
                  ),
                ),
              if (state.status == SearchStatus.empty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 380,
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: l10n.noResultsTitle,
                      body: l10n.noResultsBody,
                      actionLabel: state.filters.isDefault ? null : l10n.reset,
                      actionIcon: Icons.filter_alt_off_rounded,
                      onAction: state.filters.isDefault
                          ? null
                          : () => ref
                                .read(searchControllerProvider.notifier)
                                .resetFilters(),
                    ),
                  ),
                ),
              if (state.items.isNotEmpty)
                ResponsiveCoverGrid(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.md,
                    AppSpacing.screen,
                    AppSpacing.xl,
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final Game game = state.items[index];
                    return RevealOnMount(
                      index: index,
                      child: GameCard(
                        game: game,
                        heroTag: 'explore-${game.id}',
                      ),
                    );
                  },
                  itemCount: state.items.length,
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    0,
                    AppSpacing.screen,
                    context.bottomChromePadding,
                  ),
                  child: _ResultsFooter(
                    state: state,
                    onLoadMore: () =>
                        ref.read(searchControllerProvider.notifier).loadMore(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterBadge extends StatelessWidget {
  const _FilterBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return const SizedBox.shrink();
    }
    return Container(
      width: 17,
      height: 17,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accent,
      ),
      child: Text(
        count.toString(),
        style: context.texts.labelSmall?.copyWith(
          fontSize: 9,
          color: AppColors.onAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ResultsFooter extends StatelessWidget {
  const _ResultsFooter({required this.state, required this.onLoadMore});

  final SearchState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accent,
          ),
        ),
      );
    }
    if (state.error != null && state.items.isNotEmpty) {
      return Center(
        child: SecondaryButton(
          label: context.l10n.tryAgain,
          icon: Icons.refresh_rounded,
          expand: false,
          onPressed: onLoadMore,
        ),
      );
    }
    if (!state.hasMore) {
      return Center(
        child: Text(
          '— PORTIX —',
          style: context.texts.labelSmall?.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 3,
          ),
        ),
      );
    }
    return Center(
      child: SecondaryButton(
        label: context.l10n.seeAll,
        icon: Icons.expand_more_rounded,
        expand: false,
        onPressed: onLoadMore,
      ),
    );
  }
}
