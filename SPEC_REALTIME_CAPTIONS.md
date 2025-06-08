# Real-Time Captioning Rooms Specification

## Overview

A peer-to-peer captioning system that enables inclusive conversations for people with hearing difficulties. Users create temporary rooms where speech is converted to text in real-time and shared with all participants. The system enforces turn-taking (one speaker at a time) and provides end-to-end encryption for privacy.

## Core Principles

1. **Accessibility First** - Designed for real conversations where people with hearing difficulties need live captions
2. **Privacy by Design** - End-to-end encryption ensures even the server cannot read messages
3. **Turn-Taking** - Mirrors natural conversation with one speaker at a time
4. **Persistence** - Captions remain visible until manually dismissed
5. **Cross-Platform** - Works on any device with a modern web browser

## Architecture

```
┌─────────────────┐     WebSocket      ┌──────────────────┐
│   User A (PWA)  │◄──────────────────►│                  │
│   [Speaking]    │   (Encrypted)       │                  │
└─────────────────┘                     │  Cloudflare      │
                                        │  Worker          │
┌─────────────────┐     WebSocket      │                  │
│   User B (PWA)  │◄──────────────────►│  (Encrypted      │
│   [Viewing]     │   (Encrypted)       │   Relay Only)    │
└─────────────────┘                     │                  │
                                        │                  │
┌─────────────────┐     WebSocket      │                  │
│   User C (PWA)  │◄──────────────────►│                  │
│   [Viewing]     │   (Encrypted)       │                  │
└─────────────────┘                     └──────────────────┘
```

## User Experience Flow

### 1. Creating a Room
- User taps "Create Room" button
- System generates:
  - 6-character room code (e.g., "TALK47")
  - Room encryption key (not sent to server)
- UI displays QR code containing: `https://app.url/join/TALK47#key=<encryption-key>`
- Creator automatically joins the room

### 2. Joining a Room
- Scan QR code OR manually enter room code + encryption key
- Enter display name (saved in localStorage for future use)
- Join room and see existing participants

### 3. Speaking Rules
- **Microphone Lock**: Only one person can activate speech-to-text at a time
- When someone is speaking:
  - Their name shows as "[Name] is speaking..."
  - Microphone button disabled for others (shows "Please wait...")
  - Haptic feedback alerts others to new speaker
- When speaker stops:
  - 1-second cooldown before next person can speak
  - Prevents accidental interruptions

### 4. Caption Display
- Captions appear with speaker name and timestamp
- Messages persist until manually dismissed
- Each caption has a ✓ (check) button to dismiss
- Dismissed messages fade out smoothly
- Optional: "Clear All" button for bulk dismissal

### 5. Haptic Feedback
- **New Speaker Alert**: 200ms strong vibration
- **Ongoing Speech**: 50ms pulse every second while someone else speaks
- Respects device vibration settings

## Technical Implementation

### PWA Modifications

#### New UI Components
```
┌─────────────────────────────┐
│ Room: TALK47 (3 people)  ⚙️ │
├─────────────────────────────┤
│ ┌─────────────────────────┐ │
│ │ John (2:34 PM)       ✓ │ │ <- Dismiss button
│ │ "Can everyone hear me?" │ │
│ └─────────────────────────┘ │
│                             │
│ ┌─────────────────────────┐ │
│ │ Sarah (2:34 PM)      ✓ │ │
│ │ "Yes, loud and clear"   │ │
│ └─────────────────────────┘ │
│                             │
│ ┌─────────────────────────┐ │
│ │ Mike is speaking...     │ │ <- Active speaker
│ │ "Great, let's start"    │ │
│ └─────────────────────────┘ │
├─────────────────────────────┤
│   🎤 Please wait...      📤 │ <- Disabled while someone speaks
└─────────────────────────────┘
```

#### State Management
```javascript
interface RoomState {
  roomId: string;
  encryptionKey: CryptoKey;
  participants: Participant[];
  messages: EncryptedMessage[];
  activeSpeaker: string | null;
  isConnected: boolean;
  isSpeaking: boolean;
}

interface Participant {
  id: string;
  name: string;
  joinedAt: Date;
}

interface EncryptedMessage {
  id: string;
  speakerId: string;
  speakerName: string;
  encryptedText: string;
  timestamp: Date;
  isFinal: boolean;
  dismissed: boolean;
}
```

### End-to-End Encryption

#### Key Generation
```javascript
// Generate room key when creating room
const roomKey = await crypto.subtle.generateKey(
  { name: "AES-GCM", length: 256 },
  true,
  ["encrypt", "decrypt"]
);

// Export for sharing via QR
const exportedKey = await crypto.subtle.exportKey("raw", roomKey);
const keyBase64 = btoa(String.fromCharCode(...new Uint8Array(exportedKey)));
```

#### Message Encryption
```javascript
// Before sending
const iv = crypto.getRandomValues(new Uint8Array(12));
const encrypted = await crypto.subtle.encrypt(
  { name: "AES-GCM", iv },
  roomKey,
  new TextEncoder().encode(messageText)
);

// Send: { iv: base64(iv), data: base64(encrypted), ...metadata }
```

### WebSocket Protocol

