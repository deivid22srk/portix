import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../shared/widgets/app_mark.dart';
import '../../shared/widgets/primitives.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const PortixMark(size: 76, glow: false),
                  const SizedBox(height: 20),
                  Text(
                    '404',
                    style: context.texts.displayMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                      color: p.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.noResultsTitle,
                    textAlign: TextAlign.center,
                    style: context.texts.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.errorNotFound,
                    textAlign: TextAlign.center,
                    style: context.texts.bodyMedium?.copyWith(
                      color: p.muted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  GradientButton(
                    label: l10n.navHome,
                    icon: Icons.home_rounded,
                    expand: false,
                    height: 48,
                    onPressed: () => context.go('/home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
