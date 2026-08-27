import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/favorite_item.dart';
import '../widgets/video_card.dart';
import '../models/play_record.dart';
import '../models/video_info.dart';
import '../services/page_cache_service.dart';
import '../utils/device_utils.dart';
import '../utils/font_utils.dart';
import 'video_menu_bottom_sheet.dart';
import 'shimmer_effect.dart';

class FavoritesGrid extends StatefulWidget {
  final Function(PlayRecord) onVideoTap;
  final Function(VideoInfo, VideoMenuAction)? onGlobalMenuAction;

  const FavoritesGrid({
    super.key,
    required this.onVideoTap,
    this.onGlobalMenuAction,
  });

  @override
  State<FavoritesGrid> createState() => _FavoritesGridState();

  /// 静态方法：刷新收藏夹数据
  static Future<void> refreshFavorites() async {
    await _FavoritesGridState._currentInstance?._refreshDataInBackground();
  }

  /// 静态方法：从UI中移除指定的收藏项目
  static void removeFavoriteFromUI(String source, String id) {
    _FavoritesGridState._currentInstance?.removeFavoriteFromUI(source, id);
  }
}

class _FavoritesGridState extends State<FavoritesGrid>
    with TickerProviderStateMixin {
  List<FavoriteItem> _favorites = [];
  List<PlayRecord> _playRecords = [];
  bool _isLoading = true;
  String? _errorMessage;
  final PageCacheService _cacheService = PageCacheService();

  // 静态变量存储当前实例
  static _FavoritesGridState? _currentInstance;

  @override
  void initState() {
    super.initState();

    // 设置当前实例
    _currentInstance = this;

    _loadData();
  }

  @override
  void dispose() {
    // 清除当前实例引用
    if (_currentInstance == this) {
      _currentInstance = null;
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 直接使用统一的获取方法（内部已包含缓存检查和异步刷新）
      await Future.wait([
        _loadFavorites(),
        _loadPlayRecords(),
      ]);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 后台刷新数据
  Future<void> _refreshDataInBackground() async {
    try {
      // 分别刷新收藏夹和播放记录数据
      final futures = <Future>[];

      // 刷新收藏夹数据
      futures.add(_refreshFavorites());

      // 刷新播放记录数据
      futures.add(_refreshPlayRecords());

      await Future.wait(futures);
    } catch (e) {
      // 后台刷新失败，静默处理，保持原有数据
    }
  }

  /// 刷新收藏夹数据
  Future<void> _refreshFavorites() async {
    try {
      if (!mounted) return;
      // 刷新缓存数据
      await _cacheService.refreshFavorites(context);
      if (!mounted) return;

      // 重新获取收藏夹数据
      final result = await _cacheService.getFavorites(context);
      if (!mounted) return;

      if (result.success && result.data != null) {
        // 只有当新数据与当前数据不同时才更新UI
        if (_favorites.length != result.data!.length ||
            !_isSameFavorites(_favorites, result.data!)) {
          setState(() {
            _favorites = result.data!;
          });
        }
      }
      // 如果刷新失败，保持原有数据不变
    } catch (e) {
      // 刷新失败，静默处理，保持原有数据
    }
  }

  /// 刷新播放记录数据
  Future<void> _refreshPlayRecords() async {
    try {
      if (!mounted) return;
      final cachedRecordsResult =
          await _cacheService.getPlayRecordsDirect(context);
      if (!mounted) return;
      if (cachedRecordsResult.success && cachedRecordsResult.data != null) {
        final cachedRecords = cachedRecordsResult.data!;
        // 只有当新数据与当前数据不同时才更新UI
        if (_playRecords.length != cachedRecords.length ||
            !_isSamePlayRecords(_playRecords, cachedRecords)) {
          setState(() {
            _playRecords = cachedRecords;
          });
        }
      }
    } catch (e) {
      // 静默处理错误，保持原有数据
    }
  }

  /// 比较两个收藏夹列表是否相同
  bool _isSameFavorites(List<FavoriteItem> list1, List<FavoriteItem> list2) {
    if (list1.length != list2.length) return false;

    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id ||
          list1[i].source != list2[i].source ||
          list1[i].saveTime != list2[i].saveTime) {
        return false;
      }
    }
    return true;
  }

  /// 比较两个播放记录列表是否相同
  bool _isSamePlayRecords(List<PlayRecord> list1, List<PlayRecord> list2) {
    if (list1.length != list2.length) return false;

    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id ||
          list1[i].source != list2[i].source ||
          list1[i].saveTime != list2[i].saveTime) {
        return false;
      }
    }
    return true;
  }

  /// 从UI中移除指定的收藏项目（供外部调用）
  void removeFavoriteFromUI(String source, String id) {
    if (!mounted) return;

    setState(() {
      _favorites.removeWhere(
          (favorite) => favorite.source == source && favorite.id == id);
    });
  }

  Future<void> _loadFavorites() async {
    try {
      if (!mounted) return;
      // 使用缓存服务获取数据
      final result = await _cacheService.getFavorites(context);
      if (!mounted) return;

      if (result.success && result.data != null) {
        setState(() {
          _favorites = result.data!;
        });
      } else {
        throw Exception(result.errorMessage ?? '获取收藏夹失败');
      }
    } catch (e) {
      throw Exception('获取收藏夹失败: $e');
    }
  }

  Future<void> _loadPlayRecords() async {
    try {
      if (!mounted) return;
      // 使用缓存服务获取数据
      final result = await _cacheService.getPlayRecords(context);
      if (!mounted) return;

      if (result.success && result.data != null) {
        setState(() {
          _playRecords = result.data!;
        });
      } else {
        throw Exception(result.errorMessage ?? '获取播放记录失败');
      }
    } catch (e) {
      throw Exception('获取播放记录失败: $e');
    }
  }

  PlayRecord _favoriteToPlayRecord(FavoriteItem favorite) {
    // 查找匹配的播放记录
    try {
      final matchingPlayRecord = _playRecords.firstWhere(
        (record) =>
            record.source == favorite.source && record.id == favorite.id,
      );
      // 如果有匹配的播放记录，使用播放记录的数据
      return matchingPlayRecord;
    } catch (e) {
      // 如果没有匹配的播放记录，使用收藏夹的默认数据
      return PlayRecord(
        id: favorite.id,
        source: favorite.source,
        title: favorite.title,
        cover: favorite.cover,
        year: favorite.year,
        sourceName: favorite.sourceName,
        totalEpisodes: favorite.totalEpisodes,
        index: 0, // 0表示没有播放记录
        playTime: 0, // 未播放
        totalTime: 0, // 未知总时长
        saveTime: favorite.saveTime,
        searchTitle: favorite.title, // 使用标题作为搜索标题
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_favorites.isEmpty) {
      return _buildEmptyState();
    }

    return _buildFavoritesGrid();
  }

  Widget _buildLoadingState() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF27ae60),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 平板模式根据宽度动态展示6～9列，手机模式3列
          final int crossAxisCount = DeviceUtils.getTabletColumnCount(context);
          final isTablet = DeviceUtils.isTablet(context);

          // 计算每列的宽度
          final double screenWidth = constraints.maxWidth;
          const double padding = 16.0; // 左右padding
          const double spacing = 12.0; // 列间距
          final double availableWidth = screenWidth -
              (padding * 2) -
              (spacing * (crossAxisCount - 1)); // 减去padding和间距
          // 确保最小宽度，防止负宽度约束
          const double minItemWidth = 80.0; // 最小项目宽度
          final double calculatedItemWidth = availableWidth / crossAxisCount;
          final double itemWidth = math.max(calculatedItemWidth, minItemWidth);
          final double itemHeight = itemWidth * 2.0; // 增加高度比例，确保有足够空间避免溢出

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: itemWidth / itemHeight, // 精确计算宽高比
              crossAxisSpacing: spacing, // 列间距
              mainAxisSpacing: isTablet ? 0 : 16, // 行间距
            ),
            itemCount: isTablet ? crossAxisCount * 2 : 6, // 平板显示2行，手机显示6个骨架卡片
            itemBuilder: (context, index) {
              return _buildSkeletonCard(itemWidth);
            },
          );
        },
      ),
    );
  }

  /// 构建骨架卡片
  Widget _buildSkeletonCard(double width) {
    final double height = width * 1.4; // 保持与VideoCard相同的比例

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 封面骨架
        ShimmerEffect(
          width: width,
          height: height,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 4),
        // 标题骨架
        Center(
          child: ShimmerEffect(
            width: width * 0.8,
            height: 12,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 2),
        // 源名称骨架
        Center(
          child: ShimmerEffect(
            width: width * 0.6,
            height: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 80,
            color: Color(0xFFbdc3c7),
          ),
          const SizedBox(height: 24),
          Text(
            '加载失败',
            style: FontUtils.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF7f8c8d),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? '未知错误',
            style: FontUtils.poppins(
              fontSize: 14,
              color: const Color(0xFF95a5a6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadFavorites,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27ae60),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              '重试',
              style: FontUtils.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 120.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.favorite_border,
              size: 80,
              color: Color(0xFFbdc3c7),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无收藏内容',
              style: FontUtils.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF7f8c8d),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '您收藏的视频将显示在这里',
              style: FontUtils.poppins(
                fontSize: 14,
                color: const Color(0xFF95a5a6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesGrid() {
    return RefreshIndicator(
      onRefresh: _loadFavorites,
      color: const Color(0xFF27ae60),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 平板模式根据宽度动态展示6～9列，手机模式3列
          final int crossAxisCount = DeviceUtils.getTabletColumnCount(context);
          final isTablet = DeviceUtils.isTablet(context);

          // 计算每列的宽度
          final double screenWidth = constraints.maxWidth;
          const double padding = 16.0; // 左右padding
          const double spacing = 12.0; // 列间距
          final double availableWidth = screenWidth -
              (padding * 2) -
              (spacing * (crossAxisCount - 1)); // 减去padding和间距
          // 确保最小宽度，防止负宽度约束
          const double minItemWidth = 80.0; // 最小项目宽度
          final double calculatedItemWidth = availableWidth / crossAxisCount;
          final double itemWidth = math.max(calculatedItemWidth, minItemWidth);
          final double itemHeight = itemWidth * 2.0; // 增加高度比例，确保有足够空间避免溢出

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: itemWidth / itemHeight, // 精确计算宽高比
              crossAxisSpacing: spacing, // 列间距
              mainAxisSpacing: isTablet ? 0 : 16, // 行间距
            ),
            itemCount: _favorites.length,
            itemBuilder: (context, index) {
              final favorite = _favorites[index];
              final playRecord = _favoriteToPlayRecord(favorite);

              return VideoCard(
                videoInfo: VideoInfo.fromPlayRecord(playRecord),
                onTap: () => widget.onVideoTap(playRecord),
                from: 'favorite', // 统一设置为收藏场景
                cardWidth: itemWidth, // 传递计算出的宽度
                onGlobalMenuAction: widget.onGlobalMenuAction != null
                    ? (action) => widget.onGlobalMenuAction!(
                        VideoInfo.fromPlayRecord(playRecord), action)
                    : null,
                isFavorited: true, // 收藏页面默认已收藏
              );
            },
          );
        },
      ),
    );
  }
}
