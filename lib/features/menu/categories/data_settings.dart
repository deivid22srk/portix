import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/primitives.dart';
import '../../collections/collections_controller.dart';
import '../../home/home_controller.dart';
import '../../profile/profile_controller.dart';

/// Categoria "Dados e Armazenamento": recarregar catálogo e limpar cache.
/// Limpar cache apaga dados locais → confirmação antes.
class DataSettingsBody extends ConsumerWidget {
  const DataSettingsBody({super.key, required this.l10n});

  final L10n l10n;

  Future<void> _reload(BuildContext context, WidgetRef ref) async {
    final L10n l10n = context.l10n;
    ref.invalidate(homeFeedProvider);
    ref.invalidate(catalogFacetsProvider);
    ref.invalidate(collectionsProvider);
    await ref.read(homeFeedProvider.notifier).refresh();
    if (!context.mounted) {
      return;
    }
    // Sucesso honesto: o refresh com AsyncValue.guard não lança — o estado
    // pós-refresh é quem diz se a revalidação funcionou.
    final bool ok = ref.read(homeFeedProvider).hasValue;
    showAppSnackBar(
      context,
      message: ok ? l10n.catalogReloaded : l10n.catalogReloadFailed,
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final L10n l10n = context.l10n;
    // Destrutivo: confirmação antes de apagar o cache local.
    final bool ok = await showAppConfirm(
      context,
      title: l10n.clearCache,
      message: l10n.settingsClearCacheConfirm,
    );
    if (!ok || !context.mounted) {
      return;
    }
    // O aviso promete catálogo E imagens: limpa os dois caches de verdade.
    await ref.read(cacheStoreProvider).clearAll();
    await DefaultCacheManager().emptyCache();
    ref.invalidate(homeFeedProvider);
    ref.invalidate(catalogFacetsProvider);
    ref.invalidate(collectionsProvider);
    ref.invalidate(profileProvider);
    if (!context.mounted) {
      return;
    }
    showAppSnackBar(context, message: l10n.cacheCleared);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L10n l10n = context.l10n;
    return Column(
      children: <Widget>[
        SectionTile(
          icon: Icons.sync_rounded,
          label: l10n.reloadCatalog,
          onTap: () => _reload(context, ref),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionTile(
          icon: Icons.cleaning_services_rounded,
          label: l10n.clearCache,
          onTap: () => _clearCache(context, ref),
        ),
      ],
    );
  }
}
