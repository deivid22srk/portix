import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/theme/tokens.dart';
import '../../models/game.dart';
import 'game_media.dart';
import 'primitives.dart';

/// Carrossel de destaques 16:10 com parallax leve, indicadores animados e
/// controles de vidro. Autoplay pausável; pré-carrega a próxima capa.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.games,
    this.tagPrefix = 'carousel',
  });

  final List<Game> games;
  final String tagPrefix;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.94);
  Timer? _timer;
  int _index = 0;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _startAutoplay();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) => _precache(1));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoplay() {
    _timer?.cancel();
    if (widget.games.length < 2 || _paused) {
      return;
    }
    _timer = Timer.periodic(AppMotion.autoplay, (Timer timer) {
      if (!mounted || _paused || !_controller.hasClients) {
        return;
      }
      _controller.animateToPage(
        (_index + 1) % widget.games.length,
        duration: const Duration(milliseconds: 520),
        curve: AppMotion.emphasized,
      );
    });
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
  }

  void _resume() {
    if (!_paused) {
      _startAutoplay();
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _pause();
    } else {
      _startAutoplay();
    }
  }

  void _go(int delta) {
    if (!_controller.hasClients || widget.games.isEmpty) {
      return;
    }
    final int count = widget.games.length;
    _controller.animateToPage(
      ((_index + delta) % count + count) % count,
      duration: AppMotion.slow,
      curve: AppMotion.emphasized,
    );
  }

  void _precache(int index) {
    if (!mounted || index < 0 || index >= widget.games.length) {
      return;
    }
    final String? url = widget.games[index].coverUrl;
    if (url == null) {
      return;
    }
    precacheImage(CachedNetworkImageProvider(url), context);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.games.isEmpty) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: Column(
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 10,
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification notification) {
                if (notification is ScrollStartNotification) {
                  _pause();
                } else if (notification is ScrollEndNotification) {
                  _resume();
                }
                return false;
              },
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.games.length,
                onPageChanged: (int index) {
                  setState(() => _index = index);
                  _precache(index + 1);
                },
                itemBuilder: (BuildContext context, int index) {
                  final Game game = widget.games[index];
                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (BuildContext context, Widget? child) {
                      double delta = 0;
                      if (_controller.hasClients &&
                          _controller.position.hasContentDimensions) {
                        delta = (_controller.page ?? _index.toDouble()) - index;
                      }
                      final double scale = (1 - delta.abs() * 0.05).clamp(0.94, 1.0);
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _CarouselCard(
                        game: game,
                        heroTag: '${widget.tagPrefix}-${game.id}',
                        onTap: () => context.push<Object?>(
                          '/game/${game.slug}',
                          extra: '${widget.tagPrefix}-${game.id}',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    for (int i = 0; i < widget.games.length; i += 1)
                      Pressable(
                        haptics: false,
                        onTap: () {
                          if (_controller.hasClients) {
                            _controller.animateToPage(
                              i,
                              duration: AppMotion.slow,
                              curve: AppMotion.emphasized,
                            );
                          }
                        },
                        child: AnimatedContainer(
                          duration: AppMotion.indicator,
                          curve: AppMotion.emphasized,
                          margin: const EdgeInsets.only(right: 6),
                          width: i == _index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            color: i == _index
                                ? AppColors.textPrimary
                                : AppColors.textPrimary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              GlassCircleButton(
                icon: Icons.chevron_left_rounded,
                size: 40,
                onTap: () => _go(-1),
              ),
              const SizedBox(width: 8),
              GlassCircleButton(
                icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 40,
                onTap: _togglePause,
              ),
              const SizedBox(width: 8),
              GlassCircleButton(
                icon: Icons.chevron_right_rounded,
                size: 40,
                onTap: () => _go(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({
    required this.game,
    required this.heroTag,
    required this.onTap,
  });

  final Game game;
  final String heroTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Hero(
              tag: heroTag,
              child: GameCover(
                imageUrl: game.coverUrl,
                title: game.title,
                memWidth: 1000,
                borderRadius: 0,
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Color(0x33000000),
                    Color(0x00000000),
                    Color(0xCC000000),
                  ],
                  stops: <double>[0, 0.4, 1],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            if (game.primaryPlatform.isNotEmpty)
              Positioned(
                left: 14,
                top: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0x66000000),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Text(
                    game.primaryPlatform,
                    style: context.texts.labelSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Text(
                game.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.06,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
