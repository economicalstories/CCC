import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/room_service.dart';
import '../widgets/room_caption_display.dart';
import '../utils/room_code_generator.dart';

class GroupRoomScreen extends StatefulWidget {
  final String? roomCode;
  final String? encryptionKey;

  const GroupRoomScreen({
    Key? key,
    this.roomCode,
    this.encryptionKey,
  }) : super(key: key);

  @override
  State<GroupRoomScreen> createState() => _GroupRoomScreenState();
}

class _GroupRoomScreenState extends State<GroupRoomScreen> {
  late RoomService _roomService;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _roomCodeController = TextEditingController();

  bool _isJoining = false;
  bool _showQrCode = false;

  @override
  void initState() {
    super.initState();
    _roomService = RoomService();

    // Auto-join if room code provided
    if (widget.roomCode != null && widget.encryptionKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _joinRoomWithCode(widget.roomCode!, widget.encryptionKey!);
      });
    }
  }

  @override
  void dispose() {
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
      await _roomService.joinRoom(roomCode, 'mock-key', name);
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
      await _roomService.joinRoom(roomCode, encryptionKey, name);
      setState(() => _isJoining = false);
    } catch (e) {
      setState(() => _isJoining = false);
      _showError('Failed to join room: $e');
    }
  }

  Future<String?> _promptForName() async {
    _nameController.text = _roomService.savedName ?? '';

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter Your Name'),
        content: TextField(
          controller: _nameController,
          autofocus: true,
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
            hintText: 'ABC123',
          ),
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
            LengthLimitingTextInputFormatter(6),
          ],
          onSubmitted: (value) {
            if (value.length == 6) {
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
              if (code.length == 6) {
                Navigator.of(context).pop(code);
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
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

  void _handleMicPress() {
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
    }
  }

  void _handleMicRelease() {
    if (_roomService.isSpeaking) {
      HapticFeedback.selectionClick();
      _roomService.stopSpeaking();
    }
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
                onPressed: () {
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
          const Expanded(
            child: RoomCaptionDisplay(),
          ),

        // Active speaker indicator
        if (roomService.activeSpeaker != null && !_showQrCode)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  '${roomService.activeSpeaker!.name} is speaking...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),

        // Microphone button
        if (!_showQrCode)
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
                  color: roomService.isSpeaking
                      ? Theme.of(context).colorScheme.error
                      : roomService.activeSpeaker != null
                          ? Theme.of(context).disabledColor
                          : Theme.of(context).colorScheme.primary,
                  boxShadow: [
                    BoxShadow(
                      color: (roomService.isSpeaking
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
                    roomService.activeSpeaker != null && !roomService.isSpeaking
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
        if (!_showQrCode)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              roomService.isSpeaking
                  ? 'Release to stop'
                  : roomService.activeSpeaker != null
                      ? 'Please wait...'
                      : 'Hold to speak',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}
