import 'package:flutter/widgets.dart';

import '../app/app_strings.dart';

/// Versão exibida/comparada com os avisos de atualização.
const String kAppVersion = '1.0.2';

/// Landing page pública do PORTIX (GitHub Pages), com os APKs nas releases.
const String kLandingUrl = 'https://deivid22srk.github.io/portix-landing/';
const String kReleasesUrl = 'https://github.com/deivid22srk/portix-landing/releases/latest';

/// Documentos legais publicados na landing page.
const String kTermsUrl = '${kLandingUrl}termos.html';
const String kPrivacyUrl = '${kLandingUrl}privacidade.html';

class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;
}

enum FailureKind { config, network, server, auth, notFound, unknown }

class AppFailure implements Exception {
  const AppFailure(this.kind, {this.detail});

  final FailureKind kind;
  final String? detail;

  @override
  String toString() => 'AppFailure(${kind.name}${detail == null ? '' : ': $detail'})';
}

String describeFailure(Object? error, L10n l10n) {
  if (error is AppFailure) {
    switch (error.kind) {
      case FailureKind.config:
        return l10n.configBody;
      case FailureKind.network:
        return l10n.errorNetwork;
      case FailureKind.server:
        return l10n.errorServer;
      case FailureKind.auth:
        return l10n.errorAuth;
      case FailureKind.notFound:
        return l10n.errorNotFound;
      case FailureKind.unknown:
        return l10n.errorGeneric;
    }
  }
  return l10n.errorGeneric;
}
extension FailureContext on BuildContext {
  String failureText(Object? error) => describeFailure(error, l10n);
}
