import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme_config.dart';

class SettingsService extends ChangeNotifier {
  static const String _fontSizeKey = 'fontSize';
  static const String _themeModeKey = 'themeMode';
  static const String _saveTranscriptsKey = 'saveTranscripts';
  static const String _speechServiceKey = 'speechService';
  static const String _speechLocaleKey = 'speechLocale';
  static const String _userNameKey = 'userName';

  late SharedPreferences _prefs;

  // Settings
  double _fontSize = ThemeConfig.defaultFontSize;
  ThemeMode _themeMode = ThemeMode.system;
  bool _saveTranscripts = true;
  String _speechService = 'google'; // 'device', 'google', 'azure'
  String _speechLocale = 'en_AU'; // Default to Australian English
  String? _userName;

  // Getters
  double get fontSize => _fontSize;
  ThemeMode get themeMode => _themeMode;
  bool get saveTranscripts => _saveTranscripts;
  String get speechService => _speechService;
  String get speechLocale => _speechLocale;
  String? get userName => _userName;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Load font size
    _fontSize = _prefs.getDouble(_fontSizeKey) ?? ThemeConfig.defaultFontSize;

    // Load theme mode
    final themeModeIndex =
        _prefs.getInt(_themeModeKey) ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[themeModeIndex];

    // Load save transcripts
    _saveTranscripts = _prefs.getBool(_saveTranscriptsKey) ?? true;

    // Load speech service
    _speechService = _prefs.getString(_speechServiceKey) ?? 'google';

    // Load speech locale
    _speechLocale = _prefs.getString(_speechLocaleKey) ?? 'en_AU';

    // Load user name
    _userName = _prefs.getString(_userNameKey);

    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    if (size < ThemeConfig.minFontSize || size > ThemeConfig.maxFontSize)
      return;

    _fontSize = size;
    await _prefs.setDouble(_fontSizeKey, size);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setInt(_themeModeKey, mode.index);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    // Simple toggle between light and dark
    final newMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await setThemeMode(newMode);
  }

  Future<void> setSaveTranscripts(bool enabled) async {
    _saveTranscripts = enabled;
    await _prefs.setBool(_saveTranscriptsKey, enabled);
    notifyListeners();
  }

  Future<void> setSpeechService(String service) async {
    _speechService = service;
    await _prefs.setString(_speechServiceKey, service);
    notifyListeners();
  }

  Future<void> setSpeechLocale(String locale) async {
    _speechLocale = locale;
    await _prefs.setString(_speechLocaleKey, locale);
    notifyListeners();
  }

  Future<void> setUserName(String? name) async {
    _userName = name?.trim();
    if (_userName != null && _userName!.isNotEmpty) {
      await _prefs.setString(_userNameKey, _userName!);
    } else {
      await _prefs.remove(_userNameKey);
      _userName = null;
    }
    notifyListeners();
  }

  // Convenience methods for font size adjustment
  Future<void> increaseFontSize() async {
    final newSize =
        (_fontSize + 4).clamp(ThemeConfig.minFontSize, ThemeConfig.maxFontSize);
    await setFontSize(newSize);
  }

  Future<void> decreaseFontSize() async {
    final newSize =
        (_fontSize - 4).clamp(ThemeConfig.minFontSize, ThemeConfig.maxFontSize);
    await setFontSize(newSize);
  }

  Future<void> resetSettings() async {
    await setFontSize(ThemeConfig.defaultFontSize);
    await setThemeMode(ThemeMode.system);
    await setSaveTranscripts(true);
    await setSpeechService('google');
    await setSpeechLocale('en_AU');
    await setUserName(null);
  }
}
