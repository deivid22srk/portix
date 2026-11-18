import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/session.dart';
import '../../data/catalog_repository.dart';
import '../../models/app_update.dart';
import '../../models/game.dart';
import '../../models/home_feed.dart';
import 'feed_impressions.dart';

/// Sessão do feed (anon_id + seed de 30 min). Vive num provider para a tela e
/// o repositório compartilharem a MESMA semente — inclusive no registro de
/// impressões (session_id).
final feedSessionProvider = Provider<FeedSession>(
  (ref) => FeedSession(ref.watch(cacheStoreProvider)),
);

final homeFeedProvider = AsyncNotifierProvider<HomeFeedNotifier, HomeFeed>(
  HomeFeedNotifier.new,
);

/// Registro de impressões do feed (best-effort, respeita o opt-out no repo).
final feedImpressionsProvider = Provider<FeedImpressionTracker>((ref) {
  final FeedImpressionTracker tracker = FeedImpressionTracker(
    send: (List<Map<String, dynamic>> items) async {
      final CatalogRepository repository = ref.read(catalogRepositoryProvider);
      if (repository is HomeFeedAlgorithmRepository) {
        await repository.recordImpressions(items);
      }
    },
  );
  ref.onDispose(tracker.dispose);
  return tracker;
});

/// Último aviso de atualização publicado pelo ADM raiz (público).
final latestUpdateProvider = FutureProvider<AppUpdate?>(
  (ref) => ref.watch(catalogRepositoryProvider).fetchLatestUpdate(),
);

// Facetas para os filtros. Se a rede falhar, reaproveita o que veio no feed.
final catalogFacetsProvider = FutureProvider<CatalogFacets>((ref) async {
  final CatalogRepository repository = ref.watch(catalogRepositoryProvider);
  try {
    return await repository.fetchFacets();
  } on Object {
    final HomeFeed? feed = ref.read(homeFeedProvider).value;
    if (feed == null) {
      return CatalogFacets.empty;
    }
    return CatalogFacets(platforms: feed.platforms, genres: feed.genres);
  }
});

/// Paginação da seção `discover` (cursor keyset). Separada do feed para o
/// controller manter um `AsyncNotifier<HomeFeed>` simples e compatível.
class HomeDiscoverState {
  const HomeDiscoverState({
    this.extra = const <Game>[],
    this.cursor,
    this.loading = false,
    this.ended = false,
    this.error,
  });

  /// Itens acumulados além da primeira página (já sem repetição).
  final List<Game> extra;

  /// Cursor da próxima página; `null` usa o cursor da seção do feed.
  final Map<String, dynamic>? cursor;
  final bool loading;

  /// Fim da lista (servidor não devolveu mais cursor ou a seção acabou).
  final bool ended;
  final Object? error;

  HomeDiscoverState copyWith({
    List<Game>? extra,
    Map<String, dynamic>? cursor,
    bool? loading,
    bool? ended,
    Object? error,
    bool clearError = false,
  }) => HomeDiscoverState(
    extra: extra ?? this.extra,
    cursor: cursor ?? this.cursor,
    loading: loading ?? this.loading,
    ended: ended ?? this.ended,
    error: clearError ? null : (error ?? this.error),
  );
}

final homeDiscoverProvider =
    NotifierProvider<HomeDiscoverNotifier, HomeDiscoverState>(
      HomeDiscoverNotifier.new,
    );

class HomeDiscoverNotifier extends Notifier<HomeDiscoverState> {
  @override
  HomeDiscoverState build() => const HomeDiscoverState();

  void reset() => state = const HomeDiscoverState();

