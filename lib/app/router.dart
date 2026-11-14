import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme/tokens.dart';
import '../features/details/game_detail_page.dart';
import '../features/details/game_reports_page.dart';
import '../features/explore/explore_page.dart';
import '../features/home/home_page.dart';
import '../features/hub/hub_page.dart';
import '../features/menu/menu_page.dart';
import '../features/news/news_page.dart';
import '../features/profile/auth_page.dart';
import '../features/profile/profile_edit_page.dart';
import '../features/search/search_page.dart';
import '../features/shell/main_shell.dart';
import '../features/shell/not_found_page.dart';

// Rotas com um único ponto de verdade. As cinco abas vivem num
// StatefulShellRoute (estado preservado); busca e detalhes são rotas de topo
// (sem a barra de navegação).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    redirect: (BuildContext context, GoRouterState state) =>
        state.uri.path == '/' ? '/home' : null,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell navigationShell,
        ) =>
            MainShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          _branch(<RouteBase>[GoRoute(path: '/home', builder: _home)]),
          _branch(<RouteBase>[GoRoute(path: '/explore', builder: _explore)]),
          _branch(<RouteBase>[GoRoute(path: '/news', builder: _news)]),
          _branch(<RouteBase>[GoRoute(path: '/hub', builder: _hub)]),
          _branch(<RouteBase>[GoRoute(path: '/menu', builder: _menu)]),
        ],
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _expandPage(state, const SearchPage()),
      ),
      GoRoute(
        path: '/auth',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _expandPage(state, const AuthPage()),
      ),
      GoRoute(
        path: '/profile/edit',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _expandPage(state, const ProfileEditPage()),
      ),
      GoRoute(
        path: '/game/:slug',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final Object? extra = state.extra;
          return _expandPage(
            state,
            GameDetailPage(
              slug: state.pathParameters['slug'] ?? '',
              heroTag: extra is String ? extra : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/game/:slug/reports',
        pageBuilder: (BuildContext context, GoRouterState state) => _expandPage(
          state,
          GameReportsPage(slug: state.pathParameters['slug'] ?? ''),
        ),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        const NotFoundPage(),
  );
});

StatefulShellBranch _branch(List<RouteBase> routes) =>
    StatefulShellBranch(routes: routes);

Widget _home(BuildContext context, GoRouterState state) => const HomePage();

Widget _explore(BuildContext context, GoRouterState state) => const ExplorePage();

Widget _news(BuildContext context, GoRouterState state) => const NewsPage();

Widget _hub(BuildContext context, GoRouterState state) => const HubPage();

Widget _menu(BuildContext context, GoRouterState state) => const MenuPage();

/// Transição de expansão (fade + leve escala) para busca e detalhes.
CustomTransitionPage<void> _expandPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.base,
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.emphasized,
        reverseCurve: AppMotion.out,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
