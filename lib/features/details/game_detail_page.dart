import 'dart:ui' show BlendMode, ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/apk_tools.dart';
import '../../core/auth.dart';
import '../../core/device_info.dart';
import '../../core/download_source.dart';
import '../../core/env.dart';
import '../../core/formatters.dart';
import '../../core/github_releases.dart';
import '../../core/native_downloader.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../models/collections.dart';
import '../../models/compat_report.dart';
import '../../models/compat_summary.dart';
import '../../models/download_task.dart';
import '../../models/game.dart';
import '../../models/game_detail.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/feedback_report_row.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/states.dart';
import '../collections/collections_controller.dart';
import '../downloads/downloads_controller.dart';

final gameDetailProvider = FutureProvider.family<GameDetail, String>(
  (ref, String slug) => ref.watch(catalogRepositoryProvider).fetchGame(slug),
);

final gameCompatReportsProvider =
    FutureProvider.family<List<CompatReport>, String>(
      (ref, String gameId) =>
          ref.watch(catalogRepositoryProvider).fetchCompatReports(gameId),
    );

/// Última release (com APK) do repositório de um port, identificada por
/// `owner/repo`. Serve para saber se existe uma versão mais nova que a baixada.
final latestReleaseProvider = FutureProvider.family<GithubRelease?, String>((
  ref,
  String repoId,
) {
  final List<String> parts = repoId.split('/');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
    return null;
  }
  return fetchLatestApkRelease(GithubRepo(parts[0], parts[1]));
});

