import 'package:flutter/material.dart';
import 'package:dlna_dart/dlna.dart';
import '../utils/device_utils.dart';

// 带 hover 效果的按钮组件（仅在 PC 端生效）
class HoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets padding;

  const HoverButton({
    super.key,
    required this.child,
    required this.onTap,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  State<HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<HoverButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    // 如果不是 PC，直接返回普通按钮
    if (!DeviceUtils.isPC()) {
      return GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: widget.padding,
          child: widget.child,
        ),
      );
    }

    // PC 端返回带 hover 效果的按钮
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: widget.padding,
          decoration: _isHovering
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.withValues(alpha: 0.5),
                )
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}

// 胶囊按钮的 hover 效果组件（仅在 PC 端生效）
class CapsuleHoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool isLeft; // 是否是左侧按钮

  const CapsuleHoverButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.isLeft,
  });

  @override
  State<CapsuleHoverButton> createState() => _CapsuleHoverButtonState();
}

class _CapsuleHoverButtonState extends State<CapsuleHoverButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    // 如果不是 PC，直接返回普通按钮
    if (!DeviceUtils.isPC()) {
      return GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: widget.child,
      );
    }

    // PC 端返回带 hover 效果的按钮
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: _isHovering
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: widget.isLeft
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(22),
                          bottomLeft: Radius.circular(22),
                        )
                      : const BorderRadius.only(
                          topRight: Radius.circular(22),
                          bottomRight: Radius.circular(22),
                        ),
                )
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}

class DLNAPlayerControls extends StatefulWidget {
  final DLNADevice device;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback? onBackPressed;
  final VoidCallback? onNextEpisode;
  final bool isLastEpisode;
  final VoidCallback? onPlayPause;
  final VoidCallback? onStop;
  final Function(Duration)? onSeek;
  final Function(double)? onVolumeChange;
  final VoidCallback? onChangeDevice;

  const DLNAPlayerControls({
    super.key,
    required this.device,
    required this.position,
    required this.duration,
    required this.isPlaying,
    this.isLoading = false,
    this.onBackPressed,
    this.onNextEpisode,
    this.isLastEpisode = false,
    this.onPlayPause,
    this.onStop,
    this.onSeek,
    this.onVolumeChange,
    this.onChangeDevice,
  });

  @override
  State<DLNAPlayerControls> createState() => _DLNAPlayerControlsState();
}

class _DLNAPlayerControlsState extends State<DLNAPlayerControls> {
  bool _isDragging = false;
  double _dragValue = 0.0;
  bool _isHoveringThumb = false;

  // 滑动 seek 相关
  bool _isSeekingViaSwipe = false;
  double _swipeStartX = 0;
  Duration _swipeStartPosition = Duration.zero;
  Duration? _swipeTargetPosition;

