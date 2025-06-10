import 'dart:async';

import 'package:closed_caption_companion/utils/constants.dart';
import 'package:closed_caption_companion/utils/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SettingsService extends ChangeNotifier {
  static const String _fontSizeKey = 'fontSize';
  static const String _themeModeKey = 'themeMode';
  static const String _saveTranscriptsKey = 'saveTranscripts';
  static const String _speechServiceKey = 'speechService';
  static const String _speechLocaleKey = 'speechLocale';
  static const String _userNameKey = 'userName';
  static const String _roomCodeKey = 'roomCode';
  static const String _deviceUuidKey = 'deviceUuid';
  static const String _sharingEnabledKey = 'sharingEnabled';
  static const String _accessKeySecureKey = 'accessKey';

  late SharedPreferences _prefs;
  static const _secureStorage = FlutterSecureStorage();

  // Settings
  double _fontSize = ThemeConfig.defaultFontSize;
  ThemeMode _themeMode = ThemeMode.system;
  bool _saveTranscripts = true;
  String _speechService = 'google'; // 'device', 'google', 'azure'
  String _speechLocale = 'en_AU'; // Default to Australian English
  String? _userName;
  String? _roomCode;
  String? _deviceUuid;
  bool _sharingEnabled = false;
  String? _accessKey;

  // Getters
  double get fontSize => _fontSize;
  ThemeMode get themeMode => _themeMode;
  bool get saveTranscripts => _saveTranscripts;
  String get speechService => _speechService;
  String get speechLocale => _speechLocale;
  String? get userName => _userName;
  String? get roomCode => _roomCode;
  String get deviceUuid => _deviceUuid ?? _generateAndStoreDeviceUuid();
  bool get sharingEnabled => _sharingEnabled;
  String? get accessKey => _accessKey;
  String get partyKitServer => AppConstants.partyKitServer;

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

    // Load room code
    _roomCode = _prefs.getString(_roomCodeKey);

    // Load or generate device UUID
    _deviceUuid = _prefs.getString(_deviceUuidKey);
    _deviceUuid ??= _generateAndStoreDeviceUuid();

    // Load sharing enabled
    _sharingEnabled = _prefs.getBool(_sharingEnabledKey) ?? false;

    // Load access key from secure storage
    if (_sharingEnabled) {
      _accessKey = await _secureStorage.read(key: _accessKeySecureKey);
    }

    notifyListeners();
  }

  String _generateAndStoreDeviceUuid() {
    const uuid = Uuid();
    final newUuid = uuid.v4();
    _prefs.setString(_deviceUuidKey, newUuid);
    _deviceUuid = newUuid;
    debugPrint('Generated and stored new device UUID: $newUuid');
    return newUuid;
  }

  Future<void> setFontSize(double size) async {
    if (size < ThemeConfig.minFontSize || size > ThemeConfig.maxFontSize) {
      return;
    }

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

  Future<void> setRoomCode(String? code) async {
    _roomCode = code?.trim();
    if (_roomCode != null && _roomCode!.isNotEmpty) {
      await _prefs.setString(_roomCodeKey, _roomCode!);
    } else {
      await _prefs.remove(_roomCodeKey);
      _roomCode = null;
    }
    notifyListeners();
  }

  Future<void> setSharingEnabled(bool enabled) async {
    _sharingEnabled = enabled;
    await _prefs.setBool(_sharingEnabledKey, enabled);

    // If disabling sharing, clear the access key
    if (!enabled) {
      await _secureStorage.delete(key: _accessKeySecureKey);
      _accessKey = null;
    }

    notifyListeners();
  }

  Future<void> setAccessKey(String? key) async {
    _accessKey = key?.trim();

    if (_accessKey != null &&
        _accessKey!.isNotEmpty &&
        _isValidAccessKey(_accessKey!)) {
      await _secureStorage.write(key: _accessKeySecureKey, value: _accessKey!);
    } else {
      await _secureStorage.delete(key: _accessKeySecureKey);
      _accessKey = null;
    }

    notifyListeners();
  }

  Future<void> forgetAccessKey() async {
    await _secureStorage.delete(key: _accessKeySecureKey);
    _accessKey = null;
    notifyListeners();
  }

  bool _isValidAccessKey(String key) {
    // Validate format: 4 words separated by hyphens
    final parts = key.split('-');
    return parts.length == 4 && parts.every((part) => part.trim().isNotEmpty);
  }

  String? validateAccessKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return null;

    if (!_isValidAccessKey(trimmed)) {
      return 'Access key must be 4 words separated by hyphens (e.g., apple-sky-moon-path)';
    }

    return null; // Valid
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
    await setRoomCode(null);
    await setSharingEnabled(false);
    await forgetAccessKey();
  }
}
