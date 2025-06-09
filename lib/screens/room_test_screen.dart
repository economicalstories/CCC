import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/room_service.dart';
import '../services/settings_service.dart';

class RoomTestScreen extends StatefulWidget {
  const RoomTestScreen({Key? key}) : super(key: key);

  @override
  State<RoomTestScreen> createState() => _RoomTestScreenState();
}

class _RoomTestScreenState extends State<RoomTestScreen> {
  final _roomCodeController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill with settings
    final settings = context.read<SettingsService>();
    _roomCodeController.text = settings.roomCode ?? 'TEST123';
    _nameController.text = settings.userName ?? 'Test User';
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room Test'),
      ),
      body: Consumer<RoomService>(
        builder: (context, roomService, child) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection Status
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: roomService.isConnected
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          roomService.isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Text(
                    roomService.isConnected
                        ? '✅ Connected to room: ${roomService.roomCode}'
                        : '❌ Not connected',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: roomService.isConnected
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),

                const SizedBox(height: 24),

                // Room Code Input
                TextField(
                  controller: _roomCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Room Code',
                    hintText: 'e.g. TEST123',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),

                const SizedBox(height: 16),

                // Name Input
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Your Name',
                    hintText: 'e.g. John Doe',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),

                const SizedBox(height: 24),

                // Join/Leave Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: roomService.isConnected
                        ? () => roomService.disconnect()
                        : () => _joinRoom(roomService),
                    child: Text(
                      roomService.isConnected ? 'Leave Room' : 'Join Room',
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Participants
                if (roomService.isConnected) ...[
                  Text(
                    'Participants (${roomService.participants.length})',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  ...roomService.participants.map(
                    (participant) {
                      final isSpeaking = roomService.isConcurrentMode
                          ? roomService.isParticipantSpeaking(participant.id)
                          : participant.id == roomService.activeSpeakerId;

                      return ListTile(
                        leading: Icon(
                          isSpeaking ? Icons.mic : Icons.person,
                          color: isSpeaking ? Colors.red : null,
                        ),
                        title: Text(participant.name),
                        subtitle: isSpeaking ? const Text('Speaking...') : null,
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Speaking Controls
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              roomService.canSpeak && !roomService.isSpeaking
                                  ? () => _requestSpeak(roomService)
                                  : null,
                          child: Text(
                            roomService.isSpeaking
                                ? 'You are speaking'
                                : roomService.canSpeak
                                    ? 'Request to Speak'
                                    : roomService.isConcurrentMode
                                        ? 'Ready to speak'
                                        : 'Someone else speaking',
                          ),
                        ),
                      ),
                      if (roomService.isSpeaking) ...[
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => roomService.stopSpeaking(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Stop Speaking'),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Test Caption Button
                  if (roomService.isSpeaking)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _sendTestCaption(roomService),
                        child: const Text('Send Test Caption'),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Messages
                  Text(
                    'Messages (${roomService.messages.length})',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: roomService.messages.length,
                      itemBuilder: (context, index) {
                        final message = roomService.messages[index];
                        return Card(
                          child: ListTile(
                            title: Text(message.speakerName),
                            subtitle: Text(message.text),
                            trailing: Text(
                              '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _joinRoom(RoomService roomService) {
    final roomCode = _roomCodeController.text.trim().toUpperCase();
    final name = _nameController.text.trim();

    if (roomCode.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter room code and name')),
      );
      return;
    }

    roomService.joinRoom(roomCode, name);
  }

  void _requestSpeak(RoomService roomService) async {
    final success = await roomService.requestSpeak();
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get speaking permission')),
      );
    }
  }

  void _sendTestCaption(RoomService roomService) {
    final testMessages = [
      'Hello everyone, this is a test caption.',
      'The weather is nice today.',
      'Can you hear me clearly?',
      'This is working great!',
    ];

    final message =
        testMessages[DateTime.now().millisecond % testMessages.length];
    roomService.addCaptionText(message, isFinal: true);
  }
}
