import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/room_service.dart';
import '../services/settings_service.dart';
import '../services/audio_streaming_service.dart';
import '../widgets/room_caption_display.dart';
import '../utils/room_code_generator.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late RoomService _roomService;
  late AudioStreamingService _audioService;
  late SettingsService _settingsService;

  bool _isInitialized = false;
  String? _initError;
  bool _showShareOptions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Get services
    _roomService = RoomService();
    _audioService = context.read<AudioStreamingService>();
    _settingsService = context.read<SettingsService>();

    // Inject settings service into room service
    _roomService.setSettingsService(_settingsService);

    // Initialize
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Stop any ongoing speech
    if (_roomService.isSpeaking) {
      _audioService.stopStreaming();
    }
    _audioService.disconnect();
    _roomService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Stop streaming when app goes to background
      if (_audioService.isStreaming) {
        _handleMicRelease();
      }
    }
  }

  Future<void> _initialize() async {
    try {
      // Set up audio service callbacks
      _audioService.onTranscription = (text, isFinal) {
        print('Received transcription: "$text" (final: $isFinal)');
        if (_roomService.isSpeaking) {
          _roomService.addCaptionText(text, isFinal: isFinal);
        }
      };

      _audioService.onError = (error) {
        if (_roomService.isSpeaking) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      };

      _audioService.onConnected = () {
        setState(() {
          _isInitialized = true;
        });
      };

      _audioService.onDisconnected = () {
        if (_roomService.isSpeaking) {
          _roomService.stopSpeaking();
        }
      };

      // Initialize audio service
      await _audioService.initialize(
        speechService: _settingsService.speechService,
        settingsService: _settingsService,
      );

      // Auto-create or join saved room
      await _initializeRoom();

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _initError = e.toString();
      });
    }
  }

  Future<void> _initializeRoom() async {
    // Check if we have a saved room code
    final savedRoomCode = _settingsService.roomCode;
    final userName = _settingsService.userName ?? 'User';

    if (savedRoomCode != null) {
      // Try to join the saved room
      try {
        await _roomService.joinRoom(
            savedRoomCode, 'mock-encryption-key', userName);
      } catch (e) {
        // If joining fails, create a new room
        await _createNewRoom(userName);
      }
    } else {
      // Create a new room
      await _createNewRoom(userName);
    }
  }

  Future<void> _createNewRoom(String userName) async {
    await _roomService.createRoom(userName);
    // Save the room code for next time
    await _settingsService.setRoomCode(_roomService.roomCode);
  }

  Future<void> _handleMicPress() async {
    if (!_isInitialized) return;

    if (_roomService.activeSpeaker != null) {
      // Someone else is speaking
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_roomService.activeSpeaker!.name} is speaking...'),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      // Start speaking
      HapticFeedback.selectionClick();
      _roomService.startSpeaking();

      // Start speech recognition
      if (!_audioService.isConnected) {
        await _audioService.connect();
      }

      if (_audioService.isConnected) {
        await _audioService.startStreaming();
      }
    }
  }

  Future<void> _handleMicRelease() async {
    if (_roomService.isSpeaking) {
      HapticFeedback.selectionClick();

      // Stop speech recognition
      await _audioService.stopStreaming();

      _roomService.stopSpeaking();
    }
  }

  void _toggleShareOptions() {
    setState(() {
      _showShareOptions = !_showShareOptions;
    });
    HapticFeedback.lightImpact();
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    ).then((_) {
      // Check if room code changed in settings
      if (_settingsService.roomCode != _roomService.roomCode) {
        // Room changed, reinitialize
        _roomService.leaveRoom();
        _audioService.disconnect();
        _initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _roomService,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              // Header with room info
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Top row with exit and settings
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Exit button
                        IconButton(
                          icon: Icon(
                            Icons.exit_to_app,
                            size: Theme.of(context).iconTheme.size,
                          ),
                          onPressed: () async {
                            await _audioService.disconnect();
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                            } else {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: const Text('Exit App'),
                                    content: const Text(
                                        'Close this browser tab to exit the application.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
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

                        // Room code pill
                        if (_roomService.isInRoom)
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(
                                  text: _roomService.roomCode ?? ''));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Room code copied!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.room,
                                    size: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _roomService.roomCode ?? '',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Settings button
                        IconButton(
                          icon: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.asset(
                              'web/icons/Icon-192.png',
                              width: (Theme.of(context).iconTheme.size ?? 24) *
                                  1.0,
                              height: (Theme.of(context).iconTheme.size ?? 24) *
                                  1.0,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              isAntiAlias: true,
                              errorBuilder: (context, error, stackTrace) {
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
                  ],
                ),
              ),

              // Share options (when expanded)
              if (_showShareOptions && _roomService.isInRoom)
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Placeholder for QR code
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code,
                                size: 48,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'QR Code',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Others can join with code: ${_roomService.roomCode}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_roomService.participants.length} ${_roomService.participants.length == 1 ? 'person' : 'people'} in room',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                            ),
                      ),
                    ],
                  ),
                ),

              // Caption display
              const Expanded(
                child: RoomCaptionDisplay(),
              ),

              // Active speaker indicator
              if (_roomService.activeSpeaker != null)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Row(
                    children: [
                      Icon(
                        Icons.mic,
                        size: 16,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_roomService.activeSpeaker!.name} is speaking...',
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),

              // Audio error message
              if (_initError != null)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Speech recognition unavailable: $_initError',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Microphone button
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: GestureDetector(
                  onTapDown: (_) => _handleMicPress(),
                  onTapUp: (_) => _handleMicRelease(),
                  onTapCancel: _handleMicRelease,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _roomService.isSpeaking
                          ? Theme.of(context).colorScheme.error
                          : _roomService.activeSpeaker != null
                              ? Theme.of(context).disabledColor
                              : Theme.of(context).colorScheme.primary,
                      boxShadow: [
                        BoxShadow(
                          color: (_roomService.isSpeaking
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary)
                              .withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _roomService.activeSpeaker != null &&
                                !_roomService.isSpeaking
                            ? Icons.mic_off
                            : Icons.mic,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),

              // Status text
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  _roomService.isSpeaking
                      ? 'Release to stop'
                      : _roomService.activeSpeaker != null
                          ? 'Please wait...'
                          : 'Hold to speak',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        // Share button
        floatingActionButton: _isInitialized && _initError == null
            ? FloatingActionButton.small(
                onPressed: _toggleShareOptions,
                tooltip: 'Share Room',
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(_showShareOptions ? Icons.close : Icons.share),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
}
