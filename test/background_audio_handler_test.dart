import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:selene/services/background_audio_service.dart';

class TestPlayer extends Fake implements Player {
  PlayerState value = const PlayerState();
  final playing = StreamController<bool>.broadcast(sync: true);
  final buffering = StreamController<bool>.broadcast(sync: true);
  final completed = StreamController<bool>.broadcast(sync: true);
  final duration = StreamController<Duration>.broadcast(sync: true);
  final position = StreamController<Duration>.broadcast(sync: true);
  final buffer = StreamController<Duration>.broadcast(sync: true);
  final rate = StreamController<double>.broadcast(sync: true);
  final error = StreamController<String>.broadcast(sync: true);
  Duration? sought;
  Completer<void>? pauseGate;

  @override
  PlayerState get state => value;

  @override
  PlayerStream get stream => TestPlayerStream(this);

  @override
  Future<void> play() async {
    value = value.copyWith(playing: true, completed: false);
    playing.add(true);
  }

  @override
  Future<void> pause() async {
    await pauseGate?.future;
    value = value.copyWith(playing: false);
    playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    sought = position;
    value = value.copyWith(position: position);
    this.position.add(position);
  }
}

class TestPlayerStream extends Fake implements PlayerStream {
  TestPlayerStream(this.player);
  final TestPlayer player;
  @override
  Stream<bool> get playing => player.playing.stream;
  @override
  Stream<bool> get buffering => player.buffering.stream;
  @override
  Stream<bool> get completed => player.completed.stream;
  @override
  Stream<Duration> get duration => player.duration.stream;
  @override
  Stream<Duration> get position => player.position.stream;
  @override
  Stream<Duration> get buffer => player.buffer.stream;
  @override
  Stream<double> get rate => player.rate.stream;
  @override
  Stream<String> get error => player.error.stream;
}

class TestAudioSession extends Fake implements AudioSession {
  bool allow = true;
  final activations = <bool>[];
  final noisy = StreamController<void>.broadcast(sync: true);
  final interruptions = StreamController<AudioInterruptionEvent>.broadcast(
    sync: true,
  );

  @override
  Stream<void> get becomingNoisyEventStream => noisy.stream;
  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      interruptions.stream;

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    activations.add(active);
    return !active || allow;
  }
}

void main() {
  late BackgroundAudioHandler handler;
  late TestPlayer player;

  setUp(() {
    handler = BackgroundAudioHandler();
    player = TestPlayer();
    handler.attach(player, const MediaItem(id: 'episode', title: 'Episode 1'));
  });

  tearDown(() async {
    await handler.detach(player);
    await Future.wait([
      player.playing.close(),
      player.buffering.close(),
      player.completed.close(),
      player.duration.close(),
      player.position.close(),
      player.buffer.close(),
      player.rate.close(),
      player.error.close(),
    ]);
  });

  test('notification controls operate on the existing player', () async {
    await handler.play();
    expect(player.state.playing, isTrue);
    expect(handler.playbackState.value.playing, isTrue);
    await handler.seek(const Duration(seconds: 42));
    expect(player.sought, const Duration(seconds: 42));
    await handler.pause();
    expect(player.state.playing, isFalse);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('stop releases foreground playback and can play again', () async {
    await handler.play();
    await handler.stop();
    expect(player.state.playing, isFalse);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
    await handler.play();
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
    expect(handler.playbackState.value.playing, isTrue);
  });

  test('stop wins over an in-flight player open', () async {
    player.pauseGate = Completer<void>();
    final stopping = handler.stop();
    await player.play();
    player.pauseGate!.complete();
    await stopping;
    expect(player.state.playing, isFalse);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('closing an old player cannot clear a newer session', () async {
    final replacement = TestPlayer();
    handler.attach(
      replacement,
      const MediaItem(id: 'live', title: 'Live'),
      live: true,
    );
    await handler.detach(player);
    expect(handler.mediaItem.value?.id, 'live');
    expect(
      handler.playbackState.value.systemActions,
      isNot(contains(MediaAction.seek)),
    );
    await handler.detach(replacement);
  });

  test(
    'closing the active player removes metadata and foreground state',
    () async {
      await handler.play();
      await handler.detach(player);
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      await player.play();
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test('completion and task removal release foreground playback', () async {
    await handler.play();
    player.value = player.value.copyWith(completed: true);
    player.completed.add(true);
    expect(handler.playbackState.value.playing, isFalse);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.completed,
    );
    await handler.onTaskRemoved();
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('denied audio focus pauses playback', () async {
    await handler.detach(player);
    final session = TestAudioSession()..allow = false;
    handler = BackgroundAudioHandler(session: session);
    handler.attach(player, const MediaItem(id: 'test', title: 'Test'));
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(player.state.playing, isFalse);
    expect(session.activations, containsAllInOrder([true, false]));
    await handler.detach(player);
    await session.noisy.close();
    await session.interruptions.close();
  });

  test('unplugging headphones pauses and releases focus', () async {
    await handler.detach(player);
    final session = TestAudioSession();
    handler = BackgroundAudioHandler(session: session);
    handler.attach(player, const MediaItem(id: 'test', title: 'Test'));
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    session.noisy.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(player.state.playing, isFalse);
    expect(session.activations.last, isFalse);
    await handler.detach(player);
    await session.noisy.close();
    await session.interruptions.close();
  });

  test('recoverable decoder errors do not stop playback', () async {
    await handler.play();
    player.error.add('Decoder fallback');
    expect(handler.playbackState.value.playing, isTrue);
  });

  test(
    'disabled background playback pauses and blocks remote resume',
    () async {
      await handler.play();
      handler.updateBackgroundPolicy(
        player,
        enabled: false,
        isBackground: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(player.state.playing, isFalse);
      await handler.play();
      expect(player.state.playing, isFalse);
      handler.updateBackgroundPolicy(
        player,
        enabled: false,
        isBackground: false,
      );
      expect(player.state.playing, isFalse);
      await handler.play();
      expect(player.state.playing, isTrue);
    },
  );

  test(
    'disabled background playback also pauses direct player starts',
    () async {
      handler.updateBackgroundPolicy(
        player,
        enabled: false,
        isBackground: true,
      );
      await player.play();
      await Future<void>.delayed(Duration.zero);
      expect(player.state.playing, isFalse);
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test('old player cannot disable a replacement session', () async {
    final replacement = TestPlayer();
    handler.attach(replacement, const MediaItem(id: 'next', title: 'Next'));
    handler.updateBackgroundPolicy(player, enabled: false, isBackground: true);
    await handler.play();
    expect(replacement.state.playing, isTrue);
    await handler.detach(replacement);
  });
}
