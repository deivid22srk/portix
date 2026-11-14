import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/details/game_detail_page.dart';
import '../features/downloads/downloads_page.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/profile/profile_page.dart';
import '../features/search/search_page.dart';
import '../features/shell/main_shell.dart';
import '../features/shell/not_found_page.dart';
import '../features/wishlist/wishlist_page.dart';

// Rotas com um único ponto de verdade. As abas vivem num StatefulShellRoute
// (estado preservado ao alternar) e detalhes/wishlist são rotas de topo.
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
          _branch(<RouteBase>[GoRoute(path: '/search', builder: _search)]),
          _branch(<RouteBase>[GoRoute(path: '/library', builder: _library)]),
          _branch(<RouteBase>[GoRoute(path: '/downloads', builder: _downloads)]),
          _branch(<RouteBase>[GoRoute(path: '/profile', builder: _profile)]),
        ],
      ),
      GoRoute(
        path: '/game/:slug',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final Object? extra = state.extra;
          return _fadeUpPage(
            state,
            GameDetailPage(
              slug: state.pathParameters['slug'] ?? '',
              heroTag: extra is String ? extra : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/wishlist',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _fadeUpPage(state, const WishlistPage()),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        const NotFoundPage(),
  );
});

StatefulShellBranch _branch(List<RouteBase> routes) =>
    StatefulShellBranch(routes: routes);

Widget _home(BuildContext context, GoRouterState state) => const HomePage();

Widget _search(BuildContext context, GoRouterState state) => const SearchPage();

Widget _library(BuildContext context, GoRouterState state) => const LibraryPage();

Widget _downloads(BuildContext context, GoRouterState state) =>
    const DownloadsPage();

Widget _profile(BuildContext context, GoRouterState state) => const ProfilePage();

CustomTransitionPage<void> _fadeUpPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      final Animation<double> curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
}
