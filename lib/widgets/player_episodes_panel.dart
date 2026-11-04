import 'package:flutter/material.dart';
import '../services/offline_manager.dart';
import '../utils/device_utils.dart';

class PlayerEpisodesPanel extends StatefulWidget {
  final ThemeData theme;
  final List<String> episodes;
  final List<String> episodesTitles;
  final int currentEpisodeIndex;
  final bool isReversed;
  final Function(int) onEpisodeTap;
  final VoidCallback onToggleOrder;
  final int crossAxisCount;

  /// 某一集的缓存状态（供每集右下角画角标）。
  final EpisodeCacheState Function(int episodeIndex)? cacheStateOf;

  /// 点击某一集的缓存按钮。
  final void Function(int episodeIndex)? onCacheTap;

  /// 点击「缓存全集」。
  final VoidCallback? onCacheAll;

  /// 已缓存的集数 / 总集数，用于标题栏摘要。
  final int cachedCount;

  const PlayerEpisodesPanel({
    super.key,
    required this.theme,
    required this.episodes,
    required this.episodesTitles,
    required this.currentEpisodeIndex,
    required this.isReversed,
    required this.onEpisodeTap,
    required this.onToggleOrder,
    this.crossAxisCount = 2,
    this.cacheStateOf,
    this.onCacheTap,
    this.onCacheAll,
    this.cachedCount = 0,
  });

  @override
  State<PlayerEpisodesPanel> createState() => _PlayerEpisodesPanelState();
}

class _PlayerEpisodesPanelState extends State<PlayerEpisodesPanel> {
  final GlobalKey _gridKey = GlobalKey();
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToCurrent();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (_gridKey.currentContext == null) return;

    final gridBox = _gridKey.currentContext!.findRenderObject() as RenderBox;

    final targetIndex = widget.isReversed
        ? widget.episodes.length - 1 - widget.currentEpisodeIndex
        : widget.currentEpisodeIndex;

    final crossAxisCount = widget.crossAxisCount;
    const mainAxisSpacing = 12.0;
    final childAspectRatio = widget.crossAxisCount == 4 
        ? 2.2 
        : (widget.crossAxisCount == 3 ? 2.0 : 3.0);

    final itemWidth =
        (gridBox.size.width - (crossAxisCount - 1) * 12) / crossAxisCount;
    final itemHeight = itemWidth / childAspectRatio;

