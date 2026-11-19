import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ============================================================================
// PORTIX — leitura de APKs (pacote/versão) e verificação de integridade do
// download (digest + pacote + downgrade). Pura, coberta por testes.
// ============================================================================

/// Veredito da checagem de integridade do APK baixado.
enum IntegrityVerdict {
  /// Tudo certo (ou sem dados para checar — asset sem digest no GitHub).
  pass,

  /// Digest divergente ou digest esperado sem hash calculado — descarta
  /// (fail-closed).
  digestMismatch,

  /// O pacote do APK não é o esperado — descarta.
  packageMismatch,

  /// Versão mais antiga que a instalada sem direito a downgrade
  /// (instalador Android; via Shizuku é permitido).
  downgradeBlocked,
}

/// Regras de integridade (pura):
/// - digest esperado presente e hash calculado ausente/divergente →
///   [IntegrityVerdict.digestMismatch] (fail-closed, lição 10);
/// - asset SEM digest do GitHub → valida só pacote + versão;
/// - pacote esperado conhecido e diferente do lido do APK → pacote errado;
/// - versão do APK menor que a instalada sem [allowDowngrade] → bloqueia.
IntegrityVerdict verifyDownloadedApk({
  required String? expectedDigest,
  required String? actualDigest,
  required String? expectedPackage,
  required String? actualPackage,
  required bool allowDowngrade,
  required int? installedVersionCode,
  required int? apkVersionCode,
}) {
  final String? expected = _normalizeDigest(expectedDigest);
  if (expected != null) {
    final String? actual = _normalizeDigest(actualDigest);
    if (actual == null || actual != expected) {
      return IntegrityVerdict.digestMismatch;
    }
  }
  if (expectedPackage != null && expectedPackage.isNotEmpty) {
    if (actualPackage == null ||
        actualPackage.isEmpty ||
        actualPackage != expectedPackage) {
      return IntegrityVerdict.packageMismatch;
    }
  }
  if (!allowDowngrade &&
      installedVersionCode != null &&
      apkVersionCode != null &&
      apkVersionCode < installedVersionCode) {
    return IntegrityVerdict.downgradeBlocked;
  }
  return IntegrityVerdict.pass;
}

/// Normaliza `sha256:<hex>` / `<hex>` / maiúsculas-espaços para comparação.
String? _normalizeDigest(String? raw) {
  if (raw == null) {
    return null;
  }
  var text = raw.trim().toLowerCase();
  if (text.isEmpty) {
    return null;
  }
  const String prefix = 'sha256:';
  if (text.startsWith(prefix)) {
    text = text.substring(prefix.length);
  }
  return text.isEmpty ? null : text;
}

/// Dados de um APK (arquivo baixado) ou de um app instalado no aparelho.
class ApkSummary {
  const ApkSummary({
    required this.packageName,
    this.versionName,
    this.versionCode,
  });

  /// Nome do pacote (ex.: `com.exemplo.jogo`).
  final String packageName;

  /// Versão declarada (`versionName`), quando disponível.
  final String? versionName;

  /// Código de versão (`versionCode`), quando disponível.
  final int? versionCode;

  factory ApkSummary.fromMap(Map<Object?, Object?> map) {
    String? text(Object? value) {
      final String raw = value?.toString().trim() ?? '';
      return raw.isEmpty ? null : raw;
    }

    final Object? code = map['versionCode'];
    return ApkSummary(
      packageName: text(map['packageName']) ?? '',
      versionName: text(map['versionName']),
      versionCode: code is num ? code.toInt() : null,
    );
  }
}

/// Ponte para o Android: lê o nome do pacote/versão de um APK baixado, verifica
/// se um app está instalado e abre o app (canal `portix/apk`).
class ApkTools {
  const ApkTools._();

  static const MethodChannel _channel = MethodChannel('portix/apk');

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Lê o pacote e a versão de um APK já salvo no aparelho.
  static Future<ApkSummary?> inspect(String path) async {
    if (!_supported || path.isEmpty) {
      return null;
    }
    try {
      final Map<Object?, Object?>? map = await _channel
          .invokeMethod<Map<Object?, Object?>>('inspect', <String, Object?>{
            'path': path,
          });
      if (map == null) {
        return null;
      }
      final ApkSummary summary = ApkSummary.fromMap(map);
      return summary.packageName.isEmpty ? null : summary;
    } on Object {
      return null;
    }
  }

  /// Dados do app instalado (ou `null` quando o pacote não está instalado).
  static Future<ApkSummary?> installed(String packageName) async {
    if (!_supported || packageName.isEmpty) {
      return null;
    }
    try {
      final Map<Object?, Object?>? map = await _channel
          .invokeMethod<Map<Object?, Object?>>('installed', <String, Object?>{
            'packageName': packageName,
          });
      if (map == null) {
        return null;
      }
      final ApkSummary summary = ApkSummary.fromMap(map);
      return summary.packageName.isEmpty ? null : summary;
    } on Object {
      return null;
    }
  }

  /// Abre o app instalado. Retorna `false` quando não há como lançá-lo.
  static Future<bool> launch(String packageName) async {
    if (!_supported || packageName.isEmpty) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('launch', <String, Object?>{
            'packageName': packageName,
          }) ??
          false;
    } on Object {
      return false;
    }
  }
}
