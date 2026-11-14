import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../app/theme.dart';

/// Cabeçalho que colapsa com o mesmo "vidro" da barra de navegação:
/// BackdropFilter (blur) + preenchimento escuro translúcido + borda fina.
class GlassSliverAppBar extends StatelessWidget {
  const GlassSliverAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.expandedHeight = 150,
    this.titlePaddingEnd = AppSpacing.screen,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final double expandedHeight;
  final double titlePaddingEnd;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: expandedHeight,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: AppSpacing.screen,
      actions: actions,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: EdgeInsetsDirectional.only(
          start: AppSpacing.screen,
          end: titlePaddingEnd,
          bottom: 16,
        ),
        title: Text(
          title,
          style: context.texts.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        background: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0x66000000),
                      border: Border(
                        bottom: BorderSide(color: AppColors.glassBorder),
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Color(0x4D000000),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (subtitle != null)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    0,
                    AppSpacing.screen,
                    42,
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      subtitle!,
                      style: context.texts.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
