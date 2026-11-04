// offline_manager.dart
// 离线下载的门面（Facade）+ ChangeNotifier。
// 在 main() 里 await OfflineManager().init()；UI 用 AnimatedBuilder 监听进度。
import 'package:flutter/foundation.dart';

import '../models/search_result.dart';
import 'offline_download_service.dart';
import 'offline_storage_service.dart';

/// 某一集在「缓存」这件事上的状态，供选集界面画角标。
enum EpisodeCacheState {
  none,
  pending,
  downloading,
  paused,
  error,
  cached,
}

class OfflineManager extends ChangeNotifier {
  static final OfflineManager _i = OfflineManager._();
  factory OfflineManager() => _i;

  OfflineManager._() {
    _dl.onChanged = () {
      // 下载线程里回调，切回主 isolate 的通知即可（notifyListeners 同步安全）
      notifyListeners();
    };
  }

  final OfflineStorageService _store = OfflineStorageService();
  final OfflineDownloadService _dl = OfflineDownloadService();

  bool _ready = false;
  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    await _store.init();
    _ready = true;
    await _recoverInterrupted();
    notifyListeners();
  }

  /// 上次进程被杀时仍标记为 downloading 的记录，启动时改判为 paused，
  /// 这样用户可以在下载页点「继续」从断点续传。
  Future<void> _recoverInterrupted() async {
    for (final r in _store.all()) {
      if (r.status == DownloadStatus.downloading ||
          r.status == DownloadStatus.queued) {
        await _store.upsert(r.copyWithStatus(DownloadStatus.paused));
      }
    }
  }

  /// 全部记录，按创建时间倒序。
  List<OfflineRecord> get records => _store.all();

  /// 按剧集分组的视图：同一 (source,id) 的集合并到一组，供下载页分节展示。
  List<OfflineGroup> get groups {
    final map = <String, List<OfflineRecord>>{};
    for (final r in _store.all()) {
      map.putIfAbsent('${r.source}|${r.id}', () => []).add(r);
    }
    final list = map.entries.map((e) {
      final items = e.value
        ..sort((a, b) => a.episodeIndex.compareTo(b.episodeIndex));
      return OfflineGroup(key: e.key, records: items);
    }).toList();
    // 最近有活动的剧集排前面，符合「刚缓存的想先看到」的直觉。
    list.sort((a, b) => b.latestActivity.compareTo(a.latestActivity));
    return list;
  }

  bool isCached(String source, String id, int episodeIndex) =>
      _store.isCached(source, id, episodeIndex);

  /// 播放页用：已缓存返回本地绝对路径，否则返回空串。
  Future<String> localPathOf(String source, String id, int episodeIndex) =>
      _store.localPathOf(source, id, episodeIndex);

  OfflineRecord? get(String source, String id, int episodeIndex) =>
      _store.get(source, id, episodeIndex);

  /// 某部剧的全部缓存记录（按集数升序），纯离线模式据此重建选集列表。
  List<OfflineRecord> recordsFor(String source, String id) {
    final list =
        _store.all().where((r) => r.source == source && r.id == id).toList()
          ..sort((a, b) => a.episodeIndex.compareTo(b.episodeIndex));
    return list;
  }

  /// 纯离线模式：把本地缓存记录重建成一个 SearchResult，
  /// 使播放页在没有网络（无法向服务器拉取详情）时仍能正常展示选集并播放。
  /// 未缓存的集在 episodes 中占位为空串，播放页会提示「未缓存」。
  SearchResult? offlineDetailOf(String source, String id) {
    final list = recordsFor(source, id);
    if (list.isEmpty) return null;
    final first = list.first;
    final total = list
        .map((r) => r.totalEpisodes)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final count = total > 0 ? total : list.last.episodeIndex + 1;
    final episodes = List<String>.filled(count, '');
    final titles = List<String>.filled(count, '');
    for (final r in list) {
      final i = r.episodeIndex;
      if (i < 0 || i >= count) continue;
      episodes[i] = 'local://${r.localPath}';
      final t = r.episodeTitle ?? '';
      if (t.isNotEmpty) titles[i] = t;
    }
    for (var i = 0; i < count; i++) {
      if (titles[i].isEmpty) titles[i] = '第 ${i + 1} 集';
    }
    return SearchResult(
      id: id,
      title: first.title,
      poster: first.coverUrl ?? '',
      episodes: episodes,
      episodesTitles: titles,
      source: source,
      sourceName: '本地缓存',
      year: '',
    );
  }

  /// 本地已缓存的总条目数与占用空间，用于设置页展示。
  int get totalCachedCount =>
      _store.all().where((r) => r.status == DownloadStatus.success).length;

  int get totalCachedBytes => _store
      .all()
      .where((r) => r.status == DownloadStatus.success)
      .fold(0, (s, r) => s + r.sizeBytes);

  bool isRunning(String source, String id, int episodeIndex) =>
      _dl.isRunning('$source|$id|$episodeIndex');

  /// 排队中（已入队但还没轮到）。
  bool isPending(String source, String id, int episodeIndex) =>
      _dl.isPending('$source|$id|$episodeIndex');

  /// 还有多少集在排队。
  int get pendingCount => _dl.pendingCount;

  /// 某一集的综合状态，供选集卡片渲染角标。
  /// 优先级：已缓存 > 下载中 > 排队 > 暂停/失败 > 未缓存。
  EpisodeCacheState stateOf(String source, String id, int episodeIndex) {
    if (_store.isCached(source, id, episodeIndex)) {
      return EpisodeCacheState.cached;
    }
    if (_dl.isRunning('$source|$id|$episodeIndex')) {
      return EpisodeCacheState.downloading;
    }
    if (_dl.isPending('$source|$id|$episodeIndex')) {
      return EpisodeCacheState.pending;
    }
    final r = _store.get(source, id, episodeIndex);
    if (r != null) {
      switch (r.status) {
        case DownloadStatus.paused:
          return EpisodeCacheState.paused;
        case DownloadStatus.error:
          return EpisodeCacheState.error;
        case DownloadStatus.queued:
          return EpisodeCacheState.pending;
        default:
          break;
      }
    }
    return EpisodeCacheState.none;
  }

  /// 开始缓存某一集。
  Future<void> cacheEpisode({
    required String source,
    required String id,
    required int episodeIndex,
    required String title,
    String? episodeTitle,
    String? coverUrl,
    required String originalUrl,
    int totalEpisodes = 0,
  }) async {
    await _dl.start(
      source: source,
      id: id,
      episodeIndex: episodeIndex,
      title: title,
      episodeTitle: episodeTitle,
      coverUrl: coverUrl,
      originalUrl: originalUrl,
      totalEpisodes: totalEpisodes,
    );
    notifyListeners();
  }

  /// 批量缓存多集。
  ///
  /// [episodes] 与 [episodesTitles] 按下标对应；空串表示该集没有地址（跳过）。
  /// 已缓存/已在队列中的集会自动跳过，不会重复下载。
  /// 实际并发由下载服务的队列控制，这里只管全部入队。
  Future<int> cacheEpisodes({
    required String source,
    required String id,
    required String title,
    String? coverUrl,
    required List<String> episodes,
    List<String> episodesTitles = const [],
    Iterable<int>? indexes,
    int totalEpisodes = 0,
  }) async {
    var queued = 0;
    final targets = indexes ?? Iterable<int>.generate(episodes.length);
    for (final i in targets) {
      if (i < 0 || i >= episodes.length) continue;
      final url = episodes[i];
      if (url.isEmpty || url.startsWith('local://')) continue;
      if (_store.isCached(source, id, i)) continue;
      if (_dl.isRunning('$source|$id|$i') || _dl.isPending('$source|$id|$i')) {
        continue;
      }
      final epTitle = (i < episodesTitles.length) ? episodesTitles[i] : null;
      await _dl.start(
        source: source,
        id: id,
        episodeIndex: i,
        title: title,
        episodeTitle: epTitle,
        coverUrl: coverUrl,
        originalUrl: url,
        totalEpisodes: totalEpisodes > 0 ? totalEpisodes : episodes.length,
      );
      queued++;
    }
    notifyListeners();
    return queued;
  }

  /// 暂停某部剧的全部缓存任务（正在跑的 + 排队的）。
  Future<void> pauseAll(String source, String id) async {
    await _dl.pauseAll(source, id);
    notifyListeners();
  }

  Future<void> pause(String source, String id, int episodeIndex) async {
    await _dl.pause('$source|$id|$episodeIndex');
    notifyListeners();
  }

  /// 继续：用记录里的 originalUrl 重新走一次 start（分片已存在的会跳过）。
  Future<void> resume(OfflineRecord rec) async {
    await _dl.start(
      source: rec.source,
      id: rec.id,
      episodeIndex: rec.episodeIndex,
      title: rec.title,
      episodeTitle: rec.episodeTitle,
      coverUrl: rec.coverUrl,
      originalUrl: rec.originalUrl,
      totalEpisodes: rec.totalEpisodes,
    );
    notifyListeners();
  }

  /// 删除：停止任务 + 删文件 + 删索引。
  Future<void> remove(String source, String id, int episodeIndex) async {
    await _dl.cancel('$source|$id|$episodeIndex');
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

/// 「我的下载」里的一部剧（同一 source+id 的所有已缓存/在缓存的集）。
class OfflineGroup {
  final String key; // 'source|id'
  final List<OfflineRecord> records; // 按集数升序

  OfflineGroup({required this.key, required this.records});

  String get source => records.first.source;
  String get id => records.first.id;
  String get title => records.first.title;
  String? get coverUrl => records.first.coverUrl;

  int get cachedCount =>
      records.where((r) => r.status == DownloadStatus.success).length;
  int get failedCount =>
      records.where((r) => r.status == DownloadStatus.error).length;
  int get activeCount => records
      .where((r) =>
          r.status == DownloadStatus.downloading ||
          r.status == DownloadStatus.queued)
      .length;
  int get pausedCount =>
      records.where((r) => r.status == DownloadStatus.paused).length;

  /// 只统计已完成集的体积；未完成的不计入，避免显示成「已占 XGB」。
  int get cachedBytes => records
      .where((r) => r.status == DownloadStatus.success)
      .fold(0, (s, r) => s + r.sizeBytes);

  /// 整组进度（按集数加权，而不是按字节 —— 字节数在下载完成前不准）。
  double get progress {
    if (records.isEmpty) return 0;
    final sum = records.fold<double>(0, (s, r) {
      if (r.status == DownloadStatus.success) return s + 1;
      if (r.status == DownloadStatus.downloading ||
          r.status == DownloadStatus.paused) {
        return s + r.progress.clamp(0.0, 1.0);
      }
      return s;
    });
    return (sum / records.length).clamp(0.0, 1.0);
  }

  bool get allDone =>
      records.isNotEmpty && records.every((r) => r.status == DownloadStatus.success);

  bool get hasActive => activeCount > 0;

  /// 最近一次活动时间：完成/创建，用于组间排序。
  int get latestActivity => records
      .map((r) => r.createdAt)
      .fold<int>(0, (a, b) => a > b ? a : b);

  /// 「共 12 集 · 已缓存 5 集 · 1.2GB」这类摘要。
  String get summary {
    final parts = <String>[];
    parts.add('共 ${records.length} 集');
    if (cachedCount > 0) parts.add('已缓存 $cachedCount 集');
    if (activeCount > 0) parts.add('$activeCount 集进行中');
    if (pausedCount > 0) parts.add('$pausedCount 集已暂停');
    if (failedCount > 0) parts.add('$failedCount 集失败');
    if (cachedBytes > 0) parts.add(_fmtSize(cachedBytes));
    return parts.join(' · ');
  }

  static String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    const u = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)}${u[i]}';
  }
}
