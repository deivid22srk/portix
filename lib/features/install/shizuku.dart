import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
// PORTIX — estado do Shizuku (servidor shell/root que permite instalar APKs
// sem o diálogo do Android). O Kotlin emite estados pelo canal
// `portix/shizuku` (+ eventos em `portix/shizuku/events`); o Dart só escuta,
// revalida e expõe um provider em tempo real. Canal indisponível (host de
// teste/plataforma sem bridge) → fallback seguro `notInstalled`, sem crash.
// ============================================================================

/// Estados do serviço Shizuku (mesmo mapeamento do Kotlin, ShizukuBridge.kt).
enum ShizukuStatus {
  /// App Shizuku não instalado (`getPackageInfo` → NameNotFoundException).
  notInstalled,

  /// Instalado, mas o servidor não está rodando (usuário precisa iniciá-lo).
  installedStopped,

  /// Rodando, mas o PORTIX ainda não recebeu a permissão do Shizuku.
  runningNoPermission,

  /// Rodando e com permissão: instalações silenciosas.
  active;

  /// Alias usado pelo painel recuperado (`ShizukuStatus.stopped`) — o mesmo
  /// estado "instalado mas parado" com o nome curto de leitura.
  static const ShizukuStatus stopped = installedStopped;

  bool get isActive => this == active;

  /// `true` quando faz sentido oferecer a opção Shizuku na UI (instalado,
  /// rodando ou não). Not-installed desabilita o cartão.
  bool get isInstalledOrRunning => this != notInstalled;

  /// Decodifica o nome vindo do canal nativo; valor desconhecido é seguro.
  static ShizukuStatus decode(Object? raw) {
    final String name = raw?.toString() ?? '';
    for (final ShizukuStatus status in ShizukuStatus.values) {
      if (status.name == name) {
        return status;
      }
    }
    return ShizukuStatus.notInstalled;
  }
}

/// Ponte de métodos para o Kotlin (`portix/shizuku`). O Dart nunca fala
/// direto com o binder do Shizuku — tudo passa pelo canal.
class ShizukuService {
  ShizukuService._();

  static final ShizukuService instance = ShizukuService._();

  static const MethodChannel _channel = MethodChannel('portix/shizuku');
  static const EventChannel _events = EventChannel('portix/shizuku/events');

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  ShizukuStatus _current = ShizukuStatus.notInstalled;

  /// Último estado conhecido (leitura síncrona, usada pelo resolvedor).
  ShizukuStatus get current => _current;

  /// Consulta o estado atual ao Kotlin e memoriza. Falha de canal devolve
  /// `notInstalled` sem lançar (canal ausente = fallback seguro).
  Future<ShizukuStatus> refresh() async {
    if (!isAndroid) {
      _current = ShizukuStatus.notInstalled;
      return _current;
    }
    try {
      final Object? raw = await _channel.invokeMethod<Object?>('status');
      _current = ShizukuStatus.decode(raw);
    } on Object {
      _current = ShizukuStatus.notInstalled;
    }
    return _current;
  }

  /// Estado em tempo real emitido pelo Kotlin (binder received/dead e
  /// resultado de permissão). Erros de canal são silenciosos.
  Stream<ShizukuStatus> stream() {
    return _events
        .receiveBroadcastStream()
        .map<ShizukuStatus>(
          (Object? event) => ShizukuStatus.decode(
            event is Map ? event['status'] : event,
          ),
        )
        .handleError((Object _) => _current = ShizukuStatus.notInstalled);
  }

  /// Pede a permissão ao app Shizuku (diálogo do Shizuku). O resultado chega
  /// pelo stream de eventos — não há retorno direto.
  Future<void> requestPermission() async {
    if (!isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } on Object {
      // Sem bridge não há diálogo; o estado continua o que era.
    }
  }

  /// Abre o app Shizuku (para o usuário iniciar o servidor).
  Future<void> openShizuku() async {
    if (!isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('openShizuku');
    } on Object {
      // Sem launcher/intent disponível, nada a fazer.
    }
  }
}

/// Estado do Shizuku observável pela UI (painel de permissões, setup,
/// instalador preferido). Carrega o estado inicial, assina os eventos e
/// revalida sob demanda.
final shizukuStatusProvider =
    NotifierProvider<ShizukuStatusNotifier, ShizukuStatus>(
      ShizukuStatusNotifier.new,
    );

class ShizukuStatusNotifier extends Notifier<ShizukuStatus> {
  StreamSubscription<ShizukuStatus>? _subscription;

  @override
  ShizukuStatus build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    if (ShizukuService.isAndroid) {
      _subscription ??= ShizukuService.instance.stream().listen(
            (ShizukuStatus status) => state = status,
          );
      unawaited(refresh());
    }
    return ShizukuService.instance.current;
  }

  Future<void> refresh() async {
    state = await ShizukuService.instance.refresh();
  }
}
