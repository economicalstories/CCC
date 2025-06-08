import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/caption_service.dart';
import '../services/settings_service.dart';
import '../services/audio_streaming_service.dart';
import '../widgets/push_to_talk_button.dart';
import '../widgets/caption_display.dart';
import '../widgets/status_indicator.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late AudioStreamingService _audioService;
  late CaptionService _captionService;
  late SettingsService _settingsService;

  bool _isInitialized = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Get services
    _audioService = context.read<AudioStreamingService>();
    _captionService = context.read<CaptionService>();
    _settingsService = context.read<SettingsService>();

    // Inject settings service into caption service
    _captionService.setSettingsService(_settingsService);

    // Initialize
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioService.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Stop streaming when app goes to background
      if (_audioService.isStreaming) {
        _handlePressUp();
      }
    }
  }

  Future<void> _initialize() async {
    try {
      // Set up audio service callbacks
      _audioService.onTranscription = (text, isFinal) {
        print('Received transcription: "$text" (final: $isFinal)');
        _captionService.addCaptionText(text, isFinal: isFinal);
      };

      _audioService.onError = (error) {
        _captionService.setError(error);
        HapticFeedback.mediumImpact();
      };

      _audioService.onConnected = () {
        _captionService.setConnecting(false);
      };

      _audioService.onDisconnected = () {
        _captionService.setStreaming(false);
      };

      // Initialize audio service
      await _audioService.initialize(
        speechService: _settingsService.speechService,
        settingsService: _settingsService,
      );

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _initError = e.toString();
      });
    }
  }

  Future<void> _handlePressDown() async {
    if (!_isInitialized) return;

    // Haptic feedback
    HapticFeedback.selectionClick();

    // Clear any previous error and current caption for fresh start
    _captionService.clearError();
    _captionService.clearCurrentCaption();

    // Connect if not connected
    if (!_audioService.isConnected) {
      _captionService.setConnecting(true);
      await _audioService.connect();
    }

    // Start streaming
    if (_audioService.isConnected) {
      _captionService.setStreaming(true);
      await _audioService.startStreaming();
    }
  }

  Future<void> _handlePressUp() async {
    if (!_isInitialized) return;

    // Haptic feedback
    HapticFeedback.selectionClick();

    // Stop streaming
    await _audioService.stopStreaming();
    _captionService.setStreaming(false);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    ).then((_) {
      // Reinitialize if settings changed
      _audioService.disconnect();
      _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header with settings button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Exit button
                  IconButton(
                    icon: Icon(
                      Icons.exit_to_app,
                      size: Theme.of(context).iconTheme.size,
                    ),
                    onPressed: () async {
                      // Clean up audio service before exiting
                      await _audioService.disconnect();
                      // Exit the app
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        // For web browsers, show a dialog message
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text('Exit App'),
                              content: const Text(
                                  'Close this browser tab to exit the application.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('OK'),
                                ),
                              ],
                            );
                          },
                        );
                      }
                    },
                    tooltip: 'Exit App',
                  ),

                  // Centered status indicator
                  const StatusIndicator(),

                  // Settings button with CCC icon
                  IconButton(
                    icon: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        'web/icons/Icon-192.png',
                        width: (Theme.of(context).iconTheme.size ?? 24) * 1.0,
                        height: (Theme.of(context).iconTheme.size ?? 24) * 1.0,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        isAntiAlias: true,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback to settings icon if image fails to load
                          return Icon(
                            Icons.settings,
                            size: Theme.of(context).iconTheme.size,
                          );
                        },
                      ),
                    ),
                    onPressed: _openSettings,
                    tooltip: 'Settings',
                  ),
                ],
              ),
            ),

            // Caption display
            const Expanded(
              child: CaptionDisplay(),
            ),

            // Transcript saving notification
            Consumer<SettingsService>(
              builder: (context, settings, _) {
                if (_captionService.isStreaming && settings.saveTranscripts) {
                  return Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.save,
                          size: 16,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Transcript kept temporarily • Will save when you release button',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.settings,
                            size: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                          onPressed: _openSettings,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 24, minHeight: 24),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            // Error or init message
            if (_initError != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _initError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else if (!_isInitialized)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),

            // Push to talk button - smaller padding for smaller button
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: PushToTalkButton(
                onPressDown: _handlePressDown,
                onPressUp: _handlePressUp,
                enabled: _isInitialized && _initError == null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
