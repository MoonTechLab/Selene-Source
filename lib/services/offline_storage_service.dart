// offline_storage_service.dart
// 离线缓存索引服务：以 (source,id,episodeIndex) 为键，维护下载记录的 JSON 索引。
// 存于 app 私有目录（path_provider.getApplicationDocumentsDirectory），无需任何存储权限。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_models.dart';

// 对外仍然可以从本文件导入 OfflineRecord / DownloadStatus，保持既有调用方不变。
export 'offline_models.dart';

class OfflineStorageService {
  static final OfflineStorageService _i = OfflineStorageService._();
  factory OfflineStorageService() => _i;
  OfflineStorageService._();

  static const _spKey = 'offline_index_v1';

  Directory? _dir;
  final Map<String, OfflineRecord> _cache = {};
  Future<void> _persistChain = Future<void>.value();

  Future<Directory> get _root async {
    _dir ??= await getApplicationDocumentsDirectory();
    return _dir!;
  }

  Future<String> get downloadsDir async {
    final r = await _root;
    final d = Directory('${r.path}/offline');
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_spKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          final rec = OfflineRecord.fromJson(e as Map<String, dynamic>);
          _cache[rec.key] = rec;
        }
      } catch (_) {}
    }
  }

  List<OfflineRecord> all() =>
      _cache.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  OfflineRecord? get(String source, String id, int episodeIndex) =>
      _cache['$source|$id|$episodeIndex'];

  /// 是否已缓存且可离线播放。
  ///
  /// 纯内存判断，**不做同步磁盘 IO**：本方法被 UI 的 build 每帧调用，
  /// `File.existsSync()` 会变成每帧一次 stat 系统调用，是缓存时界面卡顿的
  /// 主要来源之一。文件真实存在性在 [localPathOf]（异步，调用频率低）里校验。
  bool isCached(String source, String id, int episodeIndex) {
    final r = _cache['$source|$id|$episodeIndex'];
    return r != null && r.status == DownloadStatus.success;
  }

  /// 已缓存则返回本地绝对路径，否则空串（异步校验文件是否仍存在）。
  Future<String> localPathOf(String source, String id, int episodeIndex) async {
    final r = _cache['$source|$id|$episodeIndex'];
    if (r == null || r.status != DownloadStatus.success) return '';
    try {
      if (await File(r.localPath).exists()) return r.localPath;
    } catch (_) {}
    // 索引说成功但文件已被清理（用户手动删除/系统清理）：降级为失效记录。
    _cache[r.key] = r.copyWithStatus(DownloadStatus.deleted);
    unawaited(_persist());
    return '';
  }

  Future<void> _persist() {
    // 串行化写盘：把请求排到队尾，队列空闲时开始真正写入。
    // 这样高频进度不会引发写入风暴，但每一次 flush 都保证「排在我之前的
    // 所有变更都已经落盘」——任务结束时调用的 flush 不会被丢弃。
    final next = _persistChain.then((_) => _writeNow());
    // 吞掉异常，避免一次写失败让后续队列全部中断。
    _persistChain = next.catchError((_) {});
    return next;
  }

  Future<void> _writeNow() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _spKey,
      jsonEncode(_cache.values.map((e) => e.toJson()).toList()),
    );
  }

  /// 更新内存记录。[persist] 为 false 时只改内存不落盘 ——
  /// 下载进度这类高频变化走这条路径，落盘交给下载服务的节流器决定。
  Future<void> upsert(OfflineRecord rec, {bool persist = true}) async {
    _cache[rec.key] = rec;
    if (persist) await _persist();
  }

  /// 立即落盘（供节流器在关键节点调用）。
  Future<void> flush() => _persist();

  Future<void> remove(String source, String id, int episodeIndex) async {
    final key = '$source|$id|$episodeIndex';
    final rec = _cache[key];
    if (rec != null) {
      final f = File(rec.localPath);
      if (await f.exists()) await f.delete().catchError((_) {});
      // 删除分片临时目录
      final segDir = Directory('${rec.localPath}.parts');
      if (await segDir.exists())
        await segDir.delete(recursive: true).catchError((_) {});
    }
    _cache.remove(key);
    await _persist();
  }
}
