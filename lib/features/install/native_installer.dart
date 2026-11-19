import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ============================================================================
// PORTIX — ponte do instalador nativo (PackageInstaller do Android, canal
// `portix/install` + eventos em `portix/install/events`).
//
// Contrato com o Kotlin (InstallBridge.kt):
// - prepare      → cria a sessão, define tamanho, pede pré-aprovação
//                  (Android 14+). O resultado chega por eventos:
//                  'prepared' (sessionId) / 'preapprovalApproved' /
//                  'preapprovalDeclined' / 'preapprovalFailed'.
// - commitPrepared → grava o APK na sessão pré-aprovada e faz commit.
// - commitFresh  → fluxo clássico: sessão PackageInstaller MODE_FULL_INSTALL
//                  SEM pré-aprovação (1 diálogo no commit). Escolha
//                  documentada (decisão D3 do diário): o intent
//                  ACTION_VIEW via FileProvider continua disponível no
//                  Kotlin, mas o Dart usa a sessão para receber
//                  STATUS_PENDING_USER_ACTION/instalado/erro padronizados.
// - abandon / cancelPrepare / cleanupOrphanSessions → limpeza.
// Em não-Android (desktop/web/testes) tudo é no-op simulado: o fluxo
// considera "instalado" sem tocar em canal nenhum.
// ============================================================================

/// Evento emitido pelo instalador nativo (o mesmo mapa vindo do Kotlin).
class NativeInstallEvent {
  const NativeInstallEvent({
    required this.type,
    this.key = '',
    this.sessionId,
    this.error,
  });

  /// prepared | preapprovalPending | preapprovalApproved |
  /// preapprovalDeclined | preapprovalFailed | writing | committing |
  /// userActionPending | installDone | installFailed | failed
  final String type;

  /// Chave do fluxo (`gameId`) associado ao evento.
  final String key;

  /// Id da sessão PackageInstaller, quando aplicável.
  final int? sessionId;

  /// Mensagem de erro bruta (debug); a UI localiza por código.
  final String? error;

  factory NativeInstallEvent.fromMap(Map<Object?, Object?> map) {
    String? text(Object? value) {
      final String raw = value?.toString() ?? '';
      return raw.isEmpty ? null : raw;
    }

    return NativeInstallEvent(
      type: text(map['type']) ?? 'unknown',
      key: map['key']?.toString() ?? '',
      sessionId: map['sessionId'] is num
          ? (map['sessionId']! as num).toInt()
          : null,
      error: text(map['error']),
    );
  }
}

/// Executa uma chamada de canal engolindo qualquer falha (retorna `null`).
/// Usado onde o resultado é opcional e o fluxo segue por eventos.
Future<T?> safeInvoke<T>(Future<T?> Function() action) async {
  try {
    return await action();
  } on Object {
    return null;
  }
}

/// Ponte do instalador nativo. Estático como [NativeDownloader] — o resto do
/// app usa o mesmo estilo de canal.
class NativeInstaller {
  const NativeInstaller._();

  static const MethodChannel _channel = MethodChannel('portix/install');
  static const EventChannel _events = EventChannel('portix/install/events');

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Stream de eventos do instalador. Erros de canal são convertidos em
  /// stream fechado (o consumidor lida com eventos ausentes como no-op).
  static Stream<NativeInstallEvent> events() {
    return _events
        .receiveBroadcastStream()
        .map<NativeInstallEvent>(
          (Object? event) => NativeInstallEvent.fromMap(
            Map<Object?, Object?>.from(
              event as Map? ?? const <Object?, Object?>{},
            ),
          ),
        )
        .handleError((Object _) {});
  }

  /// Espaço livre no armazenamento privado do app (-1 = desconhecido).
  static Future<int> freeBytes() async {
    if (!isAndroid) {
      return -1;
    }
    try {
      return await _channel.invokeMethod<int>('freeBytes') ?? -1;
    } on Object {
      return -1;
    }
  }

  /// SHA-256 do arquivo (hex minúsculo, sem prefixo). Timeout interno de
  /// 10 min: digest não calculado = indefinido = descarta (fail-closed).
  static Future<String?> sha256(String path) async {
    if (!isAndroid || path.isEmpty) {
      return null;
    }
    try {
      return await _channel
          .invokeMethod<String>('sha256', <String, Object?>{'path': path})
          .timeout(const Duration(minutes: 10));
    } on Object {
      return null;
    }
  }

