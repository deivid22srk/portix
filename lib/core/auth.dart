import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers.dart';

/// Estado de conta do usuário. Sessão anônima é "convidado"; conta real é
/// quem fez login/cadastro (e-mail ou Google).
class AccountState {
  const AccountState({this.user});

  final User? user;

  bool get hasSession => user != null;
  bool get isAnonymous => user?.isAnonymous ?? false;
  bool get isSignedIn => user != null && !(user!.isAnonymous);
  String? get id => user?.id;

  /// E-mail da conta (null para convidado/sem e-mail).
  String? get email => user?.email;

  /// Nome bruto da sessão (pode ser vazio) — a UI resolve o fallback com
  /// l10n (`player`) para não fixar pt-BR em telas em inglês.
  String get displayName {
    final Object? name = user?.userMetadata?['display_name'];
    final String text = name?.toString().trim() ?? '';
    return text;
  }
}

final accountProvider = NotifierProvider<AccountController, AccountState>(
  AccountController.new,
);

class AccountController extends Notifier<AccountState> {
  StreamSubscription<AuthState>? _subscription;

  @override
  AccountState build() {
    final SupabaseClient client = ref.watch(supabaseClientProvider);
    _subscription = client.auth.onAuthStateChange.listen((AuthState data) {
      state = AccountState(user: data.session?.user);
    });
    ref.onDispose(() => _subscription?.cancel());
    return AccountState(user: client.auth.currentUser);
  }

  Future<void> signIn({required String email, required String password}) async {
    await ref
        .read(supabaseClientProvider)
        .auth
        .signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await ref
        .read(supabaseClientProvider)
        .auth
        .signUp(
          email: email,
          password: password,
          data: <String, dynamic>{
            if (displayName != null && displayName.trim().isNotEmpty)
              'display_name': displayName.trim(),
          },
        );
  }

  Future<bool> signInWithGoogle() {
    return ref
        .read(supabaseClientProvider)
        .auth
        .signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'portix://login-callback',
          authScreenLaunchMode: LaunchMode.externalApplication,
        );
  }

  Future<void> signOut() async {
    await ref.read(supabaseClientProvider).auth.signOut();
  }
}
