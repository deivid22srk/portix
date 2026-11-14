import 'parsing.dart';

enum DownloadStatus { queued, downloading, paused, done, failed }

class DownloadTask {
  const DownloadTask({
    required this.gameId,
    required this.title,
    required this.slug,
    this.coverUrl,
    this.portKey,
    this.portUrl,
    this.platformName,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.startedAt,
  });

  final String gameId;
  final String title;
  final String slug;
  final String? coverUrl;
  final String? portKey;
  final String? portUrl;
  final String? platformName;
  final DownloadStatus status;
  final double progress;
  final DateTime? startedAt;

  bool get isActive => status == DownloadStatus.queued || status == DownloadStatus.downloading;

  bool get isDone => status == DownloadStatus.done;

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    String? portUrl,
    String? platformName,
  }) =>
      DownloadTask(
        gameId: gameId,
        title: title,
        slug: slug,
        coverUrl: coverUrl,
        portKey: portKey,
        portUrl: portUrl ?? this.portUrl,
        platformName: platformName ?? this.platformName,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        startedAt: startedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'game_id': gameId,
        'title': title,
        'slug': slug,
        'cover_url': coverUrl,
        'port_key': portKey,
        'port_url': portUrl,
        'platform_name': platformName,
        'status': status.name,
        'progress': progress,
        'started_at': startedAt?.toIso8601String(),
      };

  factory DownloadTask.fromJson(Map<String, dynamic> map) {
    final String rawStatus = asTextOr(map['status'], 'paused');
    DownloadStatus status = DownloadStatus.paused;
    for (final DownloadStatus candidate in DownloadStatus.values) {
      if (candidate.name == rawStatus) {
        status = candidate;
      }
    }
    return DownloadTask(
      gameId: asTextOr(map['game_id'], ''),
      title: asTextOr(map['title'], ''),
      slug: asTextOr(map['slug'], ''),
      coverUrl: asText(map['cover_url']),
      portKey: asText(map['port_key']),
      portUrl: asText(map['port_url']),
      platformName: asText(map['platform_name']),
      status: status,
      progress: asDouble(map['progress']),
      startedAt: asDate(map['started_at']),
    );
  }
}
