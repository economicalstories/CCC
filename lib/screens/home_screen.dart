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
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late RoomService _roomService;
  late AudioStreamingService _audioService;
  late SettingsService _settingsService;

  // Track if join request dialog is currently showing

  String? _initError;
  bool _isInitialized = false;
  bool _isButtonPressed = false;
  bool _isSTTReady = false;
  bool _showSpeakClearlyMessage = false;

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

    // Join requests are now handled inline, no popup dialogs needed

    // Initialize
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // No join request listener to remove (using inline display now)
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
      // ALWAYS start in offline mode first (text-only)
      await _initializeOfflineMode();

      // Consider app initialized immediately in offline mode (text-only)
      setState(() {
        _isInitialized = true;
        _isSTTReady = false; // Start with STT disabled
      });

      // Progressive enhancement: Set up audio service callbacks
      _audioService.onTranscription = (text, isFinal) {
        print('Received transcription: "$text" (final: $isFinal)');
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
        // Audio service is ready, but don't set isInitialized again
        debugPrint('🎤 Audio service connected');
      };

      _audioService.onDisconnected = () {
        if (_roomService.isSpeaking) {
          _roomService.stopSpeaking();
        }
        setState(() {
          _isSTTReady = false; // Disable STT if audio disconnects
        });
      };

      _audioService.onListeningStarted = () {
        // Provide feedback when STT is actually ready
        HapticFeedback.mediumImpact();
        // Notify that we're ready to accept speech
        setState(() {
          _isSTTReady = true;
        });
      };

      // Progressive enhancement: Try to initialize audio service (non-blocking)
      _initializeAudioService();
    } catch (e) {
      setState(() {
        _initError = e.toString();
      });
    }
  }

  // Progressive enhancement: Initialize audio service in background
  Future<void> _initializeAudioService() async {
    try {
      debugPrint('🎤 Attempting to initialize audio service...');

      await _audioService.initialize(
        speechService: _settingsService.speechService,
        settingsService: _settingsService,
      );

      setState(() {
        _isSTTReady = true; // Enable STT buttons once audio is ready
      });

      debugPrint('✅ Audio service initialized successfully');
    } catch (e) {
      debugPrint('❌ Audio service initialization failed: $e');
      setState(() {
        _isSTTReady = false; // Keep STT disabled
      });
      // Continue without audio - app still works in text-only mode
    }
  }

  Future<void> _initializeRoom() async {
    // Ensure we have a username
    if (_settingsService.userName == null ||
        _settingsService.userName!.isEmpty) {
      debugPrint('🔧 Setting default username');
      await _settingsService.setUserName('User');
    }

    final userName = _settingsService.userName!;

    debugPrint('🚀 Initializing room with username: $userName');
    debugPrint('📱 Saved room code: ${_settingsService.roomCode}');

    // If we have a saved room code, show the room dialog and attempt to rejoin
    if (_settingsService.roomCode != null &&
        _settingsService.roomCode!.isNotEmpty) {
      debugPrint(
          '🔄 Attempting to rejoin saved room: ${_settingsService.roomCode}');

      // Try to auto-rejoin saved room
      try {
        await _roomService.autoRejoinSavedRoom();

        // If we're awaiting approval, show the room dialog with waiting state
        if (_roomService.isAwaitingApproval) {
          debugPrint('⏳ Awaiting approval for saved room');
          // Show room dialog after a brief delay to allow UI to settle
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _showRoomRestartDialog(_settingsService.roomCode!);
            }
          });
        } else if (!_roomService.isConnected) {
          debugPrint('❌ Failed to rejoin saved room, creating new one');
          await _createNewRoom(userName);
        } else {
          debugPrint('✅ Successfully rejoined saved room');
        }
      } catch (e) {
        debugPrint('❌ Error rejoining saved room: $e');
        await _createNewRoom(userName);
      }
    } else {
      // No saved room, create a new one
      debugPrint('🆕 No saved room, creating new one');
      await _createNewRoom(userName);
    }
  }

  Future<void> _initializeOfflineMode() async {
    // Ensure we have a username
    if (_settingsService.userName == null ||
        _settingsService.userName!.isEmpty) {
      debugPrint('🔧 Setting default username');
      await _settingsService.setUserName('User');
    }

    final userName = _settingsService.userName!;

    // Initialize offline mode with user info
    _roomService.initializeOfflineMode(userName: userName);

    // Attempt background connection (non-blocking)
    final savedRoomCode = _settingsService.roomCode;
    debugPrint(
        '🔗 Attempting background connection with saved room: $savedRoomCode');
    _roomService.attemptBackgroundConnection(savedRoomCode: savedRoomCode);
  }

  Future<void> _createNewRoom(String userName) async {
    try {
      debugPrint('🔨 Creating new room for user: $userName');

      // Generate a unique empty room code
      final newRoomCode = await _roomService.generateUniqueRoomCode();
      debugPrint('🎲 Generated new room code: $newRoomCode');

      // Join the new room
      await _roomService.joinRoom(newRoomCode, userName,
          settingsService: _settingsService);

      debugPrint('✅ Successfully created and joined new room: $newRoomCode');
    } catch (e) {
      debugPrint('❌ Error creating new room: $e');
      // Fallback to simple room creation
      debugPrint('🔄 Falling back to createRoom method');
      await _roomService.createRoom(userName);
    }
  }

  Future<void> _handleMicPress() async {
    if (!_isInitialized) return;

    // Set button pressed state immediately
    setState(() {
      _isButtonPressed = true;
    });

    // Check if we have opportunity to speak (optimistic)
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
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to speak right now. Please try again.'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
      return;
    }

    // We can speak - set local speaking state (button is pressed)
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
    debugPrint('🔴 HOME SCREEN: _handleMicRelease() called');
    debugPrint('🎤 Mic release started');

    // Reset button pressed state immediately
    setState(() {
      _isButtonPressed = false;
      // Don't disable _isSTTReady here - keep it available for next use
    });

    // Stop speaking immediately (button released)
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
        '🎤 Mic release completed. Is speaking: ${_roomService.isSpeaking}');
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

  void _showParticipantList(BuildContext context, RoomService roomService) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                roomService.participants.length > 1
                    ? Icons.group
                    : Icons.person,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('Room ${roomService.roomCode}'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Participants section
                Text(
                  '${roomService.participants.length} ${roomService.participants.length == 1 ? 'person' : 'people'} in this room:',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                ...roomService.participants.map((participant) {
                  final isMe = participant.id == roomService.currentUserId;
                  final isSpeaking = roomService.isConcurrentMode
                      ? roomService.isParticipantSpeaking(participant.id)
                      : participant.id == roomService.activeSpeakerId;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          isMe ? Icons.person : Icons.person_outline,
                          size: 16,
                          color: isSpeaking
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${participant.name}${isMe ? ' (You)' : ''}',
                            style: TextStyle(
                              fontWeight:
                                  isMe ? FontWeight.bold : FontWeight.normal,
                              color: isSpeaking
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                        if (isSpeaking)
                          Icon(
                            Icons.mic,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      ],
                    ),
                  );
                }).toList(),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // Room management section
                Text(
                  'Room Management',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),

                // Join different room button with text field
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showJoinRoomDialog(context),
                    icon: const Icon(Icons.meeting_room),
                    label: const Text('Join Different Room'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Create new room button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // Close dialog first
                      _createNewRoomFromDialog(context);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create New Room'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: roomService.roomCode ?? ''));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Room code copied!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy Code'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _createNewRoomFromDialog(BuildContext context) async {
    final userName = _settingsService.userName!;

    try {
      debugPrint('🔨 Creating new room from dialog for user: $userName');

      // Generate a unique empty room code
      final newRoomCode = await _roomService.generateUniqueRoomCode();
      debugPrint('🎲 Generated new room code: $newRoomCode');

      // Join the new room
      await _roomService.joinRoom(newRoomCode, userName,
          settingsService: _settingsService);

      debugPrint('✅ Successfully created and joined new room: $newRoomCode');
    } catch (e) {
      debugPrint('❌ Error creating new room from dialog: $e');
      // Fallback to simple room creation
      debugPrint('🔄 Falling back to createRoom method');
      await _roomService.createRoom(userName);
    }
  }

  void _showJoinRoomDialog(BuildContext context) {
    final TextEditingController roomCodeController = TextEditingController();
    final TextEditingController nameController = TextEditingController(
      text: _settingsService.userName ?? '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final currentRoomCode = _roomService.roomCode?.toUpperCase();
            final enteredCode = roomCodeController.text.trim().toUpperCase();
            final enteredName = nameController.text.trim();
            final isSameRoom =
                currentRoomCode != null && enteredCode == currentRoomCode;
            final isEmptyCode = enteredCode.isEmpty;
            final isEmptyName = enteredName.isEmpty;
            final isButtonDisabled = isSameRoom || isEmptyCode || isEmptyName;

            return AlertDialog(
              title: const Text('Join Different Room'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: roomCodeController,
                    decoration: InputDecoration(
                      labelText: 'Room code',
                      hintText: 'Enter room code (e.g. CAT123)',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.meeting_room),
                      errorText: isSameRoom ? 'Already in this room' : null,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    autofocus: true,
                    onChanged: (value) {
                      setState(() {}); // Rebuild to update button state
                    },
                    onSubmitted: (value) {
                      if (!isButtonDisabled) {
                        _joinRoomFromDialog(
                            dialogContext, value.trim(), enteredName);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      hintText: 'Enter your name for this room',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (value) {
                      setState(() {}); // Rebuild to update button state
                    },
                    onSubmitted: (value) {
                      if (!isButtonDisabled) {
                        _joinRoomFromDialog(dialogContext,
                            roomCodeController.text.trim(), value.trim());
                      }
                    },
                  ),
                  if (isSameRoom) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You are currently in room $currentRoomCode',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isButtonDisabled
                      ? null
                      : () {
                          final code = roomCodeController.text.trim();
                          final name = nameController.text.trim();
                          _joinRoomFromDialog(dialogContext, code, name);
                        },
                  style: isButtonDisabled
                      ? ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).disabledColor,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.38),
                        )
                      : null,
                  child: Text(
                    isSameRoom ? 'Already Here' : 'Join',
                    style: isButtonDisabled
                        ? TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.38))
                        : null,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _joinRoomFromDialog(
      BuildContext dialogContext, String code, String userName) async {
    final upperCode = code.toUpperCase();

    if (upperCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room code')),
      );
      return;
    }

    if (upperCode.length > 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room code must be 6 characters or less'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Prevent joining the room they're already in
    if (_roomService.isConnected && _roomService.roomCode == upperCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You are already in room $upperCode'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Close the join room dialog first
    Navigator.pop(dialogContext);

    try {
      // Use provided user name, with fallback
      final finalUserName = userName.trim().isEmpty ? 'User' : userName.trim();

      debugPrint('🔗 Attempting to join room: $upperCode as $finalUserName');

      // Clear any previous join denied reason before showing dialog
      _roomService.clearJoinDeniedReason();

      // Show new simple waiting dialog
      _showSimpleJoinDialog(context, upperCode);

      // Actually attempt to join the different room (without disconnecting from current)
      await _roomService.attemptJoinDifferentRoom(upperCode, finalUserName,
          settingsService: _settingsService);

      // Save the room code after successful join attempt
      await _settingsService.setRoomCode(upperCode);
    } catch (e) {
      debugPrint('❌ Error joining room: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join room: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSimpleJoinDialog(BuildContext context, String roomCode) {
    bool dialogDismissed = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('Joining Room $roomCode'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Requesting to join room...'),
            SizedBox(height: 8),
            Text(
              'This will close automatically when approved or denied.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              if (!dialogDismissed) {
                dialogDismissed = true;
                _roomService.cancelJoinRequest();
                Navigator.pop(dialogContext);
              }
            },
            icon: const Icon(Icons.close),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );

    // Set up listeners for join resolution
    _setupJoinListeners(context, roomCode, () {
      if (!dialogDismissed) {
        dialogDismissed = true;
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    });
  }

  void _setupJoinListeners(
      BuildContext context, String roomCode, VoidCallback closeDialog) {
    // This will be called when join is resolved (approved, denied, or cancelled)
    // We'll implement this to listen directly to the RoomService state changes
    // But in a much simpler way than the Consumer approach

    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      // Check for resolution every 100ms
      if (_roomService.joinSuccessful) {
        timer.cancel();
        closeDialog();
        _showJoinSuccessMessage(context, roomCode);
      } else if (_roomService.joinDeniedReason != null) {
        timer.cancel();
        closeDialog();
        _showJoinDeniedMessage(context, _roomService.joinDeniedReason!);
        _roomService.clearJoinDeniedReason();
      } else if (!_roomService.isAwaitingApproval &&
          _roomService.isConnected &&
          _roomService.roomCode != roomCode) {
        // User was returned to original room (cancelled or other reason)
        timer.cancel();
        closeDialog();
      }

      // Safety timeout after 30 seconds
      if (timer.tick > 300) {
        // 30 seconds
        timer.cancel();
        closeDialog();
        _showJoinTimeoutMessage(context);
      }
    });
  }

  void _showJoinSuccessMessage(BuildContext context, String roomCode) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully joined room $roomCode!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showJoinDeniedMessage(BuildContext context, String reason) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Join denied: $reason'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showJoinTimeoutMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Join request timed out. Please try again.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showRoomRestartDialog(String roomCode) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (dialogContext) => Consumer<RoomService>(
        builder: (context, roomService, child) {
          // If we successfully connected, close the dialog
          if (roomService.isConnected && roomService.isInRoom) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.canPop(dialogContext)) {
                Navigator.pop(dialogContext);
              }
            });
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  roomService.participants.length > 1
                      ? Icons.group
                      : Icons.person,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('Rejoining Room $roomCode'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (roomService.isAwaitingApproval) ...[
                    // Waiting for approval state
                    Row(
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Waiting for approval...',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Someone in room $roomCode needs to approve your request to rejoin.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (roomService.approvalMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceVariant
                              .withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          roomService.approvalMessage!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.7),
                                  ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                  ],

                  // Room management section
                  Text(
                    'Room Management',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),

                  // Join different room button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext); // Close this dialog
                        _showJoinRoomDialog(context);
                      },
                      icon: const Icon(Icons.meeting_room),
                      label: const Text('Join Different Room'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Create new room button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext); // Close dialog first
                        _createNewRoomFromDialog(context);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Create New Room'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: roomService.isAwaitingApproval
                ? [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _createNewRoomFromDialog(context);
                      },
                      icon: const Icon(Icons.close),
                      label: const Text('Abort & Create New Room'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ]
                : [],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _roomService,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            SafeArea(
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
                            Consumer<RoomService>(
                              builder: (context, roomService, _) {
                                if (!roomService.isInRoom)
                                  return const SizedBox.shrink();

                                return GestureDetector(
                                  onTap: () async {
                                    debugPrint('🎯 ROOM CODE PILL TAPPED');
                                    debugPrint(
                                        '   - Offline mode: ${roomService.isOfflineMode}');
                                    debugPrint(
                                        '   - Connected: ${roomService.isConnected}');
                                    debugPrint(
                                        '   - Room code: ${roomService.roomCode}');

                                    // If offline, attempt to force reconnect first
                                    if (roomService.isOfflineMode) {
                                      debugPrint(
                                          '🔌 Room code tapped while offline - attempting force reconnect');

                                      // Show connecting indicator
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Row(
                                            children: [
                                              SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              ),
                                              SizedBox(width: 12),
                                              Text(
                                                  'Attempting to reconnect...'),
                                            ],
                                          ),
                                          duration: Duration(seconds: 3),
                                        ),
                                      );

                                      try {
                                        await roomService
                                            .debugReconnectToSavedRoom();

                                        // If successful, show the participant list
                                        if (!roomService.isOfflineMode) {
                                          debugPrint(
                                              '✅ Force reconnect successful - showing participant list');
                                          _showParticipantList(
                                              context, roomService);
                                        } else {
                                          debugPrint(
                                              '⚠️ Still offline after reconnect attempt');
                                          // Show room selection dialog if still offline
                                          _showParticipantList(
                                              context, roomService);
                                        }
                                      } catch (e) {
                                        debugPrint(
                                            '❌ Force reconnect failed: $e');
                                        // Still show participant list (which will show offline options)
                                        _showParticipantList(
                                            context, roomService);
                                      }
                                    } else {
                                      debugPrint(
                                          '🌐 Room code tapped while online - showing participant list normally');
                                      // Online - show participant list normally
                                      _showParticipantList(
                                          context, roomService);
                                    }
                                  },
                                  onLongPress: () async {
                                    debugPrint(
                                        '🎯 ROOM CODE PILL LONG-PRESSED - MANUAL DEBUG RECONNECT');
                                    debugPrint(
                                        '   - Current offline mode: ${roomService.isOfflineMode}');
                                    debugPrint(
                                        '   - Current connected: ${roomService.isConnected}');

                                    // Show connecting indicator
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Row(
                                          children: [
                                            SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            ),
                                            SizedBox(width: 12),
                                            Text('Manual reconnect attempt...'),
                                          ],
                                        ),
                                        duration: Duration(seconds: 3),
                                      ),
                                    );

                                    try {
                                      await roomService
                                          .debugReconnectToSavedRoom();
                                      debugPrint(
                                          '✅ Manual debug reconnect completed');
                                    } catch (e) {
                                      debugPrint(
                                          '❌ Manual debug reconnect failed: $e');
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: roomService.isOfflineMode
                                          ? Colors.grey.withOpacity(0.1)
                                          : roomService.isConnected
                                              ? Colors.green.withOpacity(0.1)
                                              : roomService.isAwaitingApproval
                                                  ? Colors.red.withOpacity(0.1)
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: roomService.isOfflineMode
                                            ? Colors.grey
                                            : roomService.isConnected
                                                ? Colors.green
                                                : roomService.isAwaitingApproval
                                                    ? Colors.red
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          roomService.participants.length > 1
                                              ? Icons.group
                                              : Icons.person,
                                          size: 16,
                                          color: roomService.isOfflineMode
                                              ? Colors.grey.shade700
                                              : roomService.isConnected
                                                  ? Colors.green.shade700
                                                  : roomService
                                                          .isAwaitingApproval
                                                      ? Colors.red.shade700
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .onPrimaryContainer,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          roomService.roomCode ?? '',
                                          style: TextStyle(
                                            color: roomService.isOfflineMode
                                                ? Colors.grey.shade700
                                                : roomService.isConnected
                                                    ? Colors.green.shade700
                                                    : roomService
                                                            .isAwaitingApproval
                                                        ? Colors.red.shade700
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (roomService.isOfflineMode) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: Colors.grey,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.grey
                                                      .withOpacity(0.3),
                                                  blurRadius: 4,
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ] else if (roomService.isConnected) ...[
                                          const SizedBox(width: 6),
                                          Consumer<RoomService>(
                                            builder: (context, roomService, _) {
                                              final connectionStatus =
                                                  roomService
                                                      .serverConnectionStatus;

                                              Color statusColor;
                                              switch (connectionStatus) {
                                                case ConnectionStatus.good:
                                                  statusColor = Colors.green;
                                                  break;
                                                case ConnectionStatus.poor:
                                                  statusColor = Colors.orange;
                                                  break;
                                                case ConnectionStatus.bad:
                                                  statusColor = Colors.red;
                                                  break;
                                                case ConnectionStatus
                                                      .connecting:
                                                  statusColor = Colors.yellow;
                                                  break;
                                                case ConnectionStatus.offline:
                                                  statusColor = Colors.grey;
                                                  break;
                                                default:
                                                  statusColor = Colors.grey;
                                              }

                                              return Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: statusColor,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: statusColor
                                                          .withOpacity(0.5),
                                                      blurRadius: 6,
                                                      spreadRadius: 1,
                                                    ),
                                                  ],
                                                ),
                                                child: connectionStatus ==
                                                        ConnectionStatus.good
                                                    ? _HeartbeatPulse()
                                                    : null,
                                              );
                                            },
                                          ),
                                        ] else if (roomService
                                            .isAwaitingApproval) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.red
                                                      .withOpacity(0.3),
                                                  blurRadius: 4,
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                            // Settings button
                            IconButton(
                              icon: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.asset(
                                  'web/icons/Icon-192.png',
                                  width:
                                      (Theme.of(context).iconTheme.size ?? 24) *
                                          1.0,
                                  height:
                                      (Theme.of(context).iconTheme.size ?? 24) *
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

                  // Join requests are now handled inline in the participant layout

                  // Waiting for approval message
                  Consumer<RoomService>(
                    builder: (context, roomService, _) {
                      // Show join denial message
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (roomService.joinDeniedReason != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Join request declined: ${roomService.joinDeniedReason}'),
                              backgroundColor: Colors.orange,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                          // Clear the message after showing
                          roomService.clearJoinDeniedReason();
                        }
                      });

                      if (!roomService.isAwaitingApproval) {
                        return const SizedBox.shrink();
                      }

                      return Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.red,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                roomService.approvalMessage ??
                                    'Waiting for approval...',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Searching for network status
                  Consumer<RoomService>(
                    builder: (context, roomService, _) {
                      if (!roomService.isSearchingForNetwork) {
                        return const SizedBox.shrink();
                      }

                      return Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    roomService.connectionStatusMessage,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Show user choice buttons after extended searching
                            if (roomService.showUserChoice) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        roomService
                                            .userChooseContinueSearching();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.orange[700],
                                      ),
                                      child: const Text('Keep Trying'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        roomService.userChooseGoOffline();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.orange[700],
                                      ),
                                      child: const Text('Solo Mode'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),

                  // Caption display
                  Expanded(
                    child: RoomCaptionDisplay(
                      onMicPress: _handleMicPress,
                      onMicRelease: _handleMicRelease,
                      onSendMessage: _roomService.sendTextMessage,
                      isAudioInitialized: _isInitialized && _initError == null,
                      isSTTReady: _isSTTReady,
                    ),
                  ),

                  // Audio error message
                  if (_initError != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Speech recognition unavailable: $_initError',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // "Speak more clearly" popup overlay
            if (_showSpeakClearlyMessage)
              Positioned(
                top: MediaQuery.of(context).padding.top + 100,
                left: 20,
                right: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.mic_external_on,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Please speak more clearly',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeartbeatPulse extends StatefulWidget {
  @override
  State<_HeartbeatPulse> createState() => _HeartbeatPulseState();
}

class _HeartbeatPulseState extends State<_HeartbeatPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.8, end: 1.2)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Start pulsing
    _startPulsing();
  }

  void _startPulsing() {
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