  Future<void> loadMore() async {
    final HomeDiscoverState current = state;
    if (current.loading || current.ended) {
      return;
    }
    final HomeFeed? feed = ref.read(homeFeedProvider).value;
    final HomeFeedSection? section = feed?.sectionByKey('discover');
    final Map<String, dynamic>? cursor = current.cursor ?? section?.cursor;
    final CatalogRepository repository = ref.read(catalogRepositoryProvider);
    if (feed == null || section == null || cursor == null) {
      state = current.copyWith(ended: true);
      return;
    }
    if (repository is! HomeFeedAlgorithmRepository) {
      state = current.copyWith(ended: true);
      return;
    }

    state = current.copyWith(loading: true, clearError: true);
    try {
      final String seed = ref.read(feedSessionProvider).seed();
      final List<String> seen = <String>{
        ...section.items.map((Game game) => game.id),
        ...current.extra.map((Game game) => game.id),
      }.toList(growable: false);
      final HomeFeed page = await repository.loadMoreDiscover(
        seed: seed,
        cursor: cursor,
        seen: seen,
        sections: const <String>['discover'],
      );
      final HomeFeedSection? next = page.sectionByKey('discover');
      final Map<String, dynamic>? nextCursor = next?.cursor;
      state = HomeDiscoverState(
        extra: _appendUnique(current.extra, section.items, next?.items),
        cursor: nextCursor,
        ended:
            next == null ||
            nextCursor == null ||
            _sameCursor(nextCursor, cursor),
      );
    } on Object catch (error) {
      state = current.copyWith(loading: false, error: error);
    }
  }

  /// Acrescenta só os itens que ainda não apareceram (primeira página incluída)
  /// — nunca duplica id entre páginas nem entre `extra` e a seção do feed.
  List<Game> _appendUnique(
    List<Game> current,
    List<Game> firstPage,
    List<Game>? incoming,
  ) {
    final Set<String> seen = <String>{
      ...current.map((Game game) => game.id),
      ...firstPage.map((Game game) => game.id),
    };
    final List<Game> merged = List<Game>.of(current);
    for (final Game game in incoming ?? const <Game>[]) {
      if (seen.add(game.id)) {
        merged.add(game);
      }
    }
    return merged;
  }

  bool _sameCursor(Map<String, dynamic> a, Map<String, dynamic> b) =>
      '${a['score']}|${a['id']}' == '${b['score']}|${b['id']}';
}

class HomeFeedNotifier extends AsyncNotifier<HomeFeed> {
  bool _alive = true;

  @override
  Future<HomeFeed> build() {
    _alive = true;
    ref.onDispose(() => _alive = false);

    final CatalogRepository repository = ref.watch(catalogRepositoryProvider);
    final HomeFeed? cached = repository.readCachedHome();
    if (cached != null) {
      // Stale-while-revalidate: pinta o cache na hora e troca quando a rede
      // responde, sem bloquear a home.
      unawaited(_revalidate(repository));
      return Future<HomeFeed>.value(cached);
    }
    return _load(repository);
  }

  Future<void> refresh() async {
    // Pull-to-refresh (e "recarregar catálogo") gira a seed: outro feed sem
    // esperar a janela de 30 minutos.
    await ref.read(feedSessionProvider).rotate();
    ref.read(homeDiscoverProvider.notifier).reset();
    ref.read(feedImpressionsProvider).reset();
    state = await AsyncValue.guard(
      () => _load(ref.read(catalogRepositoryProvider)),
    );
  }

  /// Pagina a seção `discover` (delegado ao notifier de paginação).
  Future<void> loadMore() => ref.read(homeDiscoverProvider.notifier).loadMore();

  Future<HomeFeed> _load(CatalogRepository repository) {
    if (repository is HomeFeedAlgorithmRepository) {
      return repository.fetchHomeFeed(
        seed: ref.read(feedSessionProvider).seed(),
      );
    }
    // Repositórios legados (e fakes de teste) seguem pelo RPC antigo.
    return repository.fetchHome();
  }

  Future<void> _revalidate(CatalogRepository repository) async {
    try {
      final HomeFeed fresh = await _load(repository);
      if (!_alive) {
        return;
      }
      state = AsyncData(fresh);
    } on Object {
      // Mantém o cache pintado; o erro de revalidação não apaga a tela.
      return;
    }
  }
}
