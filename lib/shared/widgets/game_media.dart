import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/formatters.dart';
import '../../models/game.dart';
import 'primitives.dart';

class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    required this.title,
    this.showInitials = true,
  });

  final String title;
  final bool showInitials;

  @override
  Widget build(BuildContext context) {
    final List<Color> colors = coverColorsFor(title);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            top: -36,
            right: -28,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    Colors.white.withValues(alpha: 0.16),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -40,
            left: -24,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          if (showInitials)
            Center(
              child: Text(
                initialsOf(title),
                style: context.texts.displaySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class GameCover extends StatelessWidget {
  const GameCover({
    super.key,
    required this.title,
    this.imageUrl,
    this.fit = BoxFit.cover,
    this.memWidth = 420,
    this.borderRadius = 18,
  });

  final String title;
  final String? imageUrl;
  final BoxFit fit;
  final int memWidth;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final String? url = imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: url == null
          ? CoverPlaceholder(title: title)
          : CachedNetworkImage(
              imageUrl: url,
              fit: fit,
              memCacheWidth: memWidth,
              fadeInDuration: const Duration(milliseconds: 260),
              fadeOutDuration: const Duration(milliseconds: 120),
              filterQuality: FilterQuality.medium,
              placeholder: (BuildContext context, String value) =>
                  CoverPlaceholder(title: title),
              errorWidget:
                  (BuildContext context, String value, Object error) =>
                      CoverPlaceholder(title: title),
            ),
    );
  }
}

class _MediaTag extends StatelessWidget {
  const _MediaTag({required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: color ?? Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(
              color: color ?? Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.game,
    this.width = 156,
    this.heroTag,
    this.onTap,
  });

  final Game game;
  final double width;
  final String? heroTag;
  final VoidCallback? onTap;

  void _open(BuildContext context) {
    context.push<Object?>('/game/${game.slug}', extra: heroTag);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final String meta = <String>[
      if (game.year != null) game.year.toString(),
      if (game.genre != null) game.genre!,
    ].join(' · ');

    return RepaintBoundary(
      child: Pressable(
        onTap: onTap ?? () => _open(context),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Hero(
                tag: heroTag ?? 'card-${game.id}',
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      GameCover(
                        imageUrl: game.coverUrl,
                        title: game.title,
                        memWidth: (width * 2.6).round(),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.06),
                                Colors.black.withValues(alpha: 0.62),
                              ],
                              stops: const <double>[0.5, 0.72, 1],
                            ),
                          ),
                        ),
                      ),
                      if (game.primaryPlatform.isNotEmpty)
                        Positioned(
                          left: 9,
                          top: 9,
                          child: _MediaTag(label: game.primaryPlatform),
                        ),
                      if (game.portCount > 0 && game.portCount > 1)
                        Positioned(
                          right: 9,
                          top: 9,
                          child: _MediaTag(
                            label: game.portCount.toString(),
                            icon: Icons.layers_rounded,
                          ),
                        ),
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 9,
                        child: Row(
                          children: <Widget>[
                            if (game.hasRating)
                              _MediaTag(
                                label: formatRating(game.rating),
                                icon: Icons.star_rounded,
                                color: p.warning,
                              )
                            else
                              _MediaTag(label: 'PORTIX', icon: Icons.bolt_rounded),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                game.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: -0.1,
                ),
              ),
              if (meta.isNotEmpty) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    color: p.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GameRow extends StatelessWidget {
  const GameRow({
    super.key,
    required this.game,
    this.onTap,
    this.trailing,
    this.subtitle,
  });

  final Game game;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final String meta = subtitle ??
        <String>[
          if (game.year != null) game.year.toString(),
          if (game.primaryPlatform.isNotEmpty) game.primaryPlatform,
        ].join(' · ');
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: p.surface.withValues(alpha: p.dark ? 0.55 : 0.9),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 58,
              height: 78,
              child: GameCover(
                imageUrl: game.coverUrl,
                title: game.title,
                memWidth: 180,
                borderRadius: 12,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    game.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (meta.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(color: p.muted),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      if (game.hasRating)
                        RatingLine(rating: game.rating, compact: true)
                      else
                        Text(
                          context.l10n.newGame,
                          style: context.texts.labelSmall?.copyWith(color: p.muted),
                        ),
                      const Spacer(),
                      ?trailing,
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
