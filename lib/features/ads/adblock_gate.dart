import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/ads/ads_providers.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/primitives.dart';

/// Encaixa o app na monetização: inicia o SDK (Android) e, quando um
/// bloqueador de anúncios é confirmado por DNS, substitui a árvore por um
/// diálogo bloqueante — o app só volta depois que o usuário desliga o
/// bloqueador e toca em "Verificar novamente". Sem bloqueio, o gate é
/// transparente (devolve o [child] intacto).
class AdsGate extends ConsumerStatefulWidget {
  const AdsGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AdsGate> createState() => _AdsGateState();
}

class _AdsGateState extends ConsumerState<AdsGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      unawaited(ref.read(adsProvider.notifier).ensureStarted());
    });
  }

  @override
  Widget build(BuildContext context) {
    final AdblockState adblock = ref.watch(adblockProvider);
    final bool isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    // Checagem em pano de fundo NÃO mostra barreira: nada de flash de
    // bloqueio durante o boot. Só o veredito "blocked" trava o app; a
    // re-checagem do botão mostra o diálogo com spinner.
    if (!isAndroid) {
      return widget.child;
    }
    switch (adblock.phase) {
      case AdblockPhase.blocked:
        return _AdblockBarrier(checking: false);
      case AdblockPhase.checking when adblock.userInitiated:
        return const _AdblockBarrier(checking: true);
      case AdblockPhase.idle:
      case AdblockPhase.checking:
      case AdblockPhase.ok:
        return widget.child;
    }
  }
}

/// Diálogo bloqueante em tela cheia: fundo opaco (nada do app aparece por
/// baixo) e cartão de vidro com a explicação honesta — anúncios mantêm o
/// app gratuito. Não há botão de "continuar com bloqueador": a regra é
/// clara e o botão de verificação é a única saída.
class _AdblockBarrier extends ConsumerWidget {
  const _AdblockBarrier({required this.checking});

  final bool checking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;
    // ColoredBox sem tamanho explícito: com constraints finitas (app real)
    // cobre a tela inteira; em contexto não limitado, degrada sem quebrar.
    return ColoredBox(
      color: AppColors.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screen),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: GlassContainer(
                radius: AppRadii.lg,
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: const Icon(
                        Icons.gpp_bad_rounded,
                        size: 32,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      l10n.adblockTitle,
                      textAlign: TextAlign.center,
                      style: context.texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.adblockBody,
                      textAlign: TextAlign.center,
                      style: context.texts.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (checking)
                      const CircularProgressIndicator(
                        color: AppColors.accent,
                        strokeWidth: 3,
                      )
                    else
                      PrimaryButton(
                        label: l10n.adblockVerify,
                        icon: Icons.refresh_rounded,
                        onPressed: () => unawaited(
                          ref
                              .read(adblockProvider.notifier)
                              .check(userInitiated: true),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.adblockHint,
                      textAlign: TextAlign.center,
                      style: context.texts.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
