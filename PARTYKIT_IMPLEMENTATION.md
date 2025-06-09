# PartyKit Implementation Guide for CCC

## Current Status
- ✅ Room codes are generated and stored locally
- ✅ UI shows room information in settings and caption screens
- ✅ Push-to-talk captioning works locally
- ⏳ Next: Connect rooms via PartyKit for real-time caption sharing

## Next Steps Overview

### Phase 1: PartyKit Server Setup (Backend)
1. **Initialize PartyKit project**
2. **Create the relay server**
3. **Deploy to PartyKit**
4. **Test basic connectivity**

### Phase 2: Flutter WebSocket Client
1. **Add WebSocket dependencies**
2. **Create room connection service**
3. **Implement message protocol**
4. **Handle connection lifecycle**

### Phase 3: Real-time Caption Sync
1. **Send captions when speaking**
2. **Receive and display others' captions**
3. **Show active speaker status**
4. **Implement speaker lock mechanism**

### Phase 4: UI/UX Polish
1. **Show participant list**
2. **Add connection status indicators**
3. **Implement haptic feedback**
4. **Handle errors gracefully**

## Detailed Implementation Steps

### Step 1: Initialize PartyKit Project

```bash
# In project root, create server directory
mkdir partykit-server
cd partykit-server

# Initialize npm project
npm init -y

# Install PartyKit
npm install partykit

# Create PartyKit configuration
```

Create `partykit.json`:
```json
{
  "name": "ccc-rooms",
  "main": "server.js"
}
```

### Step 2: Create Basic PartyKit Server

Create `server.js`:
```javascript
export default class CaptionRoom {
  constructor(party) {
    this.party = party;
    this.connections = new Map(); // connection -> participant info
    this.activeSpeaker = null;
    this.roomState = {
      participants: [],
      activeSpeaker: null
    };
  }

  async onConnect(connection, ctx) {
    console.log(`New connection to room ${this.party.id}`);
    
    connection.addEventListener("message", (evt) => {
      this.handleMessage(connection, evt.data);
    });

    connection.addEventListener("close", () => {
      this.handleDisconnect(connection);
    });

    // Send current room state to new connection
    connection.send(JSON.stringify({
      type: "roomState",
      data: this.roomState
    }));
  }

  handleMessage(connection, message) {
    try {
      const data = JSON.parse(message);
      
      switch (data.type) {
        case "join":
          this.handleJoin(connection, data);
          break;
        case "requestSpeak":
          this.handleRequestSpeak(connection, data);
          break;
        case "stopSpeak":
          this.handleStopSpeak(connection, data);
          break;
        case "caption":
          this.handleCaption(connection, data);
          break;
      }
    } catch (e) {
      console.error("Error handling message:", e);
    }
  }

  handleJoin(connection, data) {
    const participant = {
      id: data.participantId,
      name: data.name,
      connectionId: connection.id
    };
    
    this.connections.set(connection, participant);
    this.roomState.participants.push({
      id: participant.id,
      name: participant.name
    });
    
    // Broadcast new participant to all
    this.broadcast(JSON.stringify({
      type: "participantJoined",
      data: {
        id: participant.id,
        name: participant.name
      }
    }));
  }

  handleRequestSpeak(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant) return;
    
    // Check if someone else is already speaking
    if (this.activeSpeaker && this.activeSpeaker !== participant.id) {
      connection.send(JSON.stringify({
        type: "speakDenied",
        reason: "Someone else is speaking"
      }));
      return;
    }
    
    // Grant speaking permission
    this.activeSpeaker = participant.id;
    this.roomState.activeSpeaker = participant.id;
    
    this.broadcast(JSON.stringify({
      type: "speakerChanged",
      data: {
        speakerId: participant.id,
        speakerName: participant.name
      }
    }));
  }

  handleStopSpeak(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant || this.activeSpeaker !== participant.id) return;
    
    this.activeSpeaker = null;
    this.roomState.activeSpeaker = null;
    
    this.broadcast(JSON.stringify({
      type: "speakerStopped",
      data: {
        speakerId: participant.id
      }
    }));
  }

  handleCaption(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant || this.activeSpeaker !== participant.id) return;
    
    // Relay caption to all participants
    this.broadcast(JSON.stringify({
      type: "caption",
      data: {
        speakerId: participant.id,
        speakerName: participant.name,
        text: data.text,
        isFinal: data.isFinal,
        timestamp: Date.now()
      }
    }));
  }

  handleDisconnect(connection) {
    const participant = this.connections.get(connection);
    if (!participant) return;
    
    // If they were speaking, clear speaker
    if (this.activeSpeaker === participant.id) {
      this.activeSpeaker = null;
      this.roomState.activeSpeaker = null;
    }
    
    // Remove from participants
    this.roomState.participants = this.roomState.participants.filter(
      p => p.id !== participant.id
    );
    
    this.connections.delete(connection);
    
    // Broadcast participant left
    this.broadcast(JSON.stringify({
      type: "participantLeft",
      data: {
        id: participant.id,
        name: participant.name
      }
    }));
  }

  broadcast(message, excludeConnection = null) {
    this.party.getConnections().forEach((conn) => {
      if (conn !== excludeConnection) {
        try {
          conn.send(message);
        } catch (e) {
          console.error("Error broadcasting:", e);
        }
      }
    });
  }
}
```

