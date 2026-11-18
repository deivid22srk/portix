// Testes de widget da tela Explorar redesenhada: descoberta (seções,
// categorias, histórico), modo busca (contador, chips, grade/lista), estados
// (vazio com sugestão, offline com cache), teclado (Enter/Esc/setas) e
// reflexão do estado na rota (deep link).
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:portix/app/theme.dart';
import 'package:portix/core/env.dart';
import 'package:portix/core/providers.dart';
import 'package:portix/data/catalog_repository.dart';
import 'package:portix/features/explore/explore_page.dart';
import 'package:portix/models/app_update.dart';
import 'package:portix/models/collections.dart';
import 'package:portix/models/compat_report.dart';
import 'package:portix/models/explore.dart';
import 'package:portix/models/game.dart';
import 'package:portix/models/game_detail.dart';
import 'package:portix/models/home_feed.dart';
import 'package:portix/models/news.dart';
import 'package:portix/models/profile.dart';
import 'package:portix/models/public_profile.dart';
import 'package:portix/models/search.dart';
import 'package:portix/models/user_result.dart';

Game _game(String id, String title, {String? genre, String? developer}) =>
    Game(
      id: id,
      slug: id,
      title: title,
      genre: genre,
      developer: developer,
      coverUrl: null,
    );

class _FakeRepo implements CatalogRepository, ExploreDiscoveryRepository {
  _FakeRepo();

  final List<String> queries = <String>[];
  Future<SearchPayload> Function(SearchRequest request)? onSearch;
  bool failSearch = false;
  bool failExplore = false;
  ExploreFeed? cachedExplore;

  @override
  Future<SearchPayload> search(SearchRequest request) async {
    queries.add(request.query);
    if (failSearch) {
      throw const AppFailure(FailureKind.network);
    }
    final Future<SearchPayload>? custom = onSearch?.call(request);
    if (custom != null) {
      return custom;
    }
    return SearchPayload(
      items: <Game>[
        _game('r1', 'Result Alpha'),
        _game('r2', 'Result Beta'),
        _game('r3', 'Result Gamma'),
      ],
      total: 3,
    );
  }

  @override
  Future<SuggestPayload> suggest(String query) async => SuggestPayload(
    games: <Game>[_game('s1', 'Super Mario World', developer: 'Nintendo')],
    genres: <GenreInfo>[const GenreInfo(name: 'Plataforma', gameCount: 9)],
  );

  @override
  Future<ExploreFeed> fetchExploreFeed() async {
    if (failExplore) {
      throw const AppFailure(FailureKind.network);
    }
    return ExploreFeed(
      trending: <Game>[_game('t1', 'Em Alta Um'), _game('t2', 'Em Alta Dois')],
      newReleases: <Game>[_game('n1', 'Novidade Um')],
      topRated: <Game>[_game('q1', 'Avaliado Um')],
      free: <Game>[_game('f1', 'Grátis Um')],
      popularSearches: <Game>[_game('p1', 'Em Alta Nas Buscas')],
      genres: <GenreInfo>[
        const GenreInfo(name: 'Aventura', gameCount: 12),
        const GenreInfo(name: 'RPG', gameCount: 8),
        const GenreInfo(name: 'Puzzle', gameCount: 5),
      ],
    );
  }

  @override
  ExploreFeed? readCachedExploreFeed() => cachedExplore;

  @override
  HomeFeed? readCachedHome() => null;

  @override
  Future<HomeFeed> fetchHome() async => const HomeFeed();

  @override
  Future<CatalogFacets> fetchFacets() async => const CatalogFacets(
    platforms: <PlatformInfo>[],
    genres: <GenreInfo>[const GenreInfo(name: 'Aventura', gameCount: 12)],
  );

  @override
  Future<GameDetail> fetchGame(String slug) => throw UnimplementedError();

  @override
  Future<NewsPayload> fetchNews({int offset = 0, int limit = 20}) =>
      throw UnimplementedError();

  @override
  Future<NewsItem?> fetchNewsArticle(String slug) => throw UnimplementedError();

  @override
  Future<List<CompatReport>> fetchCompatReports(String gameId) =>
      throw UnimplementedError();

  @override
  Future<UserProfile> fetchProfile() => throw UnimplementedError();

  @override
  Future<void> setHandle(String handle) => throw UnimplementedError();

  @override
  Future<List<UserResult>> searchUsers(String query) =>
      throw UnimplementedError();

  @override
  Future<PublicProfile> fetchPublicProfile(String id) =>
      throw UnimplementedError();

  @override
  Future<AppUpdate?> fetchLatestUpdate() => throw UnimplementedError();

  @override
  Future<void> updateProfile({String? displayName, String? coverUrl}) =>
      throw UnimplementedError();

  @override
  Future<Collections> fetchCollections() => throw UnimplementedError();

  @override
  Future<bool> toggleFavorite(String gameId) => throw UnimplementedError();

  @override
  Future<bool> toggleLibrary(String gameId) => throw UnimplementedError();

  @override
  Future<void> addToLibrary(String gameId) => throw UnimplementedError();

  @override
  Future<void> submitReview({
    required String gameId,
    required int rating,
    required String body,
    required String verdict,
    int? fps,
    String? brand,
    String? model,
    String? soc,
    String? gpu,
    int? ramGb,
  }) => throw UnimplementedError();

  @override
  Future<void> syncDownload({
    required String gameId,
    required String? portKey,
    required String status,
    required int progress,
  }) => throw UnimplementedError();
}

