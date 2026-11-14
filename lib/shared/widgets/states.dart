import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'primitives.dart';

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: p.surfaceHigh.withValues(alpha: p.dark ? 0.75 : 1),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// Um único controlador para a página inteira: skeleton leve, sem custo por item.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(begin: 0.55, end: 1)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: widget.child,
      );
}

class GameCardSkeleton extends StatelessWidget {
  const GameCardSkeleton({super.key, this.width = 156});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 3 / 4,
            child: SkeletonBox(height: double.infinity, radius: 18),
          ),
          const SizedBox(height: 10),
          SkeletonBox(width: width * 0.86, height: 11),
          const SizedBox(height: 7),
          SkeletonBox(width: width * 0.5, height: 9),
        ],
      ),
    );
  }
}

class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const SkeletonBox(width: 44, height: 44, radius: 14),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SkeletonBox(width: 90, height: 10),
                    SizedBox(height: 7),
                    SkeletonBox(width: 150, height: 16),
                  ],
                ),
                const Spacer(),
                const SkeletonBox(width: 44, height: 44, radius: 999),
              ],
            ),
            const SizedBox(height: 22),
            const SkeletonBox(width: double.infinity, height: 300, radius: 26),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (int index = 0; index < 4; index += 1)
                  const SkeletonBox(width: 72, height: 34, radius: 999),
              ],
            ),
            const SizedBox(height: 28),
            const SkeletonBox(width: 160, height: 18),
            const SizedBox(height: 14),
            const Row(
              children: <Widget>[
                GameCardSkeleton(width: 150),
                SizedBox(width: 14),
                GameCardSkeleton(width: 150),
              ],
            ),
            const SizedBox(height: 28),
            const SkeletonBox(width: 180, height: 18),
            const SizedBox(height: 14),
            const Row(
              children: <Widget>[
                GameCardSkeleton(width: 150),
                SizedBox(width: 14),
                GameCardSkeleton(width: 150),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SearchSkeleton extends StatelessWidget {
  const SearchSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          const double gap = 14;
          final double itemWidth = (constraints.maxWidth - 40 - gap) / 2;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            child: Wrap(
              spacing: gap,
              runSpacing: 22,
              children: <Widget>[
                for (int index = 0; index < 6; index += 1)
                  GameCardSkeleton(width: itemWidth),
              ],
            ),
          );
        },
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: p.brandSoft,
                border: Border.all(color: p.line),
              ),
              child: Icon(icon, size: 34, color: p.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(color: p.muted, height: 1.45),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 22),
              GradientButton(
                label: actionLabel!,
                expand: false,
                height: 48,
                onPressed: onAction,
                icon: Icons.explore_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    required this.retryLabel,
    this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.danger.withValues(alpha: 0.12),
                border: Border.all(color: p.danger.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.cloud_off_rounded, size: 34, color: p.danger),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(color: p.muted, height: 1.45),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 22),
              GhostButton(
                label: retryLabel,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
