import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackSettings extends ChangeNotifier {
  static final instance = PlaybackSettings();
  static const _backgroundPlaybackKey = 'background_playback_enabled';
  bool _backgroundPlaybackEnabled = true;

  bool get backgroundPlaybackEnabled => _backgroundPlaybackEnabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _backgroundPlaybackEnabled = prefs.getBool(_backgroundPlaybackKey) ?? true;
    notifyListeners();
  }

  Future<void> setBackgroundPlaybackEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_backgroundPlaybackKey, enabled)) {
      throw StateError('Could not save background playback setting');
    }
    _backgroundPlaybackEnabled = enabled;
    notifyListeners();
  }
}
