import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth.dart';
import '../../core/providers.dart';
import '../../models/profile.dart';
import '../../models/public_profile.dart';
import '../../models/user_result.dart';

/// Perfil do usuário. Para convidados (sessão anônima), devolve um perfil
/// derivado da sessão; para contas reais, busca em `profiles`.
final profileProvider = FutureProvider<UserProfile>((ref) async {
  final AccountState account = ref.watch(accountProvider);
  if (!account.isSignedIn) {
    return UserProfile(id: account.id ?? '', displayName: account.displayName);
  }
  return ref.watch(catalogRepositoryProvider).fetchProfile();
});

/// Nível de ADM do usuário logado ('root' | 'admin' | 'moderator') ou null.
final adminLevelProvider = FutureProvider<String?>((ref) async {
  final AccountState account = ref.watch(accountProvider);
  if (!account.hasSession) {
    return null;
  }
  try {
    final Object? result = await ref.watch(supabaseClientProvider).rpc('admin_me');
    if (result is Map) {
      final Object? level = result['level'];
      return level?.toString();
    }
  } on Object {
    return null;
  }
  return null;
});

/// Busca de usuários (por @handle ou nome).
final userSearchProvider = FutureProvider.family<List<UserResult>, String>(
  (ref, String query) => ref.watch(catalogRepositoryProvider).searchUsers(query),
);

/// Perfil público de um usuário (com a biblioteca).
final publicProfileProvider = FutureProvider.family<PublicProfile, String>(
  (ref, String id) => ref.watch(catalogRepositoryProvider).fetchPublicProfile(id),
);
