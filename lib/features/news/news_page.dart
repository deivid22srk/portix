import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/env.dart';
import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../models/news.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/glass_header.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/states.dart';
import '../news/news_controller.dart';

class NewsPage extends ConsumerStatefulWidget {
  const NewsPage({super.key});

  @override
  ConsumerState<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends ConsumerState<NewsPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        ref.read(newsControllerProvider.notifier).ensureLoaded();
      }
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      ref.read(newsControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final NewsState state = ref.watch(newsControllerProvider);

    return SafeArea(
      bottom: false,
      child: GlassHeader(
        title: l10n.newsTitle,
        child: RefreshIndicator(
        color: context.palette.primary,
        backgroundColor: context.palette.surface,
        onRefresh: () => ref.read(newsControllerProvider.notifier).refresh(),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: <Widget>[
            GlassSliverAppBar(
              title: l10n.newsTitle,
              subtitle: l10n.newsSubtitle,
              expandedHeight: 150,
            ),
            if (state.isInitialLoading)
              const SliverToBoxAdapter(child: SearchSkeleton()),
            if (state.status == NewsStatus.error && state.items.isEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 380,
                  child: ErrorStateView(
                    message: context.failureText(state.error),
                    retryLabel: l10n.tryAgain,
                    onRetry: () => ref.read(newsControllerProvider.notifier).refresh(),
                  ),
                ),
              ),
            if (state.status == NewsStatus.empty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 380,
                  child: EmptyState(
                    icon: Icons.article_outlined,
                    title: l10n.newsEmpty,
                    body: l10n.newsEmptyBody,
                  ),
                ),
              ),
            if (state.items.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.md,
                  AppSpacing.screen,
                  context.bottomChromePadding,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
                      final NewsItem item = state.items[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _NewsCard(item: item),
                      );
                    },
                    childCount: state.items.length,
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

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final String meta = <String>[
      if (item.game.year != null) item.game.year.toString(),
      if (item.game.primaryPlatform.isNotEmpty) item.game.primaryPlatform,
    ].join(' · ');

    return GlassContainer(
      radius: AppRadii.md,
      padding: const EdgeInsets.all(10),
      onTap: () => context.push<Object?>(
        '/game/${item.game.slug}',
        extra: 'news-${item.game.id}',
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 62,
            height: 84,
            child: Hero(
              tag: 'news-${item.game.id}',
              child: GameCover(
                imageUrl: item.game.coverUrl,
                title: item.game.title,
                memWidth: 200,
                borderRadius: AppRadii.sm,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    BadgeChip(
                      label: item.isUpdate ? l10n.newsUpdated : l10n.newsAdded,
                      color: item.isUpdate ? AppColors.accentAlt : AppColors.accent,
                      icon: item.isUpdate
                          ? Icons.upgrade_rounded
                          : Icons.fiber_new_rounded,
                    ),
                    const Spacer(),
                    Text(
                      relativeDay(item.date, en: l10n.isEn),
                      style: context.texts.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.game.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
