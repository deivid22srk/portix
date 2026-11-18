import 'dart:async' show unawaited;

import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide SearchController;

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/theme/tokens.dart';
import '../../features/explore/explore_controller.dart';
import '../../models/explore.dart';
import '../../models/game.dart';
import '../../models/home_feed.dart';
import '../../models/search.dart';
import '../../shared/widgets/app_header.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/filter_sheet.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/reveal.dart';
import '../../shared/widgets/search_widgets.dart';
import '../../shared/widgets/states.dart';
import '../home/feed_sections.dart';
import '../home/home_controller.dart';
import '../search/search_controller.dart';
import '../shell/tab_scroll_registry.dart';

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key, this.initialQuery = const <String, String>{}});

  /// Deep link: /explore?q=…&genre=…&platform=…&free=1&rom=1&min=4&sort=…&view=list
  final Map<String, String> initialQuery;

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  // O controlador pertence ao registro de abas (a casca o descarta): a posição
  // de rolagem sobrevive à troca de aba e o re-toque sabe voltar ao topo.
  late final ScrollController _scroll = ref
      .read(tabScrollRegistryProvider)
      .controllerFor(AppTab.explore);

  bool _appliedInitialQuery = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) {
        return;
      }
      _applyInitialQuery();
      ref.read(exploreControllerProvider.notifier).ensureLoaded();
      ref.read(searchControllerProvider.notifier).ensureLoaded();
    });
  }

  @override
  void didUpdateWidget(ExplorePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Deep link chegando com a tela já montada (ex.: push de outra tela).
    if (!_mapsEqual(widget.initialQuery, oldWidget.initialQuery)) {
      _appliedInitialQuery = false;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) {
          _applyInitialQuery();
        }
      });
    }
  }

  @override
  void dispose() {
    // Só solta o listener: o controlador é do registro (compartilhado).
    _scroll.removeListener(_onScroll);
    super.dispose();
  }

  Future<void> _applyInitialQuery() async {
    if (_appliedInitialQuery) {
      return;
    }
    final Map<String, String> params = widget.initialQuery;
    if (params.isEmpty) {
      return;
    }
    _appliedInitialQuery = true;
    final SearchController controller = ref.read(
      searchControllerProvider.notifier,
    );
    final String q = params['q'] ?? '';
    SearchFilters filters = ref.read(searchControllerProvider).filters;
    filters = filters.copyWith(
      platform: params['platform'],
      genre: params['genre'],
      freeOnly: params['free'] == '1',
      needsRom: params['rom'] == '1',
      minRating: params['min'] == null ? null : double.tryParse(params['min']!),
      sort: params['sort'] ?? kDefaultSort,
    );
    controller.applyFilters(filters);
    if (params['view'] == 'list') {
      ref.read(resultsViewProvider.notifier).set(true);
    }
    if (q.isNotEmpty) {
      await controller.submitQuery(q);
    }
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

  /// Estado → rota (deep link): texto, filtros, ordenação e modo de exibição.
  /// Sincroniza sem recriar a página (mesma rota, só a query string muda).
  void _syncRoute(SearchState state) {
    final Map<String, String> current = GoRouterState.of(
      context,
    ).uri.queryParameters;
    final Map<String, String> next = _routeFromState(state);
    if (_mapsEqual(current, next)) {
      return;
    }
    final Uri uri = Uri(
      path: '/explore',
      queryParameters: next.isEmpty ? null : next,
    );
    context.go(uri.toString());
  }

  Map<String, String> _routeFromState(SearchState state) {
    final SearchFilters filters = state.filters;
    final Map<String, String> params = <String, String>{
      if (state.query.trim().isNotEmpty) 'q': state.query.trim(),
      if (filters.platform != null) 'platform': filters.platform!,
      if (filters.genre != null) 'genre': filters.genre!,
      if (filters.freeOnly) 'free': '1',
      if (filters.needsRom) 'rom': '1',
      if (filters.minRating != null) 'min': '${filters.minRating}',
      if (filters.sort != kDefaultSort) 'sort': filters.sort,
      if (ref.read(resultsViewProvider)) 'view': 'list',
    };
    return params;
  }

  bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final MapEntry<String, String> entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final SearchState state = ref.watch(searchControllerProvider);
    final CatalogFacets facets =
        ref.watch(catalogFacetsProvider).value ?? const CatalogFacets();

    ref.listen<SearchState>(searchControllerProvider, (
      SearchState? previous,
      SearchState next,
    ) {
      // Sincroniza a rota quando um FETCH assenta (loading → ready/empty/
      // error) ou quando o modo descoberta retorna (idle) — nunca a cada
      // tecla: o debounce em voo não reescreve a URL.
      final bool busy =
          next.status == SearchStatus.loading ||
          next.status == SearchStatus.loadingMore;
      if (busy) {
        return;
      }
      final bool wasBusy =
          previous != null &&
          (previous.status == SearchStatus.loading ||
              previous.status == SearchStatus.loadingMore);
      final bool backToDiscovery =
          next.status == SearchStatus.idle &&
          previous?.status != SearchStatus.idle;
      if (wasBusy || backToDiscovery) {
        _syncRoute(next);
      }
    });
    ref.listen<bool>(resultsViewProvider, (bool? previous, bool next) {
      _syncRoute(ref.read(searchControllerProvider));
    });

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: context.colors.accent,
        backgroundColor: context.colors.glassStrong,
        onRefresh: () => ref.read(searchControllerProvider.notifier).refresh(),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: <Widget>[
            AppHeaderSliver(
              title: l10n.exploreTitle,
              // O contador de resultados fica na barra de ferramentas (live
              // region) — duplicar aqui competiria com ele.
              subtitle:
                  state.status == SearchStatus.loading &&
                      state.items.isEmpty &&
                      state.query.trim().isNotEmpty
                  ? l10n.loading
                  : l10n.exploreSubtitle,
              actions: <AppHeaderAction>[
                AppHeaderAction(
                  icon: Icons.tune_rounded,
                  active: state.filters.activeCount > 0,
                  tooltip: state.filters.activeCount > 0
                      ? l10n.filtersBadge(state.filters.activeCount)
                      : l10n.filters,
                  badgeCount: state.filters.activeCount,
                  onTap: () => _openFilters(state, facets),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.md,
                  AppSpacing.screen,
                  0,
                ),
                child: SearchField(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
            // Filtros rápidos (funcionalidade da tela original preservada):
            // Tudo / Grátis / plataformas mais relevantes, num toque.
            SliverToBoxAdapter(
              child: SizedBox(
                height: AppSpacing.circleButton,
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
                                  ? state.filters.copyWith(clearPlatform: true)
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
            if (state.query.trim().length < kSearchMinChars)
              ..._discoverySlivers(l10n, facets)
            else
              ..._resultsSlivers(l10n, state, facets),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- descoberta

  List<Widget> _discoverySlivers(L10n l10n, CatalogFacets facets) {
    final ExploreState explore = ref.watch(exploreControllerProvider);
    final List<String> recent = ref.watch(recentSearchesProvider);
    final List<Widget> slivers = <Widget>[];

    if (explore.stale) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              0,
              AppSpacing.screen,
              AppSpacing.md,
            ),
            child: StaleBanner(
              message: l10n.staleNotice,
              onRetry: () =>
                  ref.read(exploreControllerProvider.notifier).load(),
            ),
          ),
        ),
      );
    }
    if (explore.isInitialLoading) {
      slivers.add(const SliverToBoxAdapter(child: ExploreSkeleton()));
      return slivers;
    }
    if (explore.status == ExploreStatus.error && explore.feed.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: AppSpacing.emptyStateViewport + AppSpacing.xxxl,
            child: FeedErrorState(
              error: explore.error,
              onRetry: () =>
                  ref.read(exploreControllerProvider.notifier).load(),
            ),
          ),
        ),
      );
      return slivers;
    }

    // Buscas recentes (histórico local, com remover item e "Limpar tudo").
    if (recent.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(child: _RecentSearches(recent: recent)));
    }

    final ExploreFeed feed = explore.feed;
    // "Em alta nas buscas": popularidade (views/downloads) como proxy
    // conservador — não existe registro de termos de busca no banco.
    if (feed.popularSearches.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  0,
                  AppSpacing.screen,
                  AppSpacing.sm,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.trendingSearches,
                    style: context.texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              PopularSearchesRow(games: feed.popularSearches),
            ],
          ),
        ),
      );
    }

    // Grade de categorias (ícone + contagem por gênero).
    if (feed.genres.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.xl,
              AppSpacing.screen,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: l10n.categoriesTitle,
                  subtitle: l10n.categoriesSubtitle,
                ),
              ],
            ),
          ),
        ),
      );
      slivers.add(_CategoryGrid(genres: feed.genres));
    }

    // Carrosséis de descoberta (seções vazias não renderizam).
    void carousel(String title, List<Game> games) {
      if (games.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: GameCarousel(title: title, games: games),
            ),
          ),
        );
      }
    }

    carousel(l10n.sectionTrending, feed.trending);
    carousel(l10n.sectionNewReleases, feed.newReleases);
    carousel(l10n.sectionTopRated, feed.topRated);
    carousel(l10n.sectionFree, feed.free);

    return slivers;
  }

  // ------------------------------------------------------------------- busca

  List<Widget> _resultsSlivers(
    L10n l10n,
    SearchState state,
    CatalogFacets facets,
  ) {
    final List<Widget> slivers = <Widget>[];

    if (state.stale) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              0,
              AppSpacing.screen,
              AppSpacing.md,
            ),
            child: StaleBanner(message: l10n.staleNotice),
          ),
        ),
      );
    }

    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            0,
            AppSpacing.screen,
            AppSpacing.md,
          ),
          child: ResultsToolbar(filters: state.filters, facets: facets),
        ),
      ),
    );

    if (state.isInitialLoading) {
      slivers.add(const SliverToBoxAdapter(child: SearchSkeleton()));
      return slivers;
    }

    if (state.status == SearchStatus.error && state.items.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: AppSpacing.emptyStateViewport + AppSpacing.xxxl,
            child: FeedErrorState(
              error: state.error,
              onRetry: () =>
                  ref.read(searchControllerProvider.notifier).refresh(),
            ),
          ),
        ),
      );
      return slivers;
    }

    if (state.status == SearchStatus.empty || state.items.isEmpty) {
      slivers.add(SliverToBoxAdapter(child: _EmptySearch(state: state)));
      return slivers;
    }

    final bool isList = ref.watch(resultsViewProvider);
    if (isList) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((
              BuildContext context,
              int index,
            ) {
              final Game game = state.items[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: RevealOnMount(
                  index: index,
                  child: GameRow(game: game),
                ),
              );
            }, childCount: state.items.length),
          ),
        ),
      );
    } else {
      slivers.add(
        ResponsiveCoverGrid(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            0,
            AppSpacing.screen,
            0,
          ),
          itemBuilder: (BuildContext context, int index) {
            final Game game = state.items[index];
            return RevealOnMount(
              index: index,
              child: GameCard(game: game, heroTag: 'explore-${game.id}'),
            );
          },
          itemCount: state.items.length,
        ),
      );
    }

    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.xl,
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
    );
    return slivers;
  }
}

