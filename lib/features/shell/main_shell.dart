import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../shared/widgets/primitives.dart';

// Casca principal do app: mantém as cinco abas vivas e desenha uma barra
// flutuante própria, com blur leve e indicador de seleção por gradiente.
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
    final List<_NavItem> items = <_NavItem>[
      _NavItem(Icons.home_outlined, Icons.home_rounded, l10n.navHome),
      _NavItem(Icons.explore_outlined, Icons.explore_rounded, l10n.navSearch),
      _NavItem(Icons.video_library_outlined, Icons.video_library_rounded, l10n.navLibrary),
      _NavItem(Icons.download_outlined, Icons.download_rounded, l10n.navDownloads),
      _NavItem(Icons.person_outline_rounded, Icons.person_rounded, l10n.navProfile),
    ];

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: AppBackdrop(child: navigationShell),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset > 0 ? 10 : 16),
        child: GlassPanel(
          radius: 26,
          blur: true,
          padding: const EdgeInsets.all(6),
          child: Row(
            children: <Widget>[
              for (int index = 0; index < items.length; index += 1)
                Expanded(
                  child: _NavButton(
                    item: items[index],
                    active: navigationShell.currentIndex == index,
                    onTap: () => _select(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.activeIcon, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Pressable(
      onTap: onTap,
      haptics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          color: active ? p.primary.withValues(alpha: p.dark ? 0.18 : 0.10) : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              active ? item.activeIcon : item.icon,
              size: 22,
              color: active ? p.primary : p.muted,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall?.copyWith(
                fontSize: 10,
                color: active ? p.text : p.muted,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
