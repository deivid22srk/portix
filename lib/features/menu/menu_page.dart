import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/primitives.dart';
import 'settings_hub.dart';

/// Aba Menu — hub de configurações. Cada categoria abre sua própria rota
/// (`/menu/<id>`), ver settings_category_page.dart.
class MenuPage extends ConsumerWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(bottom: false, child: AppContentMax(child: SettingsHub()));
  }
}
