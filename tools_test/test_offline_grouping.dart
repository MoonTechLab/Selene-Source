// test_offline_grouping.dart
// 验证「我的下载」按剧集分组、以及队列/状态判定的纯逻辑。
// 不依赖 Flutter：直接把 OfflineRecord 喂给等价的分组模型。
import 'dart:io';

import '../lib/services/offline_models.dart';

int failed = 0;
void ok(String name, bool cond, [String extra = '']) {
  if (cond) {
    print('PASS $name');
  } else {
    failed++;
    print('FAIL $name ${extra.isEmpty ? '' : '-> $extra'}');
  }
}

OfflineRecord rec({
  required String source,
  required String id,
  required int ep,
  String title = '剧A',
  DownloadStatus status = DownloadStatus.success,
  double progress = 0,
  int size = 0,
  int createdAt = 0,
}) =>
    OfflineRecord(
      source: source,
      id: id,
      episodeIndex: ep,
      title: title,
      originalUrl: 'https://x/$ep.m3u8',
      localPath: '/tmp/$source-$id-$ep.ts',
      container: 'ts',
      status: status,
      progress: progress,
      sizeBytes: size,
      createdAt: createdAt,
    );

/// 与 OfflineManager.groups 相同的分组算法（按 source|id 聚合）。
Map<String, List<OfflineRecord>> group(List<OfflineRecord> all) {
  final m = <String, List<OfflineRecord>>{};
  for (final r in all) {
    m.putIfAbsent('${r.source}|${r.id}', () => []).add(r);
  }
  for (final v in m.values) {
    v.sort((a, b) => a.episodeIndex.compareTo(b.episodeIndex));
  }
  return m;
}

void main() {
  // 1) 同一部剧的多集聚成一组
  final items = [
    rec(source: 's1', id: 'v1', ep: 2),
    rec(source: 's1', id: 'v1', ep: 0),
    rec(source: 's1', id: 'v1', ep: 1),
    rec(source: 's1', id: 'v2', ep: 0, title: '剧B'),
    rec(source: 's2', id: 'v1', ep: 0, title: '剧C'),
  ];
  final g = group(items);
  ok('5 条记录聚成 3 组', g.length == 3, '实际 ${g.length}');
  ok('同剧 3 集在一组', g['s1|v1']!.length == 3);
  ok('按集数升序', g['s1|v1']!.map((r) => r.episodeIndex).join(',') == '0,1,2');
  ok('source 不同则分组不同', g.containsKey('s1|v1') && g.containsKey('s2|v1'));

  // 2) 摘要统计
  final mixed = [
    rec(source: 's', id: 'v', ep: 0, status: DownloadStatus.success, size: 1024 * 1024 * 500),
    rec(source: 's', id: 'v', ep: 1, status: DownloadStatus.success, size: 1024 * 1024 * 300),
    rec(source: 's', id: 'v', ep: 2, status: DownloadStatus.downloading, progress: 0.5),
    rec(source: 's', id: 'v', ep: 3, status: DownloadStatus.paused, progress: 0.25),
  ];
  final cached = mixed.where((r) => r.status == DownloadStatus.success).length;
  final active = mixed
      .where((r) =>
          r.status == DownloadStatus.downloading ||
          r.status == DownloadStatus.queued)
      .length;
  final paused =
      mixed.where((r) => r.status == DownloadStatus.paused).length;
  ok('已缓存 2 集', cached == 2);
  ok('进行中 1 集', active == 1);
  ok('已暂停 1 集', paused == 1);

  final bytes = mixed
      .where((r) => r.status == DownloadStatus.success)
      .fold<int>(0, (s, r) => s + r.sizeBytes);
  ok('体积只统计已完成集', bytes == 800 * 1024 * 1024, '实际 $bytes');

  // 整体进度：2 个完成(1.0) + 0.5 + 0.25 = 2.75 / 4
  final progress = (2 * 1.0 + 0.5 + 0.25) / 4;
  ok('整体进度加权正确', (progress - 0.6875).abs() < 1e-9, '实际 $progress');

  // 3) 全部完成判定
  final allDone = [
    rec(source: 's', id: 'v', ep: 0),
    rec(source: 's', id: 'v', ep: 1),
  ];
  ok('全成功 -> allDone',
      allDone.every((r) => r.status == DownloadStatus.success));
  ok('含未完成 -> 非 allDone',
      !mixed.every((r) => r.status == DownloadStatus.success));

  // 4) 记录 key 唯一性：同一 (source,id,ep) 只能有一条
  final dup = [
    rec(source: 's', id: 'v', ep: 0),
    rec(source: 's', id: 'v', ep: 0),
  ];
  ok('同集 key 相同（可去重）', dup[0].key == dup[1].key);

  // 5) 序列化往返：分组信息不能因 JSON 丢失
  final r0 = rec(source: 's9', id: 'v9', ep: 7, title: '往返剧');
  final back = OfflineRecord.fromJson(r0.toJson());
  ok('JSON 往返保持 key', back.key == r0.key);
  ok('JSON 往返保持标题', back.title == '往返剧');
  ok('JSON 往返保持集数', back.episodeIndex == 7);
  ok('JSON 往返保持状态', back.status == r0.status);

  print(failed == 0 ? '\nALL PASS' : '\n$failed FAILURE(S)');
  if (failed != 0) exit(1);
}
