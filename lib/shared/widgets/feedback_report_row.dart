import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/theme/tokens.dart';
import '../../models/compat_report.dart';
import 'admin_crown.dart';
import 'compat_report_sheet.dart';
import 'primitives.dart';
import 'profile_avatar.dart';

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
    final String author = report.author.isEmpty ? l10n.player : report.author;
    final String device = report.deviceLabelOr(l10n.reportDevice);
    final String authorMeta =
        '${report.authorHandle != null ? '@${report.authorHandle} · ' : ''}$author';

    return Pressable(
      onTap: () => showCompatReportSheet(context, report),
      child: GlassContainer(
        radius: AppRadii.md,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Pressable(
              onTap: report.authorId == null
                  ? null
                  : () => context.push<Object?>('/u/${report.authorId}'),
              child: ProfileAvatar(
                name: author,
                imageUrl: report.authorCover,
                size: 34,
                level: report.authorRole,
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
                          device,
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
                  const SizedBox(height: AppSpacing.xs),
                  // Estrelas, FPS e cargo num Wrap: em telas estreitas ou com
                  // fonte ampliada (200%) o grupo quebra em duas linhas em
                  // vez de estourar a Row (overflow de 93px no pior caso).
                  if (report.rating > 0 ||
                      report.fps != null ||
                      report.authorRole != null) ...<Widget>[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        if (report.rating > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
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
                            ],
                          ),
                        if (report.fps != null)
                          BadgeChip(
                            label: '${report.fps} FPS',
                            color: AppColors.accent,
                            icon: Icons.speed_rounded,
                          ),
                        if (report.authorRole != null)
                          AdminBadge(level: report.authorRole!),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  // Autor em linha própria: antes dividia espaço com as specs
                  // e truncava junto (@handle · nome · soc · gpu · ram).
                  Text(
                    authorMeta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  ..._deviceSpecsLine(context),
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
      ),
    );
  }

  /// Linha dedicada ao APARELHO DO RELATOR: processador (SoC) em destaque,
  /// seguido de GPU e RAM. Antes essas infos dividiam a linha do autor
  /// (@handle · nome) e eram quase sempre cortadas pelo ellipsis — o usuário
  /// não conseguia ver qual processador gerou o relato.
  List<Widget> _deviceSpecsLine(BuildContext context) {
    final TextStyle? base = context.texts.labelSmall?.copyWith(
      color: AppColors.textTertiary,
    );
    final TextStyle? strong = base?.copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
    );
    final List<InlineSpan> spans = <InlineSpan>[];
    void add(String text, {required bool highlight}) {
      if (spans.isNotEmpty) {
        spans.add(TextSpan(text: ' · ', style: base));
      }
      spans.add(TextSpan(text: text, style: highlight ? strong : base));
    }

    final String? soc = report.soc;
    if (soc != null && soc.isNotEmpty) {
      add(soc, highlight: true);
    }
    final String? gpu = report.gpu;
    if (gpu != null && gpu.isNotEmpty) {
      add(gpu, highlight: false);
    }
    final int? ram = report.ramGb;
    if (ram != null) {
      add('$ram GB', highlight: false);
    }
    if (spans.isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[
      const SizedBox(height: 6),
      Row(
        children: <Widget>[
          const Icon(
            Icons.memory_rounded,
            size: 12,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text.rich(
              TextSpan(children: spans),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ];
  }
}
