import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'settings_service.dart';

class AudioStreamingService {
  // Speech to text engine
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _speechEnabled = false;
  Timer? _restartTimer;
  Timer? _reliabilityTimer;
  bool _shouldContinueListening = false;
  int _restartAttempts = 0;
  bool _isRestarting = false;
  String _accumulatedText = '';
  String _currentChunk = '';
  String _speechService = 'device';
  SettingsService? _settingsService;

  // Reliability improvements
  static const int _maxRestartAttempts = 5;
  static const Duration _baseRestartDelay = Duration(milliseconds: 500);
  static const Duration _reliabilityCheckInterval = Duration(seconds: 10);
  DateTime? _lastSuccessfulRecognition;
  int _consecutiveFailures = 0;

  // Callbacks
  Function(String text, bool isFinal)? onTranscription;
  Function(String error)? onError;
  Function()? onConnected;
  Function()? onDisconnected;

  // State
  bool _isConnected = false;
  bool _isStreaming = false;

  bool get isConnected => _isConnected;
  bool get isStreaming => _isStreaming;
  String get speechService => _speechService;

  // Initialize the service
  Future<void> initialize({
    required String speechService,
    SettingsService? settingsService,
  }) async {
    _speechService = speechService;
    _settingsService = settingsService;

    // Request microphone permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw Exception('Microphone permission denied');
    }

