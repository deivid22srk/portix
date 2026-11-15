import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Evento emitido pelo serviço Android de download.
class NativeDownloadEvent {
  const NativeDownloadEvent({
    required this.id,
    required this.status,
    this.done = 0,
    this.total = 0,
    this.path,
    this.error,
    this.speedBps = 0,
    this.etaSecs = -1,
  });

  final int id;
  final String status;
  final int done;
  final int total;
  final String? path;
  final String? error;

  /// Velocidade suavizada (bytes/s) — presente em eventos `downloading`.
  final double speedBps;

  /// ETA em segundos (-1 = desconhecido).
  final int etaSecs;

  double? get progress =>
      total > 0 ? (done / total).clamp(0.0, 1.0).toDouble() : null;

  factory NativeDownloadEvent.fromMap(Map<Object?, Object?> map) {
    int asInt(Object? value) => value is num ? value.toInt() : 0;
    double asDouble(Object? value) => value is num ? value.toDouble() : 0.0;
    String? asText(Object? value) {
      final String text = value?.toString() ?? '';
      return text.isEmpty ? null : text;
    }

    return NativeDownloadEvent(
      id: asInt(map['id']),
      status: asText(map['status']) ?? 'unknown',
      done: asInt(map['done']),
      total: asInt(map['total']),
      path: asText(map['path']),
      error: asText(map['error']),
      speedBps: asDouble(map['speed']),
      etaSecs: map['eta'] is num ? (map['eta'] as num).toInt() : -1,
    );
  }
}

/// Ponte para o motor de download nativo (Rust) + serviço Android.
class NativeDownloader {
  const NativeDownloader._();

  static const MethodChannel _methods = MethodChannel('portix/downloader');
  static const EventChannel _events = EventChannel('portix/downloader/events');

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isSupported() async {
    if (!isAndroid) {
      return false;
    }
    try {
      return await _methods.invokeMethod<bool>('isSupported') ?? false;
    } on Object {
      return false;
    }
  }

  /// Pede a permissão de notificações (Android 13+), necessária para o
  /// progresso do download aparecer na gaveta.
  static Future<void> requestNotifications() async {
    if (!isAndroid) {
      return;
    }
    try {
      await _methods.invokeMethod<void>('requestNotifications');
    } on Object {
      // Sem permissão o download continua, só não mostra a notificação.
    }
  }

  static Future<bool> start({
    required int id,
    required String url,
    required String title,
  }) async {
    if (!isAndroid) {
      return false;
    }
    try {
      return await _methods.invokeMethod<bool>('start', <String, Object?>{
            'id': id,
            'url': url,
            'title': title,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  static Future<void> cancel(int id) async {
    if (!isAndroid) {
      return;
    }
    try {
      await _methods.invokeMethod<void>('cancel', <String, Object?>{'id': id});
    } on Object {
      // Sem serviço ativo não há o que cancelar.
    }
  }

  static Future<bool> install(String path) async {
    if (!isAndroid) {
      return false;
    }
    try {
      return await _methods.invokeMethod<bool>('install', <String, Object?>{
            'path': path,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  static Stream<NativeDownloadEvent> events() {
    return _events
        .receiveBroadcastStream()
        .map<NativeDownloadEvent>((Object? event) => NativeDownloadEvent.fromMap(
              Map<Object?, Object?>.from(event as Map? ?? const <Object?, Object?>{}),
            ));
  }
}
