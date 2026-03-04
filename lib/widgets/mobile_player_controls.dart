import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'dlna_device_dialog.dart';

class MobilePlayerControls extends StatefulWidget {
  final Player player;
  final VideoState state;
  final Function(bool) onControlsVisibilityChanged;
  final VoidCallback? onBackPressed;
  final Function(bool) onFullscreenChange;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPause;
  final String videoUrl;
  final bool isLastEpisode;
  final bool isLoadingVideo;
  final Function(dynamic)? onCastStarted;
  final String? videoTitle;
  final int? currentEpisodeIndex;
  final int? totalEpisodes;
  final String? sourceName;
  final VoidCallback? onExitFullScreen;
  final bool live;
  final ValueNotifier<double> playbackSpeedListenable;
  final Future<void> Function(double speed) onSetSpeed;
  final Future<void> Function() onEnterPipMode;
  final bool isPipMode;

  const MobilePlayerControls({
    super.key,
    required this.player,
    required this.state,
    required this.onControlsVisibilityChanged,
    this.onBackPressed,
    required this.onFullscreenChange,
    this.onNextEpisode,
    this.onPause,
    required this.videoUrl,
    this.isLastEpisode = false,
    this.isLoadingVideo = false,
    this.onCastStarted,
    this.videoTitle,
    this.currentEpisodeIndex,
    this.totalEpisodes,
    this.sourceName,
    this.onExitFullScreen,
    this.live = false,
    required this.playbackSpeedListenable,
    required this.onSetSpeed,
    required this.onEnterPipMode,
    required this.isPipMode,
  });

  @override
  State<MobilePlayerControls> createState() => _MobilePlayerControlsState();
}

class _MobilePlayerControlsState extends State<MobilePlayerControls> {
  final List<StreamSubscription> _subscriptions = [];
  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _isLongPressing = false;
  double _originalPlaybackSpeed = 1.0;
  Duration? _dragPosition;
  bool _isSeekingViaSwipe = false;
  double _swipeStartX = 0;
  Duration _swipeStartPosition = Duration.zero;
  Size? _screenSize;
  bool _isLocked = false;
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;
  double _currentVolume = 0.5;
  double _currentBrightness = 0.5;
  Timer? _volumeHideTimer;
  Timer? _brightnessHideTimer;
  Timer? _timeUpdateTimer;
  String _currentTime = '';
  bool _isPortrait = true; // 跟踪当前屏幕方向

