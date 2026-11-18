import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/catalog_repository.dart';
import '../data/supabase_catalog_repository.dart';
import 'cache_store.dart';
import 'env.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider precisa ser sobrescrito no bootstrap do app.',
  );
});

final cacheStoreProvider = Provider<CacheStore>(
  (ref) => CacheStore(ref.watch(sharedPreferencesProvider)),
);

// `Supabase.initialize` só pode rodar uma vez por processo. O retry do
// bootstrap reutiliza a instância já criada.
bool _supabaseInitialized = false;

final supabaseBootstrapProvider = FutureProvider<void>((ref) async {
  if (!Env.isConfigured) {
    throw const AppFailure(FailureKind.config);
  }
  if (!_supabaseInitialized) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    _supabaseInitialized = true;
  }
});

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => SupabaseCatalogRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(cacheStoreProvider),
  ),
);
