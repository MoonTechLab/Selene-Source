import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/search_result.dart';
import '../models/aggregated_search_result.dart';
import '../models/video_info.dart';
import '../services/theme_service.dart';
import '../utils/device_utils.dart';
import '../utils/font_utils.dart';
import 'video_card.dart';
import 'video_menu_bottom_sheet.dart';

/// 聚合搜索结果网格组件
class SearchResultAggGrid extends StatefulWidget {
  final List<SearchResult> results;
  final ThemeService themeService;
  final Function(VideoInfo)? onVideoTap;
  final Function(VideoInfo, VideoMenuAction)? onGlobalMenuAction;
  final Function(SearchResult)? onSourceSelected;
  final bool hasReceivedStart;

  const SearchResultAggGrid({
    super.key,
    required this.results,
    required this.themeService,
    this.onVideoTap,
    this.onGlobalMenuAction,
    this.onSourceSelected,
    required this.hasReceivedStart,
  });

  @override
  State<SearchResultAggGrid> createState() => _SearchResultAggGridState();
}

class _SearchResultAggGridState extends State<SearchResultAggGrid> 
    with AutomaticKeepAliveClientMixin {
  
  // 聚合结果映射，key为聚合键，value为聚合结果
  Map<String, AggregatedSearchResult> _aggregatedResults = {};
  
  // 按添加顺序排列的聚合键列表
  List<String> _orderedKeys = [];
  
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _updateAggregatedResults();
  }

  @override
  void didUpdateWidget(SearchResultAggGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.results != oldWidget.results) {
      _updateAggregatedResults();
    }
  }

  /// 更新聚合结果
  void _updateAggregatedResults() {
    final newAggregatedResults = <String, AggregatedSearchResult>{};
    final newOrderedKeys = <String>[];
    
    for (final result in widget.results) {
      final key = AggregatedSearchResult.generateKey(
        result.title, 
        result.year, 
        result.episodes.length
      );
      
      if (newAggregatedResults.containsKey(key)) {
        // 已存在，添加到现有聚合结果中
        newAggregatedResults[key] = newAggregatedResults[key]!.addResult(result);
      } else {
        // 新的聚合结果
        newAggregatedResults[key] = AggregatedSearchResult.fromSearchResult(result);
        newOrderedKeys.add(key);
      }
    }
    
    setState(() {
      _aggregatedResults = newAggregatedResults;
      _orderedKeys = newOrderedKeys; // 直接使用新的顺序
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin
    
    if (_aggregatedResults.isEmpty && widget.hasReceivedStart) {
      return _buildEmptyState();
    }
    
    if (_aggregatedResults.isEmpty && !widget.hasReceivedStart) {
      return const SizedBox.shrink(); // 搜索开始但未收到start消息时，不显示任何内容
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 平板模式根据宽度动态展示6～9列，手机模式3列
        final int crossAxisCount = DeviceUtils.getTabletColumnCount(context);
        final bool isTablet = DeviceUtils.isTablet(context);
        final double mainAxisSpacing = isTablet ? 0.0 : 16.0; // 平板行间距为0
        
        // 计算每列的宽度
        final double screenWidth = constraints.maxWidth;
        const double padding = 16.0; // 左右padding
        const double spacing = 12.0; // 列间距
        final double availableWidth = screenWidth - (padding * 2) - (spacing * (crossAxisCount - 1)); // 减去padding和间距
        // 确保最小宽度，防止负宽度约束
        const double minItemWidth = 80.0; // 最小项目宽度
        final double calculatedItemWidth = availableWidth / crossAxisCount;
        final double itemWidth = math.max(calculatedItemWidth, minItemWidth);
        final double itemHeight = itemWidth * 2.0; // 增加高度比例，确保有足够空间避免溢出
        
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: itemWidth / itemHeight, // 精确计算宽高比
            crossAxisSpacing: spacing, // 列间距
            mainAxisSpacing: mainAxisSpacing, // 行间距
          ),
          itemCount: _orderedKeys.length,
          itemBuilder: (context, index) {
            final key = _orderedKeys[index];
            final aggregatedResult = _aggregatedResults[key]!;
            final videoInfo = aggregatedResult.toVideoInfo();
            
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: VideoCard(
                key: ValueKey(key), // 使用聚合键作为唯一key
                videoInfo: videoInfo,
                onTap: widget.onVideoTap != null ? () => widget.onVideoTap!(videoInfo) : null,
                from: 'agg', // 标记为聚合卡片
                cardWidth: itemWidth, // 传递计算出的宽度
                onGlobalMenuAction: widget.onGlobalMenuAction != null 
                    ? (action) => widget.onGlobalMenuAction!(videoInfo, action)
                    : null,
                isFavorited: false, // 聚合卡片不显示收藏状态
                originalResults: aggregatedResult.originalResults,
                onSourceSelected: widget.onSourceSelected,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.search_off,
            size: 80,
            color: Color(0xFFbdc3c7),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无搜索结果',
            style: FontUtils.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF7f8c8d),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '请尝试其他关键词',
            style: FontUtils.poppins(
              fontSize: 14,
              color: const Color(0xFF95a5a6),
            ),
          ),
        ],
      ),
    );
  }
}