    final row = (targetIndex / crossAxisCount).floor();
    final offset = row * (itemHeight + mainAxisSpacing);

    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1c1c1e) : Colors.white,
      ),
      child: Column(
        children: [
          // 标题和关闭按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '选集 (${widget.episodes.length})',
                        style: widget.theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.cachedCount > 0)
                        Text(
                          '已缓存 ${widget.cachedCount} 集',
                          style: widget.theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF22c55e),
                          ),
                        ),
                    ],
                  ),
                ),
                // 一键缓存全集
                if (widget.onCacheAll != null)
                  TextButton.icon(
                    onPressed: widget.onCacheAll,
                    icon: const Icon(Icons.download_for_offline_outlined,
                        size: 18),
                    label: const Text('缓存全集'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // 集数网格
          // 包 AnimatedBuilder：面板在模态框里，外层的 setState 传不进来，
          // 必须自己订阅 OfflineManager 才能在下载进度变化时刷新角标。
          Expanded(
            child: AnimatedBuilder(
              animation: OfflineManager(),
              builder: (context, _) => GridView.builder(
                key: _gridKey,
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: widget.crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: widget.crossAxisCount == 4
                      ? 2.2
                      : (widget.crossAxisCount == 3 ? 2.0 : 3.0),
                ),
                itemCount: widget.episodes.length,
                itemBuilder: (context, index) {
                  final episodeIndex = widget.isReversed
                      ? widget.episodes.length - 1 - index
                      : index;
                final isCurrentEpisode =
                    episodeIndex == widget.currentEpisodeIndex;

                String episodeTitle = '';
                if (widget.episodesTitles.isNotEmpty &&
                    episodeIndex < widget.episodesTitles.length) {
                  episodeTitle = widget.episodesTitles[episodeIndex];
                } else {
                  episodeTitle = '第${episodeIndex + 1}集';
                }

                return _EpisodePanelItemWithHover(
                  isCurrentEpisode: isCurrentEpisode,
                  isDarkMode: isDarkMode,
                  episodeTitle: episodeTitle,
                  onTap: isCurrentEpisode
                      ? null
                      : () => widget.onEpisodeTap(episodeIndex),
                  cacheState:
                      widget.cacheStateOf?.call(episodeIndex) ??
                          EpisodeCacheState.none,
                  onCacheTap: widget.onCacheTap == null
                      ? null
                      : () => widget.onCacheTap!(episodeIndex),
                );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// 带 hover 效果的选集面板项（PC 端专用）
class _EpisodePanelItemWithHover extends StatefulWidget {
  final bool isCurrentEpisode;
  final bool isDarkMode;
  final String episodeTitle;
  final VoidCallback? onTap;
  final EpisodeCacheState cacheState;
  final VoidCallback? onCacheTap;

  const _EpisodePanelItemWithHover({
    required this.isCurrentEpisode,
    required this.isDarkMode,
    required this.episodeTitle,
    this.onTap,
    this.cacheState = EpisodeCacheState.none,
    this.onCacheTap,
  });

  @override
  State<_EpisodePanelItemWithHover> createState() => _EpisodePanelItemWithHoverState();
}

class _EpisodePanelItemWithHoverState extends State<_EpisodePanelItemWithHover> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: (DeviceUtils.isPC() && !widget.isCurrentEpisode) 
          ? SystemMouseCursors.click 
          : MouseCursor.defer,
      onEnter: (_) {
        if (DeviceUtils.isPC() && !widget.isCurrentEpisode) {
          setState(() => _isHovering = true);
        }
      },
      onExit: (_) {
        if (DeviceUtils.isPC()) {
          setState(() => _isHovering = false);
        }
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isCurrentEpisode
                ? Colors.green.withValues(alpha: 0.2)
                : (_isHovering && DeviceUtils.isPC()
                    ? (widget.isDarkMode 
                        ? const Color(0xFF1A3D2E)  // 深色模式下的浅绿色
                        : const Color(0xFFE8F5E9))  // 浅色模式下的浅绿色
                    : (widget.isDarkMode ? Colors.grey[800] : Colors.grey[200])),
            borderRadius: BorderRadius.circular(8),
            border: widget.isCurrentEpisode
                ? Border.all(color: Colors.green, width: 2)
                : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Text(
                    widget.episodeTitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isCurrentEpisode
                          ? Colors.green
                          : (widget.isDarkMode ? Colors.white : Colors.black),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              // 右下角缓存入口/状态角标
              if (widget.onCacheTap != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _PanelCacheButton(
                    state: widget.cacheState,
                    isDarkMode: widget.isDarkMode,
                    onTap: widget.cacheState == EpisodeCacheState.downloading
                        ? null
                        : widget.onCacheTap,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选集面板里的缓存按钮：未缓存显示下载图标，已缓存/进行中显示状态色图标。
class _PanelCacheButton extends StatelessWidget {
  final EpisodeCacheState state;
  final bool isDarkMode;
  final VoidCallback? onTap;

  const _PanelCacheButton({
    required this.state,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    Color color;
    String tooltip;
    switch (state) {
      case EpisodeCacheState.cached:
        icon = Icons.download_done;
        color = const Color(0xFF22c55e);
        tooltip = '已缓存';
      case EpisodeCacheState.downloading:
        icon = Icons.downloading;
        color = const Color(0xFF3b82f6);
        tooltip = '下载中';
      case EpisodeCacheState.pending:
        icon = Icons.hourglass_empty;
        color = const Color(0xFFf59e0b);
        tooltip = '排队中';
      case EpisodeCacheState.paused:
        icon = Icons.pause_circle_outline;
        color = const Color(0xFF9ca3af);
        tooltip = '已暂停，点击继续';
      case EpisodeCacheState.error:
        icon = Icons.error_outline;
        color = const Color(0xFFef4444);
        tooltip = '失败，点击重试';
      case EpisodeCacheState.none:
        icon = Icons.download_for_offline_outlined;
        color = isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
        tooltip = '缓存本集';
    }
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