### Step 3: Deploy PartyKit Server

```bash
# In partykit-server directory
npx partykit deploy

# Note the deployment URL, it will be something like:
# https://ccc-rooms.username.partykit.dev
```

### Step 4: Add Flutter Dependencies

Update `pubspec.yaml`:
```yaml
dependencies:
  # ... existing dependencies ...
  web_socket_channel: ^2.4.0
  uuid: ^4.2.1
```

### Step 5: Create Room Connection Service

Create `lib/services/room_service.dart`:
```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

class RoomService extends ChangeNotifier {
  static const String _partyKitUrl = 'wss://ccc-rooms.YOUR-USERNAME.partykit.dev';
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  
  String? _roomCode;
  String? _participantId;
  String? _participantName;
  
  bool _isConnected = false;
  String? _activeSpeakerId;
  String? _activeSpeakerName;
  List<Participant> _participants = [];
  List<CaptionMessage> _messages = [];
  
  // Getters
  bool get isConnected => _isConnected;
  String? get roomCode => _roomCode;
  String? get activeSpeakerId => _activeSpeakerId;
  String? get activeSpeakerName => _activeSpeakerName;
  bool get isSpeaking => _activeSpeakerId == _participantId;
  List<Participant> get participants => _participants;
  List<CaptionMessage> get messages => _messages;
  
  Future<void> joinRoom(String roomCode, String userName) async {
    _roomCode = roomCode;
    _participantName = userName;
    _participantId = const Uuid().v4();
    
    await _connect();
  }
  
  Future<void> _connect() async {
    if (_channel != null) {
      await disconnect();
    }
    
    try {
      final wsUrl = Uri.parse('$_partyKitUrl/parties/main/$_roomCode');
      _channel = WebSocketChannel.connect(wsUrl);
      
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );
      
      // Send join message
      _sendMessage({
        'type': 'join',
        'participantId': _participantId,
        'name': _participantName,
      });
      
      _isConnected = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Connection error: $e');
      _isConnected = false;
      notifyListeners();
    }
  }
  
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      
      switch (data['type']) {
        case 'roomState':
          _handleRoomState(data['data']);
          break;
        case 'participantJoined':
          _handleParticipantJoined(data['data']);
          break;
        case 'participantLeft':
          _handleParticipantLeft(data['data']);
          break;
        case 'speakerChanged':
          _handleSpeakerChanged(data['data']);
          break;
        case 'speakerStopped':
          _handleSpeakerStopped(data['data']);
          break;
        case 'caption':
          _handleCaption(data['data']);
          break;
        case 'speakDenied':
          _handleSpeakDenied(data);
          break;
      }
    } catch (e) {
      debugPrint('Error handling message: $e');
    }
  }
  
  void _handleRoomState(Map<String, dynamic> state) {
    _participants = (state['participants'] as List)
        .map((p) => Participant.fromJson(p))
        .toList();
    _activeSpeakerId = state['activeSpeaker'];
    notifyListeners();
  }
  
  void _handleParticipantJoined(Map<String, dynamic> data) {
    _participants.add(Participant.fromJson(data));
    notifyListeners();
  }
  
  void _handleParticipantLeft(Map<String, dynamic> data) {
    _participants.removeWhere((p) => p.id == data['id']);
    notifyListeners();
  }
  
  void _handleSpeakerChanged(Map<String, dynamic> data) {
    _activeSpeakerId = data['speakerId'];
    _activeSpeakerName = data['speakerName'];
    notifyListeners();
  }
  
  void _handleSpeakerStopped(Map<String, dynamic> data) {
    _activeSpeakerId = null;
    _activeSpeakerName = null;
    notifyListeners();
  }
  
  void _handleCaption(Map<String, dynamic> data) {
    final message = CaptionMessage(
      id: const Uuid().v4(),
      speakerId: data['speakerId'],
      speakerName: data['speakerName'],
      text: data['text'],
      isFinal: data['isFinal'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp']),
    );
    
    // Update or add message
    final existingIndex = _messages.indexWhere(
      (m) => m.speakerId == message.speakerId && !m.isFinal
    );
    
    if (existingIndex != -1 && !message.isFinal) {
      _messages[existingIndex] = message;
    } else {
      _messages.add(message);
    }
    
    notifyListeners();
  }
  
  void _handleSpeakDenied(Map<String, dynamic> data) {
    // Handle denied speaking request
    debugPrint('Speaking denied: ${data['reason']}');
  }
  
  Future<bool> requestSpeak() async {
    if (!_isConnected || _activeSpeakerId != null) {
      return false;
    }
    
    _sendMessage({
      'type': 'requestSpeak',
      'participantId': _participantId,
    });
    
    // Wait briefly to see if we get speaking permission
    await Future.delayed(const Duration(milliseconds: 200));
    return isSpeaking;
  }
  
  void stopSpeaking() {
    if (!isSpeaking) return;
    
    _sendMessage({
      'type': 'stopSpeak',
      'participantId': _participantId,
    });
  }
  
  void sendCaption(String text, {bool isFinal = false}) {
    if (!isSpeaking) return;
    
    _sendMessage({
      'type': 'caption',
      'text': text,
      'isFinal': isFinal,
    });
  }
  
  void _sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }
  
  void _handleError(error) {
    debugPrint('WebSocket error: $error');
    _isConnected = false;
    notifyListeners();
    
    // Attempt reconnection after delay
    Future.delayed(const Duration(seconds: 3), () {
      if (_roomCode != null && _participantName != null) {
        _connect();
      }
    });
  }
  
  void _handleDone() {
    _isConnected = false;
    notifyListeners();
  }
  
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _participants.clear();
    _messages.clear();
    _activeSpeakerId = null;
    notifyListeners();
  }
  
  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

class Participant {
  final String id;
  final String name;
  
  Participant({required this.id, required this.name});
  
  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id'],
      name: json['name'],
    );
  }
}

class CaptionMessage {
  final String id;
  final String speakerId;
  final String speakerName;
  final String text;
  final bool isFinal;
  final DateTime timestamp;
  
  CaptionMessage({
    required this.id,
    required this.speakerId,
    required this.speakerName,
    required this.text,
    required this.isFinal,
    required this.timestamp,
  });
}
```

