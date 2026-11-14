import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/primitives.dart';

// Casca principal: mantém as cinco abas vivas e desenha a barra de navegação
// de vidro flutuante + botão de busca circular.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _select(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final List<GlassNavItem> items = <GlassNavItem>[
      GlassNavItem(Icons.home_outlined, Icons.home_rounded, l10n.navHome),
      GlassNavItem(
        Icons.sports_esports_outlined,
        Icons.sports_esports_rounded,
        l10n.navExplore,
      ),
      GlassNavItem(Icons.article_outlined, Icons.article_rounded, l10n.navNews),
      GlassNavItem(Icons.layers_outlined, Icons.layers_rounded, l10n.navHub),
      GlassNavItem(Icons.menu_rounded, Icons.menu_rounded, l10n.navMenu),
    ];

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: AppBackdrop(child: navigationShell),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          0,
          AppSpacing.screen,
          bottomInset > 0 ? 10 : AppSpacing.lg,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: GlassNavBar(
                items: items,
                currentIndex: navigationShell.currentIndex,
                onSelect: _select,
              ),
            ),
            const SizedBox(width: 10),
            SearchFab(onTap: () => context.push<Object?>('/search')),
          ],
        ),
      ),
    );
  }
}