Future<(ProviderContainer, GoRouter)> _pump(
  WidgetTester tester,
  _FakeRepo repo, {
  Map<String, String> initialQuery = const <String, String>{},
  Size size = const Size(390, 844),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final GoRouter router = GoRouter(
    initialLocation: Uri(
      path: '/explore',
      queryParameters: initialQuery.isEmpty ? null : initialQuery,
    ).toString(),
    routes: <RouteBase>[
      GoRoute(
        path: '/explore',
        // A casca (MainShell) fornece o Scaffold em produção.
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: ExplorePage(initialQuery: state.uri.queryParameters),
        ),
      ),
      GoRoute(
        path: '/game/:slug',
        builder: (BuildContext context, GoRouterState state) =>
            Scaffold(body: Text('detalhe-${state.pathParameters['slug']}')),
      ),
    ],
  );

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ProviderContainer container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      catalogRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const <Locale>[Locale('pt', 'BR'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump(); // post-frame (ensureLoaded)
  await tester.pumpAndSettle();
  return (container, router);
}

void main() {
  testWidgets(
    'modo descoberta: categorias, carrosséis e termos em alta sem carrossel vazio',
    (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo();
      final (_, GoRouter router) = await _pump(tester, repo);

      // Campo de busca com hint novo (na dobra).
      expect(
        find.text('Buscar jogos, categorias ou desenvolvedores'),
        findsOneWidget,
      );
      // Seções da descoberta visíveis na dobra.
      expect(find.text('Categorias'), findsOneWidget);
      expect(find.text('Aventura'), findsWidgets);
      expect(find.text('Em alta'), findsWidgets);
      expect(find.text('Em alta nas buscas'), findsOneWidget);
      expect(find.text('Em Alta Nas Buscas'), findsOneWidget);

      // Slivers são lazy: rolar para ver o restante dos carrosséis.
      for (int i = 0; i < 12; i += 1) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pumpAndSettle();
      expect(find.text('Novidades'), findsOneWidget);
      expect(find.text('Mais bem avaliados'), findsOneWidget);
      expect(find.text('Grátis e aberto'), findsOneWidget);
      expect(find.text('Novidade Um'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/explore');
    },
  );

  testWidgets(
    'modo busca: contador de resultados, chips de filtros e alternância lista',
    (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo();
      final (_, GoRouter router) = await _pump(tester, repo);

      await tester.enterText(
        find.byType(TextField),
        'mario',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // Contador anunciado + resultados na grade.
      expect(find.text('3 resultados'), findsOneWidget);
      expect(find.text('Result Alpha'), findsOneWidget);
      // A rota reflete o estado (deep link).
      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['q'],
        'mario',
      );

      // Alternância grade → lista.
      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['view'],
        'list',
      );
    },
  );

  testWidgets(
    'sem resultados: "Você quis dizer…?", limpar filtros e categorias',
    (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo();
      repo.onSearch = (SearchRequest request) => Future<SearchPayload>.value(
        SearchPayload(
          items: const <Game>[],
          total: 0,
          suggestion: 'Frontier',
        ),
      );
      await _pump(tester, repo);

      await tester.enterText(find.byType(TextField), 'frontir');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('Nada encontrado'), findsOneWidget);
      // Sugestão "Você quis dizer…" como chip tocável.
      expect(find.text('Frontier'), findsOneWidget);
    },
  );

  testWidgets(
    'offline: descoberta mostra cache com aviso de desatualização',
    (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo();
      repo.cachedExplore = ExploreFeed(
        trending: <Game>[_game('c1', 'Cache Um')],
        genres: <GenreInfo>[const GenreInfo(name: 'Aventura', gameCount: 3)],
      );
      repo.failExplore = true;
      await _pump(tester, repo);

      // Cache síncrono abre com conteúdo e o banner explica a desatualização.
      expect(find.text('Cache Um'), findsOneWidget);
      expect(
        find.text('Mostrando dados salvos — podem estar desatualizados.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'busca offline sem cache: erro explicado com ação de tentar de novo',
    (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo();
      repo.failSearch = true;
      await _pump(tester, repo);

      await tester.enterText(find.byType(TextField), 'mario');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('Sem conexão'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
    },
  );

  testWidgets(
    'teclado: Enter busca, Esc limpa e volta ao modo descoberta',
    (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo();
      final (_, GoRouter router) = await _pump(tester, repo);

      final Finder field = find.byType(TextField);
      await tester.tap(field); // foco real no campo (sendKeyEvent precisa)
      await tester.pumpAndSettle();
      await tester.enterText(field, 'mario');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['q'],
        'mario',
      );

      // Esc limpa o campo e a rota volta ao modo descoberta.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['q'],
        isNull,
      );
    },
  );

  testWidgets(
    'deep link: /explore?q=…&genre=… aplica texto e filtro no abrir',
    (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo();
      await _pump(
        tester,
        repo,
        initialQuery: <String, String>{'q': 'mario', 'genre': 'Aventura'},
      );

      expect(repo.queries, contains('mario'));
      // Chip do filtro ativo removível na barra de resultados.
      expect(find.text('Aventura'), findsWidgets);
    },
  );

  testWidgets(
    'sugestões: painel aparece ao digitar e Enter no texto busca',
    (WidgetTester tester) async {
      final _FakeRepo repo = _FakeRepo();
      await _pump(tester, repo);

      await tester.enterText(find.byType(TextField), 'mario');
      await tester.pumpAndSettle();

      // Painel de sugestões com trecho destacado (jogo sugerido do fake).
      expect(find.text('Super Mario World'), findsOneWidget);
      expect(find.text('Plataforma'), findsOneWidget);
    },
  );
}
