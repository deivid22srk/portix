import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/env.dart';
import '../../models/game.dart';
import '../../models/home_feed.dart';
import '../../models/search.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/states.dart';
import '../home/home_controller.dart';
import 'search_controller.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) {
        return;
      }
      _text.text = ref.read(searchControllerProvider).query;
      ref.read(searchControllerProvider.notifier).ensureLoaded();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 520) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }
  }

  void _runQuery(String term) {
    _focus.unfocus();
    _text.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    ref.read(searchControllerProvider.notifier).submitQuery(term);
  }

  Future<void> _openFilters(SearchState state, CatalogFacets facets) async {
    final SearchFilters? result = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (BuildContext context) => _FilterSheet(
        initial: state.filters,
        facets: facets,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    ref.read(searchControllerProvider.notifier).applyFilters(result);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    final SearchState state = ref.watch(searchControllerProvider);
    final List<String> recent = ref.watch(recentSearchesProvider);
    final CatalogFacets facets =
        ref.watch(catalogFacetsProvider).value ?? const CatalogFacets();

    ref.listen<SearchState>(searchControllerProvider, (SearchState? previous, SearchState next) {
      if (next.query != _text.text) {
        _text.value = TextEditingValue(
          text: next.query,
          selection: TextSelection.collapsed(offset: next.query.length),
        );
      }
    });

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: p.primary,
        backgroundColor: p.surface,
        onRefresh: () => ref.read(searchControllerProvider.notifier).refresh(),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            l10n.searchTitle,
                            style: context.texts.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ),
                        IconGlassButton(
                          icon: Icons.tune_rounded,
                          tooltip: l10n.filters,
                          active: state.filters.activeCount > 0,
                          onTap: () => _openFilters(state, facets),
                          badge: state.filters.activeCount == 0
                              ? null
                              : Container(
                                  width: 17,
                                  height: 17,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: p.primary,
                                  ),
                                  child: Text(
                                    state.filters.activeCount.toString(),
                                    style: context.texts.labelSmall?.copyWith(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GlassPanel(
                      radius: 17,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.search_rounded, size: 20, color: p.muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _text,
                              focusNode: _focus,
                              onChanged: (String value) => ref
                                  .read(searchControllerProvider.notifier)
                                  .setQuery(value),
                              onSubmitted: _runQuery,
                              textInputAction: TextInputAction.search,
                              style: context.texts.bodyLarge?.copyWith(
                                color: p.text,
                              ),
                              cursorColor: p.primary,
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: l10n.searchHint,
                                hintStyle: context.texts.bodyMedium?.copyWith(
                                  color: p.muted,
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 15),
                              ),
                            ),
                          ),
                          if (state.query.isNotEmpty)
                            Pressable(
                              onTap: () {
                                _text.clear();
                                ref
                                    .read(searchControllerProvider.notifier)
                                    .setQuery('');
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: p.muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (state.filters.activeCount > 0) ...<Widget>[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: _activeFilters(context, state, facets),
                      ),
                    ],
                    if (state.query.isEmpty && recent.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 20),
                      Row(
                        children: <Widget>[
                          Icon(Icons.history_rounded, size: 15, color: p.muted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.recentSearches,
                              style: context.texts.labelMedium?.copyWith(
                                color: p.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Pressable(
                            onTap: () => ref
                                .read(recentSearchesProvider.notifier)
                                .clear(),
                            child: Text(
                              l10n.clearHistory,
                              style: context.texts.labelSmall?.copyWith(
                                color: p.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final String term in recent)
                            AppPill(
                              label: term,
                              dense: true,
                              onTap: () => _runQuery(term),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
            if (state.status == SearchStatus.loading && state.items.isEmpty)
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
                    onAction: state.filters.isDefault
                        ? null
                        : () => ref
                            .read(searchControllerProvider.notifier)
                            .resetFilters(),
                  ),
                ),
              ),
            if (state.items.isNotEmpty) ...<Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                  child: Text(
                    l10n.resultsCount(state.total),
                    style: context.texts.labelMedium?.copyWith(color: p.muted),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 210,
                    mainAxisSpacing: 22,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.56,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
                      final Game game = state.items[index];
                      return GameCard(
                        game: game,
                        width: double.infinity,
                        heroTag: 'search-${game.id}',
                      );
                    },
                    childCount: state.items.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
                  child: _ResultsFooter(
                    state: state,
                    onLoadMore: () =>
                        ref.read(searchControllerProvider.notifier).loadMore(),
                  ),
                ),
              ),
            ],
            if (state.items.isEmpty &&
                state.status != SearchStatus.loading &&
                state.status != SearchStatus.error &&
                state.status != SearchStatus.empty)
              const SliverToBoxAdapter(child: SizedBox(height: 130)),
          ],
        ),
      ),
    );
  }

  List<Widget> _activeFilters(
    BuildContext context,
    SearchState state,
    CatalogFacets facets,
  ) {
    final L10n l10n = context.l10n;
    final List<Widget> chips = <Widget>[];
    final String? platform = state.filters.platform;
    if (platform != null) {
      String name = platform;
      for (final PlatformInfo item in facets.platforms) {
        if (item.slug == platform) {
          name = item.name;
        }
      }
      chips.add(
        _ActiveChip(
          label: name,
          onTap: () => ref
              .read(searchControllerProvider.notifier)
              .applyFilters(state.filters.copyWith(clearPlatform: true)),
        ),
      );
    }
    final String? genre = state.filters.genre;
    if (genre != null) {
      chips.add(
        _ActiveChip(
          label: genre,
          onTap: () => ref
              .read(searchControllerProvider.notifier)
              .applyFilters(state.filters.copyWith(clearGenre: true)),
        ),
      );
    }
    if (state.filters.freeOnly) {
      chips.add(
        _ActiveChip(
          label: l10n.filterFree,
          onTap: () => ref
              .read(searchControllerProvider.notifier)
              .applyFilters(state.filters.copyWith(freeOnly: false)),
        ),
      );
    }
    if (state.filters.needsRom) {
      chips.add(
        _ActiveChip(
          label: l10n.filterRom,
          onTap: () => ref
              .read(searchControllerProvider.notifier)
              .applyFilters(state.filters.copyWith(needsRom: false)),
        ),
      );
    }
    if (state.filters.sort != 'trending') {
      chips.add(
        _ActiveChip(
          label: filterSortLabel(l10n, state.filters.sort),
          onTap: () => ref
              .read(searchControllerProvider.notifier)
              .applyFilters(state.filters.copyWith(sort: 'trending')),
        ),
      );
    }
    return chips;
  }
}

