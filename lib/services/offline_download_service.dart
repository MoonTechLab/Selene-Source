// offline_download_service.dart
// 离线下载核心：
//   · m3u8：主播放列表选档 → AES-128-CBC 解密（支持 key 轮换）→ byte-range
//     分块 → 16 并发 → 分片落盘（断点续传）→ 合并为单一文件
//   · mp4：直下
// 算法参考 MoonTV src/lib/m3u8-downloader.ts；解密用本地 offline_aes.dart，
// 不引入额外依赖。
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'offline_aes.dart';
import 'offline_m3u8_parser.dart';
import 'offline_storage_service.dart';

const int kConcurrency = 8;
const int kRangeChunkThreshold = 512 * 1024; // 512KB
const int kRangeChunkCount = 4;
const int kMaxRetries = 3;

/// 进度落盘间隔：下载进度是高频变化量，没必要每个分片都写一次索引。
/// 断点续传依据的是磁盘上的 seg_i.bin，不是索引里的 progress，
/// 因此即使用户在这期间强杀进程，重进后仍能从磁盘重建已完成分片。
const Duration kPersistInterval = Duration(seconds: 3);

/// UI 通知合并间隔：避免 8 个并发 worker 每完成一片就重建整个界面。
const Duration kNotifyInterval = Duration(milliseconds: 250);

/// 同时下载的「集数」上限。
///
/// 每集内部已有 [kConcurrency] 个分片并发，若一键缓存整季再让每集同时开跑，
/// 瞬时连接数会到几百，既抢带宽又拖垮 UI 通知。这里按「集」排队，
/// 前面的下完自动接下一集，用户看到的是逐集推进。
const int kMaxConcurrentEpisodes = 1;

