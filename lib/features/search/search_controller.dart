import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/game.dart';
import '../../models/search.dart';

enum SearchStatus { idle, loading, loadingMore, ready, empty, error }

class SearchState {
  const SearchState({
    this.query = '',
    this.filters = const SearchFilters(),
    this.items = const <Game>[],
    this.total = 0,
    this.status = SearchStatus.idle,
    this.error,
  });

  final String query;
  final SearchFilters filters;
  final List<Game> items;
  final int total;
  final SearchStatus status;
  final Object? error;

  bool get isInitialLoading => status == SearchStatus.loading && items.isEmpty;

  bool get isLoadingMore => status == SearchStatus.loadingMore;

  bool get hasMore => items.length < total;

  SearchState copyWith({
    String? query,
    SearchFilters? filters,
    List<Game>? items,
    int? total,
    SearchStatus? status,
    Object? error,
    bool clearError = false,
  }) =>
      SearchState(
        query: query ?? this.query,
        filters: filters ?? this.filters,
        items: items ?? this.items,
        total: total ?? this.total,
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
      );
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

// Últimas buscas ficam no dispositivo: nenhum dado sensível, só conveniência.
final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(RecentSearchesNotifier.new);

class RecentSearchesNotifier extends Notifier<List<String>> {
  static const String _key = 'search.recent';
  static const int _limit = 8;

  @override
  List<String> build() =>
      ref.watch(sharedPreferencesProvider).getStringList(_key) ?? const <String>[];

  void remember(String query) {
    final String clean = query.trim();
    if (clean.isEmpty) {
      return;
    }
    final List<String> next = <String>[
      clean,
      ...state.where((String item) => item.toLowerCase() != clean.toLowerCase()),
    ].take(_limit).toList(growable: false);
    state = next;
    unawaited(ref.read(sharedPreferencesProvider).setStringList(_key, next));
  }

  void clear() {
    state = const <String>[];
    unawaited(ref.read(sharedPreferencesProvider).remove(_key));
  }
}

class SearchController extends Notifier<SearchState> {
  Timer? _debounce;
  int _requestId = 0;

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _debounce = null;
    });
    return const SearchState();
  }

  // A busca só dispara na primeira vez que a tela aparece ou quando a home
  // envia um filtro; evita requisição duplicada ao abrir a aba.
  void ensureLoaded() {
    if (state.status == SearchStatus.idle) {
      unawaited(_fetch(reset: true));
    }
  }

  void setQuery(String value) {
    state = state.copyWith(query: value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_fetch(reset: true));
    });
  }

  void submitQuery(String value) {
    _debounce?.cancel();
    state = state.copyWith(query: value);
    unawaited(_fetch(reset: true));
  }

  void browse({
    String? platform,
    String? genre,
    bool freeOnly = false,
    String sort = 'trending',
  }) {
    _debounce?.cancel();
    state = state.copyWith(
      query: '',
      filters: SearchFilters(
        platform: platform,
        genre: genre,
        freeOnly: freeOnly,
        sort: sort,
      ),
    );
    unawaited(_fetch(reset: true));
  }

  void applyFilters(SearchFilters filters) {
    _debounce?.cancel();
    state = state.copyWith(filters: filters);
    unawaited(_fetch(reset: true));
  }

  void resetFilters() => applyFilters(const SearchFilters());

  Future<void> refresh() => _fetch(reset: true);

  Future<void> loadMore() async {
    if (state.status != SearchStatus.ready || !state.hasMore) {
      return;
    }
    await _fetch(reset: false);
  }

  Future<void> _fetch({required bool reset}) async {
    final int requestId = ++_requestId;
    final String query = state.query.trim();
    final SearchFilters filters = state.filters;
    final int offset = reset ? 0 : state.items.length;

    state = SearchState(
      query: state.query,
      filters: filters,
      items: reset ? const <Game>[] : state.items,
      total: reset ? 0 : state.total,
      status: reset ? SearchStatus.loading : SearchStatus.loadingMore,
    );

    try {
      final SearchPayload payload = await ref.read(catalogRepositoryProvider).search(
            SearchRequest(query: query, filters: filters, offset: offset),
          );
      if (requestId != _requestId) {
        return;
      }
      final List<Game> items =
          reset ? payload.items : _merge(state.items, payload.items);
      state = SearchState(
        query: query,
        filters: filters,
        items: items,
        total: payload.total,
        status: items.isEmpty ? SearchStatus.empty : SearchStatus.ready,
      );
      if (reset && query.isNotEmpty) {
        ref.read(recentSearchesProvider.notifier).remember(query);
      }
    } on Object catch (error) {
      if (requestId != _requestId) {
        return;
      }
      state = SearchState(
        query: query,
        filters: filters,
        items: reset ? const <Game>[] : state.items,
        total: reset ? 0 : state.total,
        status: reset ? SearchStatus.error : SearchStatus.ready,
        error: error,
      );
    }
  }

  List<Game> _merge(List<Game> current, List<Game> incoming) {
    final Set<String> seen = current.map((Game game) => game.id).toSet();
    final List<Game> next = <Game>[...current];
    for (final Game game in incoming) {
      if (seen.add(game.id)) {
        next.add(game);
      }
    }
    return next;
  }
}