  void _updateDragPosition(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final width = box.size.width - 32; // 减去左右 margin
    final value = ((dx - 16) / width).clamp(0.0, 1.0);

    setState(() {
      _dragValue = value;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  void _onSwipeStart(DragStartDetails details) {
    if (!mounted) return;

    setState(() {
      _isSeekingViaSwipe = true;
      _swipeStartX = details.globalPosition.dx;
      _swipeStartPosition = widget.position;
      _swipeTargetPosition = null;
    });
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    if (!mounted || !_isSeekingViaSwipe) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final swipeDistance = details.globalPosition.dx - _swipeStartX;
    final swipeRatio = swipeDistance / (screenWidth * 0.5);
    final duration = widget.duration;

    final targetPosition = _swipeStartPosition +
        Duration(
            milliseconds: (duration.inMilliseconds * swipeRatio * 0.1).round());
    final clampedPosition = Duration(
        milliseconds:
            targetPosition.inMilliseconds.clamp(0, duration.inMilliseconds));

    setState(() {
      _swipeTargetPosition = clampedPosition;
    });
  }

  void _onSwipeEnd(DragEndDetails details) {
    if (!mounted || !_isSeekingViaSwipe) return;

    if (_swipeTargetPosition != null) {
      widget.onSeek?.call(_swipeTargetPosition!);
    }

    setState(() {
      _isSeekingViaSwipe = false;
      _swipeTargetPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 如果正在加载，只显示加载界面
    if (widget.isLoading) {
      return Stack(
        children: [
          // 全黑背景
          Positioned.fill(
            child: Container(
              color: Colors.black,
            ),
          ),
          // 左上角返回按钮
          Positioned(
            top: 4,
            left: 8.0,
            child: HoverButton(
              onTap: () {
                widget.onBackPressed?.call();
              },
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          // 顶部正中央设备名称
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.device.info.friendlyName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          // 右上角电源按钮
          Positioned(
            top: 4,
            right: 8.0,
            child: HoverButton(
              onTap: () {
                widget.onStop?.call();
              },
              child: const Icon(
                Icons.power_settings_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          // 中央加载指示器
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
                SizedBox(height: 16),
                Text(
                  '视频加载中...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        // 全黑背景
        Positioned.fill(
          child: Container(
            color: Colors.black,
          ),
        ),

        // 空白区域手势检测（排除底部控制栏和顶部按钮区域）
        Positioned(
          top: 50,
          left: 0,
          right: 0,
          bottom: 70,
          child: GestureDetector(
            onHorizontalDragStart: _onSwipeStart,
            onHorizontalDragUpdate: _onSwipeUpdate,
            onHorizontalDragEnd: _onSwipeEnd,
            onTap: () {
              // 点击事件不做任何处理，避免隐藏按钮
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),

        // 左上角返回按钮
        Positioned(
          top: 4,
          left: 8.0,
          child: HoverButton(
            onTap: () {
              widget.onBackPressed?.call();
            },
            child: const Icon(
              Icons.arrow_back,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),

        // 顶部正中央设备名称
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.device.info.friendlyName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),

        // 右上角电源按钮
        Positioned(
          top: 4,
          right: 8.0,
          child: HoverButton(
            onTap: () {
              widget.onStop?.call();
            },
            child: const Icon(
              Icons.power_settings_new,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),

        // 中央胶囊按钮（拖动时隐藏）
        if (!_isSeekingViaSwipe)
          Center(
            child: Container(
              width: 160,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF2a2a2a),
                    Color(0xFF1a1a1a),
                    Color(0xFF000000),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.1),
                    blurRadius: 2,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 左侧：换设备
                  Expanded(
                    child: CapsuleHoverButton(
                      isLeft: true,
                      onTap: () {
                        widget.onChangeDevice?.call();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            '换设备',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 右侧：播放/暂停
                  Expanded(
                    child: CapsuleHoverButton(
                      isLeft: false,
                      onTap: () {
                        widget.onPlayPause?.call();
                      },
                      child: Center(
                        child: Text(
                          widget.isPlaying ? '暂停' : '播放',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 底部控制栏
        Positioned(
          bottom: -6.0,
          left: 0,
          right: 0,
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(
                left: 8.0,
                right: 8.0,
                bottom: 8.0,
              ),
              child: Row(
                children: [
                  // 播放/暂停按钮
                  HoverButton(
                    onTap: () {
                      widget.onPlayPause?.call();
                    },
                    child: Icon(
                      widget.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),

                  // 下一集按钮
                  if (!widget.isLastEpisode)
                    Transform.translate(
                      offset: const Offset(-8, 0),
                      child: HoverButton(
                        onTap: () {
                          widget.onNextEpisode?.call();
                        },
                        child: const Icon(
                          Icons.skip_next,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),

                  // 时间显示
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        '${_formatDuration(_isSeekingViaSwipe && _swipeTargetPosition != null ? _swipeTargetPosition! : widget.position)} / ${_formatDuration(widget.duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 进度条
        Positioned(
          bottom: 42.0,
          left: 0,
          right: 0,
          child: DeviceUtils.isPC()
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (details) {
                      setState(() {
                        _isDragging = true;
                      });
                      _updateDragPosition(details.localPosition.dx);
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_isDragging) {
                        _updateDragPosition(details.localPosition.dx);
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      if (_isDragging) {
                        setState(() {
                          _isDragging = false;
                        });
                        final seekPosition = Duration(
                            milliseconds:
                                (_dragValue * widget.duration.inMilliseconds)
                                    .round());
                        widget.onSeek?.call(seekPosition);
                      }
                    },
                    onTapDown: (details) {
                      _updateDragPosition(details.localPosition.dx);
                      final seekPosition = Duration(
                          milliseconds:
                              (_dragValue * widget.duration.inMilliseconds)
                                  .round());
                      widget.onSeek?.call(seekPosition);
                    },
                    child: Container(
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final progressWidth = constraints.maxWidth;
                            double progressValue = 0.0;
                            if (widget.duration.inMilliseconds > 0) {
                              if (_isDragging) {
                                progressValue = _dragValue;
                              } else if (_isSeekingViaSwipe &&
                                  _swipeTargetPosition != null) {
                                progressValue =
                                    _swipeTargetPosition!.inMilliseconds /
                                        widget.duration.inMilliseconds;
                              } else {
                                progressValue = widget.position.inMilliseconds /
                                    widget.duration.inMilliseconds;
                              }
                            }
                            progressValue = progressValue.clamp(0.0, 1.0);
                            final thumbPosition =
                                (progressValue * progressWidth)
                                    .clamp(8.0, progressWidth - 8.0);

                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // 进度条背景
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 9,
                                  child: Container(
                                    height: 6,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(3),
                                      color:
                                          Colors.white.withValues(alpha: 0.3),
                                    ),
                                  ),
                                ),
                                // 已播放进度
                                Positioned(
                                  left: 0,
                                  top: 9,
                                  child: Container(
                                    width: progressValue * progressWidth,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(3),
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                                // 可拖拽的圆形把手
                                Positioned(
                                  left: thumbPosition - 8,
                                  top: 4,
                                  child: DeviceUtils.isPC()
                                      ? MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          onEnter: (_) => setState(
                                              () => _isHoveringThumb = true),
                                          onExit: (_) => setState(
                                              () => _isHoveringThumb = false),
                                          child: AnimatedScale(
                                            scale: (_isHoveringThumb ||
                                                    _isDragging ||
                                                    _isSeekingViaSwipe)
                                                ? 1.25
                                                : 1.0,
                                            duration: const Duration(
                                                milliseconds: 150),
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.red,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.3),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )
                                      : AnimatedScale(
                                          scale:
                                              _isSeekingViaSwipe ? 1.25 : 1.0,
                                          duration:
                                              const Duration(milliseconds: 150),
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.red,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.3),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                )
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    setState(() {
                      _isDragging = true;
                    });
                    _updateDragPosition(details.localPosition.dx);
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_isDragging) {
                      _updateDragPosition(details.localPosition.dx);
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    if (_isDragging) {
                      setState(() {
                        _isDragging = false;
                      });
                      final seekPosition = Duration(
                          milliseconds:
                              (_dragValue * widget.duration.inMilliseconds)
                                  .round());
                      widget.onSeek?.call(seekPosition);
                    }
                  },
                  onTapDown: (details) {
                    _updateDragPosition(details.localPosition.dx);
                    final seekPosition = Duration(
                        milliseconds:
                            (_dragValue * widget.duration.inMilliseconds)
                                .round());
                    widget.onSeek?.call(seekPosition);
                  },
                  child: Container(
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final progressWidth = constraints.maxWidth;
                          double progressValue = 0.0;
                          if (widget.duration.inMilliseconds > 0) {
                            if (_isDragging) {
                              progressValue = _dragValue;
                            } else if (_isSeekingViaSwipe &&
                                _swipeTargetPosition != null) {
                              progressValue =
                                  _swipeTargetPosition!.inMilliseconds /
                                      widget.duration.inMilliseconds;
                            } else {
                              progressValue = widget.position.inMilliseconds /
                                  widget.duration.inMilliseconds;
                            }
                          }
                          progressValue = progressValue.clamp(0.0, 1.0);
                          final thumbPosition = (progressValue * progressWidth)
                              .clamp(8.0, progressWidth - 8.0);

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // 进度条背景
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 9,
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                              // 已播放进度
                              Positioned(
                                left: 0,
                                top: 9,
                                child: Container(
                                  width: progressValue * progressWidth,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                              // 可拖拽的圆形把手
                              Positioned(
                                left: thumbPosition - 8,
                                top: 4,
                                child: DeviceUtils.isPC()
                                    ? MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        onEnter: (_) => setState(
                                            () => _isHoveringThumb = true),
                                        onExit: (_) => setState(
                                            () => _isHoveringThumb = false),
                                        child: AnimatedScale(
                                          scale: (_isHoveringThumb ||
                                                  _isDragging ||
                                                  _isSeekingViaSwipe)
                                              ? 1.25
                                              : 1.0,
                                          duration:
                                              const Duration(milliseconds: 150),
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.red,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.3),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : AnimatedScale(
                                        scale: _isSeekingViaSwipe ? 1.25 : 1.0,
                                        duration:
                                            const Duration(milliseconds: 150),
                                        child: Container(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.red,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.3),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