  /// Cria a sessão + pede a pré-aprovação ANTES do download (Android 14+).
  /// `key` identifica o fluxo (gameId); `attemptId` monotônico invalida
  /// callbacks velhos após cancelamento. O ícone é buscado aqui (bytes PNG)
  /// para o diálogo do sistema. Retorna `true` quando a sessão foi criada
  /// (o desenrolar chega por eventos). Não-Android → false.
  static Future<bool> prepare({
    required String key,
    required int attemptId,
    required String packageName,
    required String label,
    String? iconUrl,
    int sizeBytes = 0,
  }) async {
    if (!isAndroid || key.isEmpty || packageName.isEmpty) {
      return false;
    }
    final Uint8List? iconPng = await _fetchIcon(iconUrl);
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'prepare',
        <String, Object?>{
          'key': key,
          'attemptId': attemptId,
          'packageName': packageName,
          'label': label,
          'iconPng': iconPng,
          // Tamanho estimado do APK (quando conhecido): o pré-aproval do
          // sistema usa para reservar/alocar espaço.
          'sizeBytes': sizeBytes,
        },
      );
      return ok ?? false;
    } on Object {
      return false;
    }
  }

  /// Grava o APK na sessão pré-aprovada e faz commit (nenhum diálogo:
  /// aprovação já recebida). Falha de canal é silenciosa — o estado chega
  /// por eventos ('installFailed').
  static Future<void> commitPrepared({
    required String key,
    required int sessionId,
    required String path,
    String? expectedPackage,
  }) async {
    if (!isAndroid) {
      return;
    }
    await safeInvoke<void>(
      () => _channel.invokeMethod<void>('commitPrepared', <String, Object?>{
        'key': key,
        'sessionId': sessionId,
        'path': path,
        'expectedPackage': expectedPackage,
      }),
    );
  }

  /// Fluxo clássico: sessão PackageInstaller sem pré-aprovação (1 diálogo no
  /// commit — inclui o caso de pacote desconhecido e Android ≤ 13).
  static Future<void> commitFresh({
    required String key,
    required String path,
  }) async {
    if (!isAndroid) {
      return;
    }
    await safeInvoke<void>(
      () => _channel.invokeMethod<void>('commitFresh', <String, Object?>{
        'key': key,
        'path': path,
      }),
    );
  }

  /// Abandona a sessão (staging descartado). O Kotlin tenta pelo
  /// PackageInstaller do app e cai para o caminho Shizuku quando a sessão
  /// pertence ao shell (SecurityException).
  static Future<void> abandon(int sessionId) async {
    if (!isAndroid || sessionId <= 0) {
      return;
    }
    await safeInvoke<void>(
      () => _channel.invokeMethod<void>('abandon', <String, Object?>{
        'sessionId': sessionId,
      }),
    );
  }

  /// Cancela um prepare em andamento (ícone/sessão): impede o diálogo de
  /// pré-aprovação de aparecer. `attemptId` monotônico: callbacks velhos
  /// são ignorados no Kotlin.
  static Future<void> cancelPrepare(
    String key, {
    required int attemptId,
  }) async {
    if (!isAndroid) {
      return;
    }
    await safeInvoke<void>(
      () => _channel.invokeMethod<void>('cancelPrepare', <String, Object?>{
        'key': key,
        'attemptId': attemptId,
      }),
    );
  }

  /// Abandona sessões do próprio app sem dono vivo (app morto depois do
  /// createSession antes do commit). Chamar no startup.
  static Future<void> cleanupOrphanSessions() async {
    if (!isAndroid) {
      return;
    }
    await safeInvoke<void>(
      () => _channel.invokeMethod<void>('cleanupOrphanSessions'),
    );
  }

  static Future<Uint8List?> _fetchIcon(String? url) async {
    if (url == null || url.isEmpty) {
      return null;
    }
    try {
      final http.Response response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 ||
          response.bodyBytes.isEmpty ||
          // Teto de 2 MB: catálogo de boa-fé manda ícone; acima disso é
          // hostil e o canal não deveria transportar bytes ilimitados.
          response.bodyBytes.length > 2 * 1024 * 1024) {
        return null;
      }
      return response.bodyBytes;
    } on Object {
      return null;
    }
  }
}
