import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/download_task.dart';
import '../../models/game.dart';
import '../../models/game_detail.dart';
import '../collections/collections_controller.dart';

final downloadsProvider =
    NotifierProvider<DownloadsController, List<DownloadTask>>(DownloadsController.new);

final downloadForGameProvider = Provider.family<DownloadTask?, String>(
  (ref, String gameId) {
    final List<DownloadTask> tasks = ref.watch(downloadsProvider);
    for (final DownloadTask task in tasks) {
      if (task.gameId == gameId) {
        return task;
      }
    }
    return null;
  },
);

class DownloadsController extends Notifier<List<DownloadTask>> {
  static const String _storageKey = 'downloads.tasks';

  Timer? _ticker;
  int _ticks = 0;

  @override
  List<DownloadTask> build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _ticker = null;
    });
    return _loadPersisted();
  }

  List<DownloadTask> _loadPersisted() {
    final String? raw = ref.read(sharedPreferencesProvider).getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const <DownloadTask>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <DownloadTask>[];
      }
      final List<DownloadTask> tasks = <DownloadTask>[];
      for (final Object? item in decoded) {
        if (item is Map) {
          final DownloadTask task =
              DownloadTask.fromJson(Map<String, dynamic>.from(item));
          if (task.gameId.isEmpty) {
            continue;
          }
          // Um download interrompido pelo sistema volta como pausado,
          // nunca como se estivesse progredindo sozinho.
          tasks.add(
            task.isActive ? task.copyWith(status: DownloadStatus.paused) : task,
          );
        }
      }
      return tasks;
    } on Object {
      return const <DownloadTask>[];
    }
  }

  void start(Game game, {GamePort? port}) {
    final int index =
        state.indexWhere((DownloadTask task) => task.gameId == game.id);
    if (index >= 0) {
      final DownloadTask current = state[index];
      if (current.status == DownloadStatus.done) {
        return;
      }
      if (current.status != DownloadStatus.downloading) {
        resume(game.id);
      }
      return;
    }
    final DownloadTask task = DownloadTask(
      gameId: game.id,
      title: game.title,
      slug: game.slug,
      coverUrl: game.coverUrl,
      portKey: port?.portKey,
      portUrl: port?.url,
      platformName: port?.platformName,
      status: DownloadStatus.downloading,
      progress: 0.03,
      startedAt: DateTime.now(),
    );
    state = <DownloadTask>[task, ...state];
    _persist();
    _ensureTicker();
    _sync(task);
    HapticFeedback.selectionClick();
  }

  void pause(String gameId) {
    _update(
      gameId,
      (DownloadTask task) => task.copyWith(status: DownloadStatus.paused),
    );
    _persist();
    _syncFor(gameId);
    _stopTickerIfIdle();
  }

  void resume(String gameId) {
    _update(
      gameId,
      (DownloadTask task) => task.copyWith(status: DownloadStatus.downloading),
    );
    _persist();
    _syncFor(gameId);
    _ensureTicker();
    HapticFeedback.selectionClick();
  }

  void cancel(String gameId) {
    state = state
        .where((DownloadTask task) => task.gameId != gameId)
        .toList(growable: false);
    _persist();
    _stopTickerIfIdle();
  }

  void remove(String gameId) {
    state = state
        .where((DownloadTask task) => task.gameId != gameId)
        .toList(growable: false);
    _persist();
    _stopTickerIfIdle();
  }

  void clearCompleted() {
    state = state
        .where((DownloadTask task) => !task.isDone)
        .toList(growable: false);
    _persist();
  }

  DownloadTask? taskFor(String gameId) {
    for (final DownloadTask task in state) {
      if (task.gameId == gameId) {
        return task;
      }
    }
    return null;
  }

  void _update(String gameId, DownloadTask Function(DownloadTask) transform) {
    state = state
        .map((DownloadTask task) => task.gameId == gameId ? transform(task) : task)
        .toList(growable: false);
  }

  void _ensureTicker() {
    if (_ticker != null) {
      return;
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 420), (Timer timer) {
      _tick();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _ticks = 0;
  }

  void _stopTickerIfIdle() {
    final bool anyActive =
        state.any((DownloadTask task) => task.status == DownloadStatus.downloading);
    if (!anyActive) {
      _stopTicker();
    }
  }

  void _tick() {
    final List<DownloadTask> next = <DownloadTask>[];
    final List<DownloadTask> finished = <DownloadTask>[];
    for (final DownloadTask task in state) {
      if (task.status != DownloadStatus.downloading) {
        next.add(task);
        continue;
      }
      final double value = task.progress + 0.028;
      if (value >= 1) {
        final DownloadTask done =
            task.copyWith(status: DownloadStatus.done, progress: 1);
        next.add(done);
        finished.add(done);
      } else {
        next.add(task.copyWith(progress: value));
      }
    }
    state = next;
    _ticks += 1;
    if (_ticks % 8 == 0) {
      _persist();
    }
    for (final DownloadTask task in finished) {
      _complete(task);
    }
    _stopTickerIfIdle();
  }

  void _complete(DownloadTask task) {
    _persist();
    _sync(task);
    HapticFeedback.mediumImpact();
    unawaited(_addToLibrary(task));
  }

  Future<void> _addToLibrary(DownloadTask task) async {
    try {
      await ref.read(catalogRepositoryProvider).addToLibrary(task.gameId);
      ref.invalidate(collectionsProvider);
    } on Object {
      return;
    }
  }

  void _syncFor(String gameId) {
    for (final DownloadTask task in state) {
      if (task.gameId == gameId) {
        _sync(task);
        return;
      }
    }
  }

  void _sync(DownloadTask task) {
    unawaited(_pushSync(task));
  }

  Future<void> _pushSync(DownloadTask task) async {
    try {
      await ref.read(catalogRepositoryProvider).syncDownload(
            gameId: task.gameId,
            portKey: task.portKey,
            status: task.status.name,
            progress: (task.progress * 100).round(),
          );
    } on Object {
      // Sem conexão o estado local continua válido; a próxima sincronização
      // envia o progresso mais recente.
    }
  }

  void _persist() {
    final String payload = jsonEncode(
      state.map((DownloadTask task) => task.toJson()).toList(growable: false),
    );
    unawaited(
      ref.read(sharedPreferencesProvider).setString(_storageKey, payload),
    );
  }
}
