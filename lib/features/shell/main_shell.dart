import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/primitives.dart';
import '../home/update_dialog.dart';

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
    final double bottomInset = context.systemBottomInset;
    final List<GlassNavItem> items = <GlassNavItem>[
      GlassNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: l10n.navHome,
      ),
      GlassNavItem(
        icon: Icons.sports_esports_outlined,
        activeIcon: Icons.sports_esports_rounded,
        label: l10n.navExplore,
      ),
      GlassNavItem(
        icon: Icons.article_outlined,
        activeIcon: Icons.article_rounded,
        label: l10n.navNews,
      ),
      GlassNavItem(
        icon: Icons.layers_outlined,
        activeIcon: Icons.layers_rounded,
        label: l10n.navHub,
      ),
      GlassNavItem(
        icon: Icons.menu_rounded,
        activeIcon: Icons.menu_rounded,
        label: l10n.navMenu,
      ),
    ];

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: AppBackdrop(
        child: Stack(
          children: <Widget>[
            navigationShell,
            const UpdateGate(),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          0,
          AppSpacing.screen,
          bottomInset + 12,
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
