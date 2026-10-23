import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'playback_settings.dart';

/// Keeps Android's media session connected to the visible video player.
/// The service retains the Flutter engine while the screen is off.
class BackgroundAudioService {
  static BackgroundAudioHandler? handler;

  static Future<void> initialize() async {
    if (!Platform.isAndroid || handler != null) return;
    await PlaybackSettings.instance.load();
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    handler = await AudioService.init<BackgroundAudioHandler>(
      builder: () => BackgroundAudioHandler(session: session),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'org.moontechlab.selene.playback',
        androidNotificationChannelName: 'Media playback',
        androidStopForegroundOnPause: true,
      ),
    );
  }
}

class BackgroundAudioHandler extends BaseAudioHandler {
  BackgroundAudioHandler({AudioSession? session}) : _session = session {
    session?.becomingNoisyEventStream.listen((_) => pause());
    session?.interruptionEventStream.listen((event) {
      if (event.begin) unawaited(pause());
    });
  }

  final AudioSession? _session;
  Player? _player;
  bool _live = false;
  bool _stopped = false;
  bool _backgroundEnabled = true;
  bool _inBackground = false;
  bool get _playbackAllowed => _backgroundEnabled || !_inBackground;
  int _commandGeneration = 0;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _focusUpdate = Future<void>.value();

  void attach(Player player, MediaItem item, {bool live = false}) {
    _commandGeneration++;
    _cancelSubscriptions();
    _player = player;
    _live = live;
    _stopped = false;
    mediaItem.add(item);
    void refresh(dynamic _) => _publish();
    _subscriptions.addAll([
      player.stream.playing.listen((playing) {
        if (playing && !_playbackAllowed) {
          unawaited(pause());
        }
        if (playing) _stopped = false;
        _publish();
        _syncAudioFocus();
      }),
      player.stream.buffering.listen(refresh),
      player.stream.completed.listen((_) {
        _publish();
        _syncAudioFocus();
      }),
      player.stream.position.listen(refresh),
      player.stream.buffer.listen(refresh),
      player.stream.rate.listen(refresh),
      player.stream.duration.listen((duration) {
        final current = mediaItem.value;
        if (current != null && !_live) {
          mediaItem.add(current.copyWith(duration: duration));
        }
        _publish();
      }),
      player.stream.error.listen((message) {
        debugPrint('Media playback: $message');
      }),
    ]);
    _publish();
  }

  void updateBackgroundPolicy(
    Player player, {
    required bool enabled,
    required bool isBackground,
  }) {
    if (!identical(player, _player)) return;
    _backgroundEnabled = enabled;
    _inBackground = isBackground;
    if (!_playbackAllowed) unawaited(pause());
  }

  void updateMetadata(Player player, MediaItem item, {bool live = false}) {
    if (!identical(player, _player)) return;
    _live = live;
    mediaItem.add(item);
    _publish();
  }

  Future<void> detach(Player player) async {
    if (!identical(player, _player)) return;
    _commandGeneration++;
    _player = null;
    _cancelSubscriptions();
    mediaItem.add(null);
    playbackState.add(PlaybackState());
    _syncAudioFocus();
    await _focusUpdate;
  }

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _syncAudioFocus() {
    if (_session == null) return;
    // Serialize activation and release so a late pause cannot steal focus
    // from a replacement player or a quick notification resume.
    _focusUpdate = _focusUpdate
        .then<void>((_) async {
          final player = _player;
          final playing =
              player != null &&
              player.state.playing &&
              !player.state.completed &&
              !_stopped &&
              _playbackAllowed;
          final allowed = await _session.setActive(playing);
          if (playing && !allowed && identical(player, _player)) {
            await player.pause();
          }
        })
        .catchError((Object error) async {
          // Failed focus requests must not allow competing background audio.
          if (_player?.state.playing ?? false) await pause();
        });
  }

  void _publish() {
    final player = _player;
    if (player == null) return;
    final state = player.state;
    final playing =
        state.playing && !state.completed && !_stopped && _playbackAllowed;
    playbackState.add(
      PlaybackState(
        controls: [
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop.copyWith(
            androidIcon: 'drawable/ic_notification_stop',
          ),
        ],
        systemActions: {if (!_live) MediaAction.seek},
        androidCompactActionIndices: const [0, 1],
        processingState: _stopped
            ? AudioProcessingState.idle
            : state.completed
            ? AudioProcessingState.completed
            : state.buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: state.position,
        bufferedPosition: state.buffer,
        speed: state.rate,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (!_playbackAllowed) return;
    _commandGeneration++;
    _stopped = false;
    await _player?.play();
    _publish();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
    _publish();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_live) await _player?.seek(position);
    _publish();
  }

  @override
  Future<void> stop() async {
    final player = _player;
    final generation = ++_commandGeneration;
    _stopped = true;
    await player?.pause();
    if (identical(player, _player) && generation == _commandGeneration) {
      _stopped = true;
      _publish();
      _syncAudioFocus();
    }
  }

  @override
  Future<void> onTaskRemoved() => stop();
}
