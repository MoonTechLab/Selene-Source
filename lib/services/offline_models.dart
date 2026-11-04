// offline_models.dart
// 离线缓存的数据模型（纯 Dart，无 Flutter/IO 依赖）。
//
// 独立成文件的原因：OfflineRecord 与分组统计属于纯数据处理，
// 放在这里就能用 dart run 直接跑单元测试，不必拉起 Flutter 引擎。

enum DownloadStatus {
  none,
  queued,
  downloading,
  paused,
  success,
  error,
  deleted,
}

class OfflineRecord {
  final String source;
  final String id;
  final int episodeIndex;
  final String title;
  final String? episodeTitle;
  final String? coverUrl;
  final String originalUrl; // 在线播放地址（m3u8 或 mp4）
  final String localPath; // 最终本地文件路径（.ts 或 .mp4）
  final String container; // 'ts' | 'mp4'
  final int totalSegments; // m3u8 分片总数；mp4 为 1
  final int doneSegments; // 已完成分片数（断点续传索引）
  final int sizeBytes;
  final DownloadStatus status;
  final double progress; // 0..1
  final String? error;
  final int createdAt; // epoch millis

  /// 该剧的总集数（缓存时记录），纯离线模式下用它重建选集列表。
  final int totalEpisodes;

  OfflineRecord({
    required this.source,
    required this.id,
    required this.episodeIndex,
    required this.title,
    this.episodeTitle,
    this.coverUrl,
    required this.originalUrl,
    required this.localPath,
    required this.container,
    this.totalSegments = 1,
    this.doneSegments = 0,
    this.sizeBytes = 0,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.error,
    required this.createdAt,
    this.totalEpisodes = 0,
  });

  String get key => '$source|$id|$episodeIndex';

  /// 只改状态的轻量副本（进度/总数保持不变）。
  OfflineRecord copyWithStatus(DownloadStatus s) => OfflineRecord(
    source: source,
    id: id,
    episodeIndex: episodeIndex,
    title: title,
    episodeTitle: episodeTitle,
    coverUrl: coverUrl,
    originalUrl: originalUrl,
    localPath: localPath,
    container: container,
    totalSegments: totalSegments,
    doneSegments: doneSegments,
    sizeBytes: sizeBytes,
    status: s,
    progress: progress,
    error: error,
    createdAt: createdAt,
    totalEpisodes: totalEpisodes,
  );

  Map<String, dynamic> toJson() => {
    'source': source,
    'id': id,
    'episodeIndex': episodeIndex,
    'title': title,
    'episodeTitle': episodeTitle,
    'coverUrl': coverUrl,
    'originalUrl': originalUrl,
    'localPath': localPath,
    'container': container,
    'totalSegments': totalSegments,
    'doneSegments': doneSegments,
    'sizeBytes': sizeBytes,
    'status': status.index,
    'progress': progress,
    'error': error,
    'createdAt': createdAt,
    'totalEpisodes': totalEpisodes,
  };

  factory OfflineRecord.fromJson(Map<String, dynamic> j) => OfflineRecord(
    source: j['source'] as String,
    id: j['id'] as String,
    episodeIndex: j['episodeIndex'] as int,
    title: j['title'] as String,
    episodeTitle: j['episodeTitle'] as String?,
    coverUrl: j['coverUrl'] as String?,
    originalUrl: j['originalUrl'] as String,
    localPath: j['localPath'] as String,
    container: j['container'] as String,
    totalSegments: j['totalSegments'] as int? ?? 1,
    doneSegments: j['doneSegments'] as int? ?? 0,
    sizeBytes: j['sizeBytes'] as int? ?? 0,
    status: DownloadStatus.values[j['status'] as int? ?? 0],
    progress: (j['progress'] as num? ?? 0).toDouble(),
    error: j['error'] as String?,
    createdAt: j['createdAt'] as int? ?? 0,
    totalEpisodes: j['totalEpisodes'] as int? ?? 0,
  );
}