### Step 6: Integrate with Existing Services

Update `lib/main.dart` to include RoomService provider:
```dart
// Add to providers
ChangeNotifierProvider(create: (_) => RoomService()),
```

### Step 7: Connect Audio Service to Room Service

Modify the audio streaming service to send captions to the room when speaking (send only text, include text in progress, and text that has been edited, but never raw audio itself).

### Step 8: Update UI to Show Room State

- Show participant count
- Display active speaker indicator
- Show incoming captions from other participants
- Disable microphone when someone else is speaking

## Testing Plan

1. **Local Testing**
   - Run PartyKit server locally: `npx partykit dev`
   - Test with multiple browser tabs

2. **Network Testing**
   - Deploy to PartyKit
   - Test across different devices
   - Test reconnection scenarios

3. **User Testing**
   - Test with real users in same room
   - Test with users in different locations
   - Gather feedback on latency and reliability

## Security Considerations

For Phase 1, we'll implement basic functionality without encryption. 
Phase 2 will add:
- End-to-end encryption for messages
- Room passwords (optional)
- Participant verification

## Performance Optimization

- Throttle caption updates (max 3/second)
- Batch UI updates
- Implement message cleanup (remove old messages)
- Add connection quality indicators

## Next Actions

1. **Set up PartyKit project** (30 minutes)
2. **Deploy basic server** (15 minutes)
3. **Add Flutter WebSocket client** (2 hours)
4. **Connect to existing caption service** (1 hour)
5. **Update UI for room features** (2 hours)
6. **Test with multiple devices** (1 hour)

Total estimated time: ~7 hours for basic functionality

## Resources

- [PartyKit Documentation](https://docs.partykit.io/)
- [Flutter WebSocket Guide](https://pub.dev/packages/web_socket_channel)
- [WebSocket Protocol Reference](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API) 