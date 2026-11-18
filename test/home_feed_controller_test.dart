import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/core/env.dart';
import 'package:portix/core/providers.dart';
import 'package:portix/data/supabase_catalog_repository.dart';
import 'package:portix/features/home/home_controller.dart';
import 'package:portix/models/game.dart';
import 'package:portix/models/home_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_feed_repository.dart';

// Controller do feed: cascata de fallback, cache (stale-while-revalidate),
// rotação de seed no refresh e paginação de `discover` sem duplicar ids.

HomeFeedSection _section(String id) => HomeFeedSection(
  key: 'trending',
  kind: 'row',
  items: <Game>[Game(id: id, slug: id, title: id)],
);

HomeFeedSection _discover(List<Game> items, {Map<String, dynamic>? cursor}) =>
    HomeFeedSection(
      key: 'discover',
      kind: 'grid',
      cursor: cursor,
      items: items,
    );

Game _game(String id) => Game(id: id, slug: id, title: 'Game $id');

Future<ProviderContainer> _container(FakeFeedRepository repository) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      catalogRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Deixa os microtasks/futuros pendentes concluírem.
Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cascata de fallback (resolveHomeFeedWithFallback)', () {
    test('usa a RPC nova quando ela responde', () async {
      final HomeFeed feed = await resolveHomeFeedWithFallback(
        primary: () async => const HomeFeed(seed: 'novo'),
        legacy: () async => const HomeFeed(seed: 'legado'),
      );
      expect(feed.seed, 'novo');
      expect(feed.degraded, isFalse);
    });

    test('cai na RPC legada e marca degradado', () async {
      final HomeFeed feed = await resolveHomeFeedWithFallback(
        primary: () async => throw const AppFailure(FailureKind.server),
        legacy: () async =>
            HomeFeed(sections: <HomeFeedSection>[_section('legado')]),
      );
      expect(feed.degraded, isTrue);
      expect(feed.sections.single.items.single.id, 'legado');
    });

    test('se a legada também falha, o erro sobe (controller mantém cache)', () {
      return expectLater(
        resolveHomeFeedWithFallback(
          primary: () async => throw const AppFailure(FailureKind.server),
          legacy: () async => throw const AppFailure(FailureKind.network),
        ),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('HomeFeedNotifier', () {
    test('pinta o cache na hora e revalida em seguida', () async {
      final FakeFeedRepository repository = FakeFeedRepository(
        cached: HomeFeed(sections: <HomeFeedSection>[_section('cached')]),
        onFetch: (_) async =>
            HomeFeed(sections: <HomeFeedSection>[_section('fresh')]),
      );
      final ProviderContainer container = await _container(repository);

      final HomeFeed first = await container.read(homeFeedProvider.future);
      expect(first.sections.single.items.single.id, 'cached');

      await _flush();
      expect(
        container.read(homeFeedProvider).value!.sections.single.items.single.id,
        'fresh',
      );
    });

    test(
      'mantém o cache quando a revalidação falha (sem erro na tela)',
      () async {
        final FakeFeedRepository repository = FakeFeedRepository(
          cached: HomeFeed(sections: <HomeFeedSection>[_section('cached')]),
          onFetch: (_) async => throw const AppFailure(FailureKind.network),
        );
        final ProviderContainer container = await _container(repository);

        final HomeFeed first = await container.read(homeFeedProvider.future);
        expect(first.sections.single.items.single.id, 'cached');
        await _flush();

        final AsyncValue<HomeFeed> state = container.read(homeFeedProvider);
        expect(state.hasError, isFalse);
        expect(state.value!.sections.single.items.single.id, 'cached');
      },
    );

    test(
      'sem cache, a falha vira estado de erro (tela mostra retry)',
      () async {
        final FakeFeedRepository repository = FakeFeedRepository(
          onFetch: (_) async => throw const AppFailure(FailureKind.network),
        );
        final ProviderContainer container = await _container(repository);

        await expectLater(
          container.read(homeFeedProvider.future),
          throwsA(isA<AppFailure>()),
        );
        expect(container.read(homeFeedProvider).hasError, isTrue);
      },
    );

    test('refresh gira a seed da sessão e refaz o feed', () async {
      final FakeFeedRepository repository = FakeFeedRepository(
        onFetch: (_) async =>
            HomeFeed(sections: <HomeFeedSection>[_section('a')]),
      );
      final ProviderContainer container = await _container(repository);

      await container.read(homeFeedProvider.future);
      expect(repository.seeds.length, 1);

      await container.read(homeFeedProvider.notifier).refresh();
      expect(repository.seeds.length, 2);
      expect(repository.seeds.first, isNot(repository.seeds.last));
    });

    test('loadMore acumula a descoberta sem duplicar id', () async {
      final FakeFeedRepository repository = FakeFeedRepository(
        onFetch: (_) async => HomeFeed(
          seed: 's',
          sections: <HomeFeedSection>[
            _discover(
              <Game>[_game('a')],
              cursor: <String, dynamic>{'score': 2, 'id': 'a'},
            ),
          ],
        ),
        loadMorePages: <HomeFeed>[
          HomeFeed(
            sections: <HomeFeedSection>[
              _discover(
                <Game>[_game('a'), _game('b')],
                cursor: <String, dynamic>{'score': 1, 'id': 'b'},
              ),
            ],
          ),
          HomeFeed(
            sections: <HomeFeedSection>[
              _discover(
                <Game>[_game('c')],
                cursor: <String, dynamic>{'score': 0, 'id': 'c'},
              ),
            ],
          ),
        ],
      );
      final ProviderContainer container = await _container(repository);
      await container.read(homeFeedProvider.future);
      final HomeFeedNotifier notifier = container.read(
        homeFeedProvider.notifier,
      );

      await notifier.loadMore();
      HomeDiscoverState more = container.read(homeDiscoverProvider);
      expect(more.extra.map((Game g) => g.id).toList(), <String>['b']);
      expect(more.cursor!['id'], 'b');

      await notifier.loadMore();
      more = container.read(homeDiscoverProvider);
      expect(more.extra.map((Game g) => g.id).toList(), <String>['b', 'c']);
      expect(more.cursor!['id'], 'c');

      // Páginas esgotadas: o fake devolve a seção sem cursor ⇒ fim de lista.
      await notifier.loadMore();
      more = container.read(homeDiscoverProvider);
      expect(more.ended, isTrue);
      expect(repository.loadMoreCursors.length, 3);
    });
  });
}