  @override
  void initState() {
    super.initState();
    _initSystemControls();
    _listenPlayerStreams();
    _updateCurrentTime();
    _startTimeUpdateTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _forceStartHideTimer();
      widget.onControlsVisibilityChanged(true);
    });
  }

  @override
  void didUpdateWidget(covariant MobilePlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 PIP 模式停止时，显示控制栏
    if (oldWidget.isPipMode && !widget.isPipMode) {
      setState(() => _controlsVisible = true);
      widget.onControlsVisibilityChanged(true);
      _startHideTimer();
    }
  }

  void _initSystemControls() {
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.getVolume().then((value) {
      if (mounted) {
        setState(() => _currentVolume = value);
      }
    }).catchError((_) {});
    ScreenBrightness().application.then((value) {
      if (mounted) {
        setState(() => _currentBrightness = value);
      }
    }).catchError((_) {});
  }

  void _listenPlayerStreams() {
    _subscriptions.add(widget.player.stream.playing.listen((playing) {
      if (!mounted) return;
      if (playing && _controlsVisible) {
        _startHideTimer();
      }
      if (!playing) {
        _hideTimer?.cancel();
        if (!_controlsVisible) {
          setState(() => _controlsVisible = true);
          widget.onControlsVisibilityChanged(true);
        }
      }
    }));

    _subscriptions.add(widget.player.stream.position.listen((_) {
      if (!mounted) return;
      if (_controlsVisible && !_isSeekingViaSwipe) {
        setState(() {});
      }
    }));

    _subscriptions.add(widget.player.stream.completed.listen((_) {
      if (!mounted) return;
      setState(() {});
    }));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _hideTimer?.cancel();
    _volumeHideTimer?.cancel();
    _brightnessHideTimer?.cancel();
    _timeUpdateTimer?.cancel();
    VolumeController.instance.showSystemUI = true;
    super.dispose();
  }

  bool get _isFullscreen => widget.state.isFullscreen();
  bool get _isPlaying => widget.player.state.playing;
  Duration get _position => widget.player.state.position;
  Duration get _duration => widget.player.state.duration;

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_isPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _controlsVisible = false);
          widget.onControlsVisibilityChanged(false);
        }
      });
    }
  }

  void _forceStartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _controlsVisible = false);
        widget.onControlsVisibilityChanged(false);
      }
    });
  }

  void _onUserInteraction() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      widget.onControlsVisibilityChanged(true);
    }
    _startHideTimer();
  }

  void _toggleControlsVisibility() {
    if (_isLocked) {
      setState(() => _controlsVisible = !_controlsVisible);
      if (_controlsVisible) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
      }
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    widget.onControlsVisibilityChanged(_controlsVisible);
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_isLocked || widget.live || !_isPlaying) return;
    setState(() {
      _isLongPressing = true;
      _originalPlaybackSpeed = widget.playbackSpeedListenable.value;
    });
    widget.onSetSpeed(2.0);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_isLocked || !_isLongPressing || widget.live) return;
    widget.onSetSpeed(_originalPlaybackSpeed);
    setState(() => _isLongPressing = false);
  }

  void _onSwipeStart(DragStartDetails details) {
    if (_isLocked || widget.live) return;
    _screenSize ??= MediaQuery.of(context).size;
    setState(() {
      _isSeekingViaSwipe = true;
      _swipeStartX = details.globalPosition.dx;
      _swipeStartPosition = _position;
      _dragPosition = null;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    if (_isLocked || !_isSeekingViaSwipe || widget.live || _screenSize == null)
      return;
    final screenWidth = _screenSize!.width;
    final swipeDistance = details.globalPosition.dx - _swipeStartX;
    final swipeRatio = swipeDistance / (screenWidth * 0.5);
    final duration = _duration;
    if (duration == Duration.zero) return;
    final targetPosition = _swipeStartPosition +
        Duration(
          milliseconds: (duration.inMilliseconds * swipeRatio * 0.1).round(),
        );
    final clamped = Duration(
      milliseconds:
          targetPosition.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    setState(() => _dragPosition = clamped);
  }

  void _onSwipeEnd(DragEndDetails details) {
    if (_isLocked || !_isSeekingViaSwipe || widget.live) return;
    if (_dragPosition != null) {
      widget.player.seek(_dragPosition!);
    }
    setState(() {
      _isSeekingViaSwipe = false;
      _dragPosition = null;
    });
    _startHideTimer();
  }

  void _onVolumeSwipeStart(DragStartDetails details) {
    if (!_isFullscreen || _isLocked) return;
    _volumeHideTimer?.cancel();
    _hideTimer?.cancel();
    setState(() => _controlsVisible = true);
  }

  void _onVolumeSwipeUpdate(DragUpdateDetails details) {
    if (!_isFullscreen || _isLocked) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final volumeChange = -(details.delta.dy / screenHeight) * 2;
    setState(() {
      _currentVolume = (_currentVolume + volumeChange).clamp(0.0, 1.0);
      _showVolumeIndicator = true;
    });
    VolumeController.instance.setVolume(_currentVolume);
    _startVolumeHideTimer();
  }

  void _onVolumeSwipeEnd(DragEndDetails details) {
    if (!_isFullscreen || _isLocked) return;
    _startVolumeHideTimer();
    _startHideTimer();
  }

  void _startVolumeHideTimer() {
    _volumeHideTimer?.cancel();
    _volumeHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showVolumeIndicator = false);
      }
    });
  }

  void _onBrightnessSwipeStart(DragStartDetails details) {
    if (!_isFullscreen || _isLocked) return;
    _brightnessHideTimer?.cancel();
    _hideTimer?.cancel();
    setState(() => _controlsVisible = true);
  }

  void _onBrightnessSwipeUpdate(DragUpdateDetails details) {
    if (!_isFullscreen || _isLocked) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final brightnessChange = -(details.delta.dy / screenHeight) * 2;
    setState(() {
      _currentBrightness =
          (_currentBrightness + brightnessChange).clamp(0.0, 1.0);
      _showBrightnessIndicator = true;
    });
    ScreenBrightness().setApplicationScreenBrightness(_currentBrightness);
    _startBrightnessHideTimer();
  }

  void _onBrightnessSwipeEnd(DragEndDetails details) {
    if (!_isFullscreen || _isLocked) return;
    _startBrightnessHideTimer();
    _startHideTimer();
  }

  void _startBrightnessHideTimer() {
    _brightnessHideTimer?.cancel();
    _brightnessHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showBrightnessIndicator = false);
      }
    });
  }

  void _updateCurrentTime() {
    final now = DateTime.now();
    setState(() {
      _currentTime = DateFormat('HH:mm').format(now);
    });
  }

  void _startTimeUpdateTimer() {
    _timeUpdateTimer?.cancel();
    _timeUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateCurrentTime();
      }
    });
  }

  Future<void> _togglePlayPause() async {
    _onUserInteraction();
    if (_isPlaying) {
      await widget.player.pause();
      widget.onPause?.call();
    } else {
      await widget.player.play();
    }
  }

  void _enterFullscreen() {
    widget.state.enterFullscreen();
    widget.onFullscreenChange(true);
    _onUserInteraction();
  }

  void _exitFullscreen() {
    widget.state.exitFullscreen();
    widget.onFullscreenChange(false);
    // 触发退出全屏回调
    widget.onExitFullScreen?.call();
    // 重置屏幕方向为默认设置
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    setState(() {
      _isPortrait = true;
      _controlsVisible = true;
      _isLocked = false;
    });
    widget.onControlsVisibilityChanged(true);
    _startHideTimer();
  }

  Future<void> _showDLNADialog() async {
    if (_isPlaying) {
      await widget.player.pause();
      widget.onPause?.call();
    }
    if (_isFullscreen) {
      _exitFullscreen();
      await Future.delayed(const Duration(milliseconds: 250));
    }
    final resumePos = widget.player.state.position;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => DLNADeviceDialog(
        currentUrl: widget.videoUrl,
        resumePosition: resumePos,
        videoTitle: widget.videoTitle,
        currentEpisodeIndex: widget.currentEpisodeIndex,
        totalEpisodes: widget.totalEpisodes,
        sourceName: widget.sourceName,
        onCastStarted: widget.onCastStarted,
      ),
    );
  }

  Future<void> _showSpeedDialog() async {
    final speeds = [0.5, 0.75, 1.0, 1.5, 2.0];
    final currentSpeed = widget.playbackSpeedListenable.value;
    final screenHeight = MediaQuery.of(context).size.height;
    final result = await showModalBottomSheet<double>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.75,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: speeds.map((speed) {
                  final selected = (speed - currentSpeed).abs() < 0.01;
                  return ListTile(
                    title: Text(
                      '${speed}x',
                      style: TextStyle(
                        color: selected
                            ? Colors.red
                            : (isDark ? Colors.white : Colors.black87),
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(speed),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
    if (result != null) {
      await widget.onSetSpeed(result);
    }
  }

  Future<void> _enterPipMode() async {
    debugPrint('_enterPipMode');
    // 隐藏控制栏
    setState(() => _controlsVisible = false);
    widget.onControlsVisibilityChanged(false);
    _hideTimer?.cancel();
    // 调用父层的 PIP 逻辑
    await widget.onEnterPipMode();
  }

  Future<void> _toggleScreenOrientation() async {
    _onUserInteraction();
    setState(() {
      _isPortrait = !_isPortrait;
    });
    if (_isPortrait) {
      // 切换到竖屏
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      // 切换到横屏
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
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

  @override
  Widget build(BuildContext context) {
    if (widget.isLoadingVideo) {
      return Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              SizedBox(height: 16),
              Text('加载中...',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    Widget content = Stack(
      children: [
        Positioned.fill(child: _buildGestureLayer()),
        _buildTopGradient(),
        _buildBottomGradient(),
        if (_isFullscreen) _buildCurrentTime(),
        _buildBackButton(),
        _buildCastButton(),
        _buildCenterPlayPause(),
        _buildProgressBar(),
        _buildBottomControls(),
        if (_isLongPressing && !_isLocked) _buildLongPressIndicator(),
        if (_isFullscreen && _showBrightnessIndicator && !_isLocked)
          _buildBrightnessIndicator(),
        if (_isFullscreen) _buildRightOverlay(),
      ],
    );

    if (_isFullscreen) {
      content = PopScope(
        canPop: !_isLocked,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop && _isLocked) {
            setState(() {
              _isLocked = false;
              _controlsVisible = true;
            });
            _startHideTimer();
          }
        },
        child: content,
      );
    }

    return content;
  }

  Widget _buildGestureLayer() {
    return Positioned.fill(
      child: Row(
        children: [
          if (_isFullscreen)
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: _toggleControlsVisibility,
                onLongPressStart: _onLongPressStart,
                onLongPressEnd: _onLongPressEnd,
                onLongPressCancel: () {
                  if (_isLongPressing) {
                    _onLongPressEnd(const LongPressEndDetails());
                  }
                },
                onHorizontalDragStart: _onSwipeStart,
                onHorizontalDragUpdate: _onSwipeUpdate,
                onHorizontalDragEnd: _onSwipeEnd,
                onVerticalDragStart: _onBrightnessSwipeStart,
                onVerticalDragUpdate: _onBrightnessSwipeUpdate,
                onVerticalDragEnd: _onBrightnessSwipeEnd,
                behavior: HitTestBehavior.opaque,
              ),
            ),
          Expanded(
            flex: _isFullscreen ? 2 : 1,
            child: GestureDetector(
              onTap: _toggleControlsVisibility,
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
              onLongPressCancel: () {
                if (_isLongPressing) {
                  _onLongPressEnd(const LongPressEndDetails());
                }
              },
              onHorizontalDragStart: _onSwipeStart,
              onHorizontalDragUpdate: _onSwipeUpdate,
              onHorizontalDragEnd: _onSwipeEnd,
              behavior: HitTestBehavior.opaque,
            ),
          ),
          if (_isFullscreen)
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: _toggleControlsVisibility,
                onLongPressStart: _onLongPressStart,
                onLongPressEnd: _onLongPressEnd,
                onLongPressCancel: () {
                  if (_isLongPressing) {
                    _onLongPressEnd(const LongPressEndDetails());
                  }
                },
                onHorizontalDragStart: _onSwipeStart,
                onHorizontalDragUpdate: _onSwipeUpdate,
                onHorizontalDragEnd: _onSwipeEnd,
                onVerticalDragStart: _onVolumeSwipeStart,
                onVerticalDragUpdate: _onVolumeSwipeUpdate,
                onVerticalDragEnd: _onVolumeSwipeEnd,
                behavior: HitTestBehavior.opaque,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopGradient() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          child: Container(
            height: _isFullscreen ? 120 : 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTime() {
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          child: Center(
            child: Text(
              _currentTime,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomGradient() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          child: Container(
            height: _isFullscreen ? 140 : 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      top: _isFullscreen ? 8 : 4,
      left: _isFullscreen ? 16.0 : 8.0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controlsVisible || _isLocked,
          child: GestureDetector(
            onTap: () {
              _onUserInteraction();
              if (_isFullscreen) {
                _exitFullscreen();
              } else {
                widget.onBackPressed?.call();
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: _isFullscreen ? 24 : 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCastButton() {
    return Positioned(
      top: _isFullscreen ? 8 : 4,
      right: _isFullscreen ? 16.0 : 8.0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controlsVisible || _isLocked,
          child: GestureDetector(
            onTap: () async {
              _onUserInteraction();
              if (!widget.live) {
                widget.player.pause();
              }
              await _showDLNADialog();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.cast,
                color: Colors.white,
                size: _isFullscreen ? 24 : 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterPlayPause() {
    return Positioned.fill(
      child: Center(
        child: AnimatedOpacity(
          opacity:
              (!_isLocked && (!_isPlaying || _controlsVisible)) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: _isLocked || (_isPlaying && !_controlsVisible),
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: _isFullscreen ? 64 : 48,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Positioned(
      bottom: _isFullscreen ? 58.0 : 42.0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controlsVisible || _isLocked,
          child: Container(
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: _MobileVideoProgressBar(
              player: widget.player,
              live: widget.live,
              onDragStart: () {
                setState(() => _controlsVisible = true);
                _hideTimer?.cancel();
              },
              onDragEnd: () {
                setState(() => _dragPosition = null);
                _startHideTimer();
              },
              onDragUpdate: () {
                if (!_controlsVisible) {
                  setState(() => _controlsVisible = true);
                }
                _hideTimer?.cancel();
              },
              onPositionUpdate: (duration) {
                setState(() => _dragPosition = duration);
              },
              dragPosition: _dragPosition,
              isSeekingViaSwipe: _isSeekingViaSwipe,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final position = _dragPosition ?? _position;
    final duration = _duration;
    return Positioned(
      bottom: _isFullscreen ? 4.0 : -6.0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controlsVisible || _isLocked,
          child: Padding(
            padding: EdgeInsets.only(
              left: _isFullscreen ? 16.0 : 8.0,
              right: _isFullscreen ? 16.0 : 8.0,
              bottom: _isFullscreen ? 8.0 : 8.0,
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _togglePlayPause,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: _isFullscreen ? 28 : 24,
                    ),
                  ),
                ),
                if (!widget.isLastEpisode && !widget.live)
                  GestureDetector(
                    onTap: () {
                      _onUserInteraction();
                      widget.onNextEpisode?.call();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.skip_next,
                        color: Colors.white,
                        size: _isFullscreen ? 28 : 24,
                      ),
                    ),
                  ),
                if (!widget.live)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                      child: Text(
                        '${_formatDuration(position)} / ${_formatDuration(duration)}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                if (widget.live) const Spacer(),
                if (!widget.live)
                  GestureDetector(
                    onTap: () async {
                      _onUserInteraction();
                      await _showSpeedDialog();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: EdgeInsets.only(right: _isFullscreen ? 22 : 10),
                      child: Icon(
                        Icons.speed,
                        color: Colors.white,
                        size: _isFullscreen ? 22 : 20,
                      ),
                    ),
                  ),
                if (Platform.isAndroid)
                  GestureDetector(
                    onTap: () async {
                      print('PIP button clicked!');
                      _onUserInteraction();
                      await _enterPipMode();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.picture_in_picture_alt,
                        color: Colors.white,
                        size: _isFullscreen ? 22 : 20,
                      ),
                    ),
                  ),
                if (_isFullscreen) // 只在全屏模式下显示方向切换按钮
                  GestureDetector(
                    onTap: () async {
                      _onUserInteraction();
                      await _toggleScreenOrientation();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        _isPortrait ? Icons.screen_rotation : Icons.screen_rotation_alt,
                        color: Colors.white,
                        size: _isFullscreen ? 22 : 20,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: () {
                    _onUserInteraction();
                    if (_isFullscreen) {
                      _exitFullscreen();
                    } else {
                      _enterFullscreen();
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: EdgeInsets.only(left: _isFullscreen ? 12 : 5, right: _isFullscreen ? 12 : 8),
                    child: Icon(
                      _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                      size: _isFullscreen ? 28 : 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLongPressIndicator() {
    return const Positioned(
      top: 10,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('2x',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          SizedBox(width: 6),
          Icon(Icons.fast_forward, color: Colors.white, size: 32),
        ],
      ),
    );
  }

  Widget _buildBrightnessIndicator() {
    return Positioned(
      left: 16.0,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _currentBrightness < 0.5
                    ? Icons.brightness_low
                    : Icons.brightness_high,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                width: 4,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: _currentBrightness,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_currentBrightness * 100).round()}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightOverlay() {
    if (_showVolumeIndicator && !_isLocked) {
      return Positioned(
        right: 16.0,
        top: 0,
        bottom: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _currentVolume == 0
                      ? Icons.volume_off
                      : _currentVolume < 0.5
                          ? Icons.volume_down
                          : Icons.volume_up,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  width: 4,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: _currentVolume,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_currentVolume * 100).round()}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Positioned(
      right: 16.0,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isLocked = !_isLocked;
                  _controlsVisible = true;
                });
                _startHideTimer();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  _isLocked ? Icons.lock : Icons.lock_open,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileVideoProgressBar extends StatefulWidget {
  final Player player;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final VoidCallback? onDragUpdate;
  final Function(Duration)? onPositionUpdate;
  final Duration? dragPosition;
  final bool isSeekingViaSwipe;
  final bool live;

  const _MobileVideoProgressBar({
    required this.player,
    this.onDragStart,
    this.onDragEnd,
    this.onDragUpdate,
    this.onPositionUpdate,
    this.dragPosition,
    this.isSeekingViaSwipe = false,
    this.live = false,
  });

  @override
  State<_MobileVideoProgressBar> createState() =>
      _MobileVideoProgressBarState();
}

class _MobileVideoProgressBarState extends State<_MobileVideoProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;
  bool _isSeeking = false; // 新增：标记是否正在 seek
  StreamSubscription<Duration>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _positionSubscription = widget.player.stream.position.listen((_) {
      if (mounted && !_isDragging && !_isSeeking) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.player.state.duration;
    final position = widget.dragPosition ?? widget.player.state.position;

    double value = 0.0;
    if (duration.inMilliseconds > 0) {
      if (widget.live) {
        value = 1.0;
      } else {
        value = position.inMilliseconds / duration.inMilliseconds;
      }
    }

    if (_isDragging && !widget.live) {
      value = _dragValue;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: widget.live
          ? null
          : (details) {
              _isDragging = true;
              widget.onDragStart?.call();
              _updateDrag(details.localPosition.dx, context);
            },
      onHorizontalDragUpdate: widget.live
          ? null
          : (details) {
              if (_isDragging) {
                widget.onDragUpdate?.call();
                _updateDrag(details.localPosition.dx, context);
              }
            },
      onHorizontalDragEnd: widget.live
          ? null
          : (details) async {
              if (_isDragging) {
                final seekPosition = Duration(
                  milliseconds: (_dragValue * duration.inMilliseconds).round(),
                );

                setState(() {
                  _isDragging = false;
                  _isSeeking = true; // 标记开始 seek
                });

                await widget.player.seek(seekPosition);

                // seek 完成后，延迟一小段时间再允许位置更新，确保播放器状态已同步
                await Future.delayed(const Duration(milliseconds: 100));

                if (mounted) {
                  setState(() {
                    _isSeeking = false; // 标记 seek 完成
                  });
                }

                widget.onDragEnd?.call();
              }
            },
      onTapDown: widget.live
          ? null
          : (details) async {
              widget.onDragStart?.call();
              _updateDrag(details.localPosition.dx, context);
              final seekPosition = Duration(
                milliseconds: (_dragValue * duration.inMilliseconds).round(),
              );

              setState(() {
                _isSeeking = true; // 标记开始 seek
              });

              await widget.player.seek(seekPosition);

              // seek 完成后，延迟一小段时间再允许位置更新，确保播放器状态已同步
              await Future.delayed(const Duration(milliseconds: 100));

              if (mounted) {
                setState(() {
                  _isSeeking = false; // 标记 seek 完成
                });
              }

              widget.onDragEnd?.call();
            },
      child: Container(
        height: 24,
        color: Colors.transparent,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final progressWidth = constraints.maxWidth;
              final progressValue = value.clamp(0.0, 1.0);
              final thumbPosition = (progressValue * progressWidth)
                  .clamp(8.0, progressWidth - 8.0);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 9,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ),
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
                  if (!widget.live)
                    Positioned(
                      left: thumbPosition - 8,
                      top: 4,
                      child: AnimatedScale(
                        scale: widget.isSeekingViaSwipe ? 1.25 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
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
    );
  }

  void _updateDrag(double dx, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    final value = (dx / width).clamp(0.0, 1.0);
    setState(() => _dragValue = value);
    if (!widget.live) {
      final duration = widget.player.state.duration;
      final position =
          Duration(milliseconds: (value * duration.inMilliseconds).round());
      widget.onPositionUpdate?.call(position);
    }
  }
}