// ------------------------------------------------------------------ componentes

/// Buscas recentes: chips removíveis + "Limpar tudo" com confirmação e undo.
class _RecentSearches extends ConsumerStatefulWidget {
  const _RecentSearches({required this.recent});

  final List<String> recent;

  @override
  ConsumerState<_RecentSearches> createState() => _RecentSearchesState();
}

class _RecentSearchesState extends ConsumerState<_RecentSearches> {
  Future<void> _clearAll() async {
    final L10n l10n = context.l10n;
    final List<String> removed = ref.read(recentSearchesProvider);
    if (removed.isEmpty) {
      return;
    }
    final bool ok = await showAppConfirm(
      context,
      title: l10n.clearHistory,
      message: l10n.clearHistoryConfirm,
    );
    if (!ok || !mounted) {
      return;
    }
    ref.read(recentSearchesProvider.notifier).clear();
    showAppSnackBar(
      context,
      message: l10n.historyCleared,
      actionLabel: l10n.undo,
      onAction: () =>
          ref.read(recentSearchesProvider.notifier).restoreAll(removed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.history_rounded,
                size: 15,
                color: context.colors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.recentSearches,
                    style: context.texts.labelMedium?.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
              Pressable(
                onTap: _clearAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxs,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Text(
                    l10n.clearHistory,
                    style: context.texts.labelSmall?.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final String term in widget.recent)
                _RecentChip(
                  term: term,
                  onTap: () => unawaited(
                    ref
                        .read(searchControllerProvider.notifier)
                        .submitQuery(term),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentChip extends ConsumerWidget {
  const _RecentChip({required this.term, required this.onTap});

  final String term;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPill(
      label: term,
      dense: true,
      leading: Icon(
        Icons.search_rounded,
        size: AppSpacing.navIconSize - AppSpacing.xs,
        color: context.colors.textTertiary,
      ),
      trailing: Semantics(
        button: true,
        label: context.l10n.removeSearch,
        child: Pressable(
          onTap: () => ref.read(recentSearchesProvider.notifier).remove(term),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.hairline),
            child: Icon(
              Icons.close_rounded,
              size: AppSpacing.navIconSize - AppSpacing.xxs - AppSpacing.xs,
              color: context.colors.textTertiary,
            ),
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Grade de categorias: 2 colunas no telefone, 3 no tablet, 4 nas larguras.
class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid({required this.genres});

  final List<GenreInfo> genres;

  int _columns(double width) {
    if (width >= AppBreakpoints.desktop) {
      return 4;
    }
    if (width >= AppBreakpoints.tablet) {
      return 3;
    }
    return 2;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverLayoutBuilder(
      builder: (BuildContext context, SliverConstraints constraints) {
        final double width = constraints.crossAxisExtent;
        final double extra = width > AppBreakpoints.contentMax
            ? (width - AppBreakpoints.contentMax) / 2
            : 0;
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screen + extra,
            AppSpacing.md,
            AppSpacing.screen + extra,
            0,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns(width),
              mainAxisSpacing: AppSpacing.gridGap,
              crossAxisSpacing: AppSpacing.gridGap,
              mainAxisExtent: SearchMetrics.categoryTile,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) => RevealOnMount(
                index: index,
                child: CategoryCard(
                  genre: genres[index],
                  onTap: () {
                    final SearchFilters filters = ref
                        .read(searchControllerProvider)
                        .filters;
                    ref
                        .read(searchControllerProvider.notifier)
                        .applyFilters(
                          filters.copyWith(genre: genres[index].name),
                        );
                  },
                ),
              ),
              childCount: genres.length,
            ),
          ),
        );
      },
    );
  }
}

/// Estado vazio da busca: "Você quis dizer…?", limpar filtros e sugestões.
class _EmptySearch extends ConsumerWidget {
  const _EmptySearch({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;
    final CatalogFacets facets =
        ref.watch(catalogFacetsProvider).value ?? const CatalogFacets();
    final String? suggestion = state.suggestion;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: Column(
        children: <Widget>[
          const SizedBox(height: AppSpacing.xxl),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              color: context.colors.glass,
              border: Border.all(color: context.colors.glassBorder),
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 36,
              color: context.colors.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.emptySearchTitle,
            textAlign: TextAlign.center,
            style: context.texts.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.emptySearchBody,
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          if (suggestion != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              button: true,
              child: AppPill(
                label: suggestion,
                leading: Icon(
                  Icons.spellcheck_rounded,
                  size: AppSpacing.navIconSize - AppSpacing.xs,
                  color: context.colors.accent,
                ),
                onTap: () => unawaited(
                  ref
                      .read(searchControllerProvider.notifier)
                      .submitQuery(suggestion),
                ),
              ),
            ),
          ],
          if (!state.filters.isDefault) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            SecondaryButton(
              label: l10n.clearFilters,
              icon: Icons.filter_alt_off_rounded,
              expand: false,
              onPressed: () =>
                  ref.read(searchControllerProvider.notifier).resetFilters(),
            ),
          ],
          if (facets.genres.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xxl),
            Row(
              children: <Widget>[
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: context.colors.accent,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    l10n.sectionGenres,
                    style: context.texts.labelMedium?.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final GenreInfo genre in facets.genres.take(6))
                  AppPill(
                    label: genre.name,
                    dense: true,
                    onTap: () => ref
                        .read(searchControllerProvider.notifier)
                        .applyFilters(
                          state.filters.copyWith(genre: genre.name),
                        ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _ResultsFooter extends StatelessWidget {
  _ResultsFooter({required this.state, required this.onLoadMore});

  final SearchState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.colors.accent,
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
            color: context.colors.textTertiary,
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
