import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shizuku.dart';

// ============================================================================
// PORTIX — permissões do dispositivo relevantes para instalação:
// "Instalar apps desconhecidos" (canRequestPackageInstalls), notificações
// (POST_NOTIFICATIONS, Android 13+) e estado do Shizuku. Consulta o canal
// `portix/permissions` (Kotlin) e mantém um snapshot observável com refresh.
// Em não-Android (desktop/web/testes) devolve default gracioso sem crash.
// ============================================================================

/// Foto do estado de permissões em um instante.
class PermissionSnapshot {
  const PermissionSnapshot({
    required this.canInstallApps,
    required this.notificationsGranted,
    required this.shizuku,
    required this.sdkInt,
    this.freeBytes = -1,
    this.isAndroid = false,
  });

  /// `PackageManager.canRequestPackageInstalls()` — "Instalar apps
  /// desconhecidos" liberado para o PORTIX.
  final bool canInstallApps;

  /// `areNotificationsEnabled()` (relevante no Android 13+).
  final bool notificationsGranted;

  /// Estado atual do Shizuku (mesmo enum do canal `portix/shizuku`).
  final ShizukuStatus shizuku;

  /// `Build.VERSION.SDK_INT` (0 fora do Android).
  final int sdkInt;

  /// Bytes livres no armazenamento privado do app (-1 = desconhecido).
  final int freeBytes;

  /// `false` em desktop/web/testes (fallback gracioso).
  final bool isAndroid;

  /// Snapshot padrão fora do Android: tudo concedido, Shizuku ausente.
  static const PermissionSnapshot desktop = PermissionSnapshot(
    canInstallApps: true,
    notificationsGranted: true,
    shizuku: ShizukuStatus.notInstalled,
    sdkInt: 0,
    freeBytes: -1,
    isAndroid: false,
  );
}

/// Ações e consultas de permissão (canal `portix/permissions`).
class PortixPermissions {
  const PortixPermissions._();

  static const MethodChannel _channel = MethodChannel('portix/permissions');

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Consulta o estado atual. Retorna `null` quando o canal não responde
  /// (ex.: Android sem bridge — nunca deve acontecer, mas não pode crashar).
  static Future<PermissionSnapshot?> snapshot() async {
    if (!isAndroid) {
      return PermissionSnapshot.desktop;
    }
    try {
      final Map<Object?, Object?>? map = await _channel
          .invokeMethod<Map<Object?, Object?>>('snapshot');
      if (map == null) {
        return null;
      }
      return PermissionSnapshot(
        canInstallApps: map['canInstallApps'] == true,
        notificationsGranted: map['notificationsGranted'] == true,
        shizuku: ShizukuStatus.decode(map['shizuku']),
        sdkInt: map['sdkInt'] is num ? (map['sdkInt']! as num).toInt() : 0,
        freeBytes: map['freeBytes'] is num
            ? (map['freeBytes']! as num).toInt()
            : -1,
        isAndroid: true,
      );
    } on Object {
      return null;
    }
  }

  /// Abre a tela do sistema "Instalar apps desconhecidos" já direcionada ao
  /// PORTIX (ACTION_MANAGE_UNKNOWN_APP_SOURCES com `package:<appId>`).
  /// Fora do Android é no-op.
  static Future<void> openInstallAppsSettings() async {
    if (!isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('openInstallAppsSettings');
    } on Object {
      // Tela indisponível (raro): o sheet do app continua com o contexto.
    }
  }

  /// Pede POST_NOTIFICATIONS (Android 13+). Em <13 (permissão implícita) e
  /// fora do Android devolve `true`; falha de canal devolve `false`.
  static Future<bool> requestNotifications() async {
    if (!isAndroid) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('requestNotifications') ?? false;
    } on Object {
      return false;
    }
  }
}

/// Snapshot consultável pela UI (uso: `ref.watch(permissionSnapshotProvider).value`).
final permissionSnapshotProvider = FutureProvider<PermissionSnapshot?>(
  (ref) => PortixPermissions.snapshot(),
);

/// Snapshot mantido em notifier com `refresh()` — usado pelo setup e pela
/// categoria de instalação. Reage a mudança do Shizuku (permissão concedida
/// pelo app do Shizuku revalida o snapshot inteiro).
final permissionsProvider =
    NotifierProvider<PermissionsNotifier, PermissionSnapshot?>(
      PermissionsNotifier.new,
    );

class PermissionsNotifier extends Notifier<PermissionSnapshot?> {
  @override
  PermissionSnapshot? build() {
    ref.listen<ShizukuStatus>(shizukuStatusProvider, (
      ShizukuStatus? previous,
      ShizukuStatus next,
    ) {
      if (previous != null && previous != next) {
        unawaited(refresh());
      }
    });
    unawaited(refresh());
    return null;
  }

  /// Consulta um snapshot novo (retorna o mesmo valor em `state`).
  Future<PermissionSnapshot?> refresh() async {
    final PermissionSnapshot? snapshot = await PortixPermissions.snapshot();
    state = snapshot;
    return snapshot;
  }
}