class OfflineDownloadService {
  static final OfflineDownloadService _i = OfflineDownloadService._();
  factory OfflineDownloadService() => _i;
  OfflineDownloadService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 90),
      headers: {'User-Agent': 'Mozilla/5.0'},
    ),
  );

  final OfflineStorageService _store = OfflineStorageService();
  final Map<String, _Task> _tasks = {};

  /// 排队待跑的集（FIFO）。一键缓存整季时不会一次性全开。
  final List<String> _pending = [];

  /// 批量入队的集数，用于给 UI 展示「还有 N 集在排队」。
  int get pendingCount => _pending.length;

  /// 任一进度/状态变化后回调，由 OfflineManager 挂上 notifyListeners。
  void Function()? onChanged;

  bool isRunning(String key) => _tasks.containsKey(key);

  bool isPending(String key) => _pending.contains(key);

  /// 启动（或恢复）一次下载，返回 taskKey。
  ///
  /// 任务会进入排队，实际并发由 [kMaxConcurrentEpisodes] 控制；
  /// 调用方无需等待，进度通过 onChanged 推送。
  Future<String> start({
    required String source,
    required String id,
    required int episodeIndex,
    required String title,
    String? episodeTitle,
    String? coverUrl,
    required String originalUrl,
    int totalEpisodes = 0,
  }) async {
    final key = '$source|$id|$episodeIndex';
    // 已有任务在跑或在排队：直接复用，避免重复下载
    if (_tasks[key] != null || _pending.contains(key)) return key;

    final dir = await _store.downloadsDir;
    final isM3u8 = originalUrl.contains('.m3u8');
    final container = isM3u8 ? 'ts' : 'mp4';
    final localPath = '$dir/${_safe(title)}_${episodeIndex + 1}.$container';

    var rec = _store.get(source, id, episodeIndex);
    if (rec == null) {
      rec = OfflineRecord(
        source: source,
        id: id,
        episodeIndex: episodeIndex,
        title: title,
        episodeTitle: episodeTitle,
        coverUrl: coverUrl,
        originalUrl: originalUrl,
        localPath: localPath,
        container: container,
        status: DownloadStatus.queued,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        totalEpisodes: totalEpisodes,
      );
      await _store.upsert(rec);
    }

    _pending.add(key);
    // 把 url 记在队列边上，出队时不必再查索引。
    _pendingUrls[key] = originalUrl;
    _pump();
    return key;
  }

  final Map<String, String> _pendingUrls = {};

  /// 队列泵：有空位就取出下一个开跑。
  void _pump() {
    while (_tasks.length < kMaxConcurrentEpisodes && _pending.isNotEmpty) {
      final key = _pending.removeAt(0);
      final url = _pendingUrls.remove(key) ?? '';
      final parts = key.split('|');
      if (parts.length != 3 || url.isEmpty) continue;
      final rec = _store.get(parts[0], parts[1], int.parse(parts[2]));
      if (rec == null) continue;
      // 已完成的不重复下载（批量入队时可能包含已缓存的集）。
      if (rec.status == DownloadStatus.success &&
          File(rec.localPath).existsSync()) {
        continue;
      }
      final task = _Task(key: key, record: rec);
      _tasks[key] = task;
      unawaited(_run(task, url, url.contains('.m3u8')));
    }
  }

  Future<void> pause(String key) async {
    _pending.remove(key);
    _pendingUrls.remove(key);
    final t = _tasks[key];
    if (t != null) {
      t.cancel();
      _tasks.remove(key);
      await _store.upsert(t.record.copyWith(status: DownloadStatus.paused));
    } else {
      // 排队中被暂停：直接标记，避免又变回「排队中」。
      final parts = key.split('|');
      if (parts.length == 3) {
        final rec = _store.get(parts[0], parts[1], int.parse(parts[2]));
        if (rec != null) {
          await _store.upsert(rec.copyWith(status: DownloadStatus.paused));
        }
      }
    }
    _pump();
    onChanged?.call();
  }

  /// 暂停某部剧全部集（队列 + 正在跑的）。
  Future<void> pauseAll(String source, String id) async {
    final prefix = '$source|$id|';
    for (final k in [..._pending.where((e) => e.startsWith(prefix))]) {
      _pending.remove(k);
      _pendingUrls.remove(k);
    }
    for (final k in [..._tasks.keys.where((e) => e.startsWith(prefix))]) {
      final t = _tasks.remove(k);
      t?.cancel();
      if (t != null) {
        await _store.upsert(t.record.copyWith(status: DownloadStatus.paused));
      }
    }
    // 队列里被移走的也要落成已暂停状态
    for (final r in _store.all()) {
      if (r.source == source &&
          r.id == id &&
          r.status == DownloadStatus.queued) {
        await _store.upsert(r.copyWith(status: DownloadStatus.paused));
      }
    }
    _pump();
    onChanged?.call();
  }

  Future<void> cancel(String key) async {
    _pending.remove(key);
    _pendingUrls.remove(key);
    final t = _tasks[key];
    if (t != null) {
      t.cancel();
      _tasks.remove(key);
    }
    final p = key.split('|');
    await _store.remove(p[0], p[1], int.parse(p[2]));
    _pump();
  }

  Future<void> _run(_Task task, String url, bool isM3u8) async {
    try {
      if (isM3u8) {
        await _downloadM3u8(task, url);
      } else {
        await _downloadFile(task, url);
      }
      final f = File(task.record.localPath);
      final size = await f.exists() ? await f.length() : 0;
      await _save(
        task,
        status: DownloadStatus.success,
        progress: 1,
        sizeBytes: size,
        doneSegments: task.record.totalSegments,
      );
    } on _CancelException {
      // 用户取消：状态已由 pause/cancel 写入
    } catch (e) {
      if (!task.cancelled) {
        await _save(task, status: DownloadStatus.error, error: '$e');
      }
    } finally {
      // 先移除任务再判断是否空闲，否则本任务仍留在 _tasks 里，
      // ticker 永远停不下来（会一直每 3 秒空写一次索引）。
      _tasks.remove(task.key);
      _stopPersistTickerIfIdle();
      await _store.flush();
      // 本集结束（成功/失败/取消）后接着跑队列里的下一集。
      _pump();
      onChanged?.call();
    }
  }

  /// 统一写回：更新 task.record 后持久化并通知 UI。
  /// 只传需要改的字段，其余沿用当前内存记录（避免进度被旧值覆盖）。
  ///
  /// 性能优化：进度更新走 `_reportProgress`（只改内存 + 节流通知/落盘），
  /// 只有状态迁移（开始/完成/暂停/出错）才立即落盘。
  Future<void> _save(
    _Task task, {
    DownloadStatus? status,
    double? progress,
    int? doneSegments,
    int? totalSegments,
    int? sizeBytes,
    String? container,
    String? error,
  }) async {
    task.record = task.record.copyWith(
      status: status,
      progress: progress,
      doneSegments: doneSegments,
      totalSegments: totalSegments,
      sizeBytes: sizeBytes,
      container: container,
      error: error,
    );
    await _store.upsert(task.record, persist: false);
    // 状态迁移属关键节点：立即落盘，保证重启后状态正确。
    await _store.flush();
    onChanged?.call();
  }

  /// 高频进度更新：只改内存，通知与落盘都按时间合并。
  void _reportProgress(
    _Task task, {
    required int doneSegments,
    required double progress,
  }) {
    task.record = task.record.copyWith(
      doneSegments: doneSegments,
      progress: progress,
    );
    // 不 await：让下载 worker 立刻继续，避免把写盘串进关键路径。
    unawaited(_store.upsert(task.record, persist: false));
    _scheduleNotify();
  }

  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _notifyTimer;

  void _scheduleNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) >= kNotifyInterval) {
      _lastNotify = now;
      onChanged?.call();
      return;
    }
    // 合并窗口内：只挂一个定时器，到点补发一次，保证最后一次进度不丢。
    _notifyTimer ??= Timer(kNotifyInterval, () {
      _notifyTimer = null;
      _lastNotify = DateTime.now();
      onChanged?.call();
    });
  }

  /// 周期性把内存进度落盘。这是全局的：索引是整份序列化的，
  /// 多个任务并行时共用同一个 ticker 即可，避免各自写盘互相打断。
  Timer? _persistTicker;

  void _startPersistTicker() {
    _persistTicker ??= Timer.periodic(kPersistInterval, (_) {
      unawaited(_store.flush());
    });
  }

  void _stopPersistTickerIfIdle() {
    if (_tasks.isNotEmpty) return;
    _persistTicker?.cancel();
    _persistTicker = null;
  }

  // ---------------------------------------------------------------- mp4

  Future<void> _downloadFile(_Task task, String url) async {
    await _save(task, status: DownloadStatus.downloading, totalSegments: 1);
    _startPersistTicker();
    final tmp = File('${task.record.localPath}.part');
    final sink = tmp.openWrite();
    var received = 0;
    int? totalBytes;
    try {
      final resp = await _dio.get<ResponseBody>(
        url,
        options: Options(responseType: ResponseType.stream),
        cancelToken: task.cancelToken,
      );
      totalBytes = int.tryParse(resp.headers.value('content-length') ?? '');
      await for (final chunk in resp.data!.stream) {
        if (task.cancelled) throw _CancelException();
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes != null && totalBytes > 0) {
          // 每个网络 chunk 都会走到这里（几十 KB 一次），必须走节流路径。
          _reportProgress(
            task,
            doneSegments: 0,
            progress: received / totalBytes,
          );
        }
      }
    } finally {
      await sink.close();
    }
    if (task.cancelled) {
      await tmp.delete().catchError((_) => tmp);
      throw _CancelException();
    }
    await tmp.rename(task.record.localPath);
    await _save(task, progress: 1, doneSegments: 1, sizeBytes: received);
  }

  // ---------------------------------------------------------------- m3u8

  Future<void> _downloadM3u8(_Task task, String url) async {
    // 1) 解析（master → 子列表 → 媒体列表）
    final parsed = await _resolvePlaylist(task, url);
    final segments = parsed.segments;
    if (segments.isEmpty) throw StateError('m3u8 无可下载分片');

    // 2) 分片目录（断点续传依据：seg_i.bin 已存在即跳过）
    final partsDir = Directory('${task.record.localPath}.parts');
    if (!await partsDir.exists()) await partsDir.create(recursive: true);
    final total = segments.length + (parsed.initSegment != null ? 1 : 0);

    await _save(
      task,
      totalSegments: total,
      container: parsed.container,
      status: DownloadStatus.downloading,
    );

    // 3) 已完成分片
    final existing = <int>{};
    for (var i = 0; i < total; i++) {
      if (await File('${partsDir.path}/seg_$i.bin').exists()) existing.add(i);
    }
    var done = existing.length;
    if (done > 0) {
      await _save(task, doneSegments: done, progress: done / total);
    }

    // 4) fMP4 初始化段（#EXT-X-MAP）作为 seg_0
    if (parsed.initSegment != null && !existing.contains(0)) {
      final bytes = await _getBytes(task, parsed.initSegment!);
      await File('${partsDir.path}/seg_0.bin').writeAsBytes(bytes);
      done++;
      await _save(task, doneSegments: done, progress: done / total);
    }
    final offset = parsed.initSegment != null ? 1 : 0;

    // 进度改为「内存 + 节流落盘」，启动周期性落盘保证掉电/强杀时进度不丢太多。
    _startPersistTicker();

    // 5) 并发下载
    final queue = <int>[
      for (var i = 0; i < segments.length; i++)
        if (!existing.contains(i + offset)) i,
    ];
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        if (task.cancelled) throw _CancelException();
        if (cursor >= queue.length) return;
        final i = queue[cursor++];
        final seg = segments[i];
        var bytes = await _downloadSegment(task, seg.url, seg.byteRange);
        // AES-128 解密（key 可能轮换，按 uri 缓存）
        final key = seg.key;
        if (key != null && key.isAes128) {
          final keyBytes = await _fetchKey(task, key.uri!);
          final iv = key.iv != null && key.iv!.isNotEmpty
              ? OfflineAes.ivFromHex(key.iv)
              : OfflineAes.ivFromSequence(parsed.mediaSequence + i);
          bytes = OfflineAes.decryptCbcPkcs7(bytes, keyBytes, iv);
        }
        await File('${partsDir.path}/seg_${i + offset}.bin')
            .writeAsBytes(bytes, flush: false);
        done++;
        _reportProgress(task, doneSegments: done, progress: done / total);
      }
    }

    await Future.wait([for (var i = 0; i < kConcurrency; i++) worker()]);
    if (task.cancelled) throw _CancelException();

    // 6) 合并为单一文件（media_kit 可直接播放 ts / fMP4）
    // 用流式管道拼接：分片可能有几十 MB，一次性 readAsBytes 会造成明显的内存
    // 峰值与 GC 停顿（表现为合并收尾时界面僵一下）。
    final out = File(task.record.localPath);
    final sink = out.openWrite();
    try {
      for (var i = 0; i < total; i++) {
        final f = File('${partsDir.path}/seg_$i.bin');
        if (!await f.exists()) throw StateError('分片 $i 缺失');
        await sink.addStream(f.openRead());
      }
    } finally {
      await sink.close();
    }
    await partsDir.delete(recursive: true).catchError((_) => partsDir);
  }

  /// master playlist → 递归选档；媒体 playlist → 分片表。
  Future<ParsedM3u8> _resolvePlaylist(
    _Task task,
    String url, {
    int depth = 0,
  }) async {
    if (depth > 5) throw StateError('m3u8 嵌套过深');
    final text = await _getText(task, url);
    final parsed = parseM3u8Content(text, url);
    if (!parsed.isMaster) return parsed;
    final variant = pickVariant(text, url);
    if (variant == null) throw StateError('主播放列表没有可用子列表');
    return _resolvePlaylist(task, variant, depth: depth + 1);
  }

  Future<String> _getText(_Task task, String url) async {
    final resp = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
      cancelToken: task.cancelToken,
    );
    return resp.data ?? '';
  }

  Future<List<int>> _fetchKey(_Task task, String url) async {
    final cached = task.keys[url];
    if (cached != null) return cached;
    final bytes = await _getBytes(task, url);
    task.keys[url] = bytes;
    return bytes;
  }

  Future<List<int>> _getBytes(
    _Task task,
    String url, {
    Map<String, String>? headers,
  }) async {
    for (var attempt = 0; attempt < kMaxRetries; attempt++) {
      if (task.cancelled) throw _CancelException();
      try {
        final resp = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes, headers: headers),
          cancelToken: task.cancelToken,
        );
        return resp.data ?? const [];
      } on _CancelException {
        rethrow;
      } catch (e) {
        if (attempt == kMaxRetries - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
      }
    }
    throw StateError('下载失败：$url');
  }

  /// 单个分片下载：优先按 byteRange；否则探测大小，>512KB 时切 4 块并发。
  Future<List<int>> _downloadSegment(
    _Task task,
    String url,
    String? byteRange,
  ) async {
    if (byteRange != null) {
      final r = _parseRange(byteRange);
      final end = r.end ?? '';
      return _getBytes(task, url, headers: {'Range': 'bytes=${r.start}-$end'});
    }
    // 探测：Range: bytes=0-0
    final probe = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Range': 'bytes=0-0'},
      ),
      cancelToken: task.cancelToken,
    );
    // 服务器忽略 Range（200）：body 已是完整内容，直接复用，避免下两遍
    if (probe.statusCode == 200) return probe.data ?? const [];
    final length = _contentRangeTotal(probe);
    if (length == null || length <= kRangeChunkThreshold) {
      return _getBytes(task, url);
    }
    return _downloadByRanges(task, url, length);
  }

  Future<List<int>> _downloadByRanges(
    _Task task,
    String url,
    int length,
  ) async {
    final chunk = (length / kRangeChunkCount).ceil();
    final futures = <Future<MapEntry<int, List<int>>>>[];
    for (var i = 0; i < kRangeChunkCount; i++) {
      final start = i * chunk;
      if (start >= length) break;
      final end = (start + chunk - 1).clamp(0, length - 1);
      futures.add(
        _getBytes(
          task,
          url,
          headers: {'Range': 'bytes=$start-$end'},
        ).then((b) => MapEntry(start, b)),
      );
    }
    final parts = await Future.wait(futures);
    parts.sort((a, b) => a.key.compareTo(b.key));
    final out = <int>[];
    for (final p in parts) {
      out.addAll(p.value);
    }
    return out;
  }

  ({int start, int? end}) _parseRange(String br) {
    if (br.contains('@')) {
      final p = br.split('@');
      final length = int.parse(p[0]);
      final start = int.parse(p[1]);
      return (start: start, end: start + length - 1);
    }
    final p = br.split('-');
    final start = int.parse(p[0]);
    final end = p.length > 1 && p[1].isNotEmpty ? int.parse(p[1]) : null;
    return (start: start, end: end);
  }

  int? _contentRangeTotal(Response<List<int>> resp) {
    final cr = resp.headers.value('content-range');
    if (cr == null) return null;
    final m = RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(cr);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 文件名安全化：保留中文/字母/数字/下划线/连字符，其余替换。
  String _safe(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5\-]'), '_');
    final trimmed = cleaned.replaceAll(RegExp(r'_+'), '_');
    if (trimmed.isEmpty) return 'video';
    return trimmed.length <= 40 ? trimmed : trimmed.substring(0, 40);
  }
}

class _Task {
  final String key;
  OfflineRecord record;
  final CancelToken cancelToken = CancelToken();
  final Map<String, List<int>> keys = {};
  bool cancelled = false;

  _Task({required this.key, required this.record});

  void cancel() {
    cancelled = true;
    if (!cancelToken.isCancelled) cancelToken.cancel('user');
  }
}

class _CancelException implements Exception {}

extension _RecCopy on OfflineRecord {
  OfflineRecord copyWith({
    DownloadStatus? status,
    double? progress,
    int? doneSegments,
    int? totalSegments,
    int? sizeBytes,
    String? error,
    String? container,
  }) => OfflineRecord(
    source: source,
    id: id,
    episodeIndex: episodeIndex,
    title: title,
    episodeTitle: episodeTitle,
    coverUrl: coverUrl,
    originalUrl: originalUrl,
    localPath: localPath,
    container: container ?? this.container,
    totalSegments: totalSegments ?? this.totalSegments,
    doneSegments: doneSegments ?? this.doneSegments,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    error: error,
    createdAt: createdAt,
    totalEpisodes: totalEpisodes,
  );
}