// O catálogo de facetas é lido de forma tolerante: os filtros funcionam mesmo
// se a rede ainda não respondeu (lista vazia, sem travar a tela).
String filterSortLabel(L10n l10n, String sort) {
  switch (sort) {
    case 'recent':
      return l10n.sortRecent;
    case 'az':
      return l10n.sortAz;
    case 'year':
      return l10n.sortYear;
    case 'trending':
    default:
      return l10n.sortTrending;
  }
}

class _ResultsFooter extends StatelessWidget {
  const _ResultsFooter({required this.state, required this.onLoadMore});

  final SearchState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    if (state.isLoadingMore) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: p.primary),
        ),
      );
    }
    if (state.error != null && state.items.isNotEmpty) {
      return Center(
        child: GhostButton(
          label: context.l10n.tryAgain,
          icon: Icons.refresh_rounded,
          onPressed: onLoadMore,
        ),
      );
    }
    if (!state.hasMore) {
      return Center(
        child: Text(
          '— PORTIX —',
          style: context.texts.labelSmall?.copyWith(
            color: p.muted,
            letterSpacing: 3,
          ),
        ),
      );
    }
    return Center(
      child: GhostButton(
        label: context.l10n.seeAll,
        icon: Icons.expand_more_rounded,
        onPressed: onLoadMore,
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: p.primary.withValues(alpha: 0.14),
          border: Border.all(color: p.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: context.texts.labelSmall?.copyWith(
                color: p.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.close_rounded, size: 13, color: p.muted),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.facets});

  final SearchFilters initial;
  final CatalogFacets facets;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late SearchFilters _filters = widget.initial;

  void _apply() => Navigator.of(context).pop(_filters);

  void _reset() => setState(() => _filters = const SearchFilters());

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    final double maxHeight = MediaQuery.of(context).size.height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: BoxDecoration(
          color: p.bgSoft,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.muted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.filters,
                        style: context.texts.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Pressable(
                      onTap: _reset,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Text(
                          l10n.reset,
                          style: context.texts.labelMedium?.copyWith(
                            color: p.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _SheetLabel(l10n.filterPlatform),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            AppPill(
                              label: l10n.all,
                              dense: true,
                              selected: _filters.platform == null,
                              onTap: () => setState(
                                () => _filters =
                                    _filters.copyWith(clearPlatform: true),
                              ),
                            ),
                            for (final PlatformInfo platform in widget.facets.platforms)
                              AppPill(
                                label: platform.name,
                                dense: true,
                                selected: _filters.platform == platform.slug,
                                onTap: () => setState(() {
                                  _filters = _filters.platform == platform.slug
                                      ? _filters.copyWith(clearPlatform: true)
                                      : _filters.copyWith(platform: platform.slug);
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _SheetLabel(l10n.filterGenre),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            AppPill(
                              label: l10n.all,
                              dense: true,
                              selected: _filters.genre == null,
                              onTap: () => setState(
                                () => _filters =
                                    _filters.copyWith(clearGenre: true),
                              ),
                            ),
                            for (final GenreInfo genre in widget.facets.genres)
                              AppPill(
                                label: genre.name,
                                dense: true,
                                selected: _filters.genre == genre.name,
                                onTap: () => setState(() {
                                  _filters = _filters.genre == genre.name
                                      ? _filters.copyWith(clearGenre: true)
                                      : _filters.copyWith(genre: genre.name);
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _SheetLabel(l10n.sortLabel),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final String sort in <String>[
                              'trending',
                              'recent',
                              'az',
                              'year',
                            ])
                              AppPill(
                                label: filterSortLabel(l10n, sort),
                                dense: true,
                                selected: _filters.sort == sort,
                                onTap: () => setState(
                                  () => _filters = _filters.copyWith(sort: sort),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _ToggleRow(
                          title: l10n.filterFree,
                          value: _filters.freeOnly,
                          onChanged: (bool value) => setState(
                            () => _filters = _filters.copyWith(freeOnly: value),
                          ),
                        ),
                        _ToggleRow(
                          title: l10n.filterRom,
                          value: _filters.needsRom,
                          onChanged: (bool value) => setState(
                            () => _filters = _filters.copyWith(needsRom: value),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GradientButton(
                  label: l10n.apply,
                  icon: Icons.check_rounded,
                  onPressed: _apply,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: context.texts.labelSmall?.copyWith(
          color: context.palette.muted,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: context.texts.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          AppToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
