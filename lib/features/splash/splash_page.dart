import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/env.dart';
import '../../core/providers.dart';
import '../../shared/widgets/app_mark.dart';
import '../../shared/widgets/primitives.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Scaffold(
      body: AppBackdrop(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const PortixMark(size: 112)
                  .animate()
                  .fadeIn(duration: 520.ms, curve: Curves.easeOut)
                  .scale(
                    begin: const Offset(0.86, 0.86),
                    end: const Offset(1, 1),
                    duration: 640.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(height: 26),
              Text(
                'PORTIX',
                style: context.texts.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 10,
                  color: p.text,
                ),
              ).animate().fadeIn(delay: 140.ms, duration: 420.ms),
              const SizedBox(height: 10),
              Text(
                context.l10n.tagline,
                textAlign: TextAlign.center,
                style: context.texts.bodyMedium?.copyWith(
                  color: p.muted,
                  letterSpacing: 0.3,
                ),
              ).animate().fadeIn(delay: 260.ms, duration: 420.ms),
              const SizedBox(height: 42),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: p.primary.withValues(alpha: 0.9),
                ),
              ).animate().fadeIn(delay: 380.ms, duration: 320.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class BootstrapErrorPage extends ConsumerWidget {
  const BootstrapErrorPage({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    final bool isConfig =
        error is AppFailure && error.kind == FailureKind.config;
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const PortixMark(size: 84),
                const SizedBox(height: 28),
                Text(
                  isConfig ? l10n.configTitle : l10n.errorGeneric,
                  textAlign: TextAlign.center,
                  style: context.texts.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isConfig ? l10n.configBody : context.failureText(error),
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(
                    color: p.muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                GradientButton(
                  label: l10n.tryAgain,
                  expand: false,
                  icon: Icons.refresh_rounded,
                  onPressed: () => ref.invalidate(supabaseBootstrapProvider),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
