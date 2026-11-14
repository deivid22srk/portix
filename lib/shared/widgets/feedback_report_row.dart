import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../models/compat_report.dart';
import 'primitives.dart';

/// Rótulo de cada veredito de compatibilidade.
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

/// Linha de um relato: autor, aparelho, nota, veredito, FPS e texto.
class FeedbackReportRow extends StatelessWidget {
  const FeedbackReportRow({
    super.key,
    required this.report,
    this.sameSoc = false,
  });

  final CompatReport report;
  final bool sameSoc;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final String specs = <String>[
      ?report.soc,
      ?report.gpu,
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
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    if (report.rating > 0) ...<Widget>[
                      for (int i = 1; i <= 5; i += 1)
                        Icon(
                          i <= report.rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 12,
                          color: i <= report.rating
                              ? AppColors.warning
                              : AppColors.textTertiary,
                        ),
                      const SizedBox(width: 6),
                    ],
                    if (report.fps != null) ...<Widget>[
                      BadgeChip(
                        label: '${report.fps} FPS',
                        color: AppColors.accent,
                        icon: Icons.speed_rounded,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (report.authorRole != null) ...<Widget>[
                      BadgeChip(
                        label: l10n.adminBadge,
                        color: AppColors.accent,
                        icon: Icons.verified_rounded,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        '${report.author}${specs.isEmpty ? '' : ' · $specs'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (report.body.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    report.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
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
