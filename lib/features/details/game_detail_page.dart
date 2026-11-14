import 'dart:ui' show BlendMode, ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/auth.dart';
import '../../core/device_info.dart';
import '../../core/download_source.dart';
import '../../core/env.dart';
import '../../core/formatters.dart';
import '../../core/native_downloader.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../models/collections.dart';
import '../../models/compat_report.dart';
import '../../models/compat_summary.dart';
import '../../models/download_task.dart';
import '../../models/game.dart';
import '../../models/game_detail.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/states.dart';
import '../collections/collections_controller.dart';
import '../downloads/downloads_controller.dart';

final gameDetailProvider = FutureProvider.family<GameDetail, String>(
  (ref, String slug) => ref.watch(catalogRepositoryProvider).fetchGame(slug),
);

final gameCompatReportsProvider = FutureProvider.family<List<CompatReport>, String>(
  (ref, String gameId) =>
      ref.watch(catalogRepositoryProvider).fetchCompatReports(gameId),
);

class GameDetailPage extends ConsumerStatefulWidget {
  const GameDetailPage({super.key, required this.slug, this.heroTag});

  final String slug;
  final String? heroTag;

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _review = TextEditingController();

  bool _expandedDescription = false;
  bool _submitting = false;
  bool _barTitle = false;
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final bool next = _scroll.offset > 220;
    if (next != _barTitle && mounted) {
      setState(() => _barTitle = next);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _review.dispose();
    super.dispose();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _showSnack(String message, {String? actionLabel, VoidCallback? onAction}) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.bgElevated,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: AppColors.accent,
                onPressed: onAction ?? () {},
              ),
      ),
    );
  }

  Future<void> _install(GameDetail detail) async {
    final L10n l10n = context.l10n;
    final DownloadTask? current = ref.read(downloadForGameProvider(detail.game.id));
    if (current != null && current.isDone) {
      final String? path = current.apkPath;
      if (path != null && await NativeDownloader.install(path)) {
        return;
      }
      final GamePort? donePort = detail.primaryPort;
      if (donePort?.url != null) {
        await _openLink(donePort!.url);
      } else if (mounted) {
        _showSnack(l10n.installedLabel);
      }
      return;
    }

    final GamePort? port = detail.primaryPort;
    final String? url = port?.url;
    if (port == null || url == null) {
      _showSnack(l10n.noLink);
      return;
    }

    final String direct = resolveDirectUrl(url);
    if (!isDirectApkUrl(direct)) {
      // A maioria dos ports é uma página de destino; abrimos a fonte.
      await _openLink(url);
      if (mounted) {
        _showSnack(l10n.sourceOnly);
      }
      return;
    }

    ref.read(downloadsProvider.notifier).start(
          detail.game,
          port: port,
          urlOverride: direct,
        );
    _showSnack(
      l10n.downloadStarted,
      actionLabel: l10n.viewDownloads,
      onAction: () => context.go('/hub'),
    );
  }

  Future<void> _toggleFavorite(GameDetail detail) async {
    final bool ok = await ref.read(collectionsProvider.notifier).toggleFavorite(detail.game);
    if (!mounted) {
      return;
    }
    if (!ok) {
      _showSnack(context.l10n.errorGeneric);
    }
  }

  Future<void> _toggleLibrary(GameDetail detail) async {
    final bool wasInLibrary =
        ref.read(collectionsProvider).value?.isInLibrary(detail.game.id) ?? false;
    final bool ok = await ref.read(collectionsProvider.notifier).toggleLibrary(detail.game);
    if (!mounted) {
      return;
    }
    final L10n l10n = context.l10n;
    _showSnack(
      !ok
          ? l10n.errorGeneric
          : wasInLibrary
              ? l10n.removedFromLibrary
              : l10n.addedToLibrary,
    );
  }

  Future<void> _share(GameDetail detail) async {
    final String url = 'https://portix.app/game/${detail.game.slug}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) {
      return;
    }
    _showSnack(context.l10n.linkCopied);
  }

  Future<void> _openLink(String? url) async {
    if (url == null) {
      return;
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      if (mounted) {
        _showSnack(context.l10n.errorGeneric);
      }
      return;
    }
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      launched = false;
    }
    if (!launched && mounted) {
      _showSnack(context.l10n.errorGeneric);
    }
  }

  Future<void> _submitReview(GameDetail detail) async {
    final L10n l10n = context.l10n;
    if (_rating == 0) {
      _showSnack(l10n.ratingRequired);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(catalogRepositoryProvider).submitReview(
            gameId: detail.game.id,
            rating: _rating,
            body: _review.text.trim(),
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _rating = 0;
      });
      _review.clear();
      ref.invalidate(gameDetailProvider(widget.slug));
      _showSnack(l10n.reviewSent);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      _showSnack(l10n.errorGeneric);
    }
  }

  Future<void> _openCompatSheet(GameDetail detail) async {
    final L10n l10n = context.l10n;
    if (!ref.read(accountProvider).isSignedIn) {
      _showSnack(
        l10n.loginRequired,
        actionLabel: l10n.signIn,
        onAction: () => context.push<Object?>('/auth'),
      );
      return;
    }
    final DeviceSpecs specs = await DeviceInfo.load();
    if (!mounted) {
      return;
    }
    final String? status = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (BuildContext context) => _CompatSheet(specs: specs),
    );
    if (status == null || !mounted) {
      return;
    }
    try {
      await ref.read(catalogRepositoryProvider).submitCompatReport(
            gameId: detail.game.id,
            status: status,
            brand: specs.brand,
            model: specs.model,
            soc: specs.soc,
            gpu: specs.gpu,
            ramGb: specs.ramGb,
          );
      if (!mounted) {
        return;
      }
      ref.invalidate(gameDetailProvider(widget.slug));
      ref.invalidate(gameCompatReportsProvider(detail.game.id));
      _showSnack(l10n.compatSent);
    } on Object {
      if (mounted) {
        _showSnack(l10n.errorGeneric);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<GameDetail> async = ref.watch(gameDetailProvider(widget.slug));

    if (async.hasValue) {
      return _buildDetail(context, async.requireValue);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackdrop(
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              Positioned(
                left: AppSpacing.md,
                top: AppSpacing.sm,
                child: GlassCircleButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: _back,
                ),
              ),
              if (async.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: ErrorStateView(
                    message: context.failureText(async.error),
                    retryLabel: context.l10n.tryAgain,
                    onRetry: () => ref.invalidate(gameDetailProvider(widget.slug)),
                  ),
                )
              else
                const _DetailSkeleton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, GameDetail detail) {
    final L10n l10n = context.l10n;
    final Game game = detail.game;
    final Collections collections = ref.watch(collectionsProvider).value ?? Collections.empty;
    final bool favorite = collections.isFavorite(game.id);
    final bool inLibrary = collections.isInLibrary(game.id);
    final DownloadTask? task = ref.watch(downloadForGameProvider(game.id));

    final String installLabel = task == null || task.status == DownloadStatus.failed
        ? l10n.install
        : task.isDone
            ? (task.apkPath != null ? l10n.install : l10n.installedLabel)
            : l10n.continueAction;
    final IconData installIcon = task == null || task.status == DownloadStatus.failed
        ? Icons.download_rounded
        : task.isDone
            ? Icons.check_circle_rounded
            : Icons.play_arrow_rounded;

    final bool longDescription = game.description.length > 320;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _CoverBackdrop(coverUrl: game.coverUrl, title: game.title),
          ),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.md,
                    AppSpacing.screen,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      GlassCircleButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: _back,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Header(game: game, heroTag: widget.heroTag),
                      const SizedBox(height: AppSpacing.lg),
                      _Chips(game: game),
                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(
                        label: installLabel,
                        icon: installIcon,
                        onPressed: () => _install(detail),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SecondaryButton(
                        label: inLibrary ? l10n.inLibrary : l10n.installedAction,
                        icon: inLibrary ? Icons.check_rounded : Icons.download_done_rounded,
                        active: inLibrary,
                        onPressed: () => _toggleLibrary(detail),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _FavoritePill(
                              active: favorite,
                              label: l10n.favoriteTooltip,
                              onTap: () => _toggleFavorite(detail),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          GlassCircleButton(
                            icon: Icons.ios_share_rounded,
                            size: AppSpacing.secondaryButtonHeight,
                            tooltip: l10n.share,
                            onTap: () => _share(detail),
                          ),
                        ],
                      ),
                      if (task != null && !task.isDone) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: <Widget>[
                            Expanded(child: GradientProgress(value: task.progress)),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              l10n.progressPercent((task.progress * 100).round()),
                              style: context.texts.labelSmall?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxl),
                      _BlockTitle(title: l10n.descriptionTitle),
                      const SizedBox(height: AppSpacing.md),
                      GlassContainer(
                        radius: AppRadii.lg,
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              game.description.isEmpty ? l10n.notInformed : game.description,
                              maxLines: _expandedDescription ? null : 5,
                              overflow: _expandedDescription
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: context.texts.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (longDescription) ...<Widget>[
                              const SizedBox(height: AppSpacing.sm),
                              Pressable(
                                onTap: () => setState(
                                  () => _expandedDescription = !_expandedDescription,
                                ),
                                child: Text(
                                  _expandedDescription ? l10n.readLess : l10n.readMore,
                                  style: context.texts.labelMedium?.copyWith(
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      CompatReportCard(
                        summary: detail.compat,
                        onReport: () => _openCompatSheet(detail),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      _BlockTitle(title: l10n.compatCommunity),
                      const SizedBox(height: AppSpacing.md),
                      _CommunityReports(gameId: game.id),
                      const SizedBox(height: AppSpacing.xxl),
                      _BlockTitle(title: l10n.infoTitle),
                      const SizedBox(height: AppSpacing.md),
                      _InfoPanel(game: game, ports: detail.ports.length),
                      if (detail.ports.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xxl),
                        _BlockTitle(
                          title: l10n.portsTitle,
                          trailing: l10n.portCount(detail.ports.length),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (final GamePort port in detail.ports)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: _PortCard(port: port, onOpen: () => _openLink(port.url)),
                          ),
                      ],
                      const SizedBox(height: AppSpacing.xxl),
                      _BlockTitle(
                        title: l10n.reviewsTitle,
                        trailing: l10n.reviewCount(detail.reviews.length),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      GlassContainer(
                        radius: AppRadii.lg,
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              l10n.yourRating,
                              style: context.texts.labelMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            StarPicker(
                              value: _rating,
                              onChanged: (int value) => setState(() => _rating = value),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _review,
                              maxLines: 3,
                              minLines: 2,
                              maxLength: 1000,
                              style: context.texts.bodyMedium,
                              cursorColor: AppColors.accent,
                              decoration: InputDecoration(
                                hintText: l10n.reviewHint,
                                hintStyle: context.texts.bodySmall?.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                                filled: true,
                                fillColor: AppColors.glassStrong,
                                counterText: '',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadii.md),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.all(AppSpacing.md),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            PrimaryButton(
                              label: l10n.send,
                              icon: Icons.send_rounded,
                              isLoading: _submitting,
                              height: AppSpacing.secondaryButtonHeight,
                              onPressed: () => _submitReview(detail),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (detail.reviews.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                          child: Center(
                            child: Text(
                              l10n.noReviews,
                              textAlign: TextAlign.center,
                              style: context.texts.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        )
                      else
                        for (final Review review in detail.reviews)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: _ReviewCard(review: review),
                          ),
                      if (detail.related.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        _BlockTitle(title: l10n.relatedTitle),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          height: 236,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: detail.related.length,
                            separatorBuilder: (BuildContext context, int index) =>
                                const SizedBox(width: AppSpacing.md),
                            itemBuilder: (BuildContext context, int index) {
                              final Game related = detail.related[index];
                              return GameCard(
                                game: related,
                                width: 142,
                                heroTag: 'detail-${game.id}-related-${related.id}',
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxxl),
                    ],
                  ),
                ),
              ),
            ],
          ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(visible: _barTitle, title: game.title, onBack: _back),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.visible,
    required this.title,
    required this.onBack,
  });

  final bool visible;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.base,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 8,
                left: AppSpacing.screen,
                right: AppSpacing.screen,
                bottom: 10,
              ),
              decoration: const BoxDecoration(
                color: Color(0x66000000),
                border: Border(
                  bottom: BorderSide(color: AppColors.glassBorder),
                ),
              ),
              child: Row(
                children: <Widget>[
                  GlassCircleButton(
                    icon: Icons.arrow_back_rounded,
                    size: 40,
                    onTap: onBack,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.game, this.heroTag});

  final Game game;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final GameCover cover = GameCover(
      imageUrl: game.coverUrl,
      title: game.title,
      memWidth: 360,
      borderRadius: AppRadii.md,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            boxShadow: AppShadows.glass,
          ),
          child: SizedBox(
            width: 122,
            height: 164,
            child: heroTag == null ? cover : Hero(tag: heroTag!, child: cover),
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                game.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.texts.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.08,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (game.hasRating)
                RatingLine(rating: game.rating, count: game.ratingCount),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final List<Widget> chips = <Widget>[
      if (game.genre != null) InfoChip(label: game.genre!, icon: Icons.category_rounded),
      if (game.primaryPlatform.isNotEmpty)
        InfoChip(label: game.primaryPlatform, icon: Icons.layers_rounded),
      if (game.year != null)
        InfoChip(label: game.year.toString(), icon: Icons.event_rounded),
      if (game.hasRating)
        InfoChip(
          label: formatPercent(game.rating / 5),
          icon: Icons.star_rounded,
          color: AppColors.warning,
        ),
      if (game.visitCount > 0)
        InfoChip(
          label: compactNumber(game.visitCount),
          icon: Icons.visibility_rounded,
          color: AppColors.accentAlt,
        ),
      if (game.isFree)
        InfoChip(label: l10n.freeBadge, icon: Icons.bolt_rounded, color: AppColors.success),
      if (game.needsRom)
        InfoChip(label: l10n.needsFiles, icon: Icons.folder_rounded, color: AppColors.warning),
    ];
    return Wrap(spacing: 10, runSpacing: 10, children: chips);
  }
}

class _FavoritePill extends StatefulWidget {
  const _FavoritePill({
    required this.active,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final String label;
  final VoidCallback onTap;

  @override
  State<_FavoritePill> createState() => _FavoritePillState();
}

class _FavoritePillState extends State<_FavoritePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  late final Animation<double> _scale = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 1.35)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.35, end: 1)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
    ],
  ).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handle() {
    _controller.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final bool active = widget.active;
    return Pressable(
      onTap: _handle,
      child: Container(
        height: AppSpacing.secondaryButtonHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          color: active ? AppColors.accent.withValues(alpha: 0.16) : AppColors.glass,
          border: Border.all(
            color: active
                ? AppColors.accent.withValues(alpha: 0.5)
                : AppColors.glassBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedBuilder(
              animation: _scale,
              builder: (BuildContext context, Widget? child) =>
                  Transform.scale(scale: _scale.value, child: child),
              child: Icon(
                active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 19,
                color: active ? AppColors.favorite : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelLarge?.copyWith(
                  color: active ? AppColors.accent : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockTitle extends StatelessWidget {
  const _BlockTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: context.texts.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: context.texts.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
      ],
    );
  }
}

class CompatReportCard extends StatelessWidget {
  const CompatReportCard({super.key, required this.summary, required this.onReport});

  final CompatSummary summary;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    return GlassContainer(
      radius: AppRadii.lg,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  color: AppColors.accent.withValues(alpha: 0.14),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
                ),
                child: const Icon(Icons.phone_android_rounded, color: AppColors.accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.compatTitle,
                      style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.compatSubtitle,
                      style: context.texts.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                l10n.compatReports(summary.total),
                style: context.texts.labelSmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (summary.isEmpty)
            Text(
              l10n.notInformed,
              style: context.texts.bodySmall?.copyWith(color: AppColors.textTertiary),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _CompatPill(
                  label: l10n.compatPerfect,
                  count: summary.perfect,
                  color: AppColors.success,
                ),
                _CompatPill(
                  label: l10n.compatGood,
                  count: summary.good,
                  color: AppColors.accentAlt,
                ),
                _CompatPill(
                  label: l10n.compatStutter,
                  count: summary.stutter,
                  color: AppColors.warning,
                ),
                _CompatPill(
                  label: l10n.compatUnplayable,
                  count: summary.unplayable,
                  color: AppColors.danger,
                ),
                _CompatPill(
                  label: l10n.compatNotRun,
                  count: summary.notRun,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            label: l10n.compatReport,
            icon: Icons.add_rounded,
            height: 44,
            onPressed: onReport,
          ),
        ],
      ),
    );
  }
}

class _CompatPill extends StatelessWidget {
  const _CompatPill({required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.labelSmall?.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(
            count.toString(),
            style: context.texts.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompatSheet extends StatelessWidget {
  const _CompatSheet({required this.specs});

  final DeviceSpecs specs;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final String device = <String>[
      if (specs.brand != null) specs.brand!,
      if (specs.model != null) specs.model!,
    ].join(' ');
    final String details = <String>[
      if (specs.soc != null) specs.soc!,
      if (specs.gpu != null) specs.gpu!,
      if (specs.ramGb != null) '${specs.ramGb} GB',
    ].join(' · ');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.vertical(top: AppRadii.sheet),
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                context.l10n.compatTitle,
                style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                device.isEmpty ? l10n.compatYourDevice : device,
                style: context.texts.labelMedium?.copyWith(color: AppColors.textSecondary),
              ),
              if (details.isNotEmpty)
                Text(
                  details,
                  style: context.texts.labelSmall?.copyWith(color: AppColors.textTertiary),
                ),
              const SizedBox(height: AppSpacing.lg),
              _VerdictOption(value: 'perfect', label: l10n.compatPerfect, icon: Icons.rocket_launch_rounded, color: AppColors.success),
              const SizedBox(height: AppSpacing.sm),
              _VerdictOption(value: 'good', label: l10n.compatGood, icon: Icons.thumb_up_rounded, color: AppColors.accentAlt),
              const SizedBox(height: AppSpacing.sm),
              _VerdictOption(value: 'stutter', label: l10n.compatStutter, icon: Icons.speed_rounded, color: AppColors.warning),
              const SizedBox(height: AppSpacing.sm),
              _VerdictOption(value: 'unplayable', label: l10n.compatUnplayable, icon: Icons.hourglass_disabled_rounded, color: AppColors.danger),
              const SizedBox(height: AppSpacing.sm),
              _VerdictOption(value: 'not_run', label: l10n.compatNotRun, icon: Icons.block_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerdictOption extends StatelessWidget {
  const _VerdictOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SecondaryButton(
      label: label,
      icon: icon,
      iconColor: color,
      onPressed: () => Navigator.of(context).pop(value),
    );
  }
}

/// Rótulo e cor de cada veredito de compatibilidade.
String compatVerdictLabel(L10n l10n, String status) {
  switch (status) {
    case 'perfect':
      return l10n.compatPerfect;
    case 'stutter':
      return l10n.compatStutter;
    case 'unplayable':
      return l10n.compatUnplayable;
    case 'not_run':
      return l10n.compatNotRun;
    case 'good':
    default:
      return l10n.compatGood;
  }
}

Color compatVerdictColor(String status) {
  switch (status) {
    case 'perfect':
      return AppColors.success;
    case 'stutter':
      return AppColors.warning;
    case 'unplayable':
      return AppColors.danger;
    case 'not_run':
      return AppColors.textSecondary;
    case 'good':
    default:
      return AppColors.accentAlt;
  }
}

class _CommunityReports extends ConsumerWidget {
  const _CommunityReports({required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;
    final AsyncValue<List<CompatReport>> async =
        ref.watch(gameCompatReportsProvider(gameId));
    final List<CompatReport> reports = async.value ?? const <CompatReport>[];

    if (async.isLoading && reports.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
          ),
        ),
      );
    }
    if (reports.isEmpty) {
      return GlassContainer(
        radius: AppRadii.lg,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          l10n.compatNoReports,
          style: context.texts.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      );
    }

    return FutureBuilder<DeviceSpecs>(
      future: DeviceInfo.load(),
      builder: (BuildContext context, AsyncSnapshot<DeviceSpecs> snapshot) {
        final String? soc = snapshot.data?.soc;
        return Column(
          children: <Widget>[
            for (final CompatReport report in reports)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _CompatReportRow(
                  report: report,
                  sameSoc: soc != null && soc.isNotEmpty && report.soc == soc,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CompatReportRow extends StatelessWidget {
  const _CompatReportRow({required this.report, required this.sameSoc});

  final CompatReport report;
  final bool sameSoc;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final String specs = <String>[
      if (report.soc != null) report.soc!,
      if (report.gpu != null) report.gpu!,
      if (report.ramGb != null) '${report.ramGb} GB',
    ].join(' · ');

    return GlassContainer(
      radius: AppRadii.md,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.glassStrong,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(
              initialsOf(report.author),
              style: context.texts.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        report.deviceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    BadgeChip(
                      label: compatVerdictLabel(l10n, report.status),
                      color: compatVerdictColor(report.status),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${report.author}${specs.isEmpty ? '' : ' · $specs'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelSmall?.copyWith(color: AppColors.textTertiary),
                ),
                if (sameSoc) ...<Widget>[
                  const SizedBox(height: 6),
                  BadgeChip(
                    label: l10n.compatSameSoc,
                    color: AppColors.accent,
                    icon: Icons.memory_rounded,
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

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.game, required this.ports});

  final Game game;
  final int ports;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final List<List<String>> rows = <List<String>>[
      <String>[l10n.releaseYear, game.year?.toString() ?? l10n.notInformed],
      <String>[l10n.developer, game.developer ?? l10n.notInformed],
      <String>[l10n.genreLabel, game.genre ?? l10n.notInformed],
      <String>[
        l10n.platformsLabel,
        game.platforms.isEmpty ? l10n.notInformed : game.platforms.join(' · '),
      ],
      <String>[l10n.portsTitle, l10n.portCount(ports)],
      <String>[
        l10n.needsFiles,
        game.needsRom ? l10n.needsFilesYes : l10n.needsFilesNo,
      ],
    ];

    return GlassContainer(
      radius: AppRadii.lg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 6),
      child: Column(
        children: <Widget>[
          for (int index = 0; index < rows.length; index += 1) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 112,
                    child: Text(
                      rows[index][0],
                      style: context.texts.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      rows[index][1],
                      style: context.texts.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (index < rows.length - 1)
              const Divider(height: 1, color: AppColors.glassBorder),
          ],
        ],
      ),
    );
  }
}

class _PortCard extends StatelessWidget {
  const _PortCard({required this.port, required this.onOpen});

  final GamePort port;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final String? works = port.works;
    String worksLabel = l10n.worksUntested;
    Color worksColor = AppColors.textSecondary;
    if (works == 'yes') {
      worksLabel = l10n.worksYes;
      worksColor = AppColors.success;
    } else if (works == 'no') {
      worksLabel = l10n.worksNo;
      worksColor = AppColors.danger;
    } else if (works == 'bug') {
      worksLabel = l10n.worksBug;
      worksColor = AppColors.warning;
    } else if (works == 'partial') {
      worksLabel = l10n.worksPartial;
      worksColor = AppColors.accentAlt;
    }

    return GlassContainer(
      radius: AppRadii.md,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              BadgeChip(label: port.platformName, color: AppColors.accent),
              const SizedBox(width: 6),
              BadgeChip(label: worksLabel, color: worksColor),
              const Spacer(),
              if (port.url == null)
                BadgeChip(label: l10n.noLink, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            port.project ?? port.platformName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (port.developer != null || port.version != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              <String>[
                ?port.developer,
                if (port.version != null) 'v${port.version!}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (port.notes != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              port.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (port.needsGameFiles && port.needsGameFilesNote != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.folder_rounded, size: 13, color: AppColors.warning),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    port.needsGameFilesNote!,
                    style: context.texts.labelSmall?.copyWith(color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              if (port.url != null)
                SecondaryButton(
                  label: l10n.openSource,
                  icon: Icons.open_in_new_rounded,
                  height: 42,
                  expand: false,
                  onPressed: onOpen,
                ),
              if (port.url != null) const SizedBox(width: AppSpacing.sm),
              if (port.lastUpdate != null)
                Flexible(
                  child: Text(
                    '${l10n.portUpdated} ${formatMonthYear(port.lastUpdate, en: l10n.isEn)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    return GlassContainer(
      radius: AppRadii.md,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.glassStrong,
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Text(
                  initialsOf(review.author),
                  style: context.texts.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      review.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        for (int index = 1; index <= 5; index += 1)
                          Icon(
                            index <= review.rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 12,
                            color: index <= review.rating
                                ? AppColors.warning
                                : AppColors.textTertiary,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          formatDate(review.createdAt, en: l10n.isEn),
                          style: context.texts.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review.body.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              review.body,
              style: context.texts.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          72,
          AppSpacing.screen,
          40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const SkeletonBox(width: 122, height: 164, radius: AppRadii.md),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SkeletonBox(width: double.infinity, height: 24),
                      const SizedBox(height: 10),
                      const SkeletonBox(width: 140, height: 14),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const SkeletonBox(width: 200, height: 32, radius: AppRadii.pill),
            const SizedBox(height: AppSpacing.md),
            const SkeletonBox(width: double.infinity, height: 52, radius: AppRadii.pill),
            const SizedBox(height: AppSpacing.md),
            const SkeletonBox(width: double.infinity, height: 48, radius: AppRadii.pill),
            const SizedBox(height: AppSpacing.xxl),
            const SkeletonBox(width: 140, height: 18),
            const SizedBox(height: AppSpacing.md),
            const SkeletonBox(width: double.infinity, height: 110, radius: AppRadii.lg),
          ],
        ),
      ),
    );
  }
}

/// Fundo da tela de detalhes: a própria capa ampliada e desfocada, com camada
/// escura e gradiente para o fundo. Atualiza sozinho quando a capa muda.
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({required this.coverUrl, required this.title});

  final String? coverUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.sizeOf(context).height;
    return Stack(
      children: <Widget>[
        const ColoredBox(color: AppColors.bg, child: SizedBox.expand()),
        if (coverUrl != null)
          // A capa ocupa a tela inteira e perde opacidade gradualmente por uma
          // máscara de alfa vertical: nada de corte reto, some no fundo.
          Positioned.fill(
            child: IgnorePointer(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (Rect bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xFFFFFFFF),
                    Color(0xE6FFFFFF),
                    Color(0x99FFFFFF),
                    Color(0x40FFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: <double>[0.0, 0.28, 0.5, 0.72, 0.92],
                ).createShader(bounds),
                child: Opacity(
                  opacity: 0.9,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: Transform.scale(
                      scale: 1.25,
                      child: GameCover(
                        imageUrl: coverUrl,
                        title: title,
                        memWidth: 1400,
                        fit: BoxFit.cover,
                        borderRadius: 0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          Positioned(
            top: -140,
            left: -80,
            right: -80,
            height: screenHeight * 0.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.accent.withValues(alpha: 0.16),
                    AppColors.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        // Vinheta bem leve no topo, só para manter o contraste do texto.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: screenHeight * 0.4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withValues(alpha: 0.28),
                  Colors.black.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
