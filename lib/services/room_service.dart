import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:ulid/ulid.dart';
import 'package:closed_caption_companion/models/room_participant.dart';
import 'package:closed_caption_companion/models/room_message.dart';
import 'package:closed_caption_companion/utils/room_code_generator.dart';
import 'package:closed_caption_companion/services/settings_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RoomCheckResult {
  RoomCheckResult({
    required this.participantCount,
    required this.isEmpty,
  });
  final int participantCount;
  final bool isEmpty;
}

class ConnectionTestResult {
  ConnectionTestResult({
    required this.success,
    this.error,
  });
  final bool success;
  final String? error;
}

enum ConnectionStatus {
  good, // Green - recent heartbeat (< 2 seconds)
  poor, // Orange - stale heartbeat (2-5 seconds)
  bad, // Red - very stale heartbeat (> 5 seconds)
  offline, // Gray - in offline mode
  connecting, // Yellow - connecting/no heartbeat yet
  unknown, // Gray - no data
}

class RoomService extends ChangeNotifier {
  // Get PartyKit URL from settings/environment with access key support
  String _getPartyKitUrl([String? accessKey]) {
    return _settingsService?.partyKitServer ??
        'wss://ccc-rooms.economicalstories.partykit.dev';
  }

  Uri _buildWebSocketUrl(String roomCode, [String? accessKey]) {
    debugPrint('🔧 Building WebSocket URL...');
    debugPrint('🔧 Room code: $roomCode');
    debugPrint(
        '🔧 Access key provided: ${accessKey != null ? 'YES (${accessKey.substring(0, 3)}...)' : 'NO'}');
    debugPrint('🔧 Sharing enabled: ${_settingsService?.sharingEnabled}');

    final baseUrl = _getPartyKitUrl(accessKey);
    debugPrint('🔧 Base URL: $baseUrl');

    final uri = Uri.parse('$baseUrl/parties/main/$roomCode');
    debugPrint('🔧 Initial URI: $uri');

    // For connection testing, always add access key if provided
    // For normal operation, only add if sharing is enabled
    final shouldAddKey = accessKey != null &&
        accessKey.isNotEmpty &&
        (_settingsService?.sharingEnabled == true || roomCode == 'TEST');

    debugPrint(
        '🔧 Should add key: $shouldAddKey (sharingEnabled=${_settingsService?.sharingEnabled}, isTest=${roomCode == 'TEST'})');

    if (shouldAddKey) {
      debugPrint('🔧 Adding access key to URL as query parameter');
      final finalUri = uri.replace(queryParameters: {'key': accessKey});
      debugPrint(
          '🔧 Final URI with key: ${finalUri.toString().replaceAll(RegExp(r'key=[^&]*'), 'key=***')}');
      return finalUri;
    }

    debugPrint('🔧 No access key added - sharing disabled and not a test');
    debugPrint('🔧 Final URI without key: $uri');
    return uri;
  }

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  String? _roomCode;
  String? _participantId;
  String? _participantName;

  bool _isConnected = false;
  final List<RoomMessage> _messages = [];

  // Room checking
  Completer<RoomCheckResult>? _roomCheckCompleter;

  // Haptic feedback flags
  bool _participantJoinedHapticNeeded = false;

  // Join request state
  String? _pendingJoinRequest;
  String? _pendingJoinRequestName;
  bool _awaitingApproval = false;
  String? _approvalMessage;
  String? _joinDeniedReason;
  bool _joinSuccessful = false;

  // Settings service reference
  SettingsService? _settingsService;

  // Temporary connection for join attempts
  WebSocketChannel? _tempChannel;
  StreamSubscription? _tempSubscription;

  // Current speaking session ULID tracking
  String? _currentSessionUlid;

  // Fix the broken getters - keep existing API
  String? _activeSpeakerId;
  String? _activeSpeakerName;
  List<RoomParticipant> _participants = [];

  // Button state tracking for all participants
  final Map<String, bool> _participantButtonStates = {};
  final Map<String, DateTime> _lastButtonActivity = {};
  final Map<String, DateTime> _lastHeartbeat = {};

  // Add missing timer declarations
  Timer? _heartbeatTimer;
  Timer? _buttonStateCleanupTimer;

  // Add heartbeat state tracking for UI
  DateTime? _lastHeartbeatReceived;
  bool _heartbeatHealthy = false;

  // Per-participant heartbeat tracking for connection status indicators
  final Map<String, DateTime> _participantLastHeartbeat = {};

  // Track current text content for synchronization
  String _currentTextContent = '';
  final Map<String, String> _participantTextContent = {};

  // Track text editing state for participants
  bool _isCurrentlyTexting = false;
  final Map<String, bool> _participantTextingStates = {};

  // Track collapsed/acknowledged content per participant
  final Map<String, String> _acknowledgedParticipantContent = {};
  final Set<String> _collapsedParticipants = {};

  // Track inactive and removed participants
  final Set<String> _inactiveParticipants = {};
  final Set<String> _removedParticipants = {};

  // Track blocked participants (can't rejoin)
  final Set<String> _blockedParticipants = {};

  // OFFLINE MODE STATE - START IN OFFLINE MODE BY DEFAULT
  bool _isOfflineMode = true; // Default to offline mode
  bool _localSpeaking = false;
  bool _startedInOfflineMode =
      true; // Track if we started offline vs fell offline
  Timer? _reconnectionTimer;

  // SEARCHING FOR NETWORK STATE
  bool _isSearchingForNetwork = false;
  String _connectionStatusMessage = '';
  Timer? _searchingTimer;
  DateTime? _searchingStartTime;
  bool _showUserChoice = false;

  // Track if we were recently speaking to handle final transcripts after mic release
  bool _wasRecentlySpeaking = false;
  Timer? _recentSpeakingTimer;

  // Current real-time STT text (for display while speaking)
  String _currentSTTText = '';
  bool _isCurrentlyReceivingSTT = false;

  // Getters
  bool get isConnected => _isConnected;
  String? get roomCode => _isOfflineMode ? "OFFLINE" : _roomCode;

  // Add back the missing getters that the UI expects
  String? get activeSpeakerId => _isOfflineMode
      ? (_localSpeaking ? _participantId : null)
      : (_concurrentMode
          ? null
          : _activeSpeakerId); // In concurrent mode, no single active speaker
  String? get activeSpeakerName => _isOfflineMode
      ? (_localSpeaking ? _participantName : null)
      : (_concurrentMode ? null : _activeSpeakerName);

  bool get isSpeaking => _isOfflineMode
      ? _localSpeaking
      : (_concurrentMode
          ? _currentSpeakers.contains(_participantId)
          : (_activeSpeakerId == _participantId));
  bool get canSpeak => _isOfflineMode
      ? true
      : (_concurrentMode
          ? true // Always can speak in concurrent mode
          : (_activeSpeakerId == null || _activeSpeakerId == _participantId));

  // New getters for concurrent mode
  Set<String> get currentSpeakers => Set.unmodifiable(_currentSpeakers);
  bool get isConcurrentMode => _concurrentMode;
  bool isParticipantSpeaking(String participantId) {
    return _currentSpeakers.contains(participantId);
  }

  List<RoomParticipant> get participants => _isOfflineMode
      ? _getOfflineParticipants()
      : List.unmodifiable(
          _participants); // Keep participants during searching mode

  List<RoomMessage> get messages => List.unmodifiable(_messages);
  String? get savedName => _settingsService?.userName;
  String? get currentUserId => _participantId;
  String? get currentDeviceUuid =>
      _participantId; // Device UUID getter for debugging

  // Offline mode getters
  bool get isOfflineMode => _isOfflineMode;

  // Searching for network getters
  bool get isSearchingForNetwork => _isSearchingForNetwork;
  String get connectionStatusMessage => _connectionStatusMessage;
  bool get showUserChoice => _showUserChoice;

  // Real-time STT getters
  String get currentSTTText => _currentSTTText;
  bool get isCurrentlyReceivingSTT => _isCurrentlyReceivingSTT;

  // Text editing state getters
  bool get isCurrentlyTexting => _isCurrentlyTexting;
  String? get activeTexterId => _participantTextingStates.entries
      .where((entry) => entry.value == true)
      .map((entry) => entry.key)
      .firstOrNull;
  Map<String, bool> get participantTextingStates =>
      Map.unmodifiable(_participantTextingStates);

  // Inactive participant getters
  Set<String> get inactiveParticipants =>
      Set.unmodifiable(_inactiveParticipants);
  bool isParticipantInactive(String participantId) =>
      _inactiveParticipants.contains(participantId);
  bool isParticipantRemoved(String participantId) =>
      _removedParticipants.contains(participantId);

  // Collapsed/acknowledged content getters
  Set<String> get collapsedParticipants =>
      Set.unmodifiable(_collapsedParticipants);
  bool isParticipantCollapsed(String participantId) =>
      _collapsedParticipants.contains(participantId);

  // Blocked participants getters
  Set<String> get blockedParticipants => Set.unmodifiable(_blockedParticipants);
  bool isParticipantBlocked(String participantId) =>
      _blockedParticipants.contains(participantId);

  // Create offline participant list (just the current user)
  List<RoomParticipant> _getOfflineParticipants() {
    if (_participantId == null || _participantName == null) return [];
    return [
      RoomParticipant(
        id: _participantId!,
        name: _participantName!,
      )
    ];
  }

  // Backwards compatibility getters
  bool get isInRoom => _isConnected || _isOfflineMode || _isSearchingForNetwork;
  RoomParticipant? get activeSpeaker => _activeSpeakerId != null
      ? _participants.firstWhere((p) => p.id == _activeSpeakerId,
          orElse: () => RoomParticipant(
              id: _activeSpeakerId!, name: _activeSpeakerName ?? 'Unknown'))
      : null;
  bool get shouldTriggerHaptic => false; // Disable for now

  // Haptic feedback getters
  bool get shouldTriggerParticipantJoinedHaptic =>
      _participantJoinedHapticNeeded;

  // Join request getters
  bool get hasPendingJoinRequest => _pendingJoinRequest != null;
  String? get pendingJoinRequestId {
    return _pendingJoinRequest;
  }

  String? get pendingJoinRequestName => _pendingJoinRequestName;

  // Create a virtual participant for layout purposes
  RoomParticipant? get pendingParticipant => _pendingJoinRequest != null
      ? RoomParticipant(
          id: _pendingJoinRequest!,
          name: _pendingJoinRequestName ?? 'Unknown',
        )
      : null;

  // Combined participants list for layout (includes pending)
  List<RoomParticipant> get allParticipants {
    // Use the appropriate participants list based on mode
    final List<RoomParticipant> baseParticipants =
        _isOfflineMode ? _getOfflineParticipants() : _participants;

    final all = List<RoomParticipant>.from(baseParticipants);

    // Add pending participants back to the list for inline display
    if (!_isOfflineMode && pendingParticipant != null) {
      all.add(pendingParticipant!);
    }

    return all;
  }

  bool get isAwaitingApproval => _awaitingApproval;
  String? get approvalMessage => _approvalMessage;
  String? get joinDeniedReason => _joinDeniedReason;
  bool get joinSuccessful => _joinSuccessful;

  String get shareUrl {
    if (_roomCode == null || _participantName == null) return '';
    return 'https://nanatalka.app/join/$_roomCode#key=$_participantName';
  }

  // Set settings service reference
  void setSettingsService(SettingsService settingsService) {
    _settingsService = settingsService;
    notifyListeners();
  }

  // Initialize in offline mode with user info (always start here)
  void initializeOfflineMode({String? userName}) {
    debugPrint('🔌 Initializing in offline mode');

    // Set up participant info for offline mode
    _participantName = userName ?? _settingsService?.userName ?? 'User';
    _participantId = _settingsService?.deviceUuid ?? const Uuid().v4();
    _roomCode = null; // Will show as "OFFLINE"

    // Ensure we're in offline mode
    _isOfflineMode = true;
    _isConnected = false;

    // Clear any online state
    _participants.clear();
    _messages.clear();
    _activeSpeakerId = null;
    _activeSpeakerName = null;

    // Clear inactive and removed participant tracking
    _inactiveParticipants.clear();
    _removedParticipants.clear();

    debugPrint(
        '🏠 Offline mode initialized: $_participantName (${_participantId?.substring(0, 8)}...)');

    // Start continuous polling to try to get online
    _startOfflinePolling();

    notifyListeners();
  }

  // Track if we're currently attempting a background connection
  bool _isAttemptingBackgroundConnection = false;

  // Attempt to connect to online room in background (non-blocking)
  Future<void> attemptBackgroundConnection({String? savedRoomCode}) async {
    // Don't try to connect if sharing is disabled
    if (_settingsService?.sharingEnabled == false) {
      debugPrint('🔌 Sharing disabled - skipping background connection');
      return;
    }

    if (!_isOfflineMode) {
      debugPrint('⚠️ Already connected, skipping background connection');
      return;
    }

    if (_isAttemptingBackgroundConnection) {
      debugPrint('⚠️ Background connection already in progress, skipping');
      return;
    }

    _isAttemptingBackgroundConnection = true;
    debugPrint('🌐 Attempting background connection...');

    try {
      if (savedRoomCode != null && savedRoomCode.isNotEmpty) {
        debugPrint('🔄 Trying to rejoin saved room: $savedRoomCode');
        await autoRejoinSavedRoom();
      } else {
        debugPrint('🆕 Creating new room in background');
        final roomCode = await generateUniqueRoomCode();
        await joinRoom(roomCode, _participantName!,
            settingsService: _settingsService);
      }
    } catch (e) {
      debugPrint('🌐 Background connection failed: $e - staying offline');
      // Stay in offline mode - this is fine
    } finally {
      _isAttemptingBackgroundConnection = false;
    }
  }