/// Estado de instalação do app correspondente ao pacote de um APK baixado.
final installedAppProvider = FutureProvider.family<ApkSummary?, String>(
  (ref, String packageName) => ApkTools.installed(packageName),
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

  bool _expandedDescription = false;
  bool _barTitle = false;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Ao voltar do instalador do Android, revalida se o app ficou instalado.
    _lifecycle = AppLifecycleListener(onResume: _onResumed);
  }

  void _onResumed() {
    ref.invalidate(installedAppProvider);
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
    _lifecycle.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _showSnack(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // Padrão único do app (posição acima da barra de vidro, cor, duração).
    showAppSnackBar(
      context,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  Future<void> _install(GameDetail detail) async {
    final L10n l10n = context.l10n;
    final DownloadTask? current = ref.read(
      downloadForGameProvider(detail.game.id),
    );
    if (current != null && current.isDone) {
      final ApkSummary? installed = await _installedApp(current);
      if (installed != null) {
        // Instalado: se saiu uma versão nova, baixa de novo; senão abre o app.
        if (await _hasUpdate(current)) {
          await _startDownload(detail, restart: true);
          return;
        }
        final String? pkg = current.packageName;
        if (pkg != null && await ApkTools.launch(pkg)) {
          return;
        }
      }
      // Sem app instalado (ou sem como abrir): instala o APK já baixado.
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

    await _startDownload(detail);
  }

  /// Dados do app instalado correspondente à tarefa (ou `null`).
  Future<ApkSummary?> _installedApp(DownloadTask task) async {
    final String? pkg = task.packageName;
    if (pkg == null || pkg.isEmpty) {
      return null;
    }
    return ApkTools.installed(pkg);
  }

  /// `true` quando a release mais recente difere da versão já baixada.
  Future<bool> _hasUpdate(DownloadTask task) async {
    final String? stored = task.releaseTag;
    final String? url = task.portUrl;
    if (stored == null || url == null) {
      return false;
    }
    final GithubRepo? repo = githubRepoOf(url);
    if (repo == null) {
      return false;
    }
    try {
      final GithubRelease? release = await fetchLatestApkRelease(repo);
      final String? latest = release?.tag;
      return latest != null && latest.isNotEmpty && latest != stored;
    } on Object {
      return false;
    }
  }

  /// Resolve a fonte do port e inicia o download (ou abre a página de destino).
  Future<void> _startDownload(GameDetail detail, {bool restart = false}) async {
    final L10n l10n = context.l10n;
    final GamePort? port = detail.primaryPort;
    final String? url = port?.url;
    if (port == null || url == null) {
      _showSnack(l10n.noLink);
      return;
    }

    final GithubRepo? repo = githubRepoOf(url);
    if (repo != null && !isDirectApkUrl(url)) {
      await _installFromGithub(detail, port, url, repo, restart: restart);
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

    ref
        .read(downloadsProvider.notifier)
        .start(detail.game, port: port, urlOverride: direct, restart: restart);
    _showSnack(
      l10n.downloadStarted,
      actionLabel: l10n.viewDownloads,
      onAction: () => context.go('/hub'),
    );
  }

  Future<void> _toggleFavorite(GameDetail detail) async {
    final bool ok = await ref
        .read(collectionsProvider.notifier)
        .toggleFavorite(detail.game);
    if (!mounted) {
      return;
    }
    if (!ok) {
      _showSnack(context.l10n.errorGeneric);
    }
  }

  Future<void> _toggleLibrary(GameDetail detail) async {
    final bool wasInLibrary =
        ref.read(collectionsProvider).value?.isInLibrary(detail.game.id) ??
        false;
    final bool ok = await ref
        .read(collectionsProvider.notifier)
        .toggleLibrary(detail.game);
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
    // Compartilha a página do PORTIX (GitHub Pages); os APKs ficam nas releases.
    final String url = '$kLandingUrl#${detail.game.slug}';
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

  Future<void> _openFeedbackSheet(GameDetail detail) async {
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
    final _FeedbackResult? result = await showModalBottomSheet<_FeedbackResult>(
      context: context,
      backgroundColor: AppContentColors.transparent,
      useSafeArea: true,
      barrierColor: AppContentColors.scrim.withValues(alpha: 0.6),
      builder: (BuildContext context) => _FeedbackSheet(specs: specs),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(catalogRepositoryProvider)
          .submitReview(
            gameId: detail.game.id,
            rating: result.rating,
            body: result.body,
            verdict: result.verdict,
            fps: result.fps,
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
      _showSnack(l10n.reviewSent);
    } on Object {
      if (mounted) {
        _showSnack(l10n.errorGeneric);
      }
    }
  }

  Future<void> _installFromGithub(
    GameDetail detail,
    GamePort port,
    String sourceUrl,
    GithubRepo repo, {
    bool restart = false,
  }) async {
    final L10n l10n = context.l10n;
    _showSnack(l10n.searchingRelease);
    try {
      final GithubRelease? release = await fetchLatestApkRelease(repo);
      if (!mounted) {
        return;
      }
      final List<ApkAsset> assets = release?.assets ?? const <ApkAsset>[];
      if (assets.isEmpty) {
        await _openLink(sourceUrl);
        if (mounted) {
          _showSnack(l10n.sourceOnly);
        }
        return;
      }
      final ApkAsset? chosen = assets.length == 1
          ? assets.first
          : await _pickApkAsset(assets);
      if (chosen == null || !mounted) {
        return;
      }
      ref
          .read(downloadsProvider.notifier)
          .start(
            detail.game,
            port: port,
            urlOverride: chosen.url,
            releaseTag: release?.tag,
            restart: restart,
          );
      _showSnack(
        l10n.downloadStarted,
        actionLabel: l10n.viewDownloads,
        onAction: () => context.go('/hub'),
      );
    } on Object {
      if (!mounted) {
        return;
      }
      await _openLink(sourceUrl);
      if (mounted) {
        _showSnack(l10n.sourceOnly);
      }
    }
  }

  Future<ApkAsset?> _pickApkAsset(List<ApkAsset> assets) {
    return showModalBottomSheet<ApkAsset>(
      context: context,
      backgroundColor: AppContentColors.transparent,
      useSafeArea: true,
      barrierColor: AppContentColors.scrim.withValues(alpha: 0.6),
      builder: (BuildContext context) => _ApkPickerSheet(assets: assets),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<GameDetail> async = ref.watch(
      gameDetailProvider(widget.slug),
    );

    if (async.hasValue) {
      return _buildDetail(context, async.requireValue);
    }

    return Scaffold(
      backgroundColor: AppContentColors.transparent,
      body: AppBackdrop(
        child: SafeArea(
          child: AppContentMax(
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: AppSpacing.md,
                  top: AppSpacing.sm,
                  child: GlassCircleButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: context.l10n.tooltipBack,
                    onTap: _back,
                  ),
                ),
                if (async.hasError)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
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
      ),
    );
  }

  Widget _buildDetail(BuildContext context, GameDetail detail) {
    final L10n l10n = context.l10n;
    final Game game = detail.game;
    final Collections collections =
        ref.watch(collectionsProvider).value ?? Collections.empty;
    final bool favorite = collections.isFavorite(game.id);
    final bool inLibrary = collections.isInLibrary(game.id);
    final DownloadTask? task = ref.watch(downloadForGameProvider(game.id));

    // Somente depois de baixar é que dá para checar instalação e atualização.
    final bool done = task != null && task.isDone;
    final String packageName = done ? (task.packageName ?? '') : '';

    bool installed = false;
    if (packageName.isNotEmpty) {
      installed = ref.watch(installedAppProvider(packageName)).value != null;
    }

    final String? sourceUrl = detail.primaryPort?.url;
    final GithubRepo? sourceRepo = sourceUrl == null
        ? null
        : githubRepoOf(sourceUrl);
    String? latestTag;
    if (done && sourceRepo != null) {
      latestTag = ref
          .watch(
            latestReleaseProvider('${sourceRepo.owner}/${sourceRepo.repo}'),
          )
          .value
          ?.tag;
    }
    final String? storedTag = task?.releaseTag;
    final bool updateAvailable =
        installed &&
        storedTag != null &&
        latestTag != null &&
        latestTag.isNotEmpty &&
        latestTag != storedTag;

    final String installLabel =
        task == null || task.status == DownloadStatus.failed
        ? l10n.install
        : done
        ? (installed
              ? (updateAvailable ? l10n.updateNow : l10n.openApp)
              : l10n.install)
        : l10n.continueAction;
    final IconData installIcon =
        task == null || task.status == DownloadStatus.failed
        ? Icons.download_rounded
        : done
        ? (installed
              ? (updateAvailable
                    ? Icons.system_update_alt_rounded
                    : Icons.open_in_new_rounded)
              : Icons.download_done_rounded)
        : Icons.play_arrow_rounded;

    final bool longDescription = game.description.length > 320;

    return Scaffold(
      backgroundColor: AppContentColors.transparent,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _CoverBackdrop(coverUrl: game.coverUrl, title: game.title),
          ),
          SafeArea(
            bottom: false,
            child: AppContentMax(
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
                            tooltip: context.l10n.tooltipBack,
                            onTap: _back,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _Header(game: game, heroTag: widget.heroTag),
                          const SizedBox(height: AppSpacing.lg),
                          _Chips(game: game),
                          const SizedBox(height: AppSpacing.lg),
                          if (task != null &&
                              task.status ==
                                  DownloadStatus.downloading) ...<Widget>[
                            GradientProgress(value: task.progress),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: SecondaryButton(
                                    label: l10n.pause,
                                    icon: Icons.pause_rounded,
                                    onPressed: () => ref
                                        .read(downloadsProvider.notifier)
                                        .pause(game.id),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: SecondaryButton(
                                    label: l10n.cancel,
                                    icon: Icons.close_rounded,
                                    onPressed: () => ref
                                        .read(downloadsProvider.notifier)
                                        .cancel(game.id),
                                  ),
                                ),
                              ],
                            ),
                          ] else if (task != null &&
                              task.status == DownloadStatus.paused)
                            PrimaryButton(
                              label: l10n.continueAction,
                              icon: Icons.play_arrow_rounded,
                              onPressed: () => ref
                                  .read(downloadsProvider.notifier)
                                  .resume(game.id),
                            )
                          else
                            PrimaryButton(
                              label: installLabel,
                              icon: installIcon,
                              onPressed: () => _install(detail),
                            ),
                          const SizedBox(height: AppSpacing.md),
                          SecondaryButton(
                            label: inLibrary
                                ? l10n.inLibrary
                                : l10n.installedAction,
                            icon: inLibrary
                                ? Icons.check_rounded
                                : Icons.download_done_rounded,
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
                                  game.description.isEmpty
                                      ? l10n.notInformed
                                      : game.description,
                                  maxLines: _expandedDescription ? null : 5,
                                  overflow: _expandedDescription
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                  style: context.texts.bodyMedium?.copyWith(
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                                if (longDescription) ...<Widget>[
                                  const SizedBox(height: AppSpacing.sm),
                                  Pressable(
                                    onTap: () => setState(
                                      () => _expandedDescription =
                                          !_expandedDescription,
                                    ),
                                    child: Text(
                                      _expandedDescription
                                          ? l10n.readLess
                                          : l10n.readMore,
                                      style: context.texts.labelMedium
                                          ?.copyWith(
                                            color: context.colors.accent,
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
                            onReport: () => _openFeedbackSheet(detail),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: _BlockTitle(title: l10n.compatCommunity),
                              ),
                              Pressable(
                                onTap: () => context.push<Object?>(
                                  '/game/${game.slug}/reports',
                                ),
                                child: Text(
                                  l10n.seeAllReports,
                                  style: context.texts.labelMedium?.copyWith(
                                    color: context.colors.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: _PortCard(
                                  port: port,
                                  onOpen: () => _openLink(port.url),
                                ),
                              ),
                          ],
                          if (detail.related.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpacing.lg),
                            _BlockTitle(title: l10n.relatedTitle),
                            const SizedBox(height: AppSpacing.md),
                            SizedBox(
                              height: 236,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: detail.related.length,
                                separatorBuilder:
                                    (BuildContext context, int index) =>
                                        const SizedBox(width: AppSpacing.md),
                                itemBuilder: (BuildContext context, int index) {
                                  final Game related = detail.related[index];
                                  return GameCard(
                                    game: related,
                                    width: 142,
                                    heroTag:
                                        'detail-${game.id}-related-${related.id}',
                                  );
                                },
                              ),
                            ),
                          ],
                          SizedBox(
                            height: context.systemBottomInset + AppSpacing.xxxl,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(
              visible: _barTitle,
              title: game.title,
              onBack: _back,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  _TopBar({required this.visible, required this.title, required this.onBack});

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
              decoration: BoxDecoration(
                color: context.colors.glassFloating,
                border: Border(
                  bottom: BorderSide(color: context.colors.glassBorder),
                ),
              ),
              child: Row(
                children: <Widget>[
                  GlassCircleButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: context.l10n.tooltipBack,
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
            boxShadow: context.colors.glassShadow,
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
      if (game.genre != null)
        InfoChip(label: game.genre!, icon: Icons.category_rounded),
      if (game.primaryPlatform.isNotEmpty)
        InfoChip(label: game.primaryPlatform, icon: Icons.layers_rounded),
      if (game.year != null)
        InfoChip(label: game.year.toString(), icon: Icons.event_rounded),
      if (game.hasRating)
        InfoChip(
          label: formatPercent(game.rating / 5),
          icon: Icons.star_rounded,
          color: context.colors.warning,
        ),
      if (game.downloadCount > 0)
        InfoChip(
          label: l10n.downloadsCount(compactNumber(game.downloadCount)),
          icon: Icons.download_rounded,
          color: context.colors.accentAlt,
        ),
      if (game.isFree)
        InfoChip(
          label: l10n.freeBadge,
          icon: Icons.bolt_rounded,
          color: context.colors.success,
        ),
      if (game.needsRom)
        InfoChip(
          label: l10n.needsFiles,
          icon: Icons.folder_rounded,
          color: context.colors.warning,
        ),
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

  late final Animation<double> _scale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1,
            end: 1.35,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 40,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1.35,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 60,
        ),
      ]).animate(_controller);

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
          color: active
              ? context.colors.accent.withValues(alpha: 0.16)
              : context.colors.glass,
          border: Border.all(
            color: active
                ? context.colors.accent.withValues(alpha: 0.5)
                : context.colors.glassBorder,
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
                color: active
                    ? context.colors.favorite
                    : context.colors.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelLarge?.copyWith(
                  color: active
                      ? context.colors.accent
                      : context.colors.textPrimary,
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
            style: context.texts.labelSmall?.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
      ],
    );
  }
}

class CompatReportCard extends StatelessWidget {
  CompatReportCard({super.key, required this.summary, required this.onReport});

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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  color: context.colors.accent.withValues(alpha: 0.14),
                  border: Border.all(
                    color: context.colors.accent.withValues(alpha: 0.32),
                  ),
                ),
                child: Icon(
                  Icons.phone_android_rounded,
                  color: context.colors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.compatTitle,
                      style: context.texts.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.hairline),
                    Text(
                      l10n.compatSubtitle,
                      style: context.texts.labelSmall?.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                l10n.compatReports(summary.total),
                style: context.texts.labelSmall?.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (summary.isEmpty)
            Text(
              l10n.notInformed,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.textTertiary,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _CompatPill(
                  label: l10n.compatPerfect,
                  count: summary.perfect,
                  color: context.colors.success,
                ),
                _CompatPill(
                  label: l10n.compatGood,
                  count: summary.good,
                  color: context.colors.accentAlt,
                ),
                _CompatPill(
                  label: l10n.compatStutter,
                  count: summary.stutter,
                  color: context.colors.warning,
                ),
                _CompatPill(
                  label: l10n.compatUnplayable,
                  count: summary.unplayable,
                  color: context.colors.danger,
                ),
                _CompatPill(
                  label: l10n.compatNotRun,
                  count: summary.notRun,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            label: l10n.compatReport,
            icon: Icons.add_rounded,
            onPressed: onReport,
          ),
        ],
      ),
    );
  }
}

class _CompatPill extends StatelessWidget {
  const _CompatPill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.compact,
        vertical: AppSpacing.compact,
      ),
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
          const SizedBox(height: AppSpacing.hairline),
          Text(
            count.toString(),
            style: context.texts.titleMedium?.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackResult {
  const _FeedbackResult({
    required this.rating,
    required this.verdict,
    required this.body,
    this.fps,
  });

  final int rating;
  final String verdict;
  final String body;
  final int? fps;
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.specs});

  final DeviceSpecs specs;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final TextEditingController _body = TextEditingController();
  int _rating = 0;
  String _verdict = 'good';
  bool _showFps = false;
  double _fps = 60;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    if (_rating == 0) {
      showAppSnackBar(context, message: context.l10n.ratingRequired);
      return;
    }
    Navigator.of(context).pop(
      _FeedbackResult(
        rating: _rating,
        verdict: _verdict,
        body: _body.text.trim(),
        fps: _showFps ? _fps.round() : null,
      ),
    );
  }

  Widget _verdictPill(String value, String label) {
    return AppPill(
      label: label,
      dense: true,
      selected: _verdict == value,
      onTap: () => setState(() => _verdict = value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final String device = <String>[
      ?widget.specs.brand,
      ?widget.specs.model,
    ].join(' ');
    final String details = <String>[
      ?widget.specs.soc,
      ?widget.specs.gpu,
      if (widget.specs.ramGb != null) '${widget.specs.ramGb} GB',
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: context.colors.bgElevated,
        borderRadius: BorderRadius.vertical(top: AppRadii.sheet),
        border: Border(top: BorderSide(color: context.colors.glassBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.colors.textTertiary,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.feedbackTitle,
                  style: context.texts.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  device.isEmpty ? l10n.compatYourDevice : device,
                  style: context.texts.labelMedium?.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: context.texts.labelSmall?.copyWith(
                      color: context.colors.textTertiary,
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.ratingLabel,
                  style: context.texts.labelMedium?.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                StarPicker(
                  value: _rating,
                  onChanged: (int value) => setState(() => _rating = value),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.verdictLabel,
                  style: context.texts.labelMedium?.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    _verdictPill('perfect', l10n.compatPerfect),
                    _verdictPill('good', l10n.compatGood),
                    _verdictPill('stutter', l10n.compatStutter),
                    _verdictPill('unplayable', l10n.compatUnplayable),
                    _verdictPill('not_run', l10n.compatNotRun),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.fpsOptional,
                        style: context.texts.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    AppToggle(
                      value: _showFps,
                      onChanged: (bool value) =>
                          setState(() => _showFps = value),
                    ),
                  ],
                ),
                if (_showFps) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: 120,
                          divisions: 120,
                          value: _fps,
                          activeColor: context.colors.accent,
                          inactiveColor: context.colors.glassStrong,
                          label: l10n.fpsValue(_fps.round()),
                          onChanged: (double value) =>
                              setState(() => _fps = value),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${_fps.round()} FPS',
                        style: context.texts.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _body,
                  maxLines: 3,
                  minLines: 2,
                  maxLength: 1000,
                  style: context.texts.bodyMedium,
                  cursorColor: context.colors.accent,
                  decoration: InputDecoration(
                    hintText: l10n.reviewHint,
                    hintStyle: context.texts.bodySmall?.copyWith(
                      color: context.colors.textTertiary,
                    ),
                    filled: true,
                    fillColor: context.colors.glassStrong,
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
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rótulo e cor de cada veredito de compatibilidade.
class _ApkPickerSheet extends StatelessWidget {
  _ApkPickerSheet({required this.assets});

  final List<ApkAsset> assets;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.bgElevated,
        borderRadius: BorderRadius.vertical(top: AppRadii.sheet),
        border: Border(top: BorderSide(color: context.colors.glassBorder)),
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
                    color: context.colors.textTertiary,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
              SizedBox(height: AppSpacing.lg),
              Text(
                l10n.chooseApk,
                style: context.texts.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: AppSpacing.md),
              for (final ApkAsset asset in assets)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SecondaryButton(
                    label: asset.sizeBytes > 0
                        ? '${asset.name} · ${(asset.sizeBytes / 1048576).toStringAsFixed(1)} MB'
                        : asset.name,
                    icon: Icons.android_rounded,
                    onPressed: () => Navigator.of(context).pop(asset),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityReports extends ConsumerWidget {
  _CommunityReports({required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;
    final AsyncValue<List<CompatReport>> async = ref.watch(
      gameCompatReportsProvider(gameId),
    );
    final List<CompatReport> reports = async.value ?? const <CompatReport>[];

    if (async.isLoading && reports.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.colors.accent,
            ),
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
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.textTertiary,
          ),
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
                child: FeedbackReportRow(
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 6,
      ),
      child: Column(
        children: <Widget>[
          for (int index = 0; index < rows.length; index += 1) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.compact),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 112,
                    child: Text(
                      rows[index][0],
                      style: context.texts.bodySmall?.copyWith(
                        color: context.colors.textSecondary,
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
              Divider(height: 1, color: context.colors.glassBorder),
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
    Color worksColor = context.colors.textSecondary;
    if (works == 'yes') {
      worksLabel = l10n.worksYes;
      worksColor = context.colors.success;
    } else if (works == 'no') {
      worksLabel = l10n.worksNo;
      worksColor = context.colors.danger;
    } else if (works == 'bug') {
      worksLabel = l10n.worksBug;
      worksColor = context.colors.warning;
    } else if (works == 'partial') {
      worksLabel = l10n.worksPartial;
      worksColor = context.colors.accentAlt;
    }

    return GlassContainer(
      radius: AppRadii.md,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              BadgeChip(label: port.platformName, color: context.colors.accent),
              const SizedBox(width: AppSpacing.xxs),
              BadgeChip(label: worksLabel, color: worksColor),
              const Spacer(),
              if (port.url == null)
                BadgeChip(
                  label: l10n.noLink,
                  color: context.colors.textSecondary,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            port.project ?? port.platformName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (port.developer != null || port.version != null) ...<Widget>[
            const SizedBox(height: AppSpacing.hairline),
            Text(
              <String>[
                ?port.developer,
                if (port.version != null) 'v${port.version!}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
          if (port.notes != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              port.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
          if (port.needsGameFiles &&
              port.needsGameFilesNote != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.folder_rounded,
                  size: 13,
                  color: context.colors.warning,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    port.needsGameFilesNote!,
                    style: context.texts.labelSmall?.copyWith(
                      color: context.colors.warning,
                    ),
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
                      color: context.colors.textTertiary,
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
                      const SizedBox(height: AppSpacing.compact),
                      const SkeletonBox(width: 140, height: 14),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.xl),
            SkeletonBox(width: 200, height: 32, radius: AppRadii.pill),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(
              width: double.infinity,
              height: 52,
              radius: AppRadii.pill,
            ),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(
              width: double.infinity,
              height: 48,
              radius: AppRadii.pill,
            ),
            SizedBox(height: AppSpacing.xxl),
            SkeletonBox(width: 140, height: 18),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(
              width: double.infinity,
              height: 110,
              radius: AppRadii.lg,
            ),
          ],
        ),
      ),
    );
  }
}

/// Fundo da tela de detalhes: a própria capa ampliada e desfocada, com camada
/// escura e gradiente para o fundo. Atualiza sozinho quando a capa muda.
class _CoverBackdrop extends StatelessWidget {
  _CoverBackdrop({required this.coverUrl, required this.title});

  final String? coverUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.sizeOf(context).height;
    return Stack(
      children: <Widget>[
        ColoredBox(color: context.colors.bg, child: SizedBox.expand()),
        if (coverUrl != null)
          // A capa ocupa a tela inteira e perde opacidade gradualmente por uma
          // máscara de alfa vertical: nada de corte reto, some no fundo.
          Positioned.fill(
            child: IgnorePointer(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (Rect bounds) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    AppContentColors.onMedia,
                    AppContentColors.onMedia.withValues(alpha: 0.90),
                    AppContentColors.onMedia.withValues(alpha: 0.60),
                    AppContentColors.onMedia.withValues(alpha: 0.25),
                    AppContentColors.transparent,
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
                    context.colors.accent.withValues(alpha: 0.16),
                    context.colors.accent.withValues(alpha: 0),
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
                  AppContentColors.scrim.withValues(alpha: 0.28),
                  AppContentColors.scrim.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
