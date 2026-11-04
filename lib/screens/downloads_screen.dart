// downloads_screen.dart
// 「我的下载」：离线缓存内容，按「剧集」分组展示。
//
// 设计：一部剧一个可展开的分组卡片，折叠时显示封面/剧名/集数摘要/整体进度，
// 展开后是逐集列表（可单集暂停、继续、播放、删除）。
// 这样缓存了十几部剧之后不会变成一条无法阅读的长列表。
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/offline_manager.dart';
import '../services/offline_storage_service.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  /// 已展开的分组 key。默认全部折叠，避免一进来就滚动几屏。
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final mgr = OfflineManager();
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的下载'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => mgr.refresh(),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: mgr,
        builder: (context, _) {
          if (!mgr.isReady) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = mgr.groups;
          if (groups.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有缓存任何视频\n\n在选集界面点击某一集右下角的下载图标，\n或点「缓存全集」批量下载。\n下载完成后无需网络也能观看。',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final g = groups[i];
              return _GroupCard(
                group: g,
                expanded: _expanded.contains(g.key),
                onToggle: () {
                  setState(() {
                    if (!_expanded.remove(g.key)) _expanded.add(g.key);
                  });
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// 一部剧的分组卡片。
class _GroupCard extends StatelessWidget {
  final OfflineGroup group;
  final bool expanded;
  final VoidCallback onToggle;

  const _GroupCard({
    required this.group,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mgr = OfflineManager();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ---- 组头 ----
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  _Cover(url: group.coverUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          group.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          group.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ),
                        if (!group.allDone) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: group.progress <= 0 ? null : group.progress,
                              minHeight: 3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 整组操作：全部暂停 / 继续全部
                  if (group.hasActive)
                    IconButton(
                      tooltip: '全部暂停',
                      icon: const Icon(Icons.pause_circle_outline),
                      onPressed: () => mgr.pauseAll(group.source, group.id),
                    )
                  else
                    IconButton(
                      tooltip: '继续全部',
                      icon: const Icon(Icons.play_circle_outline),
                      onPressed: () => _resumeGroup(context, mgr),
                    ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),

          // ---- 展开后的逐集列表 ----
          if (expanded)
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.02),
              ),
              child: Column(
                children: [
                  for (final r in group.records)
                    _EpisodeRow(rec: r, group: group),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 继续整组：把暂停/失败的集重新入队（已完成的自动跳过）。
  Future<void> _resumeGroup(BuildContext context, OfflineManager mgr) async {
    var n = 0;
    for (final r in group.records) {
      if (r.status == DownloadStatus.success) continue;
      await mgr.resume(r);
      n++;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n == 0 ? '没有需要继续的集' : '已重新加入队列 $n 集')),
      );
    }
  }
}

/// 分组封面：有 URL 就加载网络图，失败/无网时退化成占位块。
class _Cover extends StatelessWidget {
  final String? url;
  const _Cover({required this.url});

  @override
  Widget build(BuildContext context) {
    const w = 44.0;
    const h = 62.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor =
        isDark ? Colors.grey[800] : Colors.grey[300];

    Widget fallback() => Container(
          width: w,
          height: h,
          color: placeholderColor,
          child: Icon(
            Icons.movie_outlined,
            size: 20,
            color: isDark ? Colors.grey[500] : Colors.grey[600],
          ),
        );

    final u = url;
    if (u == null || u.isEmpty) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        u,
        width: w,
        height: h,
        fit: BoxFit.cover,
        // 离线时 network image 必然失败，必须给 errorBuilder，
        // 否则会抛异常并显示红框。
        errorBuilder: (_, __, ___) => fallback(),
        loadingBuilder: (c, child, progress) =>
            progress == null ? child : fallback(),
      ),
    );
  }
}

/// 组内的一集。
class _EpisodeRow extends StatelessWidget {
  final OfflineRecord rec;
  final OfflineGroup group;
  const _EpisodeRow({required this.rec, required this.group});

  @override
  Widget build(BuildContext context) {
    final mgr = OfflineManager();
    final done = rec.status == DownloadStatus.success;
    final theme = Theme.of(context);

    return InkWell(
      onTap: done ? () => _play(context) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${rec.episodeIndex + 1}',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.brightness == Brightness.dark
                      ? Colors.grey[500]
                      : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (rec.episodeTitle?.isNotEmpty ?? false)
                        ? rec.episodeTitle!
                        : '第 ${rec.episodeIndex + 1} 集',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    _statusText(rec),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _statusColor(context, rec),
                    ),
                  ),
                ],
              ),
            ),
            if (done)
              IconButton(
                tooltip: '离线播放',
                icon: const Icon(Icons.play_arrow, size: 20),
                onPressed: () => _play(context),
              )
            else if (rec.status == DownloadStatus.downloading)
              IconButton(
                tooltip: '暂停',
                icon: const Icon(Icons.pause, size: 20),
                onPressed: () =>
                    mgr.pause(rec.source, rec.id, rec.episodeIndex),
              )
            else
              IconButton(
                tooltip: rec.status == DownloadStatus.queued ? '排队中' : '继续',
                icon: Icon(
                  rec.status == DownloadStatus.queued
                      ? Icons.hourglass_empty
                      : Icons.download,
                  size: 20,
                ),
                onPressed: () => mgr.resume(rec),
              ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _confirmDelete(context, mgr),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusText(OfflineRecord rec) {
    switch (rec.status) {
      case DownloadStatus.none:
        return '未开始';
      case DownloadStatus.queued:
        return '排队中';
      case DownloadStatus.downloading:
        return '下载中 ${(rec.progress * 100).floor()}%';
      case DownloadStatus.paused:
        return '已暂停 ${(rec.progress * 100).floor()}%';
      case DownloadStatus.success:
        return '已缓存 ${_fmtSize(rec.sizeBytes)}';
      case DownloadStatus.error:
        return '失败，点击继续重试';
      case DownloadStatus.deleted:
        return '文件已丢失';
    }
  }

  static Color _statusColor(BuildContext context, OfflineRecord rec) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (rec.status) {
      case DownloadStatus.success:
        return const Color(0xFF22c55e);
      case DownloadStatus.error:
        return const Color(0xFFef4444);
      default:
        return isDark ? Colors.grey[400]! : Colors.grey[600]!;
    }
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

  Future<void> _confirmDelete(BuildContext context, OfflineManager mgr) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除缓存'),
        content: Text('确定删除「${group.title}」第 ${rec.episodeIndex + 1} 集的本地文件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await mgr.remove(rec.source, rec.id, rec.episodeIndex);
    }
  }

  void _play(BuildContext context) {
    final local = rec.localPath;
    if (!File(local).existsSync()) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('本地文件已丢失，请重新缓存')));
      return;
    }
    // 复用播放页：player_screen.updateVideoUrl 会优先命中本地缓存
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          source: rec.source,
          id: rec.id,
          title: rec.title,
          initialEpisode: rec.episodeIndex,
        ),
      ),
    );
  }
}
