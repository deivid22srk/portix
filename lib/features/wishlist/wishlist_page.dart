import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/env.dart';
import '../../models/collections.dart';
import '../../models/game.dart';
import '../../shared/widgets/app_mark.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/states.dart';
import '../collections/collections_controller.dart';

class WishlistPage extends ConsumerWidget {
  const WishlistPage({super.key});

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    final AsyncValue<Collections> async = ref.watch(collectionsProvider);
    final Collections collections = async.value ?? Collections.empty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackdrop(
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          IconGlassButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: () => _back(context),
                          ),
                          const SizedBox(width: 12),
                          const PortixMark(size: 30, glow: false),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.wishlistTitle,
                              style: context.texts.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: p.danger.withValues(alpha: 0.14),
                              border: Border.all(
                                color: p.danger.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              collections.favorites.length.toString(),
                              style: context.texts.labelMedium?.copyWith(
                                color: p.danger,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(left: 56),
                        child: Text(
                          collections.favorites.isEmpty
                              ? l10n.wishlistEmptyBody
                              : l10n.anonymousHint,
                          style: context.texts.bodySmall?.copyWith(
                            color: p.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
              if (async.isLoading && !async.hasValue)
                const SliverToBoxAdapter(child: SearchSkeleton()),
              if (async.hasError && !async.hasValue)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 360,
                    child: ErrorStateView(
                      message: context.failureText(async.error),
                      retryLabel: l10n.tryAgain,
                      onRetry: () =>
                          ref.read(collectionsProvider.notifier).refresh(),
                    ),
                  ),
                ),
              if (async.hasValue && collections.favorites.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 380,
                    child: EmptyState(
                      icon: Icons.favorite_border_rounded,
                      title: l10n.wishlistEmpty,
                      body: l10n.wishlistEmptyBody,
                      actionLabel: l10n.explore,
                      onAction: () => context.go('/search'),
                    ),
                  ),
                ),
              if (collections.favorites.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) {
                        final Game game = collections.favorites[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GameRow(
                            game: game,
                            onTap: () =>
                                context.push<Object?>('/game/${game.slug}'),
                            trailing: IconGlassButton(
                              icon: Icons.favorite_rounded,
                              size: 32,
                              active: true,
                              tooltip: l10n.unfavoriteTooltip,
                              onTap: () => ref
                                  .read(collectionsProvider.notifier)
                                  .toggleFavorite(game),
                            ),
                          ),
                        );
                      },
                      childCount: collections.favorites.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
