import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/theme/tokens.dart';
import 'primitives.dart';

// Estados de carregamento/vazio/erro no mesmo visual de vidro do app.

/// Bloco cinza de vidro usado nos skeletons (o shimmer vem do [SkeletonPulse]).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = AppRadii.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.glassStrong,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Um único controlador de shimmer para a página inteira (barato e suave).
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
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect bounds) => LinearGradient(
            colors: const <Color>[
              AppColors.glassStrong,
              AppColors.glass,
              AppColors.glassStrong,
            ],
            stops: <double>[
              (t - 0.3).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.3).clamp(0.0, 1.0),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class GameCardSkeleton extends StatelessWidget {
  const GameCardSkeleton({super.key, this.width = 160});

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
            child: const SkeletonBox(height: double.infinity, radius: AppRadii.md),
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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          12,
          AppSpacing.screen,
          140,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SkeletonBox(width: 140, height: 34),
            const SizedBox(height: 10),
            const SkeletonBox(width: 220, height: 14),
            const SizedBox(height: 20),
            const SkeletonBox(width: double.infinity, height: 230, radius: AppRadii.lg),
            const SizedBox(height: 24),
            const SkeletonBox(width: 180, height: 22),
            const SizedBox(height: 14),
            const Row(
              children: <Widget>[
                GameCardSkeleton(width: 150),
                SizedBox(width: 12),
                GameCardSkeleton(width: 150),
              ],
            ),
            const SizedBox(height: 28),
            const SkeletonBox(width: 200, height: 22),
            const SizedBox(height: 14),
            const Row(
              children: <Widget>[
                GameCardSkeleton(width: 150),
                SizedBox(width: 12),
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
          final double itemWidth =
              (constraints.maxWidth - AppSpacing.screen * 2 - AppSpacing.gridGap) / 2;
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              8,
              AppSpacing.screen,
              140,
            ),
            child: Wrap(
              spacing: AppSpacing.gridGap,
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

/// Estado vazio com ícone de traço, texto e ação opcional.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.explore_rounded,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                color: AppColors.glass,
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Icon(icon, size: 36, color: AppColors.accent),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                label: actionLabel!,
                expand: false,
                height: AppSpacing.secondaryButtonHeight,
                onPressed: onAction,
                icon: actionIcon,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado de erro com ação de tentar novamente.
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                color: AppColors.danger.withValues(alpha: 0.12),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 36, color: AppColors.danger),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              SecondaryButton(
                label: retryLabel,
                icon: Icons.refresh_rounded,
                expand: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
