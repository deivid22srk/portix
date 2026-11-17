import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/theme/tokens.dart';

/// AppBar transparente com o título grande e a frase alinhados ao topo do
/// cabeçalho (respeitando o inset da status bar via SafeArea da tela). Ao
/// rolar, um [GlassTopBar] sobreposto aparece com o título pequeno.
class GlassSliverAppBar extends StatelessWidget {
  const GlassSliverAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.expandedHeight = 148,
    this.topPadding = 10,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final double expandedHeight;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    // Com texto ampliado (WCAG 1.4.4 até 200%) o cabeçalho precisa de mais
    // altura: escala o espaço expandido pelo scaler do sistema (piso 1.0).
    final double textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final double effectiveExpanded =
        expandedHeight * (textScale < 1.0 ? 1.0 : textScale);
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: effectiveExpanded,
      backgroundColor: AppContentColors.transparent,
      surfaceTintColor: AppContentColors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: AppSpacing.screen,
      actions: actions,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.none,
        background: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screen,
            topPadding,
            AppSpacing.screen,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
              Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de vidro sobreposta (mesmo efeito da barra de navegação): blur,
/// preenchimento escuro translúcido e borda fina. Aparece ao rolar.
class GlassTopBar extends StatelessWidget {
  GlassTopBar({
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
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: 6,
                bottom: 6,
              ),
              decoration: BoxDecoration(
                color: context.colors.glassFloating,
                border: Border(
                  bottom: BorderSide(color: context.colors.glassBorder),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppContentColors.scrim.withValues(alpha: 0.30),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
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
                  ...?actions,
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
    final bool next = notification.metrics.pixels > 80;
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
