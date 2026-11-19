import 'dart:io';

// ============================================================================
// PORTIX — limpeza de arquivos de APK baixados. Os APKs vivem no
// armazenamento privado do app (getExternalFilesDir/apk/portix-<id>.apk,
// destino do motor Rust). Regras:
// - apagar após instalação confirmada e após falha de integridade
//   (fluxo chama deleteFileQuietly);
// - helpers para órfãos: .part e .apk antigos fora da lista de tarefas vivas.
// ============================================================================

/// `true` quando o APK existe no disco (reinstalação sem novo download).
bool apkFileExists(String path) {
  if (path.isEmpty) {
    return false;
  }
  try {
    return File(path).existsSync();
  } on Object {
    return false;
  }
}

/// Apaga o arquivo sem lançar (limpeza é best-effort: falhar não pode
/// quebrar o fluxo de instalação).
void deleteFileQuietly(String path) {
  if (path.isEmpty) {
    return;
  }
  try {
    final File file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  } on Object {
    // Sem permissão/arquivo já apagado: nada a fazer.
  }
}

/// Apaga um APK baixado (após instalação confirmada ou falha de integridade).
Future<void> deleteApk(String path) async {
  deleteFileQuietly(path);
}

/// Remove `.part` e `.apk` órfãos dos diretórios de APK conhecidos
/// (derivados das tarefas persistidas). Um arquivo é órfão quando:
/// - não está em [keepPaths], e
/// - não é recentemente modificado (folga de 7 dias para downloads em
///   andamento que reaparecem após reinício do processo).
/// Retorna a quantidade removida (best-effort, nunca lança).
Future<int> cleanupOrphanApks(
  Iterable<String> keepPaths, {
  Duration grace = const Duration(days: 7),
}) async {
  final Set<String> keep = <String>{
    for (final String path in keepPaths)
      if (path.isNotEmpty) path,
  };
  final Set<Directory> dirs = <Directory>{};
  for (final String path in keep) {
    try {
      final File file = File(path);
      final Directory parent = file.parent;
      if (parent.existsSync()) {
        dirs.add(parent);
      }
    } on Object {
      // Caminho inválido: ignora.
    }
  }
  int removed = 0;
  final DateTime limit = DateTime.now().subtract(grace);
  for (final Directory dir in dirs) {
    try {
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is! File) {
          continue;
        }
        final String path = entity.path;
        final String lower = path.toLowerCase();
        final bool isApkish = lower.endsWith('.apk') || lower.endsWith('.part');
        if (!isApkish || keep.contains(path)) {
          continue;
        }
        try {
          final FileStat stat = entity.statSync();
          if (stat.modified.isBefore(limit)) {
            entity.deleteSync();
            removed += 1;
          }
        } on Object {
          // Arquivo em uso/sem permissão: deixa para a próxima varredura.
        }
      }
    } on Object {
      // Diretório sumiu: nada a fazer.
    }
  }
  return removed;
}