  // Successfully switch from offline to online mode
  void _switchToOnlineMode() {
    if (!_isOfflineMode) return;

    debugPrint('🌐 Switching from offline to online mode');
    _isOfflineMode = false;
    _startedInOfflineMode = false; // We're now online

    // Cancel any offline polling or reconnection attempts
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;

    // Messages are now unified - no migration needed
    debugPrint('📤 Messages remain unified between offline and online modes');

    notifyListeners();
  }

  // Method to attempt joining a different room without disconnecting from current room
  Future<void> attemptJoinDifferentRoom(String roomCode, String userName,
      {SettingsService? settingsService}) async {
    try {
      debugPrint(
          '🔄 Attempting to join different room $roomCode while staying connected to $_roomCode');

      // FIRST: Cancel any existing join attempts to prevent multiple dialogs
      if (_awaitingApproval || _tempChannel != null) {
        debugPrint(
            '🚫 Cancelling existing join attempt before starting new one');
        cancelJoinRequest();

        // Wait a bit for cleanup to complete
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Set up for new room attempt
      _settingsService = settingsService ?? _settingsService;

      String finalUserName = userName;
      if (userName.isEmpty) {
        finalUserName = 'Guest User';
      }

      String deviceUuid;
      if (_settingsService != null) {
        deviceUuid = _settingsService!.deviceUuid;
      } else {
        deviceUuid = const Uuid().v4();
        debugPrint(
            'Warning: No settings service provided, using fallback UUID');
      }

      debugPrint(
          'Attempting to join room: $roomCode as $finalUserName with device UUID: ${deviceUuid.substring(0, 8)}...');

      // Create new connection for the target room without disconnecting current
      final wsUrl = _buildWebSocketUrl(roomCode, _settingsService?.accessKey);
      debugPrint('Creating new connection to: $wsUrl');

      final newChannel = WebSocketChannel.connect(wsUrl);
      _tempChannel = newChannel;
      _tempSubscription = null;

      // Set up temporary message handling for the join attempt
      _tempSubscription = newChannel.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            debugPrint(
                '🎯 Received message on temporary connection: ${data['type']}');

            if (data['type'] == 'awaitingApproval') {
              // Join request is awaiting approval - this is expected for occupied rooms
              _awaitingApproval = true;
              _approvalMessage = data['data']?['message'] ?? data['message'];
              debugPrint(
                  '📝 Join request awaiting approval: $_approvalMessage');
              notifyListeners();
            } else if (data['type'] == 'joinDenied') {
              // Join was denied - clean up temp connection and stay in original room
              debugPrint(
                  '❌ Join denied: ${data['reason']} - staying in original room');
              _joinDeniedReason = data['reason'];
              _awaitingApproval = false;
              _approvalMessage = null;
              _joinSuccessful = false;

              // Clean up temporary connection
              _tempSubscription?.cancel();
              _tempChannel?.sink.close();
              _tempChannel = null;

              notifyListeners();
            } else if (data['type'] == 'participantJoined') {
              // Check if the participant who joined is us
              final joinedParticipant = RoomParticipant.fromJson(data['data']);
              if (joinedParticipant.id == deviceUuid) {
                debugPrint(
                    '🎉 WE were added to the room as participant! Join approved!');

                // We were approved and added to the room - trigger room state fetch
                // The roomState should come next, but let's make sure we handle this case
                _awaitingApproval = false;
                _approvalMessage = null;
                notifyListeners();
              }
            } else if (data['type'] == 'roomState') {
              // Check if we're successfully in the new room
              // Handle both old and new roomState formats
              List<RoomParticipant> participants = [];

              final participantsData = data['data']['participants'];

              if (participantsData is List) {
                // Old format: participants is a direct list
                participants = participantsData
                    .map((p) => RoomParticipant.fromJson(p))
                    .toList();
              } else if (participantsData is Map) {
                // New format: participants has active/timedOut/declined categories
                final activeParticipants =
                    participantsData['active'] as List? ?? [];
                participants = activeParticipants
                    .map((p) => RoomParticipant.fromJson(p))
                    .toList();
              } else {
                debugPrint(
                    '❌ Unknown participants data format: ${participantsData.runtimeType}');
                debugPrint('❌ Raw data: $participantsData');
              }

              debugPrint('🏠 Room state received on temporary connection:');
              debugPrint('  - Participants: ${participants.length}');
              for (final p in participants) {
                debugPrint('    - ${p.name} (${p.id})');
              }
              debugPrint('  - My device UUID: $deviceUuid');

              final amIInRoom = participants.any((p) => p.id == deviceUuid);
              debugPrint('  - Am I in room? $amIInRoom');

              if (amIInRoom) {
                debugPrint(
                    '✅ Successfully joined new room - switching connection');

                // First, update all the state variables
                _roomCode = roomCode;
                _participantName = finalUserName;
                _participantId = deviceUuid;
                _participants = participants;
                // DON'T auto-set as speaker - only when button is pressed
                _activeSpeakerId = null;
                _activeSpeakerName = null;
                _messages.clear(); // Clear old messages
                _awaitingApproval = false;
                _approvalMessage = null;
                _joinDeniedReason = null;
                _joinSuccessful = true; // Set success flag for dialog to detect
                debugPrint(
                    '🎉 Set joinSuccessful flag to TRUE - dialog should close now');

                // Save the new room code
                if (_settingsService != null) {
                  _settingsService!.setRoomCode(roomCode);
                  debugPrint('💾 Saved new room code: $roomCode');
                }

                // CRITICAL: Close old connection BEFORE switching
                _subscription?.cancel();
                _channel?.sink.close();

                // CRITICAL: Don't reuse the temp stream - it already has a listener
                // Instead, cancel temp connection and create a fresh one
                _tempSubscription?.cancel();
                _tempChannel?.sink.close();

                // Create a completely fresh connection for the main channel
                final wsUrl =
                    _buildWebSocketUrl(roomCode, _settingsService?.accessKey);
                _channel = WebSocketChannel.connect(wsUrl);
                _isConnected = true;

                // Set up fresh subscription on the new connection
                _subscription = _channel!.stream.listen(
                  _handleMessage, // Use the main message handler for heartbeats
                  onError: _handleError,
                  onDone: _handleDone,
                );

                // Clear temp references
                _tempChannel = null;
                _tempSubscription = null;

                // Send join message on the fresh connection to complete the handshake
                final joinMessage = {
                  'type': 'join',
                  'deviceUuid': deviceUuid,
                  'displayName': finalUserName,
                  'participantId': deviceUuid,
                  'name': finalUserName,
                };
                debugPrint('🔄 Sending join message on fresh connection');
                _channel!.sink.add(jsonEncode(joinMessage));

                // CRITICAL: Restart the polling system for the new connection
                Timer(const Duration(milliseconds: 100), () {
                  if (_isConnected && !_isOfflineMode) {
                    _startPollingSystem(); // Start heartbeat and cleanup for new connection
                  }
                });

                debugPrint('🔄 Connection switch complete:');
                debugPrint('  - New room: $_roomCode');
                debugPrint('  - Connected: $_isConnected');
                debugPrint('  - Participants: ${_participants.length}');
                debugPrint('  - Awaiting approval: $_awaitingApproval');

                // Notify listeners IMMEDIATELY
                notifyListeners();

                // Add multiple notifications to ensure UI updates
                Future.delayed(const Duration(milliseconds: 10), () {
                  notifyListeners();
                });

                Future.delayed(const Duration(milliseconds: 50), () {
                  notifyListeners();
                });

                // Force trigger another notification after a bit longer delay
                Future.delayed(const Duration(milliseconds: 100), () {
                  notifyListeners();
                });

                // Reset the join success flag after dialog has had time to close
                Future.delayed(const Duration(milliseconds: 500), () {
                  _joinSuccessful = false;
                  notifyListeners();
                });
              }
            } else {
              // Log only important message types (skip heartbeat spam)
              if (data['type'] != 'heartbeat') {
                debugPrint(
                    '📨 Other message on temp connection: ${data['type']} - ${data.toString()}');
              }
            }
          } catch (e, stackTrace) {
            debugPrint('❌ Error handling message on new connection: $e');
            debugPrint('❌ Stack trace: $stackTrace');
            debugPrint('❌ Original message: $message');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error on new connection: $error');
          _joinDeniedReason = 'Connection error: $error';
          _awaitingApproval = false;
          _approvalMessage = null;

          // Clean up temporary connection
          _tempSubscription?.cancel();
          _tempChannel?.sink.close();

          notifyListeners();
        },
      );

      // Wait for connection to stabilize
      await Future.delayed(const Duration(milliseconds: 100));

      // Send join message on new connection
      final joinMessage = {
        'type': 'join',
        'deviceUuid': deviceUuid,
        'displayName': finalUserName,
        'participantId': deviceUuid,
        'name': finalUserName,
      };

      debugPrint('Sending join message on new connection: $joinMessage');
      newChannel.sink.add(jsonEncode(joinMessage));
    } catch (e) {
      debugPrint('❌ Error attempting to join different room: $e');
      _joinDeniedReason = 'Error: $e';
      _awaitingApproval = false;
      _approvalMessage = null;
      notifyListeners();
      rethrow;
    }
  }

  // Auto-rejoin saved room with smart approval logic
  Future<void> autoRejoinSavedRoom() async {
    final savedRoomCode = _settingsService?.roomCode;
    final userName = _settingsService?.userName;

    debugPrint('🔍 Auto-rejoin check:');
    debugPrint('  - Saved room code: $savedRoomCode');
    debugPrint('  - Saved username: $userName');

    if (savedRoomCode == null) {
      debugPrint('❌ No saved room code - will create new room');
      return;
    }

    if (userName == null || userName.isEmpty) {
      debugPrint('❌ No saved username - will create new room');
      return;
    }

    try {
      debugPrint('🔍 Checking saved room: $savedRoomCode');

      // Try to check if the saved room is empty or occupied
      try {
        final roomStatus = await checkRoom(savedRoomCode);

        if (roomStatus.isEmpty) {
          debugPrint('✅ Saved room is empty - joining directly');
          await joinRoom(savedRoomCode, userName,
              settingsService: _settingsService);
        } else {
          debugPrint(
              '🔒 Saved room has ${roomStatus.participantCount} participants - requesting approval');
          // Room is occupied, go through approval process
          await joinRoom(savedRoomCode, userName,
              settingsService: _settingsService);
        }
      } catch (roomCheckError) {
        debugPrint('⚠️ Room check failed: $roomCheckError');
        debugPrint('🔄 Attempting direct join to saved room without check');

        // If room check fails, try joining directly anyway
        // The server will handle approval if needed
        await joinRoom(savedRoomCode, userName,
            settingsService: _settingsService);
      }
    } catch (e) {
      String errorType = 'Unknown error';
      if (e.toString().contains('No internet connection')) {
        errorType = 'No internet connection';
      } else if (e.toString().contains('Cannot resolve')) {
        errorType = 'DNS resolution failed';
      } else if (e.toString().contains('timeout')) {
        errorType = 'Connection timeout';
      } else if (e.toString().contains('SocketException')) {
        errorType = 'Socket connection failed';
      }

      debugPrint('❌ Error checking/joining saved room ($errorType): $e');

      // If connection fails while trying to rejoin saved room, set up offline mode
      debugPrint(
          '🔌 Failed to rejoin saved room ($errorType) - entering offline mode for graceful reconnection');

      // Set up offline mode with saved username
      _participantName = userName;
      _participantId = _settingsService?.deviceUuid ?? const Uuid().v4();
      _roomCode = null; // Will show as "OFFLINE"

      _enterOfflineMode();
      return;
    }
  }

  // New signature for direct connection
  Future<void> joinRoom(String roomCode, String userName,
      {SettingsService? settingsService}) async {
    _settingsService = settingsService;

    // Clear any existing join requests first - user can only manage requests for current room
    if (hasPendingJoinRequest || _awaitingApproval) {
      debugPrint('🚨 CLEARING PENDING JOIN REQUESTS in joinRoom()!');
      debugPrint(
          '🚨 Current pending request: $_pendingJoinRequest ($_pendingJoinRequestName)');
      debugPrint('🚨 Target room: $roomCode, current room: $_roomCode');
      debugPrint('🚨 This is likely the cause of the pending request bug!');
      cancelJoinRequest();

      // Clear pending join request state as well
      debugPrint('🚨 Setting _pendingJoinRequest to null');
      _pendingJoinRequest = null;
      _pendingJoinRequestName = null;

      // Clear awaiting approval state
      _awaitingApproval = false;
      _approvalMessage = null;
      _joinDeniedReason = null;
      _joinSuccessful = false;

      debugPrint('✅ Cleared all join request states before joining $roomCode');
    }

    // Generate final user name (add number suffix if needed)
    String finalUserName = userName;
    if (userName.isEmpty) {
      finalUserName = 'Guest User';
    }

    // Use device UUID as participant ID instead of generating new one each time
    String deviceUuid;
    if (_settingsService != null) {
      deviceUuid = _settingsService!.deviceUuid;
    } else {
      // Fallback if settings service not provided
      deviceUuid = const Uuid().v4();
      debugPrint('Warning: No settings service provided, using fallback UUID');
    }

    // Don't rejoin if already in the same room with same name and same device
    if (_isConnected &&
        _roomCode == roomCode &&
        _participantName == finalUserName &&
        _participantId == deviceUuid) {
      debugPrint(
          'Already connected to room $roomCode as $finalUserName with device $deviceUuid');
      return;
    }

    debugPrint(
        'Joining room: $roomCode as $finalUserName with device UUID: ${deviceUuid.substring(0, 8)}...');
    _roomCode = roomCode;
    _participantName = finalUserName;
    _participantId = deviceUuid; // Use device UUID as participant ID

    await _connect();
  }

  Future<void> _connect() async {
    // Always disconnect from current connection when switching rooms
    if (_channel != null) {
      debugPrint(
          '🔄 Disconnecting from current room before connecting to new one');
      await disconnect();
    }

    // Reset approval state when starting new connection
    _awaitingApproval = false;
    _approvalMessage = null;
    _joinDeniedReason = null;
    _joinSuccessful = false;

    try {
      final wsUrl = _buildWebSocketUrl(_roomCode!, _settingsService?.accessKey);
      debugPrint('Connecting to: $wsUrl');

      _channel = WebSocketChannel.connect(wsUrl);

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      // Wait a bit for connection to stabilize, then send join message
      await Future.delayed(const Duration(milliseconds: 100));

      final joinMessage = {
        'type': 'join',
        'deviceUuid': _participantId, // Send device UUID
        'displayName': _participantName, // Send display name
        // Keep participantId for backward compatibility
        'participantId': _participantId,
        'name': _participantName,
      };
      debugPrint(
          'Sending join message with device UUID: ${_participantId?.substring(0, 8)}... and display name: $_participantName');
      debugPrint('📤 Full join message: ${jsonEncode(joinMessage)}');
      _sendMessage(joinMessage);

      // Connection successful - we can now transition to online mode

      _isConnected = true;

      // Initialize heartbeat status for immediate good connection indication
      _lastHeartbeatReceived = DateTime.now();
      _heartbeatHealthy = true;

      notifyListeners();
      debugPrint('Connected to room $_roomCode');
      debugPrint('🚀🚀🚀 IMMEDIATE TEST - THIS SHOULD ALWAYS PRINT 🚀🚀🚀');

      try {
        debugPrint('🎯 CHECKPOINT 1: About to switch to online mode');

        // Switch from offline to online mode
        _switchToOnlineMode();
        debugPrint(
            '🎯 CHECKPOINT 2: Switched to online mode, about to check polling system');
      } catch (e, stackTrace) {
        debugPrint('💥 ERROR in post-connection setup: $e');
        debugPrint('📍 Stack trace: $stackTrace');
      }

      // Start polling system after a short delay to allow initial messages to process
      Timer(const Duration(milliseconds: 100), () {
        debugPrint(
            '🎯 CHECKPOINT 3: Timer callback executing - checking conditions:');
        debugPrint('  - _isConnected: $_isConnected');
        debugPrint('  - _isOfflineMode: $_isOfflineMode');

        if (_isConnected && !_isOfflineMode) {
          debugPrint(
              '🎯 CHECKPOINT 4: Conditions met - calling _startPollingSystem()');
          _startPollingSystem(); // Start heartbeat and cleanup
          debugPrint('🎯 CHECKPOINT 5: _startPollingSystem() call completed');
        } else {
          debugPrint(
              '❌ CHECKPOINT 4: Conditions NOT met - polling system NOT started');
          debugPrint('  - Required: _isConnected=true && _isOfflineMode=false');
          debugPrint(
              '  - Actual: _isConnected=$_isConnected && _isOfflineMode=$_isOfflineMode');
        }
      });

      // Connection stability check
      Timer(const Duration(seconds: 2), () {
        if (_isConnected && !_isOfflineMode) {
          debugPrint('🔗 Connection stable and online');
        }
      });
    } catch (e) {
      debugPrint('Connection error: $e');
      _isConnected = false;

      // Check if this is a network outage (DNS failure)
      final isNetworkOutage = e.toString().contains('Failed host lookup') ||
          e.toString().contains('No address associated with hostname') ||
          e.toString().contains('SocketException');

      if (isNetworkOutage) {
        debugPrint(
            '🌐 Detected network outage during connection - entering offline mode');
        _enterOfflineMode();
        return;
      }

      // For non-network errors, go to offline mode and let the reconnection timer handle it
      debugPrint(
          '🔌 Connection failed - falling back to offline mode for graceful reconnection');
      _enterOfflineMode();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      // Debug: Show full message content for join-related messages
      if (['roomState', 'participantJoined', 'awaitingApproval', 'joinDenied']
          .contains(data['type'])) {
        debugPrint('📋 Full message content: ${data.toString()}');
      }

      switch (data['type']) {
        case 'roomState':
          _handleRoomState(data['data']);
          break;
        case 'buttonPressed':
          _handleButtonPressed(data['data']);
          break;
        case 'buttonReleased':
          _handleButtonReleased(data['data']);
          break;
        case 'heartbeat':
          _handleHeartbeat(data['data']);
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
        case 'roomStatus':
          _handleRoomStatus(data['data']);
          break;
        case 'joinRequest':
          _handleJoinRequest(data['data']);
          break;
        case 'awaitingApproval':
          _handleAwaitingApproval(data['data']);
          break;
        case 'joinDenied':
          _handleJoinDenied(data);
          break;
        case 'joinApproved':
          _handleJoinApproved(data['data']);
          break;
        case 'joinDeclined':
          _handleJoinDeclined(data['data']);
          break;
        case 'joinCancelled':
          _handleJoinCancelled(data['data']);
          break;
        case 'liveSTT':
          _handleLiveSTT(data['data']);
          break;
        case 'liveTextContent':
          _handleLiveTextContent(data['data']);
          break;
        case 'liveTextingStatus':
          _handleLiveTextingStatus(data['data']);
          break;
      }
    } catch (e) {
      debugPrint('Error handling message: $e');
    }
  }

  void _handleRoomState(Map<String, dynamic> state) {
    debugPrint('Raw room state received: $state');

    // If we were searching for network and got a room state, we're back online
    if (_isSearchingForNetwork) {
      debugPrint('✅ Got room state while searching - network recovered!');
      _exitSearchingMode();
    }

    // Handle new enhanced room state format
    if (state.containsKey('participants') && state['participants'] is Map) {
      final participantsMap = state['participants'] as Map<String, dynamic>;

      // Extract active participants (main list for UI)
      final activeParticipants = (participantsMap['active'] as List? ?? [])
          .map((p) => RoomParticipant.fromJson(p))
          .toList();

      final timedOutParticipants = (participantsMap['timedOut'] as List? ?? [])
          .map((p) => RoomParticipant.fromJson(p))
          .toList();

      final declinedParticipants = (participantsMap['declined'] as List? ?? [])
          .map((p) => RoomParticipant.fromJson(p))
          .toList();

      _participants = activeParticipants;

      debugPrint(
          'Enhanced room state: ${activeParticipants.length} active, ${timedOutParticipants.length} timed out, ${declinedParticipants.length} declined');
      for (final p in activeParticipants) {
        debugPrint('  Active: ${p.name} (${p.id})');
      }
      for (final p in timedOutParticipants) {
        debugPrint('  Timed out: ${p.name} (${p.id})');
      }
      for (final p in declinedParticipants) {
        debugPrint('  Declined: ${p.name} (${p.id})');
      }
    } else {
      // Handle legacy room state format (list of participants)
      _participants = (state['participants'] as List? ?? [])
          .map((p) => RoomParticipant.fromJson(p))
          .toList();

      debugPrint('Legacy room state: ${_participants.length} participants');
      for (final p in _participants) {
        debugPrint('  - ${p.name} (${p.id})');
      }
    }

    // Check if this room supports concurrent mode
    _concurrentMode = state['concurrentMode'] == true;
    debugPrint('Room concurrent mode: $_concurrentMode');

    // Handle active speaker (only relevant in non-concurrent mode)
    if (!_concurrentMode &&
        state.containsKey('activeSpeaker') &&
        state['activeSpeaker'] != null) {
      _activeSpeakerId = state['activeSpeaker'];
      _activeSpeakerName = _participants
          .firstWhere((p) => p.id == _activeSpeakerId,
              orElse: () =>
                  RoomParticipant(id: _activeSpeakerId!, name: 'Unknown'))
          .name;
      debugPrint('Server provided active speaker: $_activeSpeakerName');
    } else {
      if (_concurrentMode) {
        debugPrint('Concurrent mode - no single active speaker');
      } else {
        debugPrint('No active speaker in room state - clearing speaking state');
      }
      _activeSpeakerId = null;
      _activeSpeakerName = null;
    }

    debugPrint('My participant ID: $_participantId');

    final amIInRoom = _participants.any((p) => p.id == _participantId);
    debugPrint('Am I in the active list? $amIInRoom');
    debugPrint('Current _awaitingApproval state: $_awaitingApproval');

    // CRITICAL: Always notify listeners when room state changes
    notifyListeners();

    // If we're not in the room but expected to be, this might be a server issue
    if (!amIInRoom && _isConnected && !_awaitingApproval) {
      debugPrint('⚠️ We\'re connected but not in the participants list!');
      debugPrint('   This might indicate:');
      debugPrint('   1. Server didn\'t process our join message');
      debugPrint('   2. We need to wait for a participantJoined message');
      debugPrint(
          '   3. The room requires approval but no awaitingApproval was sent');

      // Try sending the join message again immediately and then with retries
      final joinMessage = {
        'type': 'join',
        'deviceUuid': _participantId,
        'displayName': _participantName,
        'participantId': _participantId,
        'name': _participantName,
      };

      // First retry - immediate
      debugPrint('🔄 Immediate retry: Resending join message');
      _sendMessage(joinMessage);

      // Second retry after 500ms
      Timer(const Duration(milliseconds: 500), () {
        if (!_participants.any((p) => p.id == _participantId) &&
            _isConnected &&
            !_awaitingApproval) {
          debugPrint('🔄 Second retry: Resending join message after 500ms');
          _sendMessage(joinMessage);
        }
      });

      // Third retry after 2 seconds
      Timer(const Duration(seconds: 2), () {
        if (!_participants.any((p) => p.id == _participantId) &&
            _isConnected &&
            !_awaitingApproval) {
          debugPrint('🔄 Third retry: Resending join message after 2s');
          _sendMessage(joinMessage);
        }
      });

      // Fourth retry after 5 seconds (final attempt)
      Timer(const Duration(seconds: 5), () {
        if (!_participants.any((p) => p.id == _participantId) &&
            _isConnected &&
            !_awaitingApproval) {
          debugPrint('🔄 Final retry: Resending join message after 5s');
          _sendMessage(joinMessage);

          // If still not in room after 5 seconds, something is wrong
          Timer(const Duration(seconds: 2), () {
            if (!_participants.any((p) => p.id == _participantId) &&
                _isConnected &&
                !_awaitingApproval) {
              debugPrint(
                  '❌ Still not in room after multiple retries - this room may have an issue');
            }
          });
        }
      });
    }

    // If we're in the room but still waiting for approval, clear the waiting state
    if (amIInRoom && _awaitingApproval) {
      debugPrint('✅ Approval successful - clearing waiting state');
      debugPrint('  - Was awaiting approval: $_awaitingApproval');
      debugPrint('  - Approval message was: $_approvalMessage');
      _awaitingApproval = false;
      _approvalMessage = null;
      debugPrint('  - Now awaiting approval: $_awaitingApproval');

      // Force additional notification for approval state change
      notifyListeners();
    } else if (!amIInRoom && _awaitingApproval) {
      debugPrint(
          '⏳ Still awaiting approval - not yet in active participant list');
    } else if (amIInRoom && !_awaitingApproval) {
      debugPrint('✅ In room and not awaiting approval - normal state');
    }

    // Save the room code when we successfully join
    if (amIInRoom && _roomCode != null && _settingsService != null) {
      _settingsService!.setRoomCode(_roomCode!);
      debugPrint('💾 Saved room code: $_roomCode');
    }
  }

  void _handleParticipantJoined(Map<String, dynamic> data) {
    _participants.add(RoomParticipant.fromJson(data));
    debugPrint(
        'Participant joined: ${data['name']} - Current total: ${_participants.length}');

    // Trigger haptic feedback (three buzzes) when someone joins
    _triggerParticipantJoinedHaptic();

    notifyListeners();
  }

  void _handleParticipantLeft(Map<String, dynamic> data) {
    final participantId = data['id'];

    // CRITICAL: Never remove ourselves from the participant list
    if (participantId == _participantId) {
      debugPrint(
          '⚠️ Ignoring participantLeft for ourselves - this should not happen!');
      debugPrint(
          '  - Server sent participantLeft for our own ID: $participantId');
      debugPrint('  - This indicates a server-side bug during reconnection');
      return; // Don't remove ourselves!
    }

    _participants.removeWhere((p) => p.id == participantId);

    // Clean up heartbeat tracking for this participant
    _participantLastHeartbeat.remove(participantId);
    _lastHeartbeat.remove(participantId);
    _participantButtonStates.remove(participantId);
    _lastButtonActivity.remove(participantId);
    _participantTextContent.remove(participantId);
    _participantTextingStates.remove(participantId);
    _inactiveParticipants.remove(participantId);
    _removedParticipants.remove(participantId);

    // Clean up collapsed/acknowledged content tracking
    _acknowledgedParticipantContent.remove(participantId);
    _collapsedParticipants.remove(participantId);

    debugPrint('Participant left: ${data['name']}');
    notifyListeners();
  }

  void _handleSpeakerChanged(Map<String, dynamic> data) {
    final speakerId = data['speakerId'];
    final speakerName = data['speakerName'];
    final action = data['action'] ?? 'started';

    debugPrint(
        'Speaker event: $speakerName $action speaking (concurrent mode: $_concurrentMode)');

    if (_concurrentMode) {
      // In concurrent mode, track multiple speakers
      if (action == 'started') {
        _currentSpeakers.add(speakerId);
        debugPrint(
            '👥 $speakerName started speaking (${_currentSpeakers.length} total speakers)');
      }
    } else {
      // Legacy single-speaker mode
      if (speakerId != _participantId) {
        _activeSpeakerId = speakerId;
        _activeSpeakerName = speakerName;
        debugPrint('👥 Someone else is now speaking: $speakerName');
      }
    }

    notifyListeners();
  }

  void _handleSpeakerStopped(Map<String, dynamic> data) {
    final speakerId = data['speakerId'];
    final action = data['action'] ?? 'stopped';

    debugPrint(
        'Speaker stopped: $speakerId ($action) - concurrent mode: $_concurrentMode');

    if (_concurrentMode) {
      // In concurrent mode, remove from current speakers
      _currentSpeakers.remove(speakerId);
      final participantName = _participants
          .firstWhere((p) => p.id == speakerId,
              orElse: () => RoomParticipant(id: speakerId, name: 'Unknown'))
          .name;
      debugPrint(
          '👥 $participantName stopped speaking (${_currentSpeakers.length} total speakers)');
    } else {
      // Legacy single-speaker mode
      if (speakerId != _participantId && _activeSpeakerId == speakerId) {
        _activeSpeakerId = null;
        _activeSpeakerName = null;
        debugPrint('✅ Cleared active speaker');
      }
    }

    notifyListeners();
  }

  void _handleCaption(Map<String, dynamic> data) {
    debugPrint('🎤 Caption received:');
    debugPrint('  - Message ID: ${data['messageId']}');
    debugPrint('  - Speaker ID: ${data['speakerId']}');
    debugPrint('  - My ID: $_participantId');
    debugPrint('  - Is Final: ${data['isFinal']}');
    debugPrint(
        '  - Text: ${data['text'].substring(0, data['text'].length.clamp(0, 30))}...');

    // Create message for ALL captions (including our own)
    final message = RoomMessage(
      id: data['messageId'], // Use ULID from client
      speakerId: data['speakerId'],
      speakerName: data['speakerName'],
      text: data['text'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp']),
      isFinal: data['isFinal'],
      dismissed: false,
    );

    // Look for existing message with the same ULID
    final existingIndex = _messages.indexWhere((m) => m.id == message.id);

    if (existingIndex != -1) {
      // Update existing message with same ULID
      _messages[existingIndex] = message;
      debugPrint(
          '📝 Updated existing message ${message.id} from ${message.speakerName}');
    } else {
      // Add new message
      _messages.add(message);
      debugPrint(
          '➕ Added new message ${message.id} from ${message.speakerName}');

      // Keep only last 50 messages to prevent memory issues
      if (_messages.length > 50) {
        _messages.removeRange(0, _messages.length - 50);
      }
    }

    debugPrint(
        'Caption from ${message.speakerName}: ${message.text.substring(0, message.text.length.clamp(0, 30))}...');
    notifyListeners();
  }

  void _handleSpeakDenied(Map<String, dynamic> data) {
    debugPrint('Speaking denied by server: ${data['reason']}');

    // Instead of immediately stopping, log it and continue
    // The user can choose to stop manually if needed
    debugPrint('🔄 Continuing to speak despite server denial (user choice)');

    // Optionally stop speaking automatically:
    // if (isSpeaking) {
    //   debugPrint('🛑 Stopping speaking due to server denial');
    //   _activeSpeakerId = null;
    //   _activeSpeakerName = null;
    //   notifyListeners();
    // }
  }

  void _triggerParticipantJoinedHaptic() {
    // Signal to UI to trigger three-buzz haptic feedback
    _participantJoinedHapticNeeded = true;
    notifyListeners();

    // Reset the flag after a short delay
    Timer(const Duration(milliseconds: 100), () {
      _participantJoinedHapticNeeded = false;
    });
  }

  void _handleRoomStatus(Map<String, dynamic> data) {
    final participantCount = data['participantCount'] as int;
    final activeCount = data['activeCount'] as int? ?? participantCount;
    final timedOutCount = data['timedOutCount'] as int? ?? 0;
    final declinedCount = data['declinedCount'] as int? ?? 0;
    final isEmpty = data['isEmpty'] as bool;

    debugPrint(
        'Room status: $participantCount total ($activeCount active, $timedOutCount timed out, $declinedCount declined), empty: $isEmpty');

    // Complete the room check future if one is pending
    if (_roomCheckCompleter != null && !_roomCheckCompleter!.isCompleted) {
      _roomCheckCompleter!.complete(RoomCheckResult(
        participantCount: participantCount,
        isEmpty: isEmpty,
      ));
    }
  }

  void _handleJoinRequest(Map<String, dynamic> data) {
    debugPrint('🔔 JOIN REQUEST RECEIVED on client:');
    debugPrint('  - Requester ID: ${data['requesterId']}');
    debugPrint('  - Requester Name: ${data['requesterName']}');
    debugPrint('  - Timestamp: ${data['timestamp']}');
    debugPrint('  - Current pending request: $_pendingJoinRequest');
    debugPrint('  - My participant ID: $_participantId');

    final requesterId = data['requesterId'];
    final requesterName = data['requesterName'];

    // Don't process our own join request
    if (requesterId == _participantId) {
      debugPrint('🚫 Ignoring join request from ourselves ($requesterName)');
      return;
    }

    // Check if this participant is blocked
    if (_blockedParticipants.contains(requesterId)) {
      debugPrint(
          '🚫 Blocking join request from blocked participant: $requesterName');

      // Automatically decline the request
      _sendMessage({
        'type': 'declineJoin',
        'requesterId': requesterId,
      });

      // Don't set pending join request since we're auto-blocking
      return;
    }

    // Check if this participant should be automatically approved
    if (_shouldAutoApproveParticipant(requesterId, requesterName)) {
      debugPrint('✅ Auto-approving rejoining participant: $requesterName');

      // Automatically approve the request
      _sendMessage({
        'type': 'approveJoin',
        'requesterId': requesterId,
      });

      // Don't set pending join request since we're auto-approving
      return;
    }

    // Not auto-approved, show manual approval UI
    _pendingJoinRequest = requesterId;
    _pendingJoinRequestName = requesterName;
    debugPrint(
        '✅ Set pending join request for manual approval: $requesterName ($requesterId)');
    debugPrint('🔍 _pendingJoinRequest is now: $_pendingJoinRequest');
    debugPrint('🔍 About to call notifyListeners() for pending join request');
    notifyListeners();
    debugPrint(
        '🔍 Called notifyListeners() - _pendingJoinRequest is still: $_pendingJoinRequest');
  }

  // Check if a participant should be automatically approved for rejoining
  bool _shouldAutoApproveParticipant(
      String participantId, String participantName) {
    // Don't auto-approve if they're already in the participants list (shouldn't happen)
    final isCurrentParticipant =
        _participants.any((p) => p.id == participantId);
    if (isCurrentParticipant) {
      debugPrint(
          '⚠️ Participant $participantName is already in the room - should not request join');
      return false; // This case shouldn't happen, require manual review
    }

    // Check if they have recent activity (sent messages in the last 10 minutes)
    final recentActivityThreshold =
        DateTime.now().subtract(const Duration(minutes: 10));
    final hasRecentMessages = _messages.any((message) =>
        message.speakerId == participantId &&
        message.timestamp.isAfter(recentActivityThreshold));

    if (hasRecentMessages) {
      debugPrint(
          '🔄 Participant $participantName has recent activity - auto-approve for temporary disconnect');
      return true;
    }

    // Check if they had recent heartbeat activity (were connected recently)
    final lastHeartbeat = _lastHeartbeat[participantId];
    if (lastHeartbeat != null) {
      final timeSinceLastHeartbeat = DateTime.now().difference(lastHeartbeat);
      if (timeSinceLastHeartbeat.inMinutes < 5) {
        debugPrint(
            '🔄 Participant $participantName had recent heartbeat (${timeSinceLastHeartbeat.inMinutes} min ago) - auto-approve for temporary disconnect');
        return true;
      }
    }

    debugPrint(
        '❓ Participant $participantName is unknown or was inactive - requires manual approval');
    return false;
  }

  void _handleAwaitingApproval(Map<String, dynamic> data) {
    _awaitingApproval = true;
    // Handle both old format (data.message) and new format (data directly has message)
    _approvalMessage = data['data']?['message'] ?? data['message'];
    debugPrint('✅ Awaiting approval: $_approvalMessage');
    notifyListeners();
  }

  void _handleJoinDenied(Map<String, dynamic> data) {
    _awaitingApproval = false;
    _approvalMessage = null;
    _joinDeniedReason = data['reason'];
    debugPrint('Join denied: ${data['reason']} - staying in current room');

    // Don't automatically create a new room - let user stay where they are
    // They can manually create a new room if desired

    notifyListeners();
  }

  void _handleJoinApproved(Map<String, dynamic> data) {
    // Clear waiting state when approved
    _awaitingApproval = false;
    _approvalMessage = null;

    debugPrint(
        '🚨 _handleJoinApproved clearing pending request (was: $_pendingJoinRequest)');
    debugPrint(
        '🚨 Approved: ${data['requesterName']} by ${data['approverName']}');
    _pendingJoinRequest = null;
    _pendingJoinRequestName = null;
    debugPrint(
        '${data['requesterName']} was approved by ${data['approverName']}');
    notifyListeners();
  }

  void _handleJoinDeclined(Map<String, dynamic> data) {
    debugPrint(
        '🚨 _handleJoinDeclined clearing pending request (was: $_pendingJoinRequest)');
    debugPrint(
        '🚨 Declined: ${data['requesterName']} by ${data['declinerName']}');
    _pendingJoinRequest = null;
    _pendingJoinRequestName = null;
    debugPrint(
        '${data['requesterName']} was declined by ${data['declinerName']}');
    notifyListeners();
  }

  void _handleJoinCancelled(Map<String, dynamic> data) {
    debugPrint(
        '🚨 _handleJoinCancelled clearing pending request (was: $_pendingJoinRequest)');
    debugPrint('🚨 Cancelled: ${data['requesterName']}');
    _pendingJoinRequest = null;
    _pendingJoinRequestName = null;
    debugPrint('${data['requesterName']} cancelled their join request');
    notifyListeners();
  }

  // Real-time sync handlers
  void _handleLiveSTT(Map<String, dynamic> data) {
    final participantId = data['participantId'];
    final text = data['text'];

    // Only update for other participants, not ourselves
    if (participantId != _participantId) {
      // Check if this is new content compared to what was acknowledged
      final acknowledgedContent =
          _acknowledgedParticipantContent[participantId] ?? '';
      final isNewContent =
          text != acknowledgedContent && text.trim().isNotEmpty;

      // If participant is collapsed but content is new, expand them
      if (_collapsedParticipants.contains(participantId) && isNewContent) {
        debugPrint('📈 Expanding $participantId - new STT content detected');
        _collapsedParticipants.remove(participantId);
        _acknowledgedParticipantContent.remove(participantId);
      }

      // Update participant text content for unified display and auto-scrolling
      if (_participantTextContent[participantId] != text) {
        debugPrint(
            '🔴 Live STT from $participantId: "${text.length > 30 ? text.substring(0, 30) + "..." : text}"');
        _participantTextContent[participantId] = text;
        notifyListeners();
      }
    }
  }

  void _handleLiveTextContent(Map<String, dynamic> data) {
    final participantId = data['participantId'];
    final text = data['text'];

    // Only update for other participants, not ourselves
    if (participantId != _participantId) {
      // Check if this is new content compared to what was acknowledged
      final acknowledgedContent =
          _acknowledgedParticipantContent[participantId] ?? '';
      final isNewContent =
          text != acknowledgedContent && text.trim().isNotEmpty;

      // If participant is collapsed but content is new, expand them
      if (_collapsedParticipants.contains(participantId) && isNewContent) {
        debugPrint('📈 Expanding $participantId - new content detected');
        _collapsedParticipants.remove(participantId);
        _acknowledgedParticipantContent.remove(participantId);
      }

      if (_participantTextContent[participantId] != text) {
        debugPrint(
            '📝 Live text content from $participantId: "${text.length > 30 ? text.substring(0, 30) + "..." : text}"');
        _participantTextContent[participantId] = text;
        notifyListeners();
      }
    }
  }

  void _handleLiveTextingStatus(Map<String, dynamic> data) {
    final participantId = data['participantId'];
    final isTexting = data['isTexting'];

    // Only update for other participants, not ourselves
    if (participantId != _participantId) {
      if (_participantTextingStates[participantId] != isTexting) {
        debugPrint('✏️ Live texting status from $participantId: $isTexting');
        _participantTextingStates[participantId] = isTexting;
        notifyListeners();
      }
    }
  }

  Future<bool> requestSpeak() async {
    if (_isOfflineMode) {
      debugPrint('🔌 Offline mode: Always can speak');
      return true;
    }

    if (!_isConnected) {
      debugPrint('Cannot request speak: not connected');
      return false;
    }

    if (_concurrentMode) {
      debugPrint('✅ Concurrent mode: Everyone can speak simultaneously');
      return true;
    }

    // Legacy single-speaker mode - check for conflicts
    if (someoneElseIsPressing) {
      final activePresser = _participantButtonStates.entries
          .where((entry) => entry.key != _participantId && entry.value == true)
          .map((entry) => entry.key)
          .first;

      final activeName = _participants
          .firstWhere((p) => p.id == activePresser,
              orElse: () => RoomParticipant(id: activePresser, name: 'Unknown'))
          .name;

      debugPrint(
          '❌ Cannot speak - $activeName is actually pressing their button');
      return false;
    }

    debugPrint('✅ No one else is pressing their button - can speak');
    return true;
  }

  // Rename and simplify the local speaking state control
  void setLocalSpeakingState(bool speaking) {
    debugPrint('🔊 setLocalSpeakingState called with: $speaking');
    debugPrint(
        '🔊 Before: _activeSpeakerId = $_activeSpeakerId, isSpeaking = $isSpeaking');

    if (_isOfflineMode) {
      // In offline mode, just update local state
      _localSpeaking = speaking;
      debugPrint('🔌 Offline mode: Set local speaking to $speaking');

      // Handle recent speaking for final transcripts
      if (!speaking) {
        _wasRecentlySpeaking = true;
        _recentSpeakingTimer?.cancel();
        _recentSpeakingTimer = Timer(const Duration(seconds: 2), () {
          _wasRecentlySpeaking = false;
          debugPrint('🕒 Recent speaking window expired');
        });
      }

      notifyListeners();
      return;
    }

    // 1. Update local state IMMEDIATELY (0ms latency)
    if (_concurrentMode) {
      // In concurrent mode, track multiple speakers
      if (speaking) {
        _currentSpeakers.add(_participantId!);
        debugPrint(
            '🎤 Added self to speakers (${_currentSpeakers.length} total)');
      } else {
        _currentSpeakers.remove(_participantId);
        debugPrint(
            '🎤 Removed self from speakers (${_currentSpeakers.length} total)');

        // Set recent speaking flag to allow final transcripts
        _wasRecentlySpeaking = true;
        _recentSpeakingTimer?.cancel();
        _recentSpeakingTimer = Timer(const Duration(seconds: 2), () {
          _wasRecentlySpeaking = false;
          debugPrint('🕒 Recent speaking window expired');
        });
      }
    } else {
      // Legacy single-speaker mode
      if (speaking) {
        _activeSpeakerId = _participantId;
        _activeSpeakerName = _participantName;
      } else {
        _activeSpeakerId = null;
        _activeSpeakerName = null;

        // Set recent speaking flag to allow final transcripts
        _wasRecentlySpeaking = true;
        _recentSpeakingTimer?.cancel();
        _recentSpeakingTimer = Timer(const Duration(seconds: 2), () {
          _wasRecentlySpeaking = false;
          debugPrint('🕒 Recent speaking window expired');
        });
      }
    }

    debugPrint(
        '🔊 After: _activeSpeakerId = $_activeSpeakerId, isSpeaking = $isSpeaking');

    // CRITICAL: Update our own button state locally for immediate UI feedback
    _participantButtonStates[_participantId!] = speaking;
    debugPrint(
        '🔊 Updated local button state: ${_participantButtonStates[_participantId]}');

    notifyListeners(); // UI updates instantly

    // 2. Broadcast to peers (don't wait for response)
    _sendMessage({
      'type': speaking ? 'buttonPressed' : 'buttonReleased',
      'participantId': _participantId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void stopSpeaking() {
    if (!isSpeaking) return;

    debugPrint('Stopping speaking');

    // Clear the session ULID when stopping speaking
    if (_currentSessionUlid != null) {
      debugPrint('🧹 Clearing session ULID on stop speaking');
      _currentSessionUlid = null;
    }

    _sendMessage({
      'type': 'stopSpeak',
      'participantId': _participantId,
    });
  }

  void approveJoinRequest(String requesterId) {
    if (!_isConnected || _pendingJoinRequest != requesterId) return;

    _sendMessage({
      'type': 'approveJoin',
      'requesterId': requesterId,
    });
  }

  void declineJoinRequest(String requesterId) {
    if (!_isConnected || _pendingJoinRequest != requesterId) return;

    _sendMessage({
      'type': 'declineJoin',
      'requesterId': requesterId,
    });
  }

  void blockJoinRequest(String requesterId) {
    if (!_isConnected || _pendingJoinRequest != requesterId) return;

    // Add to blocked list
    _blockedParticipants.add(requesterId);
    debugPrint('🚫 Blocked participant: $requesterId');

    // Decline the current request
    _sendMessage({
      'type': 'declineJoin',
      'requesterId': requesterId,
    });
  }

  void clearJoinDeniedReason() {
    _joinDeniedReason = null;
    _joinSuccessful =
        false; // Also clear success flag when clearing denied reason
  }

  // Remove an inactive participant from the room
  void removeParticipant(String participantId) {
    if (!_isConnected) return;

    debugPrint('🗑️ Removing participant: $participantId');

    // Add to removed participants set so they won't be auto-approved
    _removedParticipants.add(participantId);

    // Remove from inactive set if present
    _inactiveParticipants.remove(participantId);

    // Send remove message to server
    _sendMessage({
      'type': 'removeParticipant',
      'participantId': participantId,
    });

    // Remove locally immediately for UI feedback
    _participants.removeWhere((p) => p.id == participantId);

    // Clear any related states
    _participantButtonStates.remove(participantId);
    _lastButtonActivity.remove(participantId);
    _lastHeartbeat.remove(participantId);
    _participantLastHeartbeat.remove(participantId);
    _participantTextContent.remove(participantId);
    _participantTextingStates.remove(participantId);

    // Clear collapsed/acknowledged content tracking
    _acknowledgedParticipantContent.remove(participantId);
    _collapsedParticipants.remove(participantId);

    // Clear blocked status when participant leaves
    _blockedParticipants.remove(participantId);

    // If they were speaking, clear that too
    if (_activeSpeakerId == participantId) {
      _activeSpeakerId = null;
      _activeSpeakerName = null;
    }

    notifyListeners();
  }

  void cancelJoinRequest() {
    if (_awaitingApproval) {
      debugPrint('🚫 Cancelling join request');

      // Send cancel message on the temp connection if it exists, otherwise on main connection
      if (_tempChannel != null) {
        try {
          _tempChannel!.sink.add(jsonEncode({
            'type': 'cancelJoin',
          }));
          debugPrint('Sent cancel request on temporary connection');
        } catch (e) {
          debugPrint('Error sending cancel on temp connection: $e');
        }

        // Clean up temporary connection
        _tempSubscription?.cancel();
        _tempChannel?.sink.close();
        _tempChannel = null;
        _tempSubscription = null;
      } else {
        // Fallback to main connection
        _sendMessage({
          'type': 'cancelJoin',
        });
      }

      _awaitingApproval = false;
      _approvalMessage = null;
      _joinDeniedReason = null;
      _joinSuccessful = false;
      notifyListeners();
    }
  }

  Future<void> _autoCreateNewRoomAfterDecline() async {
    try {
      debugPrint('Auto-creating new room after decline...');

      // Generate a unique empty room code
      final newRoomCode = await generateUniqueRoomCode();

      // Update settings service to use the new room code if available
      if (_settingsService != null) {
        _settingsService!.setRoomCode(newRoomCode);
      }

      debugPrint(
          'Automatically created and switched to new room: $newRoomCode');
    } catch (e) {
      debugPrint('Error auto-creating new room: $e');
      // Don't throw - we don't want to break the flow, just log the error
    }
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_isOfflineMode) {
      // Don't try to send messages in offline mode
      return;
    }

    if (_channel != null) {
      try {
        final encoded = jsonEncode(message);

        // Only log non-heartbeat messages to reduce console spam
        if (message['type'] != 'heartbeat') {
          debugPrint('Sending to server: $encoded');
        }

        _channel!.sink.add(encoded);
      } catch (e) {
        debugPrint('Error sending message: $e');
      }
    } else {
      debugPrint('Cannot send message: channel is null');

      // If we're trying to send but channel is null, connection is lost
      if (_isConnected) {
        debugPrint(
            '🔌 Channel is null but we think we\'re connected - connection lost!');
        _isConnected = false;

        // For null channel (clear network issue), enter searching mode
        debugPrint(
            '🔌 Connection lost (null channel) - entering searching mode');
        _enterSearchingMode();
      }
    }
  }

  void _handleError(error) {
    debugPrint('WebSocket error: $error');
    _isConnected = false;

    // Check if this is a network outage (DNS failure)
    final isNetworkOutage = error.toString().contains('Failed host lookup') ||
        error.toString().contains('No address associated with hostname') ||
        error.toString().contains('SocketException');

    if (isNetworkOutage) {
      debugPrint('🌐 Detected network outage - entering searching mode');
      _enterSearchingMode();
      return;
    }

    // For non-network errors, enter searching mode (user choice after 2 minutes)
    debugPrint(
        '🔌 Connection error - entering searching mode for user-controlled reconnection');
    _enterSearchingMode();
  }

  void _handleDone() {
    debugPrint('WebSocket connection closed');
    _isConnected = false;

    // Connection closed - enter searching mode (user choice after 2 minutes)
    debugPrint(
        '🔌 Connection closed - entering searching mode for user-controlled reconnection');
    _enterSearchingMode();
  }

  // Enter offline mode when connection fails
  void _enterOfflineMode() {
    if (_isOfflineMode) {
      debugPrint('🔌 Already in offline mode, ignoring duplicate call');
      return;
    }

    debugPrint('🔌 Entering offline mode');
    final wasOnline = !_startedInOfflineMode; // Were we previously online?
    _isOfflineMode = true;
    _isConnected = false;

    // Reset retry attempts when entering offline mode
    _reconnectionAttempts = 0;

    // Cancel any pending connections
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _subscription = null;

    // Cancel temp connections too
    _tempSubscription?.cancel();
    _tempChannel?.sink.close();
    _tempChannel = null;
    _tempSubscription = null;

    // Stop any timers
    _heartbeatTimer?.cancel();
    _buttonStateCleanupTimer?.cancel();

    // Ensure we have participant info for offline mode
    _participantId ??= _settingsService?.deviceUuid ?? const Uuid().v4();
    if (_participantName == null || _participantName!.isEmpty) {
      _participantName = _settingsService?.userName ?? 'User';
    }

    // Keep participant info but clear online-only state
    _participants.clear();
    // Keep _messages - they're unified now (user's own messages persist)
    _activeSpeakerId = null;
    _activeSpeakerName = null;

    debugPrint(
        '🏠 Offline mode: Current user is $_participantName (${_participantId?.substring(0, 8)}...)');

    // Only start periodic reconnection if we were previously online
    if (wasOnline) {
      debugPrint(
          '💔 Connection lost - starting periodic reconnection attempts');
      _startReconnectionTimer();
      // TODO: Show "Connection lost" notification here if needed
    } else {
      debugPrint('🔌 Started in offline mode - no reconnection needed');
    }

    notifyListeners();
  }

  // Start continuous polling when in offline mode to try to get online
  void _startOfflinePolling() {
    // Don't try to connect if sharing is disabled
    if (_settingsService?.sharingEnabled == false) {
      debugPrint('🔌 Sharing disabled - staying in solo offline mode');
      return;
    }

    _reconnectionTimer?.cancel();

    debugPrint('⏰ Starting offline polling (every 10 seconds)');
    _reconnectionTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!_isOfflineMode) {
        // Successfully connected, cancel timer
        _reconnectionTimer?.cancel();
        _reconnectionTimer = null;
        debugPrint('✅ Offline polling stopped - now online');
        return;
      }

      // Check again if sharing is still enabled
      if (_settingsService?.sharingEnabled == false) {
        debugPrint('🔌 Sharing was disabled - stopping offline polling');
        _reconnectionTimer?.cancel();
        _reconnectionTimer = null;
        return;
      }

      debugPrint('🔄 Attempting to get online from offline mode...');

      // Try to rejoin saved room first, or create new one
      final savedRoomCode = _settingsService?.roomCode;
      if (savedRoomCode != null && savedRoomCode.isNotEmpty) {
        debugPrint('🔄 Trying to rejoin saved room: $savedRoomCode');
        try {
          await autoRejoinSavedRoom();
        } catch (e) {
          debugPrint('❌ Failed to rejoin saved room: $e');
        }
      } else {
        debugPrint('🆕 No saved room, trying to create new room');
        try {
          await attemptBackgroundConnection();
        } catch (e) {
          debugPrint('❌ Background connection failed: $e');
        }
      }
    });
  }

  // Reconnection backoff tracking
  int _reconnectionAttempts = 0;

  // Start periodic reconnection attempts (when connection was lost)
  void _startReconnectionTimer() {
    // Don't try to reconnect if sharing is disabled
    if (_settingsService?.sharingEnabled == false) {
      debugPrint('🔌 Sharing disabled - skipping reconnection attempts');
      return;
    }

    debugPrint('🚀 STARTING RECONNECTION TIMER SYSTEM');
    debugPrint('   - Current offline mode: $_isOfflineMode');
    debugPrint('   - Current connected: $_isConnected');
    debugPrint('   - Room code: $_roomCode');

    _reconnectionTimer?.cancel();
    _reconnectionAttempts = 0;

    _scheduleNextReconnection();
  }

  void _scheduleNextReconnection() {
    if (!_isOfflineMode) {
      debugPrint(
          '🚫 _scheduleNextReconnection called but not in offline mode - ignoring');
      return;
    }

    // Linear backoff: 1s, 2s, 3s, 4s, 5s, 6s, 7s, 8s... up to 60s, then 60s forever
    final backoffSeconds = _reconnectionAttempts < 60
        ? _reconnectionAttempts + 1 // 1s, 2s, 3s... up to 60s
        : 60; // Cap at 60s (1 minute) - never exceed 1 minute intervals

    debugPrint(
        '⏰ SCHEDULING RECONNECTION: attempt ${_reconnectionAttempts + 1} in ${backoffSeconds}s (offline mode: $_isOfflineMode)');

    _reconnectionTimer = Timer(Duration(seconds: backoffSeconds), () async {
      debugPrint(
          '🔥 RECONNECTION TIMER FIRED: attempt ${_reconnectionAttempts + 1}');
      debugPrint('   - Current offline mode: $_isOfflineMode');
      debugPrint('   - Current connected: $_isConnected');
      debugPrint('   - Room code: $_roomCode');
      debugPrint('   - Participant name: $_participantName');
      if (!_isOfflineMode) {
        // Successfully reconnected, cancel timer
        _reconnectionTimer?.cancel();
        _reconnectionTimer = null;
        _reconnectionAttempts = 0;
        return;
      }

      _reconnectionAttempts++;
      debugPrint('🔄 Attempting reconnection #$_reconnectionAttempts...');

      // Try to reconnect using the last known room code and user name
      if (_roomCode != null && _participantName != null) {
        try {
          await joinRoom(_roomCode!, _participantName!,
              settingsService: _settingsService);
          debugPrint('✅ Periodic reconnection successful');
          _reconnectionAttempts = 0; // Reset on success
        } catch (e) {
          // Check if it's still a network outage
          final isNetworkOutage = e.toString().contains('Failed host lookup') ||
              e.toString().contains('No address associated with hostname') ||
              e.toString().contains('SocketException');

          if (isNetworkOutage) {
            debugPrint('🌐 Network still down, will retry with backoff');
          } else {
            debugPrint('❌ Reconnection failed with different error: $e');
          }

          // Schedule next attempt
          _scheduleNextReconnection();
        }
      } else {
        // No room to reconnect to, try background connection
        debugPrint('🌐 No room to reconnect to, trying background connection');
        try {
          await attemptBackgroundConnection(
              savedRoomCode: _settingsService?.roomCode);
          _reconnectionAttempts = 0; // Reset on success
        } catch (e) {
          debugPrint('❌ Background connection failed: $e');
          _scheduleNextReconnection();
        }
      }
    });
  }

  // Debug method to force reconnection attempt
  Future<void> debugReconnectToSavedRoom() async {
    if (_settingsService == null) {
      debugPrint('❌ Cannot reconnect: No settings service available');
      return;
    }

    final savedRoomCode = _settingsService!.roomCode;
    final savedUserName = _settingsService!.userName;

    if (savedRoomCode == null || savedUserName == null) {
      debugPrint('❌ Cannot reconnect: No saved room or username');
      return;
    }

    debugPrint('🔄 DEBUG RECONNECTION ATTEMPT');
    debugPrint('  Room: $savedRoomCode');
    debugPrint('  User: $savedUserName');
    debugPrint('  Current mode: ${_isOfflineMode ? "OFFLINE" : "ONLINE"}');

    // Reset retry attempts and attempt reconnection
    _reconnectionAttempts = 0;

    try {
      await joinRoom(savedRoomCode, savedUserName,
          settingsService: _settingsService);
      debugPrint('✅ Debug reconnection successful');
    } catch (e) {
      debugPrint('❌ Debug reconnection failed: $e');
    }
  }

  // Test network connectivity (simplified for web compatibility)
  Future<String> testConnectivity() async {
    try {
      debugPrint('🌐 Testing network connectivity...');

      // Simple WebSocket connection test
      try {
        final wsUrl = _buildWebSocketUrl('TEST', _settingsService?.accessKey);
        final testChannel = WebSocketChannel.connect(wsUrl);
        await testChannel.sink.close();
        debugPrint('✅ WebSocket connection test: OK');
        return 'Connectivity test passed! ✅';
      } catch (e) {
        return 'Cannot establish WebSocket connection. Please check your internet connection.';
      }
    } catch (e) {
      return 'Connectivity test failed: $e';
    }
  }

  // Test connectivity with a specific access key
  Future<ConnectionTestResult> testConnectivityWithKey(String accessKey) async {
    // Get server URL - try settings service first, then environment, then fallback
    String baseUrl;
    if (_settingsService != null) {
      baseUrl = _settingsService!.partyKitServer;
    } else {
      // Settings service not available - try to read environment directly
      try {
        final envServer = dotenv.env['PARTYKIT_SERVER'];
        if (envServer != null && envServer.isNotEmpty) {
          baseUrl = envServer;
        } else {
          baseUrl = 'wss://ccc-rooms.economicalstories.partykit.dev';
        }
      } catch (e) {
        baseUrl = 'wss://ccc-rooms.economicalstories.partykit.dev';
      }
    }

    // Build WebSocket URL with the provided access key - FORCE include for testing
    final uri = Uri.parse('$baseUrl/parties/main/TEST');
    final wsUrl = uri.replace(queryParameters: {'key': accessKey});

    debugPrint('Testing connection to room TEST...');

    WebSocketChannel? testChannel;
    StreamSubscription? subscription;
    Completer<ConnectionTestResult>? completer;

    try {
      // Create completer for test result
      completer = Completer<ConnectionTestResult>();

      testChannel = WebSocketChannel.connect(wsUrl);

      // Set up connection listeners
      subscription = testChannel.stream.listen(
        (message) {
          if (!completer!.isCompleted) {
            completer.complete(ConnectionTestResult(success: true));
          }
        },
        onError: (error) {
          if (!completer!.isCompleted) {
            String errorMessage = 'Connection failed';
            final errorStr = error.toString().toLowerCase();

            if (errorStr.contains('403') ||
                errorStr.contains('unauthorized') ||
                errorStr.contains('invalid') ||
                errorStr.contains('access')) {
              errorMessage = 'Invalid access key';
            } else if (errorStr.contains('failed host lookup') ||
                errorStr.contains('network')) {
              errorMessage = 'Network unavailable';
            } else if (errorStr.contains('socket')) {
              errorMessage = 'Network connection failed';
            } else if (errorStr.contains('timeout')) {
              errorMessage = 'Connection timeout';
            }

            completer.complete(
                ConnectionTestResult(success: false, error: errorMessage));
          }
        },
        onDone: () {
          if (!completer!.isCompleted) {
            completer.complete(ConnectionTestResult(
                success: false, error: 'Connection closed unexpectedly'));
          }
        },
      );

      // Give connection a moment to establish
      await Future.delayed(const Duration(milliseconds: 200));

      // Send a test ping message
      final testMessage = {
        'type': 'ping',
        'data': {
          'test': true,
          'timestamp': DateTime.now().millisecondsSinceEpoch
        }
      };
      testChannel.sink.add(jsonEncode(testMessage));

      // Set a timeout for the test
      Timer(const Duration(seconds: 10), () {
        if (!completer!.isCompleted) {
          completer.complete(ConnectionTestResult(
              success: false, error: 'Connection timeout'));
        }
      });

      final result = await completer.future;
      debugPrint(
          'Connection test ${result.success ? 'succeeded' : 'failed'}${result.error != null ? ': ${result.error}' : ''}');

      return result;
    } catch (e) {
      String errorMessage = 'Connection failed';
      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains('failed host lookup') ||
          errorStr.contains('network')) {
        errorMessage = 'Network unavailable';
      } else if (errorStr.contains('socket')) {
        errorMessage = 'Network connection failed';
      } else if (errorStr.contains('403') ||
          errorStr.contains('unauthorized')) {
        errorMessage = 'Invalid access key';
      } else if (errorStr.contains('timeout')) {
        errorMessage = 'Connection timeout';
      }

      debugPrint('Connection test failed: $errorMessage');
      return ConnectionTestResult(success: false, error: errorMessage);
    } finally {
      // Clean up resources
      try {
        subscription?.cancel();
        testChannel?.sink.close();
      } catch (e) {
        // Silently handle cleanup errors
      }
    }
  }

  // Check if a room is occupied without joining
  Future<RoomCheckResult> checkRoom(String roomCode) async {
    if (_roomCheckCompleter != null && !_roomCheckCompleter!.isCompleted) {
      _roomCheckCompleter!.completeError('Previous check cancelled');
    }

    _roomCheckCompleter = Completer<RoomCheckResult>();

    try {
      final wsUrl = _buildWebSocketUrl(roomCode, _settingsService?.accessKey);
      debugPrint('🌐 Room check: connecting to $wsUrl');

      final tempChannel = WebSocketChannel.connect(wsUrl);

      late StreamSubscription tempSubscription;

      tempSubscription = tempChannel.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            debugPrint('📨 Room check received: ${data['type']}');
            if (data['type'] == 'roomStatus') {
              final result = RoomCheckResult(
                participantCount: data['data']['participantCount'],
                isEmpty: data['data']['isEmpty'],
              );
              debugPrint(
                  '✅ Room check result: ${result.participantCount} participants, empty: ${result.isEmpty}');
              if (!_roomCheckCompleter!.isCompleted) {
                _roomCheckCompleter!.complete(result);
              }
              tempSubscription.cancel();
              tempChannel.sink.close();
            }
          } catch (e) {
            debugPrint('❌ Error parsing room check response: $e');
          }
        },
        onError: (error) {
          debugPrint('❌ Room check WebSocket error: $error');
          if (!_roomCheckCompleter!.isCompleted) {
            _roomCheckCompleter!.completeError(error);
          }
        },
      );

      // Wait a moment for connection to establish
      await Future.delayed(const Duration(milliseconds: 200));

      // Send check room message
      debugPrint('📤 Sending room check message');
      tempChannel.sink.add(jsonEncode({
        'type': 'checkRoom',
      }));

      // Extended timeout for startup/auto-rejoin scenarios - 15 seconds
      Timer(const Duration(seconds: 15), () {
        if (!_roomCheckCompleter!.isCompleted) {
          debugPrint(
              '⏰ Room check timeout after 15 seconds - network may be slow');
          _roomCheckCompleter!.completeError('Room check timeout');
          tempSubscription.cancel();
          tempChannel.sink.close();
        }
      });

      return await _roomCheckCompleter!.future;
    } catch (e) {
      debugPrint('❌ Room check connection error: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    debugPrint('Disconnecting from room');

    // Clear session ULID on disconnect
    _currentSessionUlid = null;

    // Clear color assignments for this room if we have room code
    if (_roomCode != null) {
      // Import the _SpeakerColors class to clean up assignments
      // Note: We'll handle this cleanup in the UI layer since _SpeakerColors is in the UI
    }

    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _subscription = null;
    _isConnected = false;
    _participants.clear();
    _messages.clear();
    _activeSpeakerId = null;
    _activeSpeakerName = null;
    notifyListeners();

    _heartbeatTimer?.cancel();
    _buttonStateCleanupTimer?.cancel();
    _searchingTimer?.cancel(); // Cancel searching timer
    _participantButtonStates.clear();
    _lastButtonActivity.clear();
    _lastHeartbeat.clear();
    _participantLastHeartbeat.clear();
    _participantTextContent.clear();
    _currentTextContent = '';

    // Clear searching state
    _isSearchingForNetwork = false;
    _connectionStatusMessage = '';
    _searchingStartTime = null;

    // Clear inactive and removed participant tracking
    _inactiveParticipants.clear();
    _removedParticipants.clear();

    // Clear collapsed/acknowledged content tracking
    _acknowledgedParticipantContent.clear();
    _collapsedParticipants.clear();

    // Clear blocked participants (room-specific)
    _blockedParticipants.clear();

    // Reset heartbeat health tracking
    _lastHeartbeatReceived = null;
    _heartbeatHealthy = false;

    // Clear all participant heartbeat tracking for fresh start
    _participantLastHeartbeat.clear();
  }

  // Generate a unique empty room code
  Future<String> generateUniqueRoomCode({int maxAttempts = 10}) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final roomCode = RoomCodeGenerator.generate();

      try {
        final result = await checkRoom(roomCode);
        if (result.isEmpty) {
          debugPrint(
              'Generated unique room code: $roomCode (attempt ${attempt + 1})');
          return roomCode;
        } else {
          debugPrint(
              'Room $roomCode is occupied (${result.participantCount} participants), trying another...');
        }
      } catch (e) {
        debugPrint(
            'Error checking room $roomCode: $e, assuming it\'s available');
        return roomCode; // If we can't check, assume it's available
      }
    }

    // Fallback: generate a timestamp-based code if all attempts fail
    final fallbackCode = 'ROOM${DateTime.now().millisecondsSinceEpoch % 10000}';
    debugPrint('Using fallback room code: $fallbackCode');
    return fallbackCode;
  }

  // Backwards compatibility methods
  Future<void> createRoom(String userName) async {
    // Clear any existing join requests first - user can escape by creating new room
    if (hasPendingJoinRequest || _awaitingApproval) {
      debugPrint(
          '🚨 CREATEROOM clearing existing join requests before creating new room');
      debugPrint(
          '🚨 Current pending request: $_pendingJoinRequest ($_pendingJoinRequestName)');
      cancelJoinRequest();

      // Clear pending join request state as well
      debugPrint('🚨 CREATEROOM setting _pendingJoinRequest to null');
      _pendingJoinRequest = null;
      _pendingJoinRequestName = null;

      // Clear awaiting approval state
      _awaitingApproval = false;
      _approvalMessage = null;
      _joinDeniedReason = null;
      _joinSuccessful = false;

      debugPrint('✅ Cleared all join request states');
    }

    try {
      // Generate a unique empty room code and join it
      final roomCode = await generateUniqueRoomCode();
      await joinRoom(roomCode, userName, settingsService: _settingsService);
    } catch (e) {
      debugPrint('❌ Failed to create room: $e - falling back to offline mode');

      // Set up offline mode with the provided username
      _participantName = userName.isEmpty ? 'User' : userName;
      _participantId = _settingsService?.deviceUuid ?? const Uuid().v4();
      _roomCode = null; // Will show as "OFFLINE"

      _enterOfflineMode();
    }
  }

  void startSpeaking() {
    requestSpeak();
  }

  void leaveRoom() {
    disconnect();
  }

  // Keep the current addCaptionText but only send if we're speaking
  void addCaptionText(String text, {bool isFinal = false}) {
    // Allow final transcripts even if we just stopped speaking (within 2 seconds)
    if (!isSpeaking && !_wasRecentlySpeaking) {
      return; // Silently ignore - no more debug spam
    }

    // Update real-time STT text for UI (always, even for non-final)
    _currentSTTText = text;
    _isCurrentlyReceivingSTT = !isFinal;

    // Generate ULID only once per speaking session (button press session)
    _currentSessionUlid ??= Ulid().toString();

    // Store message locally when final (same for both offline and online)
    if (isFinal && text.trim().isNotEmpty) {
      final message = RoomMessage(
        id: _currentSessionUlid!,
        speakerId: _participantId!,
        speakerName: _participantName!,
        text: text.trim(),
        timestamp: DateTime.now(),
        isFinal: true,
      );

      _messages.add(message);
      debugPrint('💾 Stored final message: "${text.trim()}"');
    }

    // Broadcast to server for real-time sync (both final and interim)
    if (!_isOfflineMode) {
      _sendMessage({
        'type': 'caption',
        'messageId': _currentSessionUlid!,
        'text': text,
        'isFinal': isFinal,
      });

      // Also send real-time STT update for live display on other devices
      if (!isFinal) {
        _sendMessage({
          'type': 'liveSTT',
          'participantId': _participantId!,
          'text': text,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }

    // Always notify listeners for real-time UI updates
    notifyListeners();

    // Clear session ULID when message is final (but keep it during the session)
    if (isFinal) {
      _currentSessionUlid = null;
      _currentSTTText = ''; // Clear the real-time text
      _isCurrentlyReceivingSTT = false;
      // Clear the recent speaking flag after final message
      _wasRecentlySpeaking = false;
      _recentSpeakingTimer?.cancel();
      _recentSpeakingTimer = null;
    }
  }

  void dismissMessage(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index >= 0) {
      _messages[index] = _messages[index].copyWith(dismissed: true);
      notifyListeners();

      // Remove from list after animation
      Future.delayed(const Duration(milliseconds: 300), () {
        _messages.removeWhere((m) => m.id == messageId);
        notifyListeners();
      });
    }
  }

  void editMessage(String messageId, String newText) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index >= 0) {
      _messages[index] = _messages[index].copyWith(
        text: newText,
        isFinal: true, // Edited messages are always final
      );
      notifyListeners();
    }
  }

  void sendTextMessage(String text) {
    if (text.trim().isEmpty) return;

    // Generate a unique message ID
    final messageId = DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();

    // Create the message locally first for immediate UI feedback
    final message = RoomMessage(
      id: messageId,
      text: text.trim(),
      speakerId: _participantId ?? '',
      speakerName: _participantName ?? 'You',
      timestamp: DateTime.now(),
      isFinal: true,
    );

    // Always add to unified message list
    _messages.add(message);
    debugPrint(
        '💬 Added user text message: ${text.substring(0, text.length.clamp(0, 30))}...');

    // Broadcast to server only when online
    if (!_isOfflineMode) {
      _sendMessage({
        'type': 'text_message',
        'messageId': messageId,
        'text': text.trim(),
        'participantId': _participantId,
        'participantName': _participantName ?? 'Unknown',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      debugPrint(
          '📤 Broadcasted text message to server: ${text.substring(0, text.length.clamp(0, 30))}...');
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectionTimer?.cancel();
    disconnect();
    super.dispose();
  }

  // Add message handlers
  void _handleButtonPressed(Map<String, dynamic> data) {
    final participantId = data['participantId'];
    final isPressed =
        data['isPressed'] ?? true; // Default to true for backward compatibility

    // Only update if it's not our own message
    if (participantId != _participantId) {
      debugPrint('🟡 ${data['participantName']} PRESSED their button');

      // Update button state immediately
      _participantButtonStates[participantId] = isPressed;
      _lastButtonActivity[participantId] = DateTime.now();
      _lastHeartbeat[participantId] = DateTime.now();

      // Update speaking state based on mode
      if (_concurrentMode) {
        if (isPressed) {
          _currentSpeakers.add(participantId);
          debugPrint(
              '➕ Added $participantId to concurrent speakers via button press');
        }
      } else {
        // Legacy single-speaker mode
        if (isPressed) {
          _activeSpeakerId = participantId;
          _activeSpeakerName = data['participantName'];
        }
      }
      notifyListeners();
    }
  }

  void _handleButtonReleased(Map<String, dynamic> data) {
    final participantId = data['participantId'];
    final participantName = data['participantName'];
    final isPressed = data['isPressed'] ??
        false; // Default to false for backward compatibility

    debugPrint('🟢 $participantName RELEASED their button');

    // Update button state immediately
    _participantButtonStates[participantId] = isPressed;
    _lastButtonActivity[participantId] = DateTime.now();
    _lastHeartbeat[participantId] = DateTime.now();

    // Update speaking state based on mode
    if (_concurrentMode) {
      _currentSpeakers.remove(participantId);
      debugPrint(
          '➖ Removed $participantId from concurrent speakers via button release');
    } else {
      // Legacy single-speaker mode
      if (_activeSpeakerId == participantId) {
        _activeSpeakerId = null;
        _activeSpeakerName = null;
        debugPrint('✅ Cleared active speaker');
      }
    }

    notifyListeners();
  }

  // Add heartbeat message handler
  void _handleHeartbeat(Map<String, dynamic> data) {
    final participantId = data['participantId'];

    // Log our own heartbeat responses occasionally for debugging
    if (participantId == _participantId &&
        DateTime.now().millisecond % 200 == 0) {
      debugPrint('💗 Received our own heartbeat response from server');
    } else if (participantId != _participantId &&
        DateTime.now().millisecond % 100 == 0) {
      debugPrint('💗 Heartbeat from ${participantId?.substring(0, 8)}...');
    }

    final isPressed = data['isPressed'] ?? false;
    final currentText = data['currentText'] ?? '';
    final isTexting = data['isTexting'] ?? false;
    final now = DateTime.now();

    _lastHeartbeat[participantId] = now;

    // Track per-participant heartbeats for connection status indicators
    _participantLastHeartbeat[participantId] = now;

    // Update our own health status when we receive ANY heartbeat from server
    _lastHeartbeatReceived = now;
    _heartbeatHealthy = true;

    // If we were searching for network and got a heartbeat, we're back online
    if (_isSearchingForNetwork) {
      debugPrint('✅ Network recovered - back online!');
      _exitSearchingMode();
    }

    bool shouldNotify = false;

    // Only sync states from heartbeat for OTHER participants, not ourselves
    if (participantId != _participantId) {
      // Remove from inactive list if they're sending heartbeats again
      if (_inactiveParticipants.contains(participantId)) {
        debugPrint(
            '😊 Participant $participantId is active again - removing from inactive list');
        _inactiveParticipants.remove(participantId);
        shouldNotify = true;
      }

      // Sync button state
      if (_participantButtonStates[participantId] != isPressed) {
        _participantButtonStates[participantId] = isPressed;
        shouldNotify = true;

        if (_concurrentMode) {
          // In concurrent mode, manage the speakers set
          if (isPressed) {
            _currentSpeakers.add(participantId);
            debugPrint(
                '➕ Added $participantId to concurrent speakers (${_currentSpeakers.length} total)');
          } else {
            _currentSpeakers.remove(participantId);
            debugPrint(
                '➖ Removed $participantId from concurrent speakers (${_currentSpeakers.length} total)');
          }
        } else {
          // Legacy single-speaker mode
          if (isPressed) {
            _activeSpeakerId = participantId;
            _activeSpeakerName = _participants
                .firstWhere((p) => p.id == participantId,
                    orElse: () =>
                        RoomParticipant(id: participantId, name: 'Unknown'))
                .name;
          } else if (_activeSpeakerId == participantId) {
            _activeSpeakerId = null;
            _activeSpeakerName = null;
          }
        }
      }

      // Sync text content
      if (_participantTextContent[participantId] != currentText) {
        _participantTextContent[participantId] = currentText;
        shouldNotify = true;
      }

      // Sync texting state
      if (_participantTextingStates[participantId] != isTexting) {
        _participantTextingStates[participantId] = isTexting;
        shouldNotify = true;
      }
    }

    if (shouldNotify) {
      notifyListeners();
    }
  }

  // Start heartbeat and cleanup timers
  void _startPollingSystem() {
    debugPrint('🎯 Starting polling system (heartbeat, cleanup, health check)');
    _startHeartbeat();
    _startButtonStateCleanup();
    _startHeartbeatHealthCheck();
    _startConnectionMonitoring();
    debugPrint('🎯 Polling system started successfully');
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    // Send initial heartbeat immediately
    _sendInitialHeartbeat();

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Send our current button state, text content, and texting state every 1 second
      final isPressed = _concurrentMode
          ? _currentSpeakers.contains(_participantId)
          : (_activeSpeakerId == _participantId);

      _sendMessage({
        'type': 'heartbeat',
        'participantId': _participantId,
        'isPressed': isPressed,
        'currentText': _currentTextContent,
        'isTexting': _isCurrentlyTexting,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
    debugPrint('💗 Heartbeat timer started (1s interval)');
  }

  void _sendInitialHeartbeat() {
    debugPrint('💗 Sending initial heartbeat immediately after connection');
    final isPressed = _concurrentMode
        ? _currentSpeakers.contains(_participantId)
        : (_activeSpeakerId == _participantId);

    _sendMessage({
      'type': 'heartbeat',
      'participantId': _participantId,
      'isPressed': isPressed,
      'currentText': _currentTextContent,
      'isTexting': _isCurrentlyTexting,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _startButtonStateCleanup() {
    _buttonStateCleanupTimer?.cancel();
    _buttonStateCleanupTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      const staleThreshold =
          Duration(seconds: 5); // Clear button state after 5 seconds
      const inactiveThreshold =
          Duration(seconds: 10); // Mark inactive after 10 seconds

      bool stateChanged = false;

      // Check all participants for inactivity
      for (final participant in _participants) {
        final participantId = participant.id;
        final lastSeen = _lastHeartbeat[participantId];

        if (participantId != _participantId) {
          // Don't check our own state
          if (lastSeen != null) {
            final timeSinceLastHeartbeat = now.difference(lastSeen);

            // Mark as inactive if no heartbeat for 10 seconds
            if (timeSinceLastHeartbeat > inactiveThreshold &&
                !_inactiveParticipants.contains(participantId)) {
              debugPrint(
                  '😴 Marking ${participant.name} as inactive (no heartbeat for ${timeSinceLastHeartbeat.inSeconds}s)');
              _inactiveParticipants.add(participantId);
              stateChanged = true;
            }

            // Clear button state if stale (5 seconds without heartbeat)
            if (timeSinceLastHeartbeat > staleThreshold &&
                _participantButtonStates[participantId] == true) {
              debugPrint(
                  '🧹 Clearing stale button state for ${participant.name} (no heartbeat for ${timeSinceLastHeartbeat.inSeconds}s)');

              _participantButtonStates[participantId] = false;

              // Clear speaker state in both modes
              if (_concurrentMode) {
                if (_currentSpeakers.contains(participantId)) {
                  _currentSpeakers.remove(participantId);
                  debugPrint(
                      '🧹 Removed stale participant from concurrent speakers');
                  stateChanged = true;
                }
              } else {
                // Clear active speaker if it was this stale participant
                if (_activeSpeakerId == participantId) {
                  _activeSpeakerId = null;
                  _activeSpeakerName = null;
                  stateChanged = true;
                }
              }
            }
          }
        }
      }

      if (stateChanged) {
        notifyListeners();
      }
    });
  }

  // Add getter to check if anyone else is pressing their button
  bool get someoneElseIsPressing {
    return _participantButtonStates.entries
        .any((entry) => entry.key != _participantId && entry.value == true);
  }

  // Add getter for UI - connection status
  bool get isHeartbeatHealthy => _heartbeatHealthy;
  DateTime? get lastHeartbeatReceived => _lastHeartbeatReceived;

  // Connection status getters for visual indicators
  ConnectionStatus get serverConnectionStatus {
    if (_isOfflineMode) return ConnectionStatus.offline;
    if (_lastHeartbeatReceived == null) return ConnectionStatus.connecting;

    final timeSinceLastHeartbeat =
        DateTime.now().difference(_lastHeartbeatReceived!);

    if (timeSinceLastHeartbeat.inSeconds < 2) return ConnectionStatus.good;
    if (timeSinceLastHeartbeat.inSeconds < 5) return ConnectionStatus.poor;
    return ConnectionStatus.bad;
  }

  ConnectionStatus getParticipantConnectionStatus(String participantId) {
    if (participantId == _participantId) return serverConnectionStatus;

    final lastHeartbeat = _participantLastHeartbeat[participantId];
    if (lastHeartbeat == null) return ConnectionStatus.unknown;

    final timeSinceLastHeartbeat = DateTime.now().difference(lastHeartbeat);
    if (timeSinceLastHeartbeat.inSeconds < 2) return ConnectionStatus.good;
    if (timeSinceLastHeartbeat.inSeconds < 5) return ConnectionStatus.poor;
    return ConnectionStatus.bad;
  }

  // Get seconds since last heartbeat for UI fading
  int getSecondsSinceLastHeartbeat(String participantId) {
    if (participantId == _participantId) {
      // For current user, use server connection status
      if (_lastHeartbeatReceived == null) return 999; // Very stale
      return DateTime.now().difference(_lastHeartbeatReceived!).inSeconds;
    }

    final lastHeartbeat = _participantLastHeartbeat[participantId];
    if (lastHeartbeat == null) return 999; // Very stale
    return DateTime.now().difference(lastHeartbeat).inSeconds;
  }

  // Text content management with real-time sync
  void setCurrentTextContent(String text) {
    if (_currentTextContent != text) {
      _currentTextContent = text;

      // Send real-time text content update immediately (not just on heartbeat)
      if (!_isOfflineMode) {
        _sendMessage({
          'type': 'liveTextContent',
          'participantId': _participantId!,
          'text': text,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // Don't notify listeners here as this is called from text field changes
      // The UI will update the text field locally
    }
  }

  // Text editing state management with real-time sync
  void setCurrentlyTexting(bool texting) {
    if (_isCurrentlyTexting != texting) {
      _isCurrentlyTexting = texting;
      debugPrint('📝 Set texting state to: $texting');

      // Send real-time texting status update immediately
      if (!_isOfflineMode) {
        _sendMessage({
          'type': 'liveTextingStatus',
          'participantId': _participantId!,
          'isTexting': texting,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }

      notifyListeners(); // Notify listeners for UI updates
    }
  }

  String getCurrentTextContent() => _currentTextContent;

  Map<String, String> get participantTextContent =>
      Map.unmodifiable(_participantTextContent);

  String getTextForParticipant(String participantId) {
    return _participantTextContent[participantId] ?? '';
  }

  // Add health check timer
  void _startHeartbeatHealthCheck() {
    Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lastHeartbeatReceived != null) {
        final timeSinceLastHeartbeat =
            DateTime.now().difference(_lastHeartbeatReceived!);

        // If we haven't received a heartbeat in 5 seconds, mark as unhealthy
        final wasHealthy = _heartbeatHealthy;
        _heartbeatHealthy = timeSinceLastHeartbeat.inSeconds < 5;

        // Only notify if health status changed to avoid excessive notifications
        if (wasHealthy != _heartbeatHealthy) {
          debugPrint(
              '💗 Heartbeat health changed: $wasHealthy -> $_heartbeatHealthy (${timeSinceLastHeartbeat.inSeconds}s since last heartbeat)');
          notifyListeners();
        }

        // Log connection status only when it changes or occasionally
        final connectionStatus = serverConnectionStatus;
        if (connectionStatus == ConnectionStatus.connecting) {
          // Only log connecting status every 5 seconds to avoid spam
          if (timeSinceLastHeartbeat.inSeconds % 5 == 0) {
            debugPrint(
                '🟡 Connection status: CONNECTING (${timeSinceLastHeartbeat.inSeconds}s since last heartbeat)');
          }
        }
        // Remove frequent GOOD status logging
      } else if (_heartbeatHealthy) {
        // No heartbeat received yet but we think we're healthy - update status
        _heartbeatHealthy = false;
        debugPrint('💗 No heartbeat received yet - marking as unhealthy');
        notifyListeners();
      }

      // Notify listeners for connection status updates
      notifyListeners();
    });
  }

  // Enhanced speaking state for concurrent mode
  final Set<String> _currentSpeakers = {}; // Track multiple speakers
  bool _concurrentMode = false; // Track if room supports concurrent speaking

  // Reset connection state to allow fresh connection attempts
  void resetConnectionState() {
    debugPrint(
        '🚨 RESETCONNECTION: Resetting connection state for fresh connection attempt');
    debugPrint(
        '🚨 Current pending request: $_pendingJoinRequest ($_pendingJoinRequestName)');

    // Clear any stuck approval states
    _awaitingApproval = false;
    _approvalMessage = null;
    _joinDeniedReason = null;
    _joinSuccessful = false;
    debugPrint('🚨 RESETCONNECTION setting _pendingJoinRequest to null');
    _pendingJoinRequest = null;
    _pendingJoinRequestName = null;

    // Clear temporary connections
    _tempSubscription?.cancel();
    _tempChannel?.sink.close();
    _tempChannel = null;
    _tempSubscription = null;

    // Reset background connection flag
    _isAttemptingBackgroundConnection = false;

    // Cancel any active timers
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;

    debugPrint('✅ Connection state reset - ready for fresh connection attempt');
    notifyListeners();
  }

  // Debug method to force reconnection to a specific room
  Future<void> forceReconnectToRoom(String roomCode, String userName) async {
    debugPrint(
        '🛠️ FORCE RECONNECT: Attempting to reconnect to $roomCode as $userName');

    // First reset all connection states
    resetConnectionState();

    // Disconnect if currently connected
    if (_isConnected) {
      await disconnect();
    }

    // Force exit offline mode
    _isOfflineMode = false;

    // Wait a moment for cleanup
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      // Attempt direct join
      await joinRoom(roomCode, userName, settingsService: _settingsService);
      debugPrint('✅ Force reconnect successful!');
    } catch (e) {
      debugPrint('❌ Force reconnect failed: $e');
      rethrow;
    }
  }

  // CONNECTION MONITORING FOR NETWORK OUTAGES
  void _startConnectionMonitoring() {
    Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isOfflineMode || _isSearchingForNetwork) return;

      _checkConnectionHealth();
    });
  }

  void _checkConnectionHealth() {
    if (_lastHeartbeatReceived == null) return;

    final timeSinceLastHeartbeat =
        DateTime.now().difference(_lastHeartbeatReceived!);

    // If no heartbeat for 5 seconds, probably network issue
    if (timeSinceLastHeartbeat.inSeconds >= 5 &&
        _isConnected &&
        !_isOfflineMode) {
      debugPrint(
          '🔍 No heartbeat for ${timeSinceLastHeartbeat.inSeconds}s - entering search mode');
      _enterSearchingMode();
    }
  }

  void _enterSearchingMode() {
    if (_isSearchingForNetwork) return; // Already searching

    debugPrint('🔍 ENTERING SEARCHING FOR NETWORK MODE');
    debugPrint(
        '   - Preserving ${_participants.length} participants for fade effect');
    debugPrint('   - Will NOT enter offline mode automatically');

    _isSearchingForNetwork = true;
    _connectionStatusMessage = 'Searching for network connection...';
    _searchingStartTime = DateTime.now();

    // IMPORTANT: Don't clear participants - let them fade visually
    // Don't change _isOfflineMode - we're still trying to be online

    // Start rapid reconnection attempts (every 3 seconds)
    _startRapidReconnection();

    notifyListeners();
  }

  void _exitSearchingMode() {
    if (!_isSearchingForNetwork) return;

    debugPrint('✅ EXITING SEARCHING MODE - Network recovered');
    _isSearchingForNetwork = false;
    _connectionStatusMessage = '';
    _searchingStartTime = null;
    _showUserChoice = false;

    // Cancel rapid reconnection
    _searchingTimer?.cancel();
    _searchingTimer = null;

    notifyListeners();
  }

  // User choice methods for long network outages
  void userChooseContinueSearching() {
    debugPrint('🔄 User chose to continue searching for network');
    _showUserChoice = false;
    _connectionStatusMessage = 'Continuing to search for network...';
    notifyListeners();
    // Keep searching timer running
  }

  void userChooseGoOffline() {
    debugPrint('🔌 User chose to go offline (Solo mode)');
    _showUserChoice = false;
    _searchingTimer?.cancel();
    _isSearchingForNetwork = false;

    // Enter offline mode WITHOUT starting reconnection attempts
    _enterOfflineModeByUserChoice();
  }

  // Enter offline mode when user explicitly chooses it (no reconnection attempts)
  void _enterOfflineModeByUserChoice() {
    if (_isOfflineMode) {
      debugPrint('🔌 Already in offline mode, ignoring duplicate call');
      return;
    }

    debugPrint(
        '🔌 Entering offline mode BY USER CHOICE - no reconnection attempts');
    _isOfflineMode = true;
    _isConnected = false;

    // Cancel any pending connections
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _subscription = null;

    // Cancel temp connections too
    _tempSubscription?.cancel();
    _tempChannel?.sink.close();
    _tempChannel = null;
    _tempSubscription = null;

    // Stop any timers
    _heartbeatTimer?.cancel();
    _buttonStateCleanupTimer?.cancel();
    _searchingTimer?.cancel(); // Make sure searching timer is stopped
    _reconnectionTimer?.cancel(); // Don't start reconnection attempts

    // Ensure we have participant info for offline mode
    _participantId ??= _settingsService?.deviceUuid ?? const Uuid().v4();
    if (_participantName == null || _participantName!.isEmpty) {
      _participantName = _settingsService?.userName ?? 'User';
    }

    // Clear participants for single-person offline mode
    _participants.clear();
    _activeSpeakerId = null;
    _activeSpeakerName = null;

    debugPrint(
        '🏠 Solo offline mode: Current user is $_participantName (${_participantId?.substring(0, 8)}...)');
    debugPrint(
        '🚫 NO reconnection attempts will be made - user chose Solo mode');

    notifyListeners();
  }

  void _startRapidReconnection() {
    _searchingTimer?.cancel();

    _searchingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_isSearchingForNetwork) return;

      // Check if we've been searching for more than 2 minutes - offer user choice
      if (_searchingStartTime != null &&
          DateTime.now().difference(_searchingStartTime!).inMinutes >= 2) {
        debugPrint('⏰ Searching for 2+ minutes - offering user choice');
        _connectionStatusMessage =
            'Still searching... Would you like to continue or go offline?';
        _showUserChoice = true;
        notifyListeners();
        return; // Don't auto-switch to offline mode
      } else if (_searchingStartTime != null &&
          DateTime.now().difference(_searchingStartTime!).inMinutes >= 1) {
        // Update message after 1 minute but keep trying
        _connectionStatusMessage =
            'Still searching for network... (${DateTime.now().difference(_searchingStartTime!).inMinutes}+ min)';
        notifyListeners();
      }

      debugPrint('🔄 Rapid reconnection attempt...');
      try {
        await _quickReconnect();
        // Success handled by heartbeat reception in _handleHeartbeat
      } catch (e) {
        debugPrint('❌ Still no network: $e');
        // Keep trying...
      }
    });
  }

  Future<void> _quickReconnect() async {
    if (_roomCode == null || _participantName == null) return;

    // Quick reconnect without changing app state
    final wsUrl = _buildWebSocketUrl(_roomCode!, _settingsService?.accessKey);

    // Close old connection if exists
    _subscription?.cancel();
    _channel?.sink.close();

    // Create new connection
    _channel = WebSocketChannel.connect(wsUrl);
    _subscription = _channel!.stream.listen(
      _handleMessage,
      onError: _handleError,
      onDone: _handleDone,
    );

    // Send rejoin message
    await Future.delayed(const Duration(milliseconds: 100));
    _sendMessage({
      'type': 'join',
      'deviceUuid': _participantId,
      'displayName': _participantName,
      'participantId': _participantId,
      'name': _participantName,
    });

    _isConnected = true;
  }

  // Collapse participant's text box and acknowledge current content
  void collapseParticipantTextBox(String participantId) {
    final currentContent = _participantTextContent[participantId] ?? '';

    if (currentContent.isNotEmpty) {
      final participantName = _participants
          .firstWhere((p) => p.id == participantId,
              orElse: () => RoomParticipant(id: participantId, name: 'Unknown'))
          .name;

      debugPrint(
          '📉 Collapsing text box for $participantName (content acknowledged)');

      // Store the acknowledged content and mark as collapsed
      _acknowledgedParticipantContent[participantId] = currentContent;
      _collapsedParticipants.add(participantId);

      // Keep the content visible but mark as acknowledged
      // Don't remove from _participantTextContent - let layout handle sizing

      notifyListeners();
    }
  }

  // Legacy method name for backward compatibility
  void clearParticipantTextContent(String participantId) {
    collapseParticipantTextBox(participantId);
  }

  // Getter for participant button states (for robust speaking detection)
  Map<String, bool> get participantButtonStates =>
      Map.unmodifiable(_participantButtonStates);
}
