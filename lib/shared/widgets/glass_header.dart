import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/theme/tokens.dart';

/// AppBar transparente que colapsa o título grande (sem fundo próprio).
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
        background: subtitle == null
            ? const SizedBox.shrink()
            : Padding(
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
    );
  }
}

/// Barra de vidro sobreposta (mesmo efeito da barra de navegação): blur,
/// preenchimento escuro translúcido e borda fina. Aparece ao rolar.
class GlassTopBar extends StatelessWidget {
  const GlassTopBar({
    super.key,
    required this.title,
    this.actions,
    this.visible = true,
  });

  final String title;
  final List<Widget>? actions;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.base,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: 6, bottom: 6),
              decoration: const BoxDecoration(
                color: Color(0x66000000),
                border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Color(0x4D000000), blurRadius: 20, offset: Offset(0, 8)),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (actions != null) ...actions!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Envolve uma tela rolável e sobrepõe o `GlassTopBar` quando o usuário rola.
class GlassHeader extends StatefulWidget {
  const GlassHeader({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  State<GlassHeader> createState() => _GlassHeaderState();
}

class _GlassHeaderState extends State<GlassHeader> {
  bool _visible = false;

  bool _onScroll(ScrollNotification notification) {
    final bool next = notification.metrics.pixels > 120;
    if (next != _visible && mounted) {
      setState(() => _visible = next);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: GlassTopBar(
            title: widget.title,
            actions: widget.actions,
            visible: _visible,
          ),
        ),
      ],
    );
  }
}
