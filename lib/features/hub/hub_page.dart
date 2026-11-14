import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/theme/tokens.dart';
import '../../models/collections.dart';
import '../../models/download_task.dart';
import '../../models/game.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/reveal.dart';
import '../../shared/widgets/states.dart';
import '../collections/collections_controller.dart';
import '../downloads/downloads_controller.dart';
import '../downloads/downloads_tile.dart';

class HubPage extends ConsumerStatefulWidget {
  const HubPage({super.key});

  @override
  ConsumerState<HubPage> createState() => _HubPageState();
}

enum _HubSegment { favorites, installed, downloads }

class _HubPageState extends ConsumerState<HubPage> {
  _HubSegment _segment = _HubSegment.favorites;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final AsyncValue<Collections> async = ref.watch(collectionsProvider);
    final Collections collections = async.value ?? Collections.empty;
    final List<DownloadTask> tasks = ref.watch(downloadsProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: context.palette.primary,
        backgroundColor: context.palette.surface,
        onRefresh: () => ref.read(collectionsProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.lg,
                  AppSpacing.screen,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.hubTitle,
                      style: context.texts.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.anonymousHint,
                      style: context.texts.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SegmentedControl<_HubSegment>(
                      items: <SegmentItem<_HubSegment>>[
                        SegmentItem<_HubSegment>(
                          value: _HubSegment.favorites,
                          label: '${l10n.hubFavorites} · ${collections.favorites.length}',
                          icon: Icons.favorite_rounded,
                        ),
                        SegmentItem<_HubSegment>(
                          value: _HubSegment.installed,
                          label: '${l10n.hubInstalled} · ${collections.library.length}',
                          icon: Icons.download_done_rounded,
                        ),
                        SegmentItem<_HubSegment>(
                          value: _HubSegment.downloads,
                          label: '${l10n.hubDownloads} · ${tasks.length}',
                          icon: Icons.download_rounded,
                        ),
                      ],
                      value: _segment,
                      onChanged: (_HubSegment value) => setState(() => _segment = value),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
            ..._segmentSlivers(context, l10n, collections, tasks),
          ],
        ),
      ),
    );
  }

  List<Widget> _segmentSlivers(
    BuildContext context,
    L10n l10n,
    Collections collections,
    List<DownloadTask> tasks,
  ) {
    switch (_segment) {
      case _HubSegment.favorites:
        return _gameSlivers(
          context,
          games: collections.favorites,
          prefix: 'hub-fav',
          emptyIcon: Icons.favorite_border_rounded,
          emptyTitle: l10n.wishlistEmpty,
          emptyBody: l10n.wishlistEmptyBody,
        );
      case _HubSegment.installed:
        return _gameSlivers(
          context,
          games: collections.library,
          prefix: 'hub-inst',
          emptyIcon: Icons.download_done_rounded,
          emptyTitle: l10n.libraryEmpty,
          emptyBody: l10n.libraryEmptyBody,
        );
      case _HubSegment.downloads:
        if (tasks.isEmpty) {
          return <Widget>[
            SliverToBoxAdapter(
              child: SizedBox(
                height: 360,
                child: EmptyState(
                  icon: Icons.download_rounded,
                  title: l10n.downloadEmpty,
                  body: l10n.downloadEmptyBody,
                ),
              ),
            ),
          ];
        }
        return <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              0,
              AppSpacing.screen,
              180,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: DownloadTile(task: tasks[index]),
                ),
                childCount: tasks.length,
              ),
            ),
          ),
        ];
    }
  }

  List<Widget> _gameSlivers(
    BuildContext context, {
    required List<Game> games,
    required String prefix,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyBody,
  }) {
    if (games.isEmpty) {
      return <Widget>[
        SliverToBoxAdapter(
          child: SizedBox(
            height: 360,
            child: EmptyState(
              icon: emptyIcon,
              title: emptyTitle,
              body: emptyBody,
              actionLabel: context.l10n.explore,
              onAction: () => context.go('/explore'),
            ),
          ),
        ),
      ];
    }
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          0,
          AppSpacing.screen,
          180,
        ),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.gridGap,
            crossAxisSpacing: AppSpacing.gridGap,
            childAspectRatio: 3 / 4,
          ),
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              final Game game = games[index];
              return RevealOnMount(
                index: index,
                child: GameCard(game: game, heroTag: '$prefix-${game.id}'),
              );
            },
            childCount: games.length,
          ),
        ),
      ),
    ];
  }
}
