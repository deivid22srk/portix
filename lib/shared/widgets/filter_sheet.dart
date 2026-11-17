import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/theme/tokens.dart';
import '../../models/home_feed.dart';
import '../../models/search.dart';
import 'primitives.dart';

/// Rótulo do critério de ordenação.
String filterSortLabel(L10n l10n, String sort) {
  switch (sort) {
    case 'recent':
      return l10n.sortRecent;
    case 'az':
      return l10n.sortAz;
    case 'year':
      return l10n.sortYear;
    case 'trending':
    default:
      return l10n.sortTrending;
  }
}

/// Abre o bottom sheet de filtros (vidro) e devolve o resultado aplicado.
Future<SearchFilters?> showFilterSheet(
  BuildContext context, {
  required SearchFilters initial,
  required CatalogFacets facets,
}) {
  return showModalBottomSheet<SearchFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppContentColors.transparent,
    barrierColor: AppContentColors.scrim.withValues(alpha: 0.6),
    builder: (BuildContext context) =>
        _FilterSheet(initial: initial, facets: facets),
  );
}

class _FilterSheet extends StatefulWidget {
  _FilterSheet({required this.initial, required this.facets});

  final SearchFilters initial;
  final CatalogFacets facets;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late SearchFilters _filters = widget.initial;

  void _apply() => Navigator.of(context).pop(_filters);

  void _reset() => setState(() => _filters = const SearchFilters());

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final double maxHeight = MediaQuery.of(context).size.height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.bgElevated,
          borderRadius: BorderRadius.vertical(top: AppRadii.sheet),
          border: Border(top: BorderSide(color: context.colors.glassBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              10,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
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
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.filters,
                        style: context.texts.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SecondaryButton(
                      label: l10n.reset,
                      expand: false,
                      onPressed: _reset,
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _SheetLabel(l10n.filterPlatform),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: <Widget>[
                            AppPill(
                              label: l10n.all,
                              dense: true,
                              selected: _filters.platform == null,
                              onTap: () => setState(
                                () => _filters = _filters.copyWith(
                                  clearPlatform: true,
                                ),
                              ),
                            ),
                            for (final PlatformInfo platform
                                in widget.facets.platforms)
                              AppPill(
                                label: platform.name,
                                dense: true,
                                selected: _filters.platform == platform.slug,
                                onTap: () => setState(() {
                                  _filters = _filters.platform == platform.slug
                                      ? _filters.copyWith(clearPlatform: true)
                                      : _filters.copyWith(
                                          platform: platform.slug,
                                        );
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        _SheetLabel(l10n.filterGenre),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: <Widget>[
                            AppPill(
                              label: l10n.all,
                              dense: true,
                              selected: _filters.genre == null,
                              onTap: () => setState(
                                () => _filters = _filters.copyWith(
                                  clearGenre: true,
                                ),
                              ),
                            ),
                            for (final GenreInfo genre in widget.facets.genres)
                              AppPill(
                                label: genre.name,
                                dense: true,
                                selected: _filters.genre == genre.name,
                                onTap: () => setState(() {
                                  _filters = _filters.genre == genre.name
                                      ? _filters.copyWith(clearGenre: true)
                                      : _filters.copyWith(genre: genre.name);
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        _SheetLabel(l10n.sortLabel),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: <Widget>[
                            for (final String sort in <String>[
                              'trending',
                              'recent',
                              'az',
                              'year',
                            ])
                              AppPill(
                                label: filterSortLabel(l10n, sort),
                                dense: true,
                                selected: _filters.sort == sort,
                                onTap: () => setState(
                                  () =>
                                      _filters = _filters.copyWith(sort: sort),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _ToggleRow(
                          title: l10n.filterFree,
                          value: _filters.freeOnly,
                          onChanged: (bool value) => setState(
                            () => _filters = _filters.copyWith(freeOnly: value),
                          ),
                        ),
                        _ToggleRow(
                          title: l10n.filterRom,
                          value: _filters.needsRom,
                          onChanged: (bool value) => setState(
                            () => _filters = _filters.copyWith(needsRom: value),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: l10n.apply,
                  icon: Icons.check_rounded,
                  onPressed: _apply,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: context.texts.labelSmall?.copyWith(
          color: context.colors.textTertiary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: context.texts.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          AppToggle(value: value, semanticLabel: title, onChanged: onChanged),
        ],
      ),
    );
  }
}
