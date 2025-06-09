import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:closed_caption_companion/services/room_service.dart';
import 'package:closed_caption_companion/services/audio_streaming_service.dart';
import 'package:closed_caption_companion/services/settings_service.dart';
import 'package:closed_caption_companion/widgets/room_caption_display.dart';
import 'package:closed_caption_companion/utils/room_code_generator.dart';

class GroupRoomScreen extends StatefulWidget {
  const GroupRoomScreen({
    Key? key,
    this.roomCode,
    this.encryptionKey,
  }) : super(key: key);
  final String? roomCode;
  final String? encryptionKey;

  @override
  State<GroupRoomScreen> createState() => _GroupRoomScreenState();
}

class _GroupRoomScreenState extends State<GroupRoomScreen> {
  late RoomService _roomService;
  late AudioStreamingService _audioService;
  late SettingsService _settingsService;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _roomCodeController = TextEditingController();

  bool _isJoining = false;
  bool _showQrCode = false;
  bool _isAudioInitialized = false;
  String? _audioInitError;
  bool _isButtonPressed = false;
  bool _showSpeakClearlyMessage = false;

  @override
  void initState() {
    super.initState();
    _roomService = RoomService();
    _audioService = context.read<AudioStreamingService>();
    _settingsService = context.read<SettingsService>();

    // Inject settings service into room service
    _roomService.setSettingsService(_settingsService);

    // Initialize audio service for the room
    _initializeAudio();

    // ALWAYS start in offline mode first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeOfflineMode();
    });
  }

  Future<void> _initializeOfflineMode() async {
    // Initialize offline mode with user info
    _roomService.initializeOfflineMode(userName: _settingsService.userName);

    // Attempt background connection (non-blocking)
    // Check if we have a room code to rejoin or if we should create new
    final savedRoomCode = _settingsService.roomCode;

    if (widget.roomCode != null && widget.encryptionKey != null) {
      // Explicit room code provided - try to join it
      debugPrint('🔗 Attempting to join provided room: ${widget.roomCode}');
      _roomService.attemptBackgroundConnection();
      // Then try to join the specific room
      await _joinRoomWithCode(widget.roomCode!, widget.encryptionKey!);
    } else {
      // No explicit room code - try background connection with saved room or create new
      debugPrint(
          '🔗 Attempting background connection with saved room: $savedRoomCode');
      _roomService.attemptBackgroundConnection(savedRoomCode: savedRoomCode);
    }
  }

  Future<void> _initializeAudio() async {
    try {
      // Set up audio service callbacks
      _audioService.onTranscription = (text, isFinal) {
        print('Room: Received transcription: "$text" (final: $isFinal)');
        if (_roomService.isSpeaking) {
          _roomService.addCaptionText(text, isFinal: isFinal);
          // Hide the "speak more clearly" message when we get transcription
          if (_showSpeakClearlyMessage) {
            setState(() {
              _showSpeakClearlyMessage = false;
            });
          }
        }
      };

      _audioService.onError = (error) {
        if (_roomService.isSpeaking) {
          HapticFeedback.mediumImpact();

          // Handle speech timeout by automatically releasing the button
          if (error.contains('speech_time_out') ||
              error.contains('error_speech_timeout')) {
            debugPrint(
                '🔔 Speech timeout detected - automatically releasing button');
            _handleMicRelease();
            // No snackbar message for timeout - just auto-release
          } else if (error.contains('No match') ||
              error.contains('error_no_match')) {
            debugPrint(
                '👂 No match detected - showing speak more clearly message');
            setState(() {
              _showSpeakClearlyMessage = true;
            });
            // Hide the message after 2 seconds
            Timer(const Duration(seconds: 2), () {
              if (mounted) {
                setState(() {
                  _showSpeakClearlyMessage = false;
                });
              }
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error)),
            );
          }
        }
      };

      _audioService.onConnected = () {
        setState(() {
          _isAudioInitialized = true;
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

      setState(() {
        _isAudioInitialized = true;
      });
    } catch (e) {
      setState(() {
        _audioInitError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    // Stop any ongoing speech recognition
    if (_roomService.isSpeaking) {
      _audioService.stopStreaming();
    }
    _nameController.dispose();
    _roomCodeController.dispose();
    _roomService.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final name = await _promptForName();
    if (name == null) return;

    setState(() => _isJoining = true);

    try {
      await _roomService.createRoom(name);
      setState(() => _isJoining = false);
    } catch (e) {
      setState(() => _isJoining = false);
      _showError('Failed to create room: $e');
    }
  }

  Future<void> _joinRoom() async {
    final roomCode = await _promptForRoomCode();
    if (roomCode == null) return;

    final name = await _promptForName();
    if (name == null) return;

    setState(() => _isJoining = true);

    try {
      // For now, we'll use a mock encryption key
      await _roomService.joinRoom(roomCode, name);
      setState(() => _isJoining = false);
    } catch (e) {
      setState(() => _isJoining = false);
      _showError('Failed to join room: $e');
    }
  }

  Future<void> _joinRoomWithCode(String roomCode, String encryptionKey) async {
    final name = await _promptForName();
    if (name == null) return;

    setState(() => _isJoining = true);

    try {
      await _roomService.joinRoom(roomCode, name);
      setState(() => _isJoining = false);
    } catch (e) {
      setState(() => _isJoining = false);
      _showError('Failed to join room: $e');
    }
  }

  Future<String?> _promptForName() async {
    // Pre-fill with saved name from settings
    _nameController.text = _settingsService.userName ?? '';

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter Your Name'),
        content: TextField(
          controller: _nameController,
          autofocus: _nameController.text.isEmpty,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'John',
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = _nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop(name);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForRoomCode() async {
    _roomCodeController.clear();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Room Code'),
        content: TextField(
          controller: _roomCodeController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Room code',
            hintText: 'CAT123',
            helperText: '3 letters + 3 numbers',
          ),
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
            LengthLimitingTextInputFormatter(6),
          ],
          onSubmitted: (value) {
            if (value.length == 6 && _isValidRoomCode(value)) {
              Navigator.of(context).pop(value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final code = _roomCodeController.text;
              if (code.length == 6 && _isValidRoomCode(code)) {
                Navigator.of(context).pop(code);
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  bool _isValidRoomCode(String code) {
    if (code.length != 6) return false;
    // Check first 3 characters are letters and last 3 are digits
    final letterPart = code.substring(0, 3);
    final digitPart = code.substring(3);
    return RegExp(r'^[A-Z]{3}$').hasMatch(letterPart) &&
        RegExp(r'^[0-9]{3}$').hasMatch(digitPart);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _toggleQrCode() {
    setState(() => _showQrCode = !_showQrCode);
    HapticFeedback.lightImpact();
  }

  Future<void> _handleMicPress() async {
    if (!_isAudioInitialized) return;

    // Set button pressed state immediately
    setState(() {
      _isButtonPressed = true;
    });

    // Check if we can speak
    final canSpeak = await _roomService.requestSpeak();

    if (!canSpeak) {
      // Reset button state if we can't speak
      setState(() {
        _isButtonPressed = false;
      });

      // Show error feedback
      HapticFeedback.heavyImpact();

      if (_roomService.isConcurrentMode) {
        // In concurrent mode, this shouldn't happen since everyone can speak
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to speak right now. Please try again.'),
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        // Legacy single-speaker mode
        final activeSpeaker = _roomService.activeSpeaker;
        if (activeSpeaker != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${activeSpeaker.name} is speaking...'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
      return;
    }

    // We can speak - set local speaking state
    _roomService.setLocalSpeakingState(true);
    HapticFeedback.selectionClick();

    // Start speech recognition
    if (!_audioService.isConnected) {
      await _audioService.connect();
    }

    if (_audioService.isConnected) {
      await _audioService.startStreaming();
    }
  }

  Future<void> _handleMicRelease() async {
    debugPrint('🔴 GROUP ROOM: _handleMicRelease() called');
    debugPrint('🎤 Group room mic release started');

    // Reset button pressed state immediately
    setState(() {
      _isButtonPressed = false;
    });

    // Clear local speaking state immediately
    _roomService.setLocalSpeakingState(false);
    debugPrint('🎤 Set local speaking state to false');

    if (_audioService.isStreaming) {
      HapticFeedback.selectionClick();

      // Stop speech recognition
      await _audioService.stopStreaming();
      debugPrint('🎤 Stopped audio streaming');

      _roomService.stopSpeaking();
      debugPrint('🎤 Called stopSpeaking on room service');
    }

    debugPrint(
        '🎤 Group room mic release completed. Is speaking: ${_roomService.isSpeaking}');
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _roomService,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Consumer<RoomService>(
            builder: (context, roomService, _) {
              // Show room selection if not in a room
              if (!roomService.isInRoom) {
                return _buildRoomSelection();
              }

              // Show room interface
              return _buildRoomInterface(roomService);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildRoomSelection() {
    if (_isJoining) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting...'),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Group Captions',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Share live captions with multiple people',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _createRoom,
                icon: const Icon(Icons.add),
                label: const Text('Create Room'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _joinRoom,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Join Room'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 48),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
            if (_audioInitError != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _audioInitError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomInterface(RoomService roomService) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () async {
                  // Stop any ongoing speech
                  if (_roomService.isSpeaking) {
                    await _audioService.stopStreaming();
                  }
                  roomService.leaveRoom();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Room: ${roomService.roomCode}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${roomService.participants.length} ${roomService.participants.length == 1 ? 'person' : 'people'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _toggleQrCode,
                icon: Icon(_showQrCode ? Icons.close : Icons.share),
                tooltip: 'Share Room',
              ),
            ],
          ),
        ),

        // QR Code overlay
        if (_showQrCode)
          GestureDetector(
            onTap: _toggleQrCode,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Placeholder for QR code - will add qr_flutter later
                      Container(
                        width: 200,
                        height: 200,
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
                                size: 64,
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
                        'Room: ${roomService.roomCode}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Share this code to join',
                        style: TextStyle(
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Copy button
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: roomService.roomCode ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Room code copied!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy,
                            size: 16, color: Colors.black87),
                        label: const Text(
                          'Copy Code',
                          style: TextStyle(color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Caption display
        if (!_showQrCode)
          Expanded(
            child: RoomCaptionDisplay(
              onMicPress: _handleMicPress,
              onMicRelease: _handleMicRelease,
              onSendMessage: _roomService.sendTextMessage,
              isAudioInitialized:
                  _isAudioInitialized && _audioInitError == null,
            ),
          ),

        // Audio error message
        if (!_showQrCode && _audioInitError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    'Speech recognition unavailable: $_audioInitError',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