    // Initialize speech to text
    try {
      print('Initializing speech recognition service: $_speechService');
      _speechEnabled = await _speechToText.initialize(
        onError: (error) {
          print('STT Error: ${error.errorMsg} (permanent: ${error.permanent})');
          _handleSpeechError(error);
        },
        onStatus: (status) {
          print('STT Status: $status');
          _handleSpeechStatus(status);
        },
      );

      print('Speech recognition enabled: $_speechEnabled');

      if (!_speechEnabled) {
        throw Exception('Speech recognition not available on this device');
      }

      // Check available locales and engines
      final locales = await _speechToText.locales();
      print('Available locales: ${locales.length}');
      if (locales.isNotEmpty) {
        print(
            'Sample locales: ${locales.take(5).map((l) => l.localeId).join(', ')}');
      }
      print('Using locale: ${_settingsService?.speechLocale ?? 'en_AU'}');

      // Start reliability monitoring
      _startReliabilityMonitoring();
    } catch (e) {
      print('Failed to initialize speech recognition: $e');
      throw Exception('Failed to initialize speech recognition: $e');
    }
  }

  // Enhanced error handling
  void _handleSpeechError(dynamic error) {
    _consecutiveFailures++;

    // Only restart on non-permanent errors and if we should continue listening
    if (_shouldContinueListening && _isStreaming && !_isRestarting) {
      if (error.permanent) {
        print('Permanent error detected: ${error.errorMsg}');
        onError?.call('Speech recognition unavailable: ${error.errorMsg}');
        return;
      }

      // Handle specific error types with different strategies
      Duration delay = _baseRestartDelay;

      switch (error.errorMsg) {
        case 'error_busy':
          delay = const Duration(seconds: 2);
          break;
        case 'error_no_match':
          // This is common and not really an error
          _consecutiveFailures--;
          return;
        case 'error_speech_timeout':
          delay = const Duration(milliseconds: 800);
          break;
        case 'error_network':
          delay = const Duration(seconds: 3);
          break;
        default:
          delay = Duration(
              milliseconds:
                  _baseRestartDelay.inMilliseconds * _consecutiveFailures);
      }

      if (_restartAttempts < _maxRestartAttempts) {
        _scheduleRestart(delay);
      } else {
        print('Max restart attempts reached, stopping');
        onError?.call('Speech recognition failed after multiple attempts');
      }
    }
  }

  // Enhanced status handling
  void _handleSpeechStatus(String status) {
    switch (status) {
      case 'listening':
        _consecutiveFailures = 0;
        _lastSuccessfulRecognition = DateTime.now();
        break;
      case 'notListening':
        // If listening stopped but we should continue, restart
        if (_shouldContinueListening && _isStreaming && !_isRestarting) {
          _scheduleRestart();
        }
        break;
      case 'done':
        // Speech recognition session completed
        break;
    }
  }

  // Reliability monitoring
  void _startReliabilityMonitoring() {
    _reliabilityTimer?.cancel();
    _reliabilityTimer = Timer.periodic(_reliabilityCheckInterval, (timer) {
      if (_isStreaming && _shouldContinueListening) {
        final now = DateTime.now();
        final timeSinceLastSuccess = _lastSuccessfulRecognition != null
            ? now.difference(_lastSuccessfulRecognition!)
            : Duration.zero;

        // If no successful recognition for too long, restart
        if (timeSinceLastSuccess > const Duration(seconds: 30)) {
          print('No recognition activity detected, restarting...');
          _scheduleRestart();
        }
      }
    });
  }

  // Connect - prepare the service
  Future<void> connect() async {
    if (_isConnected) return;

    print('Connecting to $_speechService speech recognition service');
    _isConnected = true;
    onConnected?.call();
  }

  // Start audio streaming with enhanced configuration
  Future<void> startStreaming() async {
    if (!_isConnected || _isStreaming) return;

    _isStreaming = true;
    _shouldContinueListening = true;
    _restartAttempts = 0;
    _consecutiveFailures = 0;
    _isRestarting = false;
    _accumulatedText = '';
    _currentChunk = '';
    _lastSuccessfulRecognition = DateTime.now();

    await _startSpeechRecognition();
  }

  // Schedule a restart with exponential backoff
  void _scheduleRestart([Duration? delay]) {
    if (_isRestarting || _restartAttempts >= _maxRestartAttempts) return;

    _restartTimer?.cancel();

    // Calculate backoff delay
    final backoffMultiplier =
        (1 << _consecutiveFailures.clamp(0, 4)); // Cap at 16x
    final calculatedDelay = delay ??
        Duration(
            milliseconds: _baseRestartDelay.inMilliseconds * backoffMultiplier);

    // Cap the delay at 10 seconds
    final finalDelay = Duration(
      milliseconds: calculatedDelay.inMilliseconds.clamp(500, 10000),
    );

    print(
        'Scheduling restart in ${finalDelay.inMilliseconds}ms (attempt ${_restartAttempts + 1}, failures: $_consecutiveFailures)');

    _restartTimer = Timer(finalDelay, () {
      if (_shouldContinueListening && _isStreaming) {
        _restartAttempts++;
        _startSpeechRecognition();
      }
    });
  }

  // Enhanced speech recognition with service-specific configurations
  Future<void> _startSpeechRecognition() async {
    if (!_speechEnabled || _isRestarting) {
      print('Speech recognition not enabled or already restarting');
      return;
    }

    if (!_shouldContinueListening || !_isStreaming) {
      return;
    }

    _isRestarting = true;

    try {
      // ALWAYS preserve current chunk before restart (regardless of speech state)
      if (_currentChunk.isNotEmpty && _isStreaming) {
        print('Preserving partial text before restart: "$_currentChunk"');
        if (_accumulatedText.isEmpty) {
          _accumulatedText = _currentChunk;
        } else {
          _accumulatedText = '$_accumulatedText $_currentChunk';
        }
        _currentChunk = '';
        print('Text preserved. New accumulated: "$_accumulatedText"');
      }

      // Stop any existing session
      if (_speechToText.isListening) {
        print('Stopping existing speech recognition session...');
        await _speechToText.stop();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Double-check we should still be listening
      if (!_shouldContinueListening || !_isStreaming) {
        _isRestarting = false;
        return;
      }

      print('Starting $_speechService speech recognition...');

      // Configure based on selected service
      final config = _getServiceConfiguration();

      await _speechToText.listen(
        onResult: (result) {
          _handleSpeechResult(result);
        },
        listenFor: config['listenDuration'] as Duration,
        pauseFor: config['pauseDuration'] as Duration,
        partialResults: config['partialResults'] as bool,
        localeId: config['localeId'] as String,
        listenMode: config['listenMode'] as stt.ListenMode,
        cancelOnError: false,
        onDevice: config['onDevice'] as bool,
      );

      print('$_speechService speech recognition started successfully');
      _isRestarting = false;
      _lastSuccessfulRecognition = DateTime.now();
    } catch (e) {
      print('Error starting speech recognition: $e');
      _isRestarting = false;

      if (_shouldContinueListening && _isStreaming) {
        _scheduleRestart(const Duration(seconds: 2));
      } else {
        onError?.call('Failed to start speech recognition: $e');
      }
    }
  }

  // Get service-specific configuration
  Map<String, dynamic> _getServiceConfiguration() {
    // Get locale from settings, default to Australian English
    final locale = _settingsService?.speechLocale ?? 'en_AU';

    switch (_speechService) {
      case 'google':
        return {
          'listenDuration': const Duration(seconds: 30),
          'pauseDuration': const Duration(seconds: 3),
          'partialResults': true,
          'localeId': locale,
          'listenMode': stt.ListenMode.dictation,
          'onDevice': false, // Use cloud for better accuracy
        };

      case 'azure':
        return {
          'listenDuration': const Duration(seconds: 30),
          'pauseDuration': const Duration(seconds: 2),
          'partialResults': true,
          'localeId': locale,
          'listenMode': stt.ListenMode.dictation,
          'onDevice': false, // Use cloud for better accuracy
        };

      case 'device':
      default:
        return {
          'listenDuration': const Duration(seconds: 60),
          'pauseDuration': const Duration(seconds: 2),
          'partialResults': true,
          'localeId': locale,
          'listenMode': stt.ListenMode.dictation,
          'onDevice': true, // Use device for offline capability
        };
    }
  }

  // Enhanced result handling
  void _handleSpeechResult(dynamic result) {
    if (result.recognizedWords.isEmpty) return;

    print(
        'Speech result ($_speechService): "${result.recognizedWords}" (final: ${result.finalResult}, confidence: ${result.confidence})');

    // Reset failure counters on successful recognition
    _consecutiveFailures = 0;
    _restartAttempts = 0;
    _lastSuccessfulRecognition = DateTime.now();

    // NEW APPROACH: Always set the current chunk to the new recognized words
    // This will be the latest recognition result from this session
    _currentChunk = result.recognizedWords;

    // Combine accumulated text (from previous sessions) with current chunk for display
    String fullText = _accumulatedText.isEmpty
        ? _currentChunk
        : '$_accumulatedText $_currentChunk';

    // Send update (never mark as final during streaming)
    onTranscription?.call(fullText, false);

    print(
        'Current accumulated: "$_accumulatedText", current chunk: "$_currentChunk", full text: "$fullText"');

    // During recording, we only accumulate when sessions end (in restart logic)
    // Not based on final results, since Google doesn't always send them before restart
  }

  // Stop audio streaming
  Future<void> stopStreaming() async {
    if (!_isStreaming) return;

    print('Stopping audio streaming...');
    _shouldContinueListening = false;
    _isStreaming = false;
    _restartAttempts = 0;
    _consecutiveFailures = 0;
    _isRestarting = false;

    _restartTimer?.cancel();

    if (_speechToText.isListening) {
      await _speechToText.stop();
    }

    // Send final transcript if we have accumulated text
    if (_accumulatedText.isNotEmpty || _currentChunk.isNotEmpty) {
      final finalText = _accumulatedText.isEmpty
          ? _currentChunk
          : _currentChunk.isEmpty
              ? _accumulatedText
              : '$_accumulatedText $_currentChunk';

      if (finalText.isNotEmpty) {
        print('Sending final transcript ($_speechService): "$finalText"');
        onTranscription?.call(finalText, true); // Mark as final for saving
      }
    }

    // Clean up
    _accumulatedText = '';
    _currentChunk = '';
  }

  // Disconnect from service
  Future<void> disconnect() async {
    await stopStreaming();
    _reliabilityTimer?.cancel();
    _isConnected = false;
    onDisconnected?.call();
  }

  // Dispose resources
  void dispose() {
    _restartTimer?.cancel();
    _reliabilityTimer?.cancel();
    disconnect();
  }
}
