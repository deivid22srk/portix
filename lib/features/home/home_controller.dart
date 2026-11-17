import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/catalog_repository.dart';
import '../../models/app_update.dart';
import '../../models/home_feed.dart';

final homeFeedProvider = AsyncNotifierProvider<HomeFeedNotifier, HomeFeed>(
  HomeFeedNotifier.new,
);

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
    return repository.fetchHome();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(catalogRepositoryProvider).fetchHome(),
    );
  }

  Future<void> _revalidate(CatalogRepository repository) async {
    try {
      final HomeFeed fresh = await repository.fetchHome();
      if (!_alive) {
        return;
      }
      state = AsyncData(fresh);
    } on Object {
      return;
    }
  }
}