#### Message Types
```typescript
// All messages wrapped in encrypted envelope
interface EncryptedEnvelope {
  type: "encrypted";
  roomId: string;
  senderId: string;
  iv: string;        // Base64
  data: string;      // Base64 encrypted payload
}

// Decrypted payload types
interface JoinRoom {
  type: "join";
  name: string;
  timestamp: number;
}

interface LeaveRoom {
  type: "leave";
  timestamp: number;
}

interface StartSpeaking {
  type: "startSpeaking";
  timestamp: number;
}

interface StopSpeaking {
  type: "stopSpeaking";
  timestamp: number;
}

interface SpeechUpdate {
  type: "speech";
  text: string;
  isFinal: boolean;
  timestamp: number;
}

interface RoomSync {
  type: "roomSync";
  participants: Array<{id: string, name: string}>;
  activeSpeaker: string | null;
}
```

### Cloudflare Worker

```javascript
// Minimal relay server - cannot read encrypted content
class EncryptedRoom {
  constructor(id) {
    this.id = id;
    this.participants = new Map(); // WebSocket -> participantId
    this.createdAt = Date.now();
    this.lastActivity = Date.now();
  }

  broadcast(message, excludeSocket) {
    this.lastActivity = Date.now();
    for (const [socket, _] of this.participants) {
      if (socket !== excludeSocket && socket.readyState === 1) {
        socket.send(message);
      }
    }
  }

  addParticipant(socket, participantId) {
    this.participants.set(socket, participantId);
    // Notify others (encrypted)
    this.broadcast(JSON.stringify({
      type: "encrypted",
      roomId: this.id,
      senderId: "system",
      event: "participantJoined"
    }), socket);
  }

  removeParticipant(socket) {
    const participantId = this.participants.get(socket);
    this.participants.delete(socket);
    // Notify others (encrypted)
    this.broadcast(JSON.stringify({
      type: "encrypted",
      roomId: this.id,
      senderId: "system",
      event: "participantLeft",
      participantId
    }));
  }

  get isEmpty() {
    return this.participants.size === 0;
  }

  get age() {
    return Date.now() - this.createdAt;
  }
}
```

## Security & Privacy Features

1. **End-to-End Encryption**
   - AES-256-GCM encryption
   - Keys never sent to server
   - Server only sees encrypted payloads

2. **Room Isolation**
   - Messages only relay within rooms
   - No cross-room communication possible

3. **Ephemeral Design**
   - No message persistence on server
   - Rooms auto-delete after 24 hours
   - Optional: Delete after 1 hour of inactivity

4. **Client-Side Security**
   - Encryption keys stored in memory only
   - Keys cleared on room exit
   - No sensitive data in localStorage

## Performance Optimizations

1. **Message Throttling**
   - Max 3 updates per second during speech
   - Send final transcription once
   - Batch UI updates

2. **Connection Management**
   - Automatic reconnection with exponential backoff
   - Preserve room state during brief disconnections
   - Show connection status to user

3. **Resource Cleanup**
   - Remove dismissed messages from DOM
   - Limit message history (e.g., last 100 messages)
   - Clean up WebRTC resources properly

## Accessibility Features

1. **Visual Indicators**
   - Clear speaker identification
   - High contrast text
   - Adjustable font sizes

2. **Haptic Feedback**
   - Configurable vibration patterns
   - Option to disable

3. **Screen Reader Support**
   - ARIA labels for all controls
   - Announce new speakers
   - Read new messages

## Error Handling

1. **Network Issues**
   - "Connection lost" banner
   - Automatic reconnection
   - Offline message queue

2. **Room Errors**
   - "Room not found" 
   - "Room expired"
   - "Invalid encryption key"

3. **Speech Recognition Errors**
   - Fall back to manual text input
   - Show clear error messages

## Future Enhancements

1. **Message Features**
   - Search within conversation
   - Export transcript
   - Bookmark important messages

2. **Room Features**
   - Password-protected rooms
   - Scheduled rooms
   - Room templates

3. **Accessibility**
   - Sign language video overlay
   - Translation support
   - Custom notification sounds

## Implementation Plan

### Phase 1: Core Infrastructure
1. Create GitHub branch: `feature/realtime-captions`
2. Set up Cloudflare Worker project
3. Implement basic WebSocket relay
4. Add room management logic

### Phase 2: Encryption Layer
1. Implement key generation/sharing
2. Add encryption/decryption utilities
3. Update message protocol
4. Test security implementation

### Phase 3: PWA Integration
1. Create room UI components
2. Implement WebSocket client
3. Add speaker management logic
4. Integrate with existing speech recognition

### Phase 4: Polish & Testing
1. Add haptic feedback
2. Implement message persistence/dismissal
3. Error handling and reconnection
4. Cross-platform testing

### Phase 5: Deployment
1. Deploy Cloudflare Worker
2. Update PWA deployment
3. Documentation
4. User testing

## Technical Requirements

- **Cloudflare Workers**: Paid plan for WebSocket support
- **PWA Updates**: React components for room UI
- **Browser Support**: Chrome 80+, Safari 14+, Firefox 85+
- **Network**: Requires stable internet connection 