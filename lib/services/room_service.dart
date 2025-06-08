import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/room_participant.dart';
import '../models/room_message.dart';
import '../utils/room_code_generator.dart';
import 'dart:async';

class RoomService extends ChangeNotifier {
  // Room state
  String? _roomCode;
  String? _encryptionKey;
  String? _currentUserId;
  String? _currentUserName;
  bool _isInRoom = false;
  bool _isSpeaking = false;

  // Participants
  final List<RoomParticipant> _participants = [];
  RoomParticipant? _activeSpeaker;

  // Messages
  final List<RoomMessage> _messages = [];

  // Haptic feedback timer
  Timer? _hapticTimer;
  Timer? _speakerTimeoutTimer;

  // Getters
  String? get roomCode => _roomCode;
  String? get encryptionKey => _encryptionKey;
  String? get currentUserId => _currentUserId;
  bool get isInRoom => _isInRoom;
  bool get isSpeaking => _isSpeaking;
  List<RoomParticipant> get participants => List.unmodifiable(_participants);
  RoomParticipant? get activeSpeaker => _activeSpeaker;
  List<RoomMessage> get messages => List.unmodifiable(_messages);
  String? get savedName => _currentUserName;

  String get shareUrl {
    if (_roomCode == null || _encryptionKey == null) return '';
    return 'https://nanatalka.app/join/$_roomCode#key=$_encryptionKey';
  }

  // Initialize from saved preferences
  RoomService() {
    _loadSavedName();
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserName = prefs.getString('room_user_name');
  }

  Future<void> _saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('room_user_name', name);
    _currentUserName = name;
  }

  // Create a new room
  Future<void> createRoom(String userName) async {
    await _saveName(userName);

    _roomCode = RoomCodeGenerator.generate();
    _encryptionKey =
        'mock-encryption-key'; // In real implementation, generate proper key
    _currentUserId = DateTime.now().millisecondsSinceEpoch.toString();
    _isInRoom = true;

    // Add self as participant
    final self = RoomParticipant(
      id: _currentUserId!,
      name: userName,
      joinedAt: DateTime.now(),
    );
    _participants.add(self);

    notifyListeners();
  }

  // Join an existing room
  Future<void> joinRoom(
      String roomCode, String encryptionKey, String userName) async {
    await _saveName(userName);

    _roomCode = roomCode;
    _encryptionKey = encryptionKey;
    _currentUserId = DateTime.now().millisecondsSinceEpoch.toString();
    _isInRoom = true;

    // Add self as participant
    final self = RoomParticipant(
      id: _currentUserId!,
      name: userName,
      joinedAt: DateTime.now(),
    );
    _participants.add(self);

    // Simulate other participants for testing
    if (roomCode == 'CAT123') {
      _participants.add(RoomParticipant(
        id: 'user1',
        name: 'Alice',
        joinedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ));
      _participants.add(RoomParticipant(
        id: 'user2',
        name: 'Bob',
        joinedAt: DateTime.now().subtract(const Duration(minutes: 3)),
      ));
    }

    notifyListeners();
  }

  // Leave room
  void leaveRoom() {
    _stopHapticFeedback();
    _speakerTimeoutTimer?.cancel();

    _roomCode = null;
    _encryptionKey = null;
    _currentUserId = null;
    _isInRoom = false;
    _isSpeaking = false;
    _participants.clear();
    _messages.clear();
    _activeSpeaker = null;

    notifyListeners();
  }

  // Start speaking
  void startSpeaking() {
    if (_activeSpeaker != null || !_isInRoom) return;

    final self = _participants.firstWhere((p) => p.id == _currentUserId);
    _activeSpeaker = self;
    _isSpeaking = true;

    // Notify others with haptic feedback
    _startHapticFeedback();

    notifyListeners();
  }

  // Stop speaking
  void stopSpeaking() {
    if (!_isSpeaking) return;

    _isSpeaking = false;
    _activeSpeaker = null;

    // Stop haptic feedback and trigger double buzz
    _stopHapticFeedback();
    _triggerStopSpeakingHaptic();

    // Add cooldown timer
    _speakerTimeoutTimer = Timer(const Duration(milliseconds: 1000), () {
      notifyListeners();
    });

    notifyListeners();
  }

  // Add caption text (from speech recognition)
  void addCaptionText(String text, {bool isFinal = false}) {
    if (!_isSpeaking || _currentUserId == null) return;

    // Find existing message or create new one
    final existingIndex = _messages.indexWhere(
      (m) => m.speakerId == _currentUserId && !m.isFinal,
    );

    if (existingIndex >= 0) {
      // Update existing message
      _messages[existingIndex] = _messages[existingIndex].copyWith(
        text: text,
        isFinal: isFinal,
      );
    } else {
      // Add new message
      final message = RoomMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        speakerId: _currentUserId!,
        speakerName: _currentUserName!,
        text: text,
        timestamp: DateTime.now(),
        isFinal: isFinal,
      );
      _messages.add(message);
    }

    notifyListeners();
  }

  // Dismiss a message
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

  // Edit a message
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

  // Haptic feedback management
  void _startHapticFeedback() {
    // Initial strong buzz is handled by the UI
    // Start repeating light buzz every second
    _hapticTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // This will be called by the UI to trigger haptic
      notifyListeners();
    });
  }

  void _stopHapticFeedback() {
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  void _triggerStopSpeakingHaptic() {
    // Double buzz pattern is handled by the UI
    notifyListeners();
  }

  // Check if haptic should fire
  bool get shouldTriggerHaptic {
    return _hapticTimer != null && _hapticTimer!.isActive;
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _speakerTimeoutTimer?.cancel();
    super.dispose();
  }
}
