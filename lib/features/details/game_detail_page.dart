import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/env.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
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
  bool _barTitle = false;
  bool _submitting = false;
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _review.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final bool next = _scroll.offset > 250;
    if (next != _barTitle) {
      setState(() => _barTitle = next);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _showSnack(String message, {String? actionLabel, VoidCallback? onAction}) {
    final AppPalette p = context.palette;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceHigh,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: p.secondary,
                onPressed: onAction ?? () {},
              ),
      ),
    );
  }

  void _install(GameDetail detail) {
    final L10n l10n = context.l10n;
    final DownloadTask? current =
        ref.read(downloadForGameProvider(detail.game.id));
    if (current != null && current.isDone) {
      _showSnack(l10n.installedLabel);
      return;
    }
    final GamePort? port = detail.primaryPort;
    if (port == null || port.url == null) {
      _showSnack(l10n.noLink);
      return;
    }
    ref.read(downloadsProvider.notifier).start(detail.game, port: port);
    _showSnack(
      l10n.downloadStarted,
      actionLabel: l10n.viewDownloads,
      onAction: () => context.go('/downloads'),
    );
  }

  Future<void> _toggleFavorite(GameDetail detail) async {
    final bool ok =
        await ref.read(collectionsProvider.notifier).toggleFavorite(detail.game);
    if (!mounted) {
      return;
    }
    if (!ok) {
      _showSnack(context.l10n.errorGeneric);
    }
  }

  Future<void> _toggleLibrary(GameDetail detail) async {
    final bool wasInLibrary = ref
            .read(collectionsProvider)
            .value
            ?.isInLibrary(detail.game.id) ??
        false;
    final bool ok =
        await ref.read(collectionsProvider.notifier).toggleLibrary(detail.game);
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

  @override
  Widget build(BuildContext context) {
    final AsyncValue<GameDetail> async =
        ref.watch(gameDetailProvider(widget.slug));

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
                left: 14,
                top: 8,
                child: IconGlassButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: _back,
                ),
              ),
              if (async.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ErrorStateView(
                    message: context.failureText(async.error),
                    retryLabel: context.l10n.tryAgain,
                    onRetry: () =>
                        ref.invalidate(gameDetailProvider(widget.slug)),
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
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    final Game game = detail.game;
    final Collections collections =
        ref.watch(collectionsProvider).value ?? Collections.empty;
    final bool favorite = collections.isFavorite(game.id);
    final bool inLibrary = collections.isInLibrary(game.id);
    final DownloadTask? task = ref.watch(downloadForGameProvider(game.id));

    final String installLabel = task == null
        ? l10n.install
        : task.isDone
            ? l10n.installedLabel
            : l10n.continueAction;
    final IconData installIcon = task == null
        ? Icons.download_rounded
        : task.isDone
            ? Icons.check_circle_rounded
            : Icons.play_arrow_rounded;

    final bool longDescription = game.description.length > 320;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackdrop(
        child: CustomScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            SliverAppBar(
              expandedHeight: 392,
              pinned: true,
              stretch: true,
              backgroundColor: p.bg,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              leadingWidth: 64,
              leading: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Center(
                  child: IconGlassButton(
                    icon: Icons.arrow_back_rounded,
                    size: 40,
                    onTap: _back,
                  ),
                ),
              ),
              titleSpacing: 0,
              title: AnimatedOpacity(
                opacity: _barTitle ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  game.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              actions: <Widget>[
                IconGlassButton(
                  icon: favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  active: favorite,
                  size: 40,
                  tooltip: favorite ? l10n.unfavoriteTooltip : l10n.favoriteTooltip,
                  onTap: () => _toggleFavorite(detail),
                ),
                const SizedBox(width: 8),
                IconGlassButton(
                  icon: Icons.ios_share_rounded,
                  size: 40,
                  tooltip: l10n.share,
                  onTap: () => _share(detail),
                ),
                const SizedBox(width: 14),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                stretchModes: const <StretchMode>[StretchMode.zoomBackground],
                background: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (widget.heroTag != null)
                      Hero(
                        tag: widget.heroTag!,
                        child: GameCover(
                          imageUrl: game.coverUrl,
                          title: game.title,
                          memWidth: 1000,
                          borderRadius: 0,
                        ),
                      )
                    else
                      GameCover(
                        imageUrl: game.coverUrl,
                        title: game.title,
                        memWidth: 1000,
                        borderRadius: 0,
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color(0x55000000),
                            Color(0x00000000),
                            Color(0x99000000),
                          ],
                          stops: <double>[0, 0.34, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 170,
                      child: DecoratedBox(decoration: BoxDecoration(gradient: p.scrim)),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      game.title,
                      style: context.texts.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.9,
                        height: 1.06,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        if (game.hasRating) ...<Widget>[
                          RatingLine(
                            rating: game.rating,
                            count: game.ratingCount,
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (game.year != null)
                          Text(
                            game.year.toString(),
                            style: context.texts.labelMedium?.copyWith(
                              color: p.muted,
                            ),
                          ),
                        if (game.genre != null) ...<Widget>[
                          if (game.year != null)
                            Text(
                              '  ·  ',
                              style: context.texts.labelMedium?.copyWith(
                                color: p.muted,
                              ),
                            ),
                          Flexible(
                            child: Text(
                              game.genre!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.labelMedium?.copyWith(
                                color: p.muted,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (game.visitCount > 0)
                          Text(
                            '${compactNumber(game.visitCount)} ${l10n.visits}',
                            style: context.texts.labelSmall?.copyWith(
                              color: p.muted,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: <Widget>[
                        for (final String platform in game.platforms.take(3))
                          BadgeChip(
                            label: platform,
                            color: p.secondary,
                            icon: Icons.layers_rounded,
                          ),
                        if (game.isFree)
                          BadgeChip(
                            label: l10n.freeBadge,
                            color: p.success,
                            icon: Icons.bolt_rounded,
                          ),
                        if (game.needsRom)
                          BadgeChip(
                            label: l10n.needsFiles,
                            color: p.warning,
                            icon: Icons.folder_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: GradientButton(
                            label: installLabel,
                            icon: installIcon,
                            height: 54,
                            onPressed: () => _install(detail),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GhostButton(
                          label: inLibrary ? l10n.inLibrary : l10n.addToLibrary,
                          icon: inLibrary
                              ? Icons.check_rounded
                              : Icons.add_rounded,
                          height: 54,
                          active: inLibrary,
                          onPressed: () => _toggleLibrary(detail),
                        ),
                      ],
                    ),
                    if (task != null && !task.isDone) ...<Widget>[
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: GradientProgress(value: task.progress),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l10n.progressPercent((task.progress * 100).round()),
                            style: context.texts.labelSmall?.copyWith(
                              color: p.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 26),
                    _BlockTitle(title: l10n.synopsis),
                    const SizedBox(height: 10),
                    GlassPanel(
                      radius: 20,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            game.description.isEmpty
                                ? l10n.notInformed
                                : game.description,
                            maxLines: _expandedDescription ? null : 5,
                            overflow: _expandedDescription
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: context.texts.bodyMedium?.copyWith(
                              color: p.muted,
                              height: 1.55,
                            ),
                          ),
                          if (longDescription) ...<Widget>[
                            const SizedBox(height: 8),
                            Pressable(
                              onTap: () => setState(
                                () => _expandedDescription =
                                    !_expandedDescription,
                              ),
                              child: Text(
                                _expandedDescription
                                    ? l10n.readLess
                                    : l10n.readMore,
                                style: context.texts.labelMedium?.copyWith(
                                  color: p.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    _BlockTitle(title: l10n.requirements),
                    const SizedBox(height: 10),
                    _RequirementsPanel(game: game, ports: detail.ports.length),
                    const SizedBox(height: 26),
                    _BlockTitle(
                      title: l10n.portsTitle,
                      trailing: l10n.portCount(detail.ports.length),
                    ),
                    const SizedBox(height: 10),
                    if (detail.ports.isEmpty)
                      Text(
                        l10n.notInformed,
                        style: context.texts.bodyMedium?.copyWith(
                          color: p.muted,
                        ),
                      )
                    else
                      for (final GamePort port in detail.ports)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PortCard(
                            port: port,
                            onOpen: () => _openLink(port.url),
                          ),
                        ),
                    const SizedBox(height: 26),
                    _BlockTitle(
                      title: l10n.reviewsTitle,
                      trailing: l10n.reviewCount(detail.reviews.length),
                    ),
                    const SizedBox(height: 10),
                    GlassPanel(
                      radius: 20,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.yourRating,
                            style: context.texts.labelMedium?.copyWith(
                              color: p.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          StarPicker(
                            value: _rating,
                            onChanged: (int value) =>
                                setState(() => _rating = value),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _review,
                            maxLines: 3,
                            minLines: 2,
                            maxLength: 1000,
                            style: context.texts.bodyMedium,
                            cursorColor: p.primary,
                            decoration: InputDecoration(
                              hintText: l10n.reviewHint,
                              hintStyle: context.texts.bodySmall?.copyWith(
                                color: p.muted,
                              ),
                              filled: true,
                              fillColor: p.surfaceHigh.withValues(alpha: 0.6),
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                          ),
                          const SizedBox(height: 10),
                          GradientButton(
                            label: l10n.send,
                            icon: Icons.send_rounded,
                            isLoading: _submitting,
                            height: 48,
                            onPressed: () => _submitReview(detail),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (detail.reviews.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text(
                            l10n.noReviews,
                            textAlign: TextAlign.center,
                            style: context.texts.bodySmall?.copyWith(
                              color: p.muted,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final Review review in detail.reviews)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ReviewCard(review: review),
                        ),
                    if (detail.related.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 18),
                      _BlockTitle(title: l10n.relatedTitle),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 250,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: detail.related.length,
                          separatorBuilder:
                              (BuildContext context, int index) =>
                                  const SizedBox(width: 12),
                          itemBuilder: (BuildContext context, int index) {
                            final Game related = detail.related[index];
                            return GameCard(
                              game: related,
                              width: 132,
                              heroTag: 'detail-${game.id}-related-${related.id}',
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
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
            style: context.texts.labelSmall?.copyWith(
              color: context.palette.muted,
            ),
          ),
      ],
    );
  }
}

class _RequirementsPanel extends StatelessWidget {
  const _RequirementsPanel({required this.game, required this.ports});

  final Game game;
  final int ports;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
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

    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: <Widget>[
          for (int index = 0; index < rows.length; index += 1) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 108,
                    child: Text(
                      rows[index][0],
                      style: context.texts.bodySmall?.copyWith(color: p.muted),
                    ),
                  ),
                  const SizedBox(width: 10),
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
              Divider(height: 1, color: p.line, thickness: 1),
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
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    final String? works = port.works;
    String worksLabel = l10n.worksUntested;
    Color worksColor = p.muted;
    if (works == 'yes') {
      worksLabel = l10n.worksYes;
      worksColor = p.success;
    } else if (works == 'no') {
      worksLabel = l10n.worksNo;
      worksColor = p.danger;
    } else if (works == 'bug') {
      worksLabel = l10n.worksBug;
      worksColor = p.warning;
    } else if (works == 'partial') {
      worksLabel = l10n.worksPartial;
      worksColor = p.secondary;
    }

    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              BadgeChip(
                label: port.platformName,
                color: p.secondary,
                icon: Icons.layers_rounded,
              ),
              const SizedBox(width: 6),
              BadgeChip(label: worksLabel, color: worksColor),
              const Spacer(),
              if (port.url == null)
                BadgeChip(
                  label: l10n.noLink,
                  color: p.muted,
                  icon: Icons.link_off_rounded,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            port.project ?? port.platformName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (port.developer != null || port.version != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              <String>[
                if (port.developer != null) port.developer!,
                if (port.version != null) 'v${port.version!}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(color: p.muted),
            ),
          ],
          if (port.notes != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              port.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(
                color: p.muted,
                height: 1.4,
              ),
            ),
          ],
          if (port.needsGameFiles && port.needsGameFilesNote != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.folder_rounded, size: 13, color: p.warning),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    port.needsGameFilesNote!,
                    style: context.texts.labelSmall?.copyWith(color: p.warning),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (port.url != null)
                GhostButton(
                  label: l10n.openSource,
                  icon: Icons.open_in_new_rounded,
                  height: 42,
                  onPressed: onOpen,
                ),
              if (port.url != null) const SizedBox(width: 8),
              if (port.lastUpdate != null)
                Flexible(
                  child: Text(
                    '${l10n.portUpdated} ${formatMonthYear(port.lastUpdate, en: l10n.isEn)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall?.copyWith(color: p.muted),
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
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
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
                  gradient: p.brandSoft,
                  border: Border.all(color: p.line),
                ),
                child: Text(
                  initialsOf(review.author),
                  style: context.texts.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: p.primary,
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
                            color: index <= review.rating ? p.warning : p.muted,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          formatDate(review.createdAt, en: l10n.isEn),
                          style: context.texts.labelSmall?.copyWith(
                            color: p.muted,
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
            const SizedBox(height: 10),
            Text(
              review.body,
              style: context.texts.bodySmall?.copyWith(
                color: p.text.withValues(alpha: 0.86),
                height: 1.45,
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
        padding: const EdgeInsets.fromLTRB(20, 76, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SkeletonBox(width: double.infinity, height: 250, radius: 24),
            const SizedBox(height: 20),
            const SkeletonBox(width: 240, height: 22),
            const SizedBox(height: 10),
            const SkeletonBox(width: 160, height: 12),
            const SizedBox(height: 22),
            const SkeletonBox(width: double.infinity, height: 54, radius: 18),
            const SizedBox(height: 26),
            const SkeletonBox(width: 140, height: 16),
            const SizedBox(height: 12),
            const SkeletonBox(width: double.infinity, height: 100, radius: 20),
          ],
        ),
      ),
    );
  }
}
