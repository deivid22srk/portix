import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/env.dart';
import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../models/news.dart';
import '../../shared/widgets/glass_header.dart';
import '../../shared/widgets/news_media.dart';
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
                expandedHeight: 140,
              ),
              if (state.isInitialLoading)
                const SliverToBoxAdapter(child: _NewsSkeleton()),
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
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: _NewsCard(
                            // O primeiro card é o destaque do feed: capa maior.
                            item: item,
                            featured: index == 0,
                          ),
                        );
                      },
                      childCount: state.items.length,
                    ),
                  ),
                ),
              if (state.isLoadingMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: context.bottomChromePadding,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
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

/// Esqueleto do feed: dois cards grandes pulsando enquanto carrega.
class _NewsSkeleton extends StatelessWidget {
  const _NewsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.md,
          AppSpacing.screen,
          AppSpacing.lg,
        ),
        child: Column(
          children: <Widget>[
            for (int index = 0; index < 2; index += 1)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ColoredBox(color: AppColors.glassStrong),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _bar(width: 64, height: 10),
                            const SizedBox(height: AppSpacing.md),
                            _bar(width: double.infinity, height: 16),
                            const SizedBox(height: 6),
                            _bar(width: 180, height: 16),
                            const SizedBox(height: AppSpacing.md),
                            _bar(width: 90, height: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.glassStrong,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
    );
  }
}

/// Card de notícia: capa retangular no topo e área escura com categoria,
/// título e tempo de publicação.
class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item, this.featured = false});

  final NewsItem item;

  /// O primeiro card do feed ganha capa um pouco mais alta e título maior.
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final TextStyle? titleStyle =
        (featured ? context.texts.titleLarge : context.texts.titleMedium)
            ?.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );

    return Pressable(
      onTap: () => context.push<Object?>(
        '/news/${item.slug}',
        extra: item,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadows.glass,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: featured ? 16 / 10 : 16 / 9,
              child: NewsCover(item: item),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.category.toUpperCase(),
                    style: context.texts.labelSmall?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        relativeDay(item.publishedAt, en: l10n.isEn),
                        style: context.texts.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
