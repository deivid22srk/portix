import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/formatters.dart';
import '../../models/download_task.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/states.dart';
import 'downloads_controller.dart';

class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    final List<DownloadTask> tasks = ref.watch(downloadsProvider);
    final List<DownloadTask> active = tasks
        .where((DownloadTask task) => !task.isDone)
        .toList(growable: false);
    final List<DownloadTask> done = tasks
        .where((DownloadTask task) => task.isDone)
        .toList(growable: false);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              l10n.downloadsTitle,
                              style: context.texts.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              l10n.downloadsSubtitle,
                              style: context.texts.bodySmall?.copyWith(
                                color: p.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (done.isNotEmpty)
                        IconGlassButton(
                          icon: Icons.cleaning_services_rounded,
                          tooltip: l10n.clearCompleted,
                          onTap: () =>
                              ref.read(downloadsProvider.notifier).clearCompleted(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      _CountChip(
                        label: l10n.activeDownloads,
                        value: active.length.toString(),
                        color: p.primary,
                      ),
                      const SizedBox(width: 8),
                      _CountChip(
                        label: l10n.completedDownloads,
                        value: done.length.toString(),
                        color: p.success,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (tasks.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 380,
                child: EmptyState(
                  icon: Icons.download_rounded,
                  title: l10n.downloadEmpty,
                  body: l10n.downloadEmptyBody,
                  actionLabel: l10n.explore,
                  onAction: () => context.go('/search'),
                ),
              ),
            ),
          if (active.isNotEmpty) ...<Widget>[
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            SliverToBoxAdapter(
              child: SectionHeader(title: l10n.activeDownloads),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DownloadCard(task: active[index]),
                  ),
                  childCount: active.length,
                ),
              ),
            ),
          ],
          if (done.isNotEmpty) ...<Widget>[
            const SliverToBoxAdapter(child: SizedBox(height: 26)),
            SliverToBoxAdapter(
              child: SectionHeader(
                title: l10n.completedDownloads,
                actionLabel: l10n.clearCompleted,
                onAction: () =>
                    ref.read(downloadsProvider.notifier).clearCompleted(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DownloadCard(task: done[index]),
                  ),
                  childCount: done.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 130)),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: p.surface.withValues(alpha: p.dark ? 0.6 : 0.9),
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(color: p.muted),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: context.texts.labelSmall?.copyWith(
              color: p.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends ConsumerWidget {
  const _DownloadCard({required this.task});

  final DownloadTask task;

  String _statusLabel(L10n l10n) {
    switch (task.status) {
      case DownloadStatus.queued:
        return l10n.statusQueued;
      case DownloadStatus.downloading:
        return l10n.progressPercent((task.progress * 100).round());
      case DownloadStatus.paused:
        return l10n.statusPaused;
      case DownloadStatus.done:
        return l10n.statusDone;
      case DownloadStatus.failed:
        return l10n.statusFailed;
    }
  }

  Color _statusColor(AppPalette p) {
    switch (task.status) {
      case DownloadStatus.queued:
        return p.warning;
      case DownloadStatus.downloading:
        return p.secondary;
      case DownloadStatus.paused:
        return p.muted;
      case DownloadStatus.done:
        return p.success;
      case DownloadStatus.failed:
        return p.danger;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette p = context.palette;
    final L10n l10n = context.l10n;
    final DownloadsController controller =
        ref.read(downloadsProvider.notifier);
    final List<String> metaParts = <String>[
      if (task.platformName != null) task.platformName!,
      if (task.portKey != null) task.portKey!,
    ];
    final String meta =
        metaParts.isEmpty ? l10n.notInformed : metaParts.join(' · ');

    return Pressable(
      onTap: task.slug.isEmpty
          ? null
          : () => context.push<Object?>('/game/${task.slug}'),
      child: GlassPanel(
        radius: 18,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 56,
              height: 74,
              child: GameCover(
                imageUrl: task.coverUrl,
                title: task.title,
                memWidth: 180,
                borderRadius: 12,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      BadgeChip(
                        label: _statusLabel(l10n),
                        color: _statusColor(p),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall?.copyWith(color: p.muted),
                  ),
                  if (!task.isDone) ...<Widget>[
                    const SizedBox(height: 9),
                    GradientProgress(value: task.progress, height: 6),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        if (task.status == DownloadStatus.downloading)
                          IconGlassButton(
                            icon: Icons.pause_rounded,
                            size: 32,
                            tooltip: l10n.pause,
                            onTap: () => controller.pause(task.gameId),
                          )
                        else
                          IconGlassButton(
                            icon: Icons.play_arrow_rounded,
                            size: 32,
                            tooltip: l10n.resume,
                            onTap: () => controller.resume(task.gameId),
                          ),
                        const SizedBox(width: 8),
                        IconGlassButton(
                          icon: Icons.close_rounded,
                          size: 32,
                          tooltip: l10n.cancel,
                          onTap: () => controller.cancel(task.gameId),
                        ),
                        const Spacer(),
                        if (task.startedAt != null)
                          Text(
                            relativeDay(task.startedAt, en: l10n.isEn),
                            style: context.texts.labelSmall?.copyWith(
                              color: p.muted,
                            ),
                          ),
                      ],
                    ),
                  ] else ...<Widget>[
                    const SizedBox(height: 9),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: p.success,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            l10n.downloadDone,
                            style: context.texts.labelSmall?.copyWith(
                              color: p.success,
                            ),
                          ),
                        ),
                        IconGlassButton(
                          icon: Icons.delete_outline_rounded,
                          size: 32,
                          tooltip: l10n.remove,
                          onTap: () => controller.remove(task.gameId),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
