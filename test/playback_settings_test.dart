import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selene/services/playback_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('background playback is enabled by default', () async {
    final settings = PlaybackSettings();
    await settings.load();
    expect(settings.backgroundPlaybackEnabled, isTrue);
  });

  test('toggle persists across new settings instances', () async {
    final settings = PlaybackSettings();
    await settings.load();
    await settings.setBackgroundPlaybackEnabled(false);
    final restored = PlaybackSettings();
    await restored.load();
    expect(restored.backgroundPlaybackEnabled, isFalse);
    await restored.setBackgroundPlaybackEnabled(true);
    await settings.load();
    expect(settings.backgroundPlaybackEnabled, isTrue);
  });
}
