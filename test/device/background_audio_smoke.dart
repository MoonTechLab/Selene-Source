// Device smoke test: build with -t test/device/background_audio_smoke.dart.
// Uses the same widget/service as on-demand and live playback, without login.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:selene/services/background_audio_service.dart';
import 'package:selene/widgets/video_player_widget.dart';
import 'package:selene/widgets/user_menu.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await BackgroundAudioService.initialize();
  runApp(const MaterialApp(home: PlaybackSmokeTest()));
}

class PlaybackSmokeTest extends StatefulWidget {
  const PlaybackSmokeTest({super.key});
  @override
  State<PlaybackSmokeTest> createState() => _PlaybackSmokeTestState();
}

class _PlaybackSmokeTestState extends State<PlaybackSmokeTest> {
  VideoPlayerWidgetController? _controller;
  Timer? _timer;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      debugPrint('BACKGROUND_AUDIO_SMOKE '
          'playing=${_controller?.isPlaying} '
          'position=${_controller?.currentPosition?.inMilliseconds} '
          'closed=$_closed');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Selene'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => UserMenu(
                  isDarkMode: false,
                  onClose: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ],
        ),
        body: Column(children: [
          if (!_closed)
            SizedBox(
              height: 260,
              child: VideoPlayerWidget(
                url: const String.fromEnvironment('SMOKE_MEDIA_URL',
                    defaultValue: 'https://storage.googleapis.com/'
                        'gtv-videos-bucket/sample/BigBuckBunny.mp4'),
                videoTitle: 'Big Buck Bunny',
                live: const bool.fromEnvironment('SMOKE_LIVE'),
                onControllerCreated: (controller) => _controller = controller,
              ),
            ),
          TextButton(
            onPressed: () => setState(() => _closed = true),
            child: const Text('Close player'),
          ),
        ]),
      );
}
