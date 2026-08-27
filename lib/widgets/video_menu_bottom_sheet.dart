import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/video_info.dart';
import '../models/douban_movie.dart';
import '../models/bangumi.dart';
import '../services/theme_service.dart';
import '../services/douban_service.dart';
import '../services/bangumi_service.dart';
import '../utils/image_url.dart';
import 'fullscreen_image_viewer.dart';
import '../models/search_result.dart';
import '../utils/font_utils.dart';

/// 判断是否为iOS平台
bool get _isIOS {
  if (kIsWeb) return false;
  try {
    return Platform.isIOS;
  } catch (e) {
    return false;
  }
}

/// 自定义滚动物理，在展开状态下的顶部向下拖拽时触发收起
class CollapsibleScrollPhysics extends ScrollPhysics {
  final bool isAtMaxHeight;
  final VoidCallback? onCollapseTriggered;
  final bool isIOS;

  const CollapsibleScrollPhysics({
    super.parent,
    this.isAtMaxHeight = false,
    this.onCollapseTriggered,
    this.isIOS = false,
  });

  @override
  CollapsibleScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CollapsibleScrollPhysics(
      parent: buildParent(ancestor),
      isAtMaxHeight: isAtMaxHeight,
      onCollapseTriggered: onCollapseTriggered,
      isIOS: isIOS,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // 如果已展开到最大高度且在顶部，向下拖拽时触发收起回调
    // iOS 需要更宽松的条件，因为 bouncing 效果会产生负值
    if (isAtMaxHeight &&
        ((isIOS && position.pixels <= 1.0) || (!isIOS && position.pixels <= 0)) &&
        offset > 0) {
      // 触发收起回调
      if (onCollapseTriggered != null) {
        // 使用 Future.microtask 确保回调在当前帧完成后执行
        Future.microtask(() => onCollapseTriggered!());
      }
      return 0.0; // 不应用滚动物理
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  ScrollPhysics buildParent(ScrollPhysics? ancestor) {
    // 根据平台选择合适的父物理效果
    final parentPhysics = isIOS ? const BouncingScrollPhysics() : const ClampingScrollPhysics();
    return parent?.applyTo(ancestor ?? parentPhysics) ?? parentPhysics;
  }
}

/// 视频菜单选项
enum VideoMenuAction {
  play,
  favorite,
  unfavorite,
  deleteRecord,
  doubanDetail,
  bangumiDetail,
}

/// 视频菜单底部弹窗组件
class VideoMenuBottomSheet extends StatefulWidget {
  final VideoInfo videoInfo;
  final bool isFavorited; // 是否已收藏
  final Function(VideoMenuAction) onActionSelected;
  final VoidCallback onClose;
  final String from; // 来源场景
  final List<SearchResult>? originalResults;
  final Function(SearchResult)? onSourceSelected;

  const VideoMenuBottomSheet({
    super.key,
    required this.videoInfo,
    required this.isFavorited,
    required this.onActionSelected,
    required this.onClose,
    this.from = 'playrecord',
    this.originalResults,
    this.onSourceSelected,
  });

  /// 显示视频菜单底部弹窗（对外公开）
  static void show(
    BuildContext context, {
    required VideoInfo videoInfo,
    required bool isFavorited,
    required Function(VideoMenuAction) onActionSelected,
    String from = 'playrecord',
    List<SearchResult>? originalResults,
    Function(SearchResult)? onSourceSelected,
  }) {
    final transitionController = AnimationController(
      duration: const Duration(milliseconds: 200), // 缩短动画时间到200ms
      vsync: Navigator.of(context),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5), // 添加半透明的遮罩层
      transitionAnimationController: transitionController,
      builder: (context) => VideoMenuBottomSheet(
        videoInfo: videoInfo,
        isFavorited: isFavorited,
        onActionSelected: onActionSelected,
        onClose: () => Navigator.of(context).pop(),
        from: from,
        originalResults: originalResults,
        onSourceSelected: onSourceSelected,
      ),
    ).whenComplete(() {
      // showModalBottomSheet 返回的 Future 在弹窗“开始关闭”（pop 触发）时就完成，
      // 而此时退出动画仍在用这个 controller 播放（约 200ms）。若在这里立即 dispose，
      // 会打断关闭动画并让遮罩层（AnimatedModalBarrier）失效，表现为“菜单无法关闭且可穿透蒙层”。
      // 因此等退出动画真正结束（dismissed）后再释放，避免内存泄漏的同时不破坏关闭流程。
      if (transitionController.status == AnimationStatus.dismissed) {
        transitionController.dispose();
      } else {
        void releaseWhenDismissed(AnimationStatus status) {
          if (status == AnimationStatus.dismissed) {
            transitionController.removeStatusListener(releaseWhenDismissed);
            transitionController.dispose();
          }
        }
        transitionController.addStatusListener(releaseWhenDismissed);
      }
    });
  }

  @override
  State<VideoMenuBottomSheet> createState() => _VideoMenuBottomSheetState();
}

class _VideoMenuBottomSheetState extends State<VideoMenuBottomSheet>
    with TickerProviderStateMixin {
  DoubanMovieDetails? _doubanDetails;
  bool _isLoadingDoubanDetails = false;
  BangumiDetails? _bangumiDetails;
  bool _isLoadingBangumiDetails = false;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollIndicator = false;
  bool _lockInnerScroll = false;
  bool _isDraggingDown = false; // 跟踪当前是否在向下拖拽
  bool _isInCollapsePhase = false; // 跟踪是否处于收起阶段（从最大高度到初始高度）
  late AnimationController _floatAnimationController;
  late AnimationController _transitionAnimationController;
  Animation<double>? _transitionAnimation;
  final GlobalKey _sheetKey = GlobalKey();
  final GlobalKey _fullContentKey = GlobalKey();
  double? _initialSheetHeight;
  double? _currentSheetHeight;
  double _maxSheetHeight = 0.0;
  double? _contentBasedMaxHeight;
  bool _hasInitialHeightCaptured = false;
  // 下拉关闭相关阈值
  final double _dismissDragThreshold = 24.0; // 超过初始高度24px继续下拉则关闭
  double get _dismissVelocityThreshold {
    // iOS 需要更敏感的阈值，因为 bouncing 效果会消耗一些速度
    return _isIOS ? 400.0 : 800.0;
  } // 快速下滑关闭的速度阈值

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 初始化浮动动画控制器 - 使用更流畅的曲线
    _floatAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200), // 缩短浮动动画时间
      vsync: this,
    )..repeat(reverse: true);

    // 初始化过渡动画控制器 - 使用更快的动画
    _transitionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 180), // 缩短到180ms
      vsync: this,
    );

    // 延迟执行初始化操作，避免阻塞动画
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 使用微任务确保动画优先执行
      Future.microtask(() {
        if (mounted) {
          _captureInitialHeight();
        }
      });

      // 延迟加载详情数据，避免影响初始动画
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _loadDoubanDetailsIfNeeded();
          _loadBangumiDetailsIfNeeded();
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在依赖变化时计算最大高度
    _maxSheetHeight = MediaQuery.of(context).size.height * 0.8;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _floatAnimationController.dispose();
    _transitionAnimationController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;

    if (_showScrollIndicator && _scrollController.hasClients && _scrollController.offset > 10) {
      setState(() {
        _showScrollIndicator = false;
      });
    }
  }

  void _captureInitialHeight() {
    try {
      // 捕获整个弹窗的高度作为初始高度
      final renderBox = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
      final height = renderBox?.size.height;
      if (height != null && mounted && !_hasInitialHeightCaptured) {
        // 延迟设置状态，避免在动画期间重建
        Future.microtask(() {
          if (mounted) {
            setState(() {
              _initialSheetHeight = height;
              _currentSheetHeight = height;
              _hasInitialHeightCaptured = true;
            });
          }
        });
      }
    } catch (e) {
      print('捕获初始高度失败: $e');
    }
  }

  void _calculateContentBasedMaxHeight() {
    if (!mounted) return;

    try {
      // 计算包含豆瓣详情的完整内容高度
      final renderBox = _fullContentKey.currentContext?.findRenderObject() as RenderBox?;
      final contentHeight = renderBox?.size.height;
      
      if (contentHeight != null && mounted) {
        // 加上顶部拖拽指示器和一些边距
        final totalContentHeight = contentHeight + 20; // 8(top margin) + 4(indicator height) + 8(bottom margin)
        
        // 取内容高度和屏幕90%的较小值作为最大高度
        final screenBasedMaxHeight = MediaQuery.of(context).size.height * 0.8;
        final effectiveMaxHeight = (totalContentHeight < screenBasedMaxHeight) 
            ? totalContentHeight 
            : screenBasedMaxHeight;
            
        setState(() {
          _contentBasedMaxHeight = effectiveMaxHeight;
        });
      }
    } catch (e) {
      print('计算内容最大高度失败: $e');
    }
  }

  /// 处理在顶部向下拖拽触发的收起
  void _handleCollapseFromScroll() {
    if (!mounted) return;

    if (_initialSheetHeight != null) {
      // iOS 上进入二段式收起阶段
      if (_isIOS) {
        setState(() {
          _isInCollapsePhase = true;
        });
      }
      _animateToHeight(_initialSheetHeight!);
      setState(() {
        _showScrollIndicator = true;
      });
    }
  }

  /// 执行平滑过渡动画
  void _animateToHeight(double targetHeight) {
    if (!mounted) return;
    if (_currentSheetHeight == null || _initialSheetHeight == null) return;

    final startHeight = _currentSheetHeight!;

    // 如果已经在目标高度，不需要动画
    if ((startHeight - targetHeight).abs() < 1.0) return;

    // 使用更高效的动画曲线
    _transitionAnimation = Tween<double>(
      begin: startHeight,
      end: targetHeight,
    ).animate(CurvedAnimation(
      parent: _transitionAnimationController,
      curve: Curves.easeOutQuart, // 使用更平滑的曲线
    ));

    _transitionAnimation!.addListener(() {
      if (mounted) {
        setState(() {
          _currentSheetHeight = _transitionAnimation!.value;
        });
      }
    });

    _transitionAnimationController.reset();
    _transitionAnimationController.forward();
  }

  /// 更新拖拽高度 - 用于更高效的拖拽处理
  void _updateDragHeight(double newHeight, double effectiveMaxHeight, bool isDraggingDown) {
    if (!mounted) return;

    // 限制高度在有效范围内
    final clampedHeight = newHeight.clamp(_initialSheetHeight!, effectiveMaxHeight);

    // 只在高度有显著变化时更新UI
    final currentHeight = _currentSheetHeight ?? _initialSheetHeight!;
    if ((currentHeight - clampedHeight).abs() > 0.5) {
      setState(() {
        _currentSheetHeight = clampedHeight;
        _showScrollIndicator = (clampedHeight - _initialSheetHeight!) < 20.0;
      });
    }
  }


  /// 如果有豆瓣ID，则加载豆瓣详情
  void _loadDoubanDetailsIfNeeded() {
    final doubanId = widget.videoInfo.doubanId;
    if (doubanId != null && doubanId.isNotEmpty && doubanId != "0") {
      _loadDoubanDetails(doubanId);
    }
  }

  /// 如果有 Bangumi ID，则加载 Bangumi 详情
  void _loadBangumiDetailsIfNeeded() {
    final bangumiId = widget.videoInfo.bangumiId;
    if (bangumiId != null && bangumiId > 0) {
      _loadBangumiDetails(bangumiId.toString());
    }
  }

  /// 加载豆瓣详情
  Future<void> _loadDoubanDetails(String doubanId) async {
    if (!mounted) return;
    if (_isLoadingDoubanDetails) return;
    
    setState(() {
      _isLoadingDoubanDetails = true;
    });

    try {
      final response = await DoubanService.getDoubanDetails(
        context,
        doubanId: doubanId,
      );
      if (!mounted) return;

      if (response.success && response.data != null) {
        setState(() {
          _doubanDetails = response.data;
          // 只有在初始高度时才显示箭头提示
          _showScrollIndicator = _hasInitialHeightCaptured && 
              (_currentSheetHeight == null || _currentSheetHeight == _initialSheetHeight);
        });
        
        // 豆瓣详情加载完成后，重新计算基于内容的最大高度
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _calculateContentBasedMaxHeight();
        });
      }
    } catch (e) {
      // 静默处理错误
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingDoubanDetails = false;
      });
    }
  }

  /// 加载 Bangumi 详情
  Future<void> _loadBangumiDetails(String bangumiId) async {
    if (!mounted) return;
    if (_isLoadingBangumiDetails) return;
    
    setState(() {
      _isLoadingBangumiDetails = true;
    });

    try {
      final response = await BangumiService.getBangumiDetails(
        context,
        bangumiId: bangumiId,
      );
      if (!mounted) return;

      if (response.success && response.data != null) {
        setState(() {
          _bangumiDetails = response.data;
          // 只有在初始高度时才显示箭头提示
          _showScrollIndicator = _hasInitialHeightCaptured && 
              (_currentSheetHeight == null || _currentSheetHeight == _initialSheetHeight);
        });
        
        // Bangumi 详情加载完成后，重新计算基于内容的最大高度
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _calculateContentBasedMaxHeight();
        });
      }
    } catch (e) {
      // 静默处理错误
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingBangumiDetails = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return FutureBuilder<String>(
          future: getImageUrl(widget.videoInfo.cover, widget.videoInfo.source),
          builder: (context, snapshot) {
            final String thumbUrl = snapshot.data ?? widget.videoInfo.cover;
            final headers = getImageRequestHeaders(thumbUrl, widget.videoInfo.source);
            
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                // 拖动开始时，确保当前高度存在
                if ((_doubanDetails != null || _bangumiDetails != null) && _initialSheetHeight != null && _currentSheetHeight == null) {
                  _currentSheetHeight = _initialSheetHeight;
                }
              },
              onPanUpdate: (details) {
                if ((_doubanDetails != null || _bangumiDetails != null) && _initialSheetHeight != null) {
                  // 检查是否应该响应拖拽
                  final isAtMaxHeight = _currentSheetHeight != null && _currentSheetHeight! >= (_contentBasedMaxHeight ?? _maxSheetHeight) - 1;
                  final isScrollAtTop = !_scrollController.hasClients || _scrollController.offset <= 0;
                  final isDraggingUp = details.delta.dy < 0; // 向上拖拽
                  final isDraggingDown = details.delta.dy > 0; // 向下拖拽

                  // 更新拖拽方向状态，减少setState调用
                  if (_isDraggingDown != isDraggingDown) {
                    _isDraggingDown = isDraggingDown;
                  }

                  // 如果已经在最大高度且内容可滚动且不在顶部，并且是向上拖拽，则不响应
                  if (isAtMaxHeight && _scrollController.hasClients && !isScrollAtTop && isDraggingUp) {
                    return;
                  }

                  // 在已展开+到顶+向下拖拽时，锁定内部滚动，让外层接管
                  final shouldLockInnerScroll = isAtMaxHeight && isScrollAtTop && isDraggingDown;
                  if (shouldLockInnerScroll && !_lockInnerScroll) {
                    _lockInnerScroll = true;
                    _isInCollapsePhase = true; // 开始收起阶段
                  }

                  final delta = -details.delta.dy; // 负值表示向上拖拽
                  final newHeight = (_currentSheetHeight ?? _initialSheetHeight!) + delta;

                  // 使用内容基础的最大高度，如果没有则使用屏幕基础的最大高度
                  final effectiveMaxHeight = _contentBasedMaxHeight ?? _maxSheetHeight;

                  // iOS 二段式滑动逻辑
                  if (_isIOS && _isInCollapsePhase) {
                    // 第一阶段：从最大高度收起到初始高度
                    if (isDraggingDown && _currentSheetHeight! > _initialSheetHeight!) {
                      // 使用高效的拖拽高度更新
                      _updateDragHeight(newHeight, effectiveMaxHeight, isDraggingDown);
                      return;
                    }

                    // 如果已经到达初始高度，继续向下拖拽则进入第二阶段（关闭弹窗）
                    if (isDraggingDown && _currentSheetHeight! <= _initialSheetHeight! + 1) {
                      // 第二阶段：从初始高度继续向下拖拽，超过阈值则关闭
                      if (newHeight < _initialSheetHeight! - _dismissDragThreshold) {
                        widget.onClose();
                        return;
                      }
                      // 否则保持在初始高度
                      _updateDragHeight(_initialSheetHeight!, effectiveMaxHeight, isDraggingDown);
                      return;
                    }
                  } else {
                    // 使用高效的拖拽高度更新
                    _updateDragHeight(newHeight, effectiveMaxHeight, isDraggingDown);
                  }
                }
              },
              onPanEnd: (details) {
                // 拖动结束时的吸附逻辑
                if ((_doubanDetails != null || _bangumiDetails != null) && _initialSheetHeight != null && _currentSheetHeight != null) {
                  final velocity = details.velocity.pixelsPerSecond.dy; // 向下为正
                  final effectiveMaxHeight = _contentBasedMaxHeight ?? _maxSheetHeight;
                  
                  // iOS 二段式滑动结束处理
                  if (_isIOS && _isInCollapsePhase) {
                    // 如果在初始高度附近并快速向下，关闭弹窗
                    if (_currentSheetHeight! <= _initialSheetHeight! + 1 && velocity > _dismissVelocityThreshold) {
                      widget.onClose();
                      return;
                    }
                    
                    // 如果还在收起阶段（高度大于初始高度），吸附到初始高度
                    if (_currentSheetHeight! > _initialSheetHeight! + 1) {
                      _animateToHeight(_initialSheetHeight!);
                      setState(() {
                        _showScrollIndicator = true;
                      });
                    }
                  } else {
                    // 非iOS或非收起阶段的正常逻辑
                    // 如果在初始高度附近并快速向下，关闭弹窗
                    if (_currentSheetHeight! <= _initialSheetHeight! + 1 && velocity > _dismissVelocityThreshold) {
                      widget.onClose();
                      return;
                    }
                    
                    // iOS 需要更敏感的阈值，因为 bouncing 效果会消耗一些速度
                    final velocityThreshold = _isIOS ? 400.0 : 800.0;
                    final negativeVelocityThreshold = _isIOS ? -400.0 : -800.0;

                    if (velocity > velocityThreshold) {
                      // 向下快速拖动 - 无论什么状态都尝试收起菜单
                      _animateToHeight(_initialSheetHeight!);
                      setState(() {
                        _showScrollIndicator = true;
                      });
                    } else if (velocity < negativeVelocityThreshold) {
                      // 向上快速拖动，展开到最大高度
                      _animateToHeight(effectiveMaxHeight);
                      setState(() {
                        _showScrollIndicator = false;
                      });
                    }
                  }
                  
                  // 拖拽结束后，解除内部滚动锁并重置所有状态
                  setState(() {
                    if (_lockInnerScroll) {
                      _lockInnerScroll = false;
                    }
                    // 重置拖拽方向状态和收起阶段状态
                    _isDraggingDown = false;
                    _isInCollapsePhase = false;
                  });
                }
              },
              child: Container(
                key: _sheetKey,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                height: _currentSheetHeight,
                decoration: BoxDecoration(
                  color: themeService.isDarkMode 
                      ? const Color(0xFF2C2C2C)
                      : Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 可滚动内容 + 悬浮下滑箭头
                  Flexible(
                    child: Stack(
                      children: [
                          // 使用 ClipRect 确保内容不会溢出
                          ClipRect(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                // 监听过度滚动通知，作为备用方案
                                if (notification is OverscrollNotification) {
                                  final isAtTop = notification.metrics.pixels <= (_isIOS ? 1.0 : 0.0);
                                  final isOverscrollingDown = notification.overscroll > 0;
                                  final velocity = notification.velocity;

                                  // iOS 需要更宽松的条件，因为 bouncing 效果
                                  final velocityThreshold = _isIOS ? 400.0 : 800.0;

                                  if (isAtTop && isOverscrollingDown && velocity > velocityThreshold) {
                                    final isAtMaxHeight = _currentSheetHeight != null &&
                                        _currentSheetHeight! >= (_contentBasedMaxHeight ?? _maxSheetHeight) - 1;

                                    if (isAtMaxHeight) {
                                      _animateToHeight(_initialSheetHeight!);
                                      setState(() {
                                        _showScrollIndicator = true;
                                      });
                                    }
                                  }
                                }

                                return false; // 继续传递通知
                              },
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                // 滚动物理控制：使用自定义物理处理展开状态下的顶部向下拖拽
                                physics: (() {
                                  final isAtMaxHeight = _currentSheetHeight != null && 
                                      _currentSheetHeight! >= (_contentBasedMaxHeight ?? _maxSheetHeight) - 1;
                                  
                                  // 当菜单高度小于最大高度时，完全禁用滚动让拖拽控制高度
                                  final shouldCompletelyDisable = (_currentSheetHeight != null && 
                                      (_contentBasedMaxHeight == null || _currentSheetHeight! < _contentBasedMaxHeight!)) 
                                      || _lockInnerScroll;
                                  
                                  if (shouldCompletelyDisable) {
                                    return const NeverScrollableScrollPhysics();
                                  }
                                  
                                  // 使用自定义物理，在展开状态下处理顶部向下拖拽
                                  return CollapsibleScrollPhysics(
                                    isAtMaxHeight: isAtMaxHeight,
                                    onCollapseTriggered: _handleCollapseFromScroll,
                                    isIOS: _isIOS,
                                  );
                                })(),
                              child: Container(
                                key: _fullContentKey,
                                child: Column(
                                  children: [
                                  // 头部信息区域
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        // 缩略图
                                        GestureDetector(
                                          onTap: () {
                                            FullscreenImageViewer.show(
                                              context,
                                              imageUrl: thumbUrl,
                                              source: widget.videoInfo.source,
                                              title: widget.videoInfo.title,
                                            );
                                          },
                                          child: Container(
                                            width: 60,
                                            height: 80,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.1),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: CachedNetworkImage(
                                                imageUrl: thumbUrl,
                                                httpHeaders: headers,
                                                fit: BoxFit.cover,
                                                // 优化图片加载，避免动画卡顿
                                                memCacheWidth: 120, // 限制内存缓存大小
                                                memCacheHeight: 160,
                                                fadeInDuration: const Duration(milliseconds: 150), // 更快的淡入动画
                                                fadeOutDuration: const Duration(milliseconds: 100),
                                                placeholder: (context, url) => Container(
                                                  color: themeService.isDarkMode
                                                      ? const Color(0xFF333333)
                                                      : Colors.grey[300],
                                                  child: Icon(
                                                    Icons.movie,
                                                    color: themeService.isDarkMode
                                                        ? const Color(0xFF666666)
                                                        : Colors.grey,
                                                    size: 24,
                                                  ),
                                                ),
                                                errorWidget: (context, url, error) => Container(
                                                  color: themeService.isDarkMode
                                                      ? const Color(0xFF333333)
                                                      : Colors.grey[300],
                                                  child: Icon(
                                                    Icons.movie,
                                                    color: themeService.isDarkMode
                                                        ? const Color(0xFF666666)
                                                        : Colors.grey,
                                                    size: 24,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      
                                      const SizedBox(width: 12),
                                      
                                      // 标题和分类信息
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // 标题
                                            Text(
                                              widget.videoInfo.title,
                                              style: FontUtils.poppins(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: themeService.isDarkMode 
                                                    ? const Color(0xFFFFFFFF)
                                                    : const Color(0xFF2C2C2C),
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            
                                            const SizedBox(height: 6),
                                            
                            // 源名称标签或播放源数量
                            (widget.videoInfo.source == 'douban' || widget.videoInfo.source == 'bangumi')
                                ? // 豆瓣或Bangumi来源：纯文本，无边框
                                  Text(
                                    widget.videoInfo.source == 'douban' ? '来自豆瓣' : '来自 Bangumi',
                                    style: FontUtils.poppins(
                                      fontSize: 12,
                                      color: themeService.isDarkMode 
                                          ? const Color(0xFF999999)
                                          : const Color(0xFF666666),
                                    ),
                                  )
                                : // 聚合来源：显示播放源数量并可点击
                                  widget.from == 'agg'
                                      ? GestureDetector(
                                          onTap: _showSourcesDialog,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '共 ${widget.videoInfo.sourceName.split(', ').length} 个播放源',
                                                style: FontUtils.poppins(
                                                  fontSize: 12,
                                                  color: themeService.isDarkMode 
                                                      ? const Color(0xFF999999)
                                                      : const Color(0xFF666666),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.chevron_right,
                                                size: 16,
                                                color: themeService.isDarkMode 
                                                    ? const Color(0xFF999999)
                                                    : const Color(0xFF666666),
                                              ),
                                            ],
                                          ),
                                        )
                                      : // 其他来源：带边框的标签
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: themeService.isDarkMode 
                                                  ? const Color(0xFF666666)
                                                  : const Color(0xFFE0E0E0),
                                              width: 1,
                                            ),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            widget.videoInfo.sourceName,
                                            style: FontUtils.poppins(
                                              fontSize: 12,
                                              color: themeService.isDarkMode 
                                                  ? const Color(0xFF999999)
                                                  : const Color(0xFF666666),
                                            ),
                                          ),
                                        ),
                                          ],
                                        ),
                                      ),
                                      
                                      // 关闭按钮
                                      GestureDetector(
                                        onTap: widget.onClose,
                                        child: SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: Icon(
                                            Icons.close,
                                            size: 18,
                                            color: themeService.isDarkMode 
                                                ? const Color(0xFF999999)
                                                : const Color(0xFF666666),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  ),
                                  
                                  // 菜单选项
                                  _buildMenuOptions(context, themeService),
                                  
                                  // 豆瓣详情区域（仅在加载完成后展示）
                                  if (_doubanDetails != null)
                                    _buildDoubanDetailsSection(context, themeService),
                                  
                                  // Bangumi 详情区域（仅在加载完成后展示）
                                  if (_bangumiDetails != null)
                                    _buildBangumiDetailsSection(context, themeService),
                                  
                                    // 底部安全区域
                                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                                  ],
                                ),
                              ),
                              ),
                            ),
                          ),
                          // 悬浮箭头提示
                          if (_showScrollIndicator && (_doubanDetails != null || _bangumiDetails != null))
                            Positioned(
                              bottom: 12.0,
                              left: 0,
                              right: 0,
                              child: IgnorePointer(
                                ignoring: true,
                                child: Center(
                                  child: _buildScrollIndicator(themeService),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
              ),
            ),
            );
          },
        );
      },
    );
  }

  /// 构建下滑指示器
  Widget _buildScrollIndicator(ThemeService themeService) {
    return AnimatedBuilder(
      animation: _floatAnimationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimationController.value * 8), // 增大浮动幅度到8像素
          child: Transform.scale(
            scaleX: 1.5, // 水平拉伸1.5倍，使箭头更宽
            scaleY: 0.8, // 垂直压缩到0.8倍，使箭头更扁
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 36, // 增大基础尺寸
              color: themeService.isDarkMode 
                  ? const Color(0xFF666666)
                  : const Color(0xFFCCCCCC),
            ),
          ),
        );
      },
    );
  }

  /// 构建豆瓣详情区域
  Widget _buildDoubanDetailsSection(BuildContext context, ThemeService themeService) {
    if (_isLoadingDoubanDetails) {
      return const SizedBox.shrink();
    }

    if (_doubanDetails == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分割线
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 16),
            color: themeService.isDarkMode 
                ? const Color(0xFF404040)
                : const Color(0xFFE0E0E0),
          ),
          
          // 豆瓣详情标题
          Text(
            '豆瓣简介',
            style: FontUtils.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: themeService.isDarkMode 
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF2C2C2C),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 评分和年份
          Row(
            children: [
              if (_doubanDetails!.rate != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star,
                        size: 16,
                        color: Color(0xFFFFB800),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _doubanDetails!.rate!,
                        style: FontUtils.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFFB800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: themeService.isDarkMode 
                        ? const Color(0xFF666666)
                        : const Color(0xFFE0E0E0),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _doubanDetails!.year,
                  style: FontUtils.poppins(
                    fontSize: 14,
                    color: themeService.isDarkMode 
                        ? const Color(0xFF999999)
                        : const Color(0xFF666666),
                  ),
                ),
              ),
            ],
          ),
          
          // 类型标签
          if (_doubanDetails!.genres.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _doubanDetails!.genres.take(5).map((genre) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: themeService.isDarkMode 
                      ? const Color(0xFF404040)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  genre,
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: themeService.isDarkMode 
                        ? const Color(0xFFCCCCCC)
                        : const Color(0xFF666666),
                  ),
                ),
              )).toList(),
            ),
          ],
          
          // 导演和演员
          if (_doubanDetails!.directors.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildDetailRow('导演', _doubanDetails!.directors.join(', '), themeService),
          ],
          
          if (_doubanDetails!.actors.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDetailRow('主演', _doubanDetails!.actors.take(3).join(', '), themeService),
          ],
          
          // 简介
          if (_doubanDetails!.summary != null && _doubanDetails!.summary!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '简介',
              style: FontUtils.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: themeService.isDarkMode 
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _doubanDetails!.summary!,
              style: FontUtils.poppins(
                fontSize: 14,
                height: 1.5,
                color: themeService.isDarkMode 
                    ? const Color(0xFFCCCCCC)
                    : const Color(0xFF666666),
              ),
            ),
          ],
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 构建 Bangumi 详情区域
  Widget _buildBangumiDetailsSection(BuildContext context, ThemeService themeService) {
    if (_isLoadingBangumiDetails) {
      return const SizedBox.shrink();
    }

    if (_bangumiDetails == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分割线
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 16),
            color: themeService.isDarkMode 
                ? const Color(0xFF404040)
                : const Color(0xFFE0E0E0),
          ),
          
          // Bangumi 详情标题
          Text(
            'Bangumi 简介',
            style: FontUtils.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: themeService.isDarkMode 
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF2C2C2C),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 评分和年份
          Row(
            children: [
              if (_bangumiDetails!.rating.score > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE91E63).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star,
                        size: 16,
                        color: Color(0xFFE91E63),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _bangumiDetails!.rating.score.toStringAsFixed(1),
                        style: FontUtils.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFE91E63),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (_bangumiDetails!.date != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: themeService.isDarkMode 
                          ? const Color(0xFF666666)
                          : const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _bangumiDetails!.date!.split('-').first,
                    style: FontUtils.poppins(
                      fontSize: 14,
                      color: themeService.isDarkMode 
                          ? const Color(0xFF999999)
                          : const Color(0xFF666666),
                    ),
                  ),
                ),
              ],
            ],
          ),
          
          // 标签
          if (_bangumiDetails!.metaTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _bangumiDetails!.metaTags.take(5).map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: themeService.isDarkMode 
                      ? const Color(0xFF404040)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: themeService.isDarkMode 
                        ? const Color(0xFFCCCCCC)
                        : const Color(0xFF666666),
                  ),
                ),
              )).toList(),
            ),
          ],
          
          // 从infobox中提取相关信息
          ..._buildBangumiInfoboxDetails(themeService),
          
          // 简介
          if (_bangumiDetails!.summary.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '简介',
              style: FontUtils.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: themeService.isDarkMode 
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _bangumiDetails!.summary,
              style: FontUtils.poppins(
                fontSize: 14,
                height: 1.5,
                color: themeService.isDarkMode 
                    ? const Color(0xFFCCCCCC)
                    : const Color(0xFF666666),
              ),
            ),
          ],
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 构建详情行
  Widget _buildDetailRow(String label, String value, ThemeService themeService) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: FontUtils.poppins(
              fontSize: 14,
              color: themeService.isDarkMode 
                  ? const Color(0xFF999999)
                  : const Color(0xFF666666),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: FontUtils.poppins(
              fontSize: 14,
              color: themeService.isDarkMode 
                  ? const Color(0xFFCCCCCC)
                  : const Color(0xFF333333),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建Bangumi infobox详情信息
  List<Widget> _buildBangumiInfoboxDetails(ThemeService themeService) {
    if (_bangumiDetails == null || _bangumiDetails!.infobox.isEmpty) {
      return [];
    }

    List<Widget> widgets = [];
    
    // 定义我们感兴趣的字段映射
    final Map<String, String> fieldMapping = {
      '导演': '导演',
      '监督': '导演',
      '原作': '原作',
      '脚本': '脚本',
      '分镜': '分镜',
      '演出': '演出',
      '系列构成': '脚本', // 系列构成也算脚本相关
      '剧本': '脚本',
      '分镜构图': '分镜',
      '分镜・演出': '分镜',
    };

    // 解析infobox信息
    Map<String, String> parsedInfo = {};
    for (String info in _bangumiDetails!.infobox) {
      if (info.contains(':')) {
        final parts = info.split(':');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join(':').trim();
          
          // 检查是否是我们感兴趣的字段
          for (final entry in fieldMapping.entries) {
            if (key.contains(entry.key)) {
              parsedInfo[entry.value] = value;
              break;
            }
          }
        }
      }
    }

    // 按优先级顺序展示信息
    final List<String> priorityOrder = [
      '原作', '导演', '脚本', '分镜', '演出'
    ];

    bool hasAddedContent = false;
    for (final field in priorityOrder) {
      if (parsedInfo.containsKey(field) && parsedInfo[field]!.isNotEmpty) {
        if (!hasAddedContent) {
          widgets.add(const SizedBox(height: 16));
          hasAddedContent = true;
        } else {
          widgets.add(const SizedBox(height: 8));
        }
        
        // 限制显示长度，避免过长
        String displayValue = parsedInfo[field]!;
        if (displayValue.length > 100) {
          displayValue = '${displayValue.substring(0, 100)}...';
        }
        
        widgets.add(_buildDetailRow(field, displayValue, themeService));
      }
    }

    return widgets;
  }

  /// 构建菜单选项
  Widget _buildMenuOptions(BuildContext context, ThemeService themeService) {
    // 如果是豆瓣来源，只显示播放和豆瓣详情
    if (widget.videoInfo.source == 'douban') {
      return Column(
        children: [
          _buildMenuItem(
            context,
            themeService,
            icon: Icons.play_circle_fill,
            iconColor: const Color(0xFF27AE60),
            title: '播放',
            subtitle: _getEpisodeSubtitle(),
            onTap: () {
              widget.onClose();
              widget.onActionSelected(VideoMenuAction.play);
            },
          ),
          
          _buildDivider(themeService),
          
          _buildMenuItem(
            context,
            themeService,
            icon: Icons.link,
            iconColor: const Color(0xFF3498DB),
            title: '豆瓣详情',
            onTap: () async {
              widget.onClose();
              // 从videoInfo中获取doubanId，优先使用doubanId，如果为空或为0则使用id
              final doubanId = (widget.videoInfo.doubanId != null && widget.videoInfo.doubanId!.isNotEmpty && widget.videoInfo.doubanId != "0") 
                  ? widget.videoInfo.doubanId! 
                  : widget.videoInfo.id;
              await _openDoubanDetail(doubanId);
            },
          ),
        ],
      );
    }
    
    // 如果是Bangumi来源，只显示播放和Bangumi详情
    if (widget.videoInfo.source == 'bangumi') {
      return Column(
        children: [
          _buildMenuItem(
            context,
            themeService,
            icon: Icons.play_circle_fill,
            iconColor: const Color(0xFF27AE60),
            title: '播放',
            subtitle: _getEpisodeSubtitle(),
            onTap: () {
              widget.onClose();
              widget.onActionSelected(VideoMenuAction.play);
            },
          ),
          
          _buildDivider(themeService),
          
          _buildMenuItem(
            context,
            themeService,
            icon: Icons.link,
            iconColor: const Color(0xFF3498DB),
            title: 'Bangumi 详情',
            onTap: () async {
              widget.onClose();
              // 从videoInfo中获取bangumiId，优先使用bangumiId，如果为空或为0则使用id
              final bangumiId = (widget.videoInfo.bangumiId != null && widget.videoInfo.bangumiId! > 0) 
                  ? widget.videoInfo.bangumiId!.toString() 
                  : widget.videoInfo.id;
              await _openBangumiDetail(bangumiId);
            },
          ),
        ],
      );
    }
    
    // 如果是收藏场景，只显示播放和取消收藏
    if (widget.from == 'favorite') {
      return Column(
        children: [
          _buildMenuItem(
            context,
            themeService,
            icon: Icons.play_circle_fill,
            iconColor: const Color(0xFF27AE60),
            title: '播放',
            subtitle: _getEpisodeSubtitle(),
            onTap: () {
              widget.onClose();
              widget.onActionSelected(VideoMenuAction.play);
            },
          ),
          
          _buildDivider(themeService),
          
          _buildMenuItem(
            context,
            themeService,
            icon: Icons.favorite,
            iconColor: const Color(0xFFE74C3C),
            title: '取消收藏',
            onTap: () {
              widget.onClose();
              widget.onActionSelected(VideoMenuAction.unfavorite);
            },
          ),
        ],
      );
    }
    
    // 如果是聚合场景，显示播放和豆瓣详情（如果有）
    if (widget.from == 'agg') {
      List<Widget> menuItems = [
        // 播放按钮
        _buildMenuItem(
          context,
          themeService,
          icon: Icons.play_circle_fill,
          iconColor: const Color(0xFF27AE60),
          title: '播放',
          subtitle: _getEpisodeSubtitle(),
          onTap: () {
            // 对于聚合卡片，关闭菜单后触发播放操作（会显示源选择对话框）
            widget.onClose();
            widget.onActionSelected(VideoMenuAction.play);
          },
        ),
      ];
      
      // 如果有豆瓣ID且不为0，添加豆瓣详情选项
      if (widget.videoInfo.doubanId != null && widget.videoInfo.doubanId!.isNotEmpty && widget.videoInfo.doubanId != "0") {
        menuItems.addAll([
          _buildDivider(themeService),
          _buildMenuItem(
            context,
            themeService,
            icon: Icons.link,
            iconColor: const Color(0xFF3498DB),
            title: '豆瓣详情',
            onTap: () async {
              widget.onClose();
              await _openDoubanDetail(widget.videoInfo.doubanId!);
            },
          ),
        ]);
      }
      
      return Column(children: menuItems);
    }
    
    // 如果是搜索场景，显示播放、收藏/取消收藏，如果有豆瓣ID则显示豆瓣详情
    if (widget.from == 'search') {
      List<Widget> menuItems = [
        _buildMenuItem(
          context,
          themeService,
          icon: Icons.play_circle_fill,
          iconColor: const Color(0xFF27AE60),
          title: '播放',
          subtitle: _getEpisodeSubtitle(),
          onTap: () {
            widget.onClose();
            widget.onActionSelected(VideoMenuAction.play);
          },
        ),
        
        _buildDivider(themeService),
        
        // 根据收藏状态动态显示收藏或取消收藏
        _buildMenuItem(
          context,
          themeService,
          icon: widget.isFavorited ? Icons.favorite : Icons.favorite_border,
          iconColor: const Color(0xFFE74C3C),
          title: widget.isFavorited ? '取消收藏' : '收藏',
          onTap: () {
            widget.onClose();
            widget.onActionSelected(widget.isFavorited ? VideoMenuAction.unfavorite : VideoMenuAction.favorite);
          },
        ),
      ];
      
      // 如果有豆瓣ID且不为0，添加豆瓣详情选项
      if (widget.videoInfo.doubanId != null && widget.videoInfo.doubanId!.isNotEmpty && widget.videoInfo.doubanId != "0") {
        menuItems.addAll([
          _buildDivider(themeService),
          _buildMenuItem(
            context,
            themeService,
            icon: Icons.link,
            iconColor: const Color(0xFF3498DB),
            title: '豆瓣详情',
            onTap: () async {
              widget.onClose();
              await _openDoubanDetail(widget.videoInfo.doubanId!);
            },
          ),
        ]);
      }
      
      // 如果有Bangumi ID且不为0，添加Bangumi详情选项
      if (widget.videoInfo.bangumiId != null && widget.videoInfo.bangumiId! > 0) {
        menuItems.addAll([
          _buildDivider(themeService),
          _buildMenuItem(
            context,
            themeService,
            icon: Icons.link,
            iconColor: const Color(0xFF3498DB),
            title: 'Bangumi 详情',
            onTap: () async {
              widget.onClose();
              await _openBangumiDetail(widget.videoInfo.bangumiId!.toString());
            },
          ),
        ]);
      }
      
      return Column(children: menuItems);
    }
    
    // 其他来源显示完整菜单
    return Column(
      children: [
        _buildMenuItem(
          context,
          themeService,
          icon: Icons.play_circle_fill,
          iconColor: const Color(0xFF27AE60),
          title: '播放',
          subtitle: _getEpisodeSubtitle(),
          onTap: () {
            widget.onClose();
            widget.onActionSelected(VideoMenuAction.play);
          },
        ),
        
        _buildDivider(themeService),
        
        // 根据收藏状态动态显示收藏或取消收藏
        _buildMenuItem(
          context,
          themeService,
          icon: widget.isFavorited ? Icons.favorite : Icons.favorite_border,
          iconColor: const Color(0xFFE74C3C),
          title: widget.isFavorited ? '取消收藏' : '收藏',
          onTap: () {
            widget.onClose();
            widget.onActionSelected(widget.isFavorited ? VideoMenuAction.unfavorite : VideoMenuAction.favorite);
          },
        ),
        
        _buildDivider(themeService),
        
        _buildMenuItem(
          context,
          themeService,
          icon: Icons.delete,
          iconColor: const Color(0xFFE74C3C),
          title: '删除记录',
          onTap: () {
            widget.onClose();
            widget.onActionSelected(VideoMenuAction.deleteRecord);
          },
        ),
      ],
    );
  }

  /// 构建菜单项
  Widget _buildMenuItem(
    BuildContext context,
    ThemeService themeService, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 图标
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: iconColor,
                ),
              ),
              
              const SizedBox(width: 12),
              
              // 标题
              Expanded(
                child: Text(
                  title,
                  style: FontUtils.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: themeService.isDarkMode 
                        ? const Color(0xFFFFFFFF)
                        : const Color(0xFF2C2C2C),
                  ),
                ),
              ),
              
              // 副标题（集数信息）
              if (subtitle != null)
                Text(
                  subtitle,
                  style: FontUtils.poppins(
                    fontSize: 14,
                    color: themeService.isDarkMode 
                        ? const Color(0xFF999999)
                        : const Color(0xFF666666),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建分割线
  Widget _buildDivider(ThemeService themeService) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: themeService.isDarkMode 
          ? const Color(0xFF404040)
          : const Color(0xFFE0E0E0),
    );
  }


  

  /// 获取集数副标题
  String? _getEpisodeSubtitle() {
    // 如果总集数只有1，则不显示集数信息
    if (widget.videoInfo.totalEpisodes <= 1) {
      return null;
    }
    
    // 只有 from=playrecord 和 from=favorite 且 index 不为 0 的场景才显示集数信息
    if (widget.from == 'playrecord') {
      return '${widget.videoInfo.index}/${widget.videoInfo.totalEpisodes}';
    }
    
    if (widget.from == 'favorite' && widget.videoInfo.index > 0) {
      return '${widget.videoInfo.index}/${widget.videoInfo.totalEpisodes}';
    }
    
    // 其他所有场景都不显示集数信息
    return null;
  }

  /// 打开豆瓣详情页面
  static Future<void> _openDoubanDetail(String doubanId) async {
    try {
      final url = 'https://movie.douban.com/subject/$doubanId';
      final uri = Uri.parse(url);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // 不处理
    }
  }

  /// 打开Bangumi详情页面
  static Future<void> _openBangumiDetail(String bangumiId) async {
    try {
      final url = 'https://bgm.tv/subject/$bangumiId';
      final uri = Uri.parse(url);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // 不处理
    }
  }

  /// 显示播放源列表对话框
  void _showSourcesDialog() {
    final themeService = Provider.of<ThemeService>(context, listen: false);
    final sources = widget.originalResults;
    if (sources == null || sources.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
              maxWidth: 320,
            ),
            decoration: BoxDecoration(
              color: themeService.isDarkMode
                  ? const Color(0xFF2C2C2C)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Text(
                    '可用播放源',
                    style: FontUtils.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: themeService.isDarkMode
                          ? const Color(0xFFFFFFFF)
                          : const Color(0xFF2C2C2C),
                    ),
                  ),
                ),

                // 播放源列表
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: sources.map((source) {
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).pop(); // Close dialog
                                widget.onClose(); // Close menu
                                widget.onSourceSelected?.call(source);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  children: [
                                    Text(
                                      source.sourceName,
                                      style: FontUtils.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (source.episodes.length > 1)
                                      Text(
                                        '${source.episodes.length}集',
                                        style: FontUtils.poppins(
                                          fontSize: 14,
                                          color: themeService.isDarkMode
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),

                // 底部间距
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

}
