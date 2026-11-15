import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../models/download_task.dart';
import '../../shared/widgets/game_media.dart';
import '../../shared/widgets/primitives.dart';
import 'downloads_controller.dart';

/// Linha de download com progresso e controles (usada no Meu Hub).
class DownloadTile extends ConsumerWidget {
  const DownloadTile({super.key, required this.task});

  final DownloadTask task;

  String _statusLabel(L10n l10n) {
    switch (task.status) {
      case DownloadStatus.queued:
        return l10n.statusQueued;
      case DownloadStatus.connecting:
        return l10n.statusConnecting;
      case DownloadStatus.downloading:
        return l10n.progressPercent((task.progress * 100).round());
      case DownloadStatus.verifying:
        return l10n.statusVerifying;
      case DownloadStatus.paused:
        return l10n.statusPaused;
      case DownloadStatus.done:
        return l10n.statusDone;
      case DownloadStatus.failed:
        return l10n.statusFailed;
    }
  }

  Color _statusColor() {
    switch (task.status) {
      case DownloadStatus.queued:
        return AppColors.warning;
      case DownloadStatus.connecting:
        return AppColors.textSecondary;
      case DownloadStatus.downloading:
        return AppColors.accent;
      case DownloadStatus.verifying:
        return AppColors.accentAlt;
      case DownloadStatus.paused:
        return AppColors.textSecondary;
      case DownloadStatus.done:
        return AppColors.success;
      case DownloadStatus.failed:
        return AppColors.danger;
    }
  }

  /// Linha de estatísticas: bytes baixados + velocidade (quando o motor
  /// informa) — nunca “solta” números sem contexto.
  String _statsLine(L10n l10n) {
    final List<String> parts = <String>[
      if (task.totalBytes > 0)
        '${formatBytes(task.doneBytes)} / ${formatBytes(task.totalBytes)}',
      if (task.speedBps > 0) formatSpeed(task.speedBps),
    ];
    if (parts.isEmpty) {
      return task.status == DownloadStatus.connecting
          ? l10n.statusConnecting
          : '';
    }
    return parts.join(' · ');
  }

  String _etaOrEmpty() => formatEta(task.etaSecs) ?? '';

  Future<void> _openSource(String? url) async {
    if (url == null) {
      return;
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // Sem app que trate o link, nada a fazer aqui.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;
    final DownloadsController controller = ref.read(downloadsProvider.notifier);
    final List<String> metaParts = <String>[?task.platformName, ?task.portKey];
    final String meta = metaParts.isEmpty
        ? l10n.notInformed
        : metaParts.join(' · ');

    return GlassContainer(
      radius: AppRadii.md,
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: task.slug.isEmpty
          ? null
          : () => context.push<Object?>('/game/${task.slug}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 58,
            height: 78,
            child: GameCover(
              imageUrl: task.coverUrl,
              title: task.title,
              memWidth: 180,
              borderRadius: AppRadii.sm,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
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
                    const SizedBox(width: AppSpacing.sm),
                    BadgeChip(label: _statusLabel(l10n), color: _statusColor()),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (task.status == DownloadStatus.failed) ...<Widget>[
                  const SizedBox(height: 9),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          l10n.downloadErrorLabel(task.error),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelSmall?.copyWith(
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Wrap (não Row): em fonte 2,0 os botões quebram de linha em
                  // vez de estourar a largura (varredura de overflow do helper).
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      if (task.portUrl != null)
                        SecondaryButton(
                          label: l10n.openSource,
                          icon: Icons.open_in_new_rounded,
                          height: AppSpacing.secondaryButtonHeight,
                          expand: false,
                          onPressed: () => _openSource(task.portUrl),
                        ),
                      GlassCircleButton(
                        icon: Icons.refresh_rounded,
                        size: 48,
                        tooltip: l10n.tryAgain,
                        onTap: () => controller.resume(task.gameId),
                      ),
                      GlassCircleButton(
                        icon: Icons.close_rounded,
                        size: 48,
                        tooltip: l10n.cancel,
                        onTap: () => controller.cancel(task.gameId),
                      ),
                    ],
                  ),
                ] else if (!task.isDone) ...<Widget>[
                  const SizedBox(height: 9),
                  GradientProgress(value: task.progress, height: 6),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _statsLine(l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (task.isTransferring && task.etaSecs >= 0)
                        Text(
                          l10n.timeLeft(_etaOrEmpty()),
                          style: context.texts.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      if (task.isTransferring)
                        GlassCircleButton(
                          icon: Icons.pause_rounded,
                          size: 48,
                          tooltip: l10n.pause,
                          onTap: () => controller.pause(task.gameId),
                        )
                      else
                        GlassCircleButton(
                          icon: Icons.play_arrow_rounded,
                          size: 48,
                          tooltip: l10n.resume,
                          onTap: () => controller.resume(task.gameId),
                        ),
                      const SizedBox(width: AppSpacing.sm),
                      GlassCircleButton(
                        icon: Icons.close_rounded,
                        size: 48,
                        tooltip: l10n.cancel,
                        onTap: () => controller.cancel(task.gameId),
                      ),
                      const Spacer(),
                      if (task.startedAt != null)
                        Text(
                          relativeDay(task.startedAt, en: l10n.isEn),
                          style: context.texts.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 9),
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          l10n.downloadDone,
                          style: context.texts.labelSmall?.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ),
                      GlassCircleButton(
                        icon: Icons.delete_outline_rounded,
                        size: 48,
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
    );
  }
}
