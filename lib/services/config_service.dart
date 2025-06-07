import 'dart:convert';
import 'package:flutter/services.dart';

class ConfigService {
  static Map<String, dynamic>? _config;

  static Future<void> initialize() async {
    try {
      final String configString =
          await rootBundle.loadString('assets/config.json');
      _config = json.decode(configString);
      print('Config loaded: $_config');
    } catch (e) {
      print('Failed to load config: $e');
      _config = _getDefaultConfig();
    }
  }

  static Map<String, dynamic> _getDefaultConfig() {
    return {
      "speechService": "google",
      "speechLocale": "en_AU",
      "fontSize": 48,
      "theme": "system",
      "saveTranscripts": true,
      "features": {
        "showTranscriptHistory": true,
        "autoScrollEnabled": true,
        "hapticFeedback": true
      },
      "speechSettings": {
        "pauseDuration": 3,
        "listenDuration": 30,
        "confidenceThreshold": 0.5
      }
    };
  }

  // Getters for easy access
  static String get speechService => _config?['speechService'] ?? 'google';
  static String get speechLocale => _config?['speechLocale'] ?? 'en_AU';
  static double get fontSize => (_config?['fontSize'] ?? 48).toDouble();
  static String get theme => _config?['theme'] ?? 'system';
  static bool get saveTranscripts => _config?['saveTranscripts'] ?? true;

  // Feature flags
  static bool get showTranscriptHistory =>
      _config?['features']?['showTranscriptHistory'] ?? true;
  static bool get autoScrollEnabled =>
      _config?['features']?['autoScrollEnabled'] ?? true;
  static bool get hapticFeedback =>
      _config?['features']?['hapticFeedback'] ?? true;

  // Speech settings
  static int get pauseDuration =>
      _config?['speechSettings']?['pauseDuration'] ?? 3;
  static int get listenDuration =>
      _config?['speechSettings']?['listenDuration'] ?? 30;
  static double get confidenceThreshold =>
      (_config?['speechSettings']?['confidenceThreshold'] ?? 0.5).toDouble();

  // Debug info
  static Map<String, dynamic> get allConfig => _config ?? {};
}
