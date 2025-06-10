import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:closed_caption_companion/services/room_service.dart';
import 'package:closed_caption_companion/services/settings_service.dart';
import 'package:closed_caption_companion/models/room_message.dart';
import 'package:closed_caption_companion/models/room_participant.dart';
import 'package:closed_caption_companion/utils/theme_config.dart';

class RoomCaptionDisplay extends StatefulWidget {
  const RoomCaptionDisplay({
    super.key,
    this.onMicPress,
    this.onMicRelease,
    this.onSendMessage,
    this.isAudioInitialized = false,
    this.isSTTReady = false,
  });
  final VoidCallback? onMicPress;
  final VoidCallback? onMicRelease;
  final Function(String)? onSendMessage;
  final bool isAudioInitialized;
  final bool isSTTReady;

  @override
  State<RoomCaptionDisplay> createState() => _RoomCaptionDisplayState();
}

// Color generator for consistent speaker colors
class _SpeakerColors {
  static const List<Color> _colors = [
    Color(0xFF2196F3), // Blue
    Color(0xFF4CAF50), // Green
    Color(0xFFFF9800), // Orange
    Color(0xFF9C27B0), // Purple
    Color(0xFFF44336), // Red
    Color(0xFF00BCD4), // Cyan
    Color(0xFF795548), // Brown
    Color(0xFF607D8B), // Blue Grey
    Color(0xFFE91E63), // Pink
    Color(0xFF8BC34A), // Light Green
    Color(0xFFFF5722), // Deep Orange
    Color(0xFF673AB7), // Deep Purple
  ];

  // Track assigned colors per room to ensure uniqueness
  static final Map<String, Map<String, int>> _roomColorAssignments = {};

  static Color getColorForSpeaker(String speakerId,
      {List<String>? allParticipantIds, String? roomId}) {
    // If we have room context, assign unique colors within the room
    if (roomId != null && allParticipantIds != null) {
      return _getUniqueColorInRoom(speakerId, allParticipantIds, roomId);
    }

    // Fallback to hash-based assignment
    final hash = speakerId.hashCode;
    return _colors[hash.abs() % _colors.length];
  }

  static Color _getUniqueColorInRoom(
      String speakerId, List<String> allParticipantIds, String roomId) {
    // Initialize room assignments if not exists
    if (!_roomColorAssignments.containsKey(roomId)) {
      _roomColorAssignments[roomId] = {};
    }

    final roomAssignments = _roomColorAssignments[roomId]!;

    // If participant already has a color assigned, use it
    if (roomAssignments.containsKey(speakerId)) {
      return _colors[roomAssignments[speakerId]!];
    }

    // Find the next available color index that's not used by current participants
    final usedIndices = allParticipantIds
        .where((id) => roomAssignments.containsKey(id))
        .map((id) => roomAssignments[id]!)
        .toSet();

    // Find first available color index
    int colorIndex = 0;
    for (int i = 0; i < _colors.length; i++) {
      if (!usedIndices.contains(i)) {
        colorIndex = i;
        break;
      }
    }

    // If all colors are used, fall back to hash-based assignment
    if (usedIndices.length >= _colors.length) {
      final hash = speakerId.hashCode;
      colorIndex = hash.abs() % _colors.length;
    }

    // Assign color to participant
    roomAssignments[speakerId] = colorIndex;
    return _colors[colorIndex];
  }

  // Helper method to get a darker shade of a color for labels
  static Color getDarkerShade(Color color, {double factor = 0.7}) {
    return Color.fromRGBO(
      (color.red * factor).round().clamp(0, 255),
      (color.green * factor).round().clamp(0, 255),
      (color.blue * factor).round().clamp(0, 255),
      color.opacity,
    );
  }

  // Clean up room assignments when rooms are left
  static void clearRoomAssignments(String roomId) {
    _roomColorAssignments.remove(roomId);
  }
}

// Activity tracking for dynamic sizing
class _ParticipantActivity {
  _ParticipantActivity({
    required this.participantId,
    DateTime? lastActivity,
  }) : lastActivity = lastActivity ?? DateTime.now();
  final String participantId;
  double activityScore = 1.0;
  DateTime lastActivity;
}

class _RoomCaptionDisplayState extends State<RoomCaptionDisplay>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final Map<String, ScrollController> _participantScrollControllers = {};
  final Map<String, _ParticipantActivity> _participantActivities = {};

  // Track previous text content for auto-scroll detection
  final Map<String, String> _lastParticipantTextContent = {};

  RoomService? _lastRoomService;
  int _lastMessageCount = 0;
  String? _lastActiveSpeakerId;

  late AnimationController _layoutAnimationController;

  // Activity decay parameters
  static const double _activityDecayRate = 0.95; // Decay per second
  static const double _newMessageBoost = 100.0;
  static const double _speakingBoost = 200.0;
  static const double _minActivityScore = 1.0;
  static const double _maxActivityScore = 500.0;

  @override
  void initState() {
    super.initState();
    _layoutAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Start activity decay timer
    _startActivityDecayTimer();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _layoutAnimationController.dispose();
    for (final controller in _participantScrollControllers.values) {
      controller.dispose();
    }
    // Clear tracked text content
    _lastParticipantTextContent.clear();
    super.dispose();
  }

  void _startActivityDecayTimer() {
    // Update activity scores every 100ms for smooth decay
    Stream.periodic(const Duration(milliseconds: 100)).listen((_) {
      if (mounted) {
        setState(() {
          _updateActivityScores();
        });
      }
    });
  }

  void _updateActivityScores() {
    final now = DateTime.now();
    const decayFactor = _activityDecayRate;

    for (final activity in _participantActivities.values) {
      final timeDelta =
          now.difference(activity.lastActivity).inMilliseconds / 1000.0;
      activity.activityScore = (activity.activityScore * decayFactor)
          .clamp(_minActivityScore, _maxActivityScore);
    }
  }

  void _boostParticipantActivity(String participantId, double boost) {
    _participantActivities.putIfAbsent(
      participantId,
      () => _ParticipantActivity(participantId: participantId),
    );

    final activity = _participantActivities[participantId]!;
    activity.activityScore = (activity.activityScore + boost)
        .clamp(_minActivityScore, _maxActivityScore);
    activity.lastActivity = DateTime.now();
  }

  ScrollController _getScrollController(String participantId) {
    return _participantScrollControllers.putIfAbsent(
      participantId,
      () => ScrollController(),
    );
  }

  void _scrollToBottom(String participantId) {
    final controller = _getScrollController(participantId);
    if (controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.animateTo(
          controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  // Helper method to trigger auto-scroll for live text content updates
  void _scrollToBottomForTextUpdate(String participantId) {
    final controller = _getScrollController(participantId);
    if (controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.animateTo(
          controller.position.maxScrollExtent,
          duration:
              const Duration(milliseconds: 100), // Faster for live updates
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RoomService>(
      builder: (context, roomService, _) {
        // Handle haptic feedback for participant joining (three buzzes)
        if (roomService.shouldTriggerParticipantJoinedHaptic) {
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 150), () {
            HapticFeedback.heavyImpact();
          });
          Future.delayed(const Duration(milliseconds: 300), () {
            HapticFeedback.heavyImpact();
          });
        }

        // Handle haptic feedback for active speaker changes
        if (_lastActiveSpeakerId != roomService.activeSpeaker?.id) {
          if (roomService.activeSpeaker != null && !roomService.isSpeaking) {
            // Someone else started speaking
            HapticFeedback.mediumImpact();
            _boostParticipantActivity(
                roomService.activeSpeaker!.id, _speakingBoost);
          } else if (_lastActiveSpeakerId != null &&
              roomService.activeSpeaker == null) {
            // Someone stopped speaking - double buzz
            HapticFeedback.lightImpact();
            Future.delayed(const Duration(milliseconds: 50), () {
              HapticFeedback.lightImpact();
            });
          }
          _lastActiveSpeakerId = roomService.activeSpeaker?.id;
          _layoutAnimationController.forward(from: 0);
        }

        // Handle ongoing speech haptic
        if (roomService.shouldTriggerHaptic &&
            roomService.activeSpeaker != null &&
            !roomService.isSpeaking) {
          HapticFeedback.lightImpact();
        }

        // Handle new messages - boost activity and scroll
        if (roomService.messages.length > _lastMessageCount) {
          final newMessages =
              roomService.messages.skip(_lastMessageCount).toList();
          for (final message in newMessages) {
            if (!message.dismissed) {
              _boostParticipantActivity(message.speakerId, _newMessageBoost);
              _scrollToBottom(message.speakerId);
            }
          }
        }
        _lastMessageCount = roomService.messages.length;

        // Handle live text content updates - trigger auto-scroll for text changes
        // This ensures the text view auto-scrolls as participants type long messages
        for (final participant in roomService.allParticipants) {
          final participantId = participant.id;
          final currentText = roomService.getTextForParticipant(participantId);
          final previousText = _lastParticipantTextContent[participantId] ?? '';

          // Only auto-scroll when text actually changes and it's not the current user
          if (currentText != previousText &&
              currentText.isNotEmpty &&
              participantId != roomService.currentUserId) {
            _scrollToBottomForTextUpdate(participantId);
          }

          // Update tracked text content
          _lastParticipantTextContent[participantId] = currentText;
        }

        _lastRoomService = roomService;

        // Get all participants (including pending) and their messages
        final participants = roomService.allParticipants;
        final messages =
            roomService.messages.where((m) => !m.dismissed).toList();

        if (participants.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mic_outlined,
                  size: 64,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                SelectionContainer.disabled(
                  child: Text(
                    'Waiting for participants to join...',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        // Debug only when actual new messages come in
        if (roomService.messages.length > _lastMessageCount) {
          debugPrint('🎯 RoomCaptionDisplay setup:');
          debugPrint('  participants.length: ${participants.length}');
          debugPrint('  messages.length: ${messages.length}');
          debugPrint('  currentUserId: ${roomService.currentUserId}');
          debugPrint('  isOfflineMode: ${roomService.isOfflineMode}');
          for (int i = 0; i < participants.length; i++) {
            final p = participants[i];
            debugPrint('  Participant $i: ${p.name} (${p.id})');
          }
        }

        return Padding(
          padding: const EdgeInsets.all(8),
          child: _DynamicCaptionLayout(
            participants: participants,
            messages: messages,
            currentUserId: roomService.currentUserId,
            activeSpeakerId: roomService.activeSpeakerId,
            pendingParticipantId: roomService.pendingJoinRequestId,
            participantActivities: _participantActivities,
            participantScrollControllers: _participantScrollControllers,
            onDismissMessage: roomService.dismissMessage,
            onApproveJoin: roomService.approveJoinRequest,
            onDeclineJoin: roomService.blockJoinRequest,
            onMicPress: widget.onMicPress,
            onMicRelease: widget.onMicRelease,
            onSendMessage: widget.onSendMessage,
            isAudioInitialized: widget.isAudioInitialized,
            isSTTReady: widget.isSTTReady,
            getScrollController: _getScrollController,
          ),
        );
      },
    );
  }
}

// Dynamic layout that implements activity-based sizing and current speaker at bottom
class _DynamicCaptionLayout extends StatelessWidget {
  const _DynamicCaptionLayout({
    required this.participants,
    required this.messages,
    required this.currentUserId,
    required this.activeSpeakerId,
    required this.pendingParticipantId,
    required this.participantActivities,
    required this.participantScrollControllers,
    required this.onDismissMessage,
    required this.onApproveJoin,
    required this.onDeclineJoin,
    this.onMicPress,
    this.onMicRelease,
    this.onSendMessage,
    required this.isAudioInitialized,
    required this.isSTTReady,
    required this.getScrollController,
  });
  final List<RoomParticipant> participants;
  final List<RoomMessage> messages;
  final String? currentUserId;
  final String? activeSpeakerId;
  final String? pendingParticipantId;

  final Map<String, _ParticipantActivity> participantActivities;
  final Map<String, ScrollController> participantScrollControllers;
  final Function(String) onDismissMessage;
  final Function(String) onApproveJoin;
  final Function(String) onDeclineJoin;
  final VoidCallback? onMicPress;
  final VoidCallback? onMicRelease;
  final Function(String)? onSendMessage;
  final bool isAudioInitialized;
  final bool isSTTReady;
  final ScrollController Function(String) getScrollController;

  @override
  Widget build(BuildContext context) {
    return Consumer<RoomService>(
      builder: (context, roomService, _) {
        // Calculate sizing with content awareness
        final screenHeight = MediaQuery.of(context).size.height;
        final baseFontSize =
            Provider.of<SettingsService>(context, listen: false).fontSize;
        final orderedParticipants =
            _calculateAdaptiveLayout(roomService, screenHeight, baseFontSize);

        return Column(
          children: orderedParticipants.map((layoutInfo) {
            final participant = layoutInfo.participant;
            final heightFraction = layoutInfo.heightFraction;

            return Expanded(
              flex: (heightFraction * 1000)
                  .round()
                  .clamp(1, 10000), // Convert to integer flex with bounds
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                child: _DynamicCaptionBox(
                  participant: participant,
                  messages: _getParticipantMessages(participant.id),
                  isCurrentUser: participant.id == currentUserId,
                  isActiveSpeaker: roomService.isConcurrentMode
                      ? roomService.isParticipantSpeaking(participant.id)
                      : participant.id == activeSpeakerId,
                  isPending: participant.id == pendingParticipantId,
                  activityScore:
                      participantActivities[participant.id]?.activityScore ??
                          1.0,
                  scrollController: getScrollController(participant.id),
                  onDismissMessage: onDismissMessage,
                  onApproveJoin: onApproveJoin,
                  onDeclineJoin: onDeclineJoin,
                  onMicPress: onMicPress,
                  onMicRelease: onMicRelease,
                  onSendMessage: onSendMessage,
                  isAudioInitialized: isAudioInitialized,
                  isSTTReady: isSTTReady,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  List<_ParticipantLayoutInfo> _calculateAdaptiveLayout(
      RoomService roomService, double screenHeight, double baseFontSize) {
    // Create layout info for each participant
    final List<_ParticipantLayoutInfo> layoutInfos =
        participants.map((participant) {
      return _ParticipantLayoutInfo(
        participant: participant,
        activityScore: 1.0, // Not used anymore, but keep for compatibility
      );
    }).toList();

    // Separate current user from others
    _ParticipantLayoutInfo? currentUserInfo;
    final List<_ParticipantLayoutInfo> otherParticipants = [];

    for (final info in layoutInfos) {
      if (info.participant.id == currentUserId) {
        currentUserInfo = info;
      } else {
        otherParticipants.add(info);
      }
    }

    // Build final layout: others first, current user at bottom for easy access
    final finalLayout = <_ParticipantLayoutInfo>[];
    finalLayout.addAll(otherParticipants);
    if (currentUserInfo != null) {
      finalLayout.add(currentUserInfo);
    }

    if (finalLayout.isEmpty) {
      return finalLayout;
    }

    // Check which participants have content to determine sizing
    final participantsWithContent = <_ParticipantLayoutInfo>[];
    final participantsWithoutContent = <_ParticipantLayoutInfo>[];

    for (final info in finalLayout) {
      final participantId = info.participant.id;
      final hasMessages = _getParticipantMessages(participantId).isNotEmpty;
      final hasLiveText =
          roomService.getTextForParticipant(participantId).isNotEmpty;
      final isCurrentUser = participantId == currentUserId;
      final isCollapsed = roomService.isParticipantCollapsed(participantId);
      final isPendingParticipant = participantId == pendingParticipantId;

      // Current user always gets full content space (for input)
      // Pending participants are always collapsed (seeking admission)
      // Others get collapsed if:
      //   1. No content at all, OR
      //   2. User has acknowledged/collapsed their content
      if (isPendingParticipant) {
        participantsWithoutContent.add(info);
      } else if (isCurrentUser ||
          (hasMessages || hasLiveText) && !isCollapsed) {
        participantsWithContent.add(info);
      } else {
        participantsWithoutContent.add(info);
      }
    }

    // Calculate fractions: collapsed participants get minimal space (1 line height)
    // When multiple participants exist, minimize current user's space to give others more room
    const collapsedFraction = 0.08; // ~1 line height relative to screen
    const pendingFraction =
        0.15; // Pending participants need more space for buttons

    // Calculate total space used by collapsed/pending participants
    double totalCollapsedSpace = 0.0;
    for (final info in participantsWithoutContent) {
      final isPendingParticipant = info.participant.id == pendingParticipantId;
      totalCollapsedSpace +=
          isPendingParticipant ? pendingFraction : collapsedFraction;
    }

    final remainingSpace = 1.0 - totalCollapsedSpace;

    // NEW LOGIC: When multiple participants, minimize current user's bubble
    if (participantsWithContent.isNotEmpty) {
      // Find current user in content participants
      _ParticipantLayoutInfo? currentUserContentInfo;
      final otherContentParticipants = <_ParticipantLayoutInfo>[];

      for (final info in participantsWithContent) {
        if (info.participant.id == currentUserId) {
          currentUserContentInfo = info;
        } else {
          otherContentParticipants.add(info);
        }
      }

      if (currentUserContentInfo != null &&
          otherContentParticipants.isNotEmpty) {
        // Check if current user is actively editing - if so, give them ample space
        final isCurrentUserEditing =
            roomService.participantTextingStates[currentUserId] == true;

        if (isCurrentUserEditing) {
          // When editing: give current user greedy space for comfortable typing
          const editingUserFraction =
              0.7; // 70% for editing user - much more generous
          final otherParticipantsSpace = remainingSpace - editingUserFraction;
          final otherParticipantFraction = otherContentParticipants.isNotEmpty
              ? otherParticipantsSpace / otherContentParticipants.length
              : 0.0;

          currentUserContentInfo.heightFraction = editingUserFraction;
          for (final info in otherContentParticipants) {
            info.heightFraction = otherParticipantFraction;
          }
        } else {
          // Multiple participants: minimize current user, but ensure at least one text row
          // Calculate minimum space needed for current user based on font size

          // Estimate minimum height: font size + padding + header + input decorations
          // This ensures at least one row of text is visible
          final minUserHeight =
              (baseFontSize * 2.5 + 80); // Font size * line height + UI chrome
          final minUserFraction =
              (minUserHeight / screenHeight).clamp(0.15, 0.4); // 15-40% max

          // Use the larger of our preferred minimum (20%) or font-based minimum
          final currentUserFraction = math.max(0.2, minUserFraction);

          // Ensure we don't exceed available space
          final actualUserFraction = math.min(currentUserFraction,
              remainingSpace * 0.6); // Max 60% of remaining

          final otherParticipantsSpace = remainingSpace - actualUserFraction;
          final otherParticipantFraction = otherContentParticipants.isNotEmpty
              ? otherParticipantsSpace / otherContentParticipants.length
              : 0.0;

          // Assign calculated space to current user
          currentUserContentInfo.heightFraction = actualUserFraction;

          // Assign remaining space to other participants
          for (final info in otherContentParticipants) {
            info.heightFraction = otherParticipantFraction;
          }
        }
      } else {
        // Single participant or only current user: use equal distribution
        final contentFraction = remainingSpace / participantsWithContent.length;
        for (final info in participantsWithContent) {
          info.heightFraction = contentFraction;
        }
      }
    }

    // Assign fractions for collapsed participants
    for (final info in participantsWithoutContent) {
      final isPendingParticipant = info.participant.id == pendingParticipantId;
      info.heightFraction =
          isPendingParticipant ? pendingFraction : collapsedFraction;
    }

    return finalLayout;
  }

  // Track previous state to reduce debug spam
  static int _lastTotalMessages = 0;
  static int _lastFilteredMessages = 0;

  List<RoomMessage> _getParticipantMessages(String participantId) {
    final filtered = messages
        .where((m) => m.speakerId == participantId && !m.dismissed)
        .toList();

    // Debug only for current user when counts actually change
    if (participantId == currentUserId) {
      final currentTotal = messages.length;
      final currentFiltered = filtered.length;

      if (currentTotal != _lastTotalMessages ||
          currentFiltered != _lastFilteredMessages) {
        debugPrint(
            '🎯 _getParticipantMessages for current user ($participantId):');
        debugPrint('  Total messages: $currentTotal');
        debugPrint('  Filtered messages for current user: $currentFiltered');
        if (messages.isNotEmpty) {
          final msg = messages.last;
          debugPrint(
              '  Latest message: speakerId=${msg.speakerId}, text="${msg.text.length > 50 ? "${msg.text.substring(0, 50)}..." : msg.text}"');
          debugPrint(
              '  Does speakerId match? ${msg.speakerId == participantId}');
        }

        _lastTotalMessages = currentTotal;
        _lastFilteredMessages = currentFiltered;
      }
    }

    return filtered;
  }
}

// Layout info for dynamic sizing calculations
class _ParticipantLayoutInfo {
  _ParticipantLayoutInfo({
    required this.participant,
    required this.activityScore,
  });
  final RoomParticipant participant;
  final double activityScore;
  double heightFraction = 0.0;
}

// Individual caption box with dynamic sizing and visual cues
class _DynamicCaptionBox extends StatelessWidget {
  const _DynamicCaptionBox({
    required this.participant,
    required this.messages,
    required this.isCurrentUser,
    required this.isActiveSpeaker,
    this.isPending = false,
    required this.activityScore,
    required this.scrollController,
    required this.onDismissMessage,
    required this.onApproveJoin,
    required this.onDeclineJoin,
    this.onMicPress,
    this.onMicRelease,
    this.onSendMessage,
    required this.isAudioInitialized,
    required this.isSTTReady,
  });
  final RoomParticipant participant;
  final List<RoomMessage> messages;
  final bool isCurrentUser;
  final bool isActiveSpeaker;
  final bool isPending;
  final double activityScore;
  final ScrollController scrollController;
  final Function(String) onDismissMessage;
  final Function(String) onApproveJoin;
  final Function(String) onDeclineJoin;
  final VoidCallback? onMicPress;
  final VoidCallback? onMicRelease;
  final Function(String)? onSendMessage;
  final bool isAudioInitialized;
  final bool isSTTReady;

  @override
  Widget build(BuildContext context) {
    return Consumer<RoomService>(
      builder: (context, roomService, _) {
        // Get all participant IDs for unique color assignment
        final allParticipantIds =
            roomService.allParticipants.map((p) => p.id).toList();
        final roomId = roomService.roomCode ?? 'offline';

        final speakerColor = _SpeakerColors.getColorForSpeaker(
          participant.id,
          allParticipantIds: allParticipantIds,
          roomId: roomId,
        );

        return Consumer<SettingsService>(
          builder: (context, settings, _) {
            final baseFontSize = settings.fontSize;
            final nameSize = baseFontSize * 0.8;
            final captionStyle = ThemeConfig.getCaptionTextStyle(
              baseFontSize,
              Theme.of(context).colorScheme.onSurface,
            );

            // Visual intensity based on activity score
            final activityIntensity = (activityScore / 100.0).clamp(0.0, 1.0);
            final borderWidth =
                isActiveSpeaker ? 4.0 : 1.5 + (activityIntensity * 1.5);

            // Calculate opacity based on heartbeat (only for other participants)
            // Pending participants always get full opacity for maximum visibility
            final heartbeatOpacity = isCurrentUser || isPending
                ? 1.0 // Always full opacity for current user and pending participants
                : _calculateHeartbeatOpacity(context, participant.id);

            return Opacity(
              opacity: heartbeatOpacity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: isCurrentUser
                      ? speakerColor
                          .withOpacity(0.08 + (activityIntensity * 0.12))
                      : Theme.of(context).brightness == Brightness.dark
                          ? Colors.black
                              .withOpacity(0.6 + (activityIntensity * 0.2))
                          : Colors.white
                              .withOpacity(0.6 + (activityIntensity * 0.2)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActiveSpeaker
                        ? speakerColor
                        : speakerColor
                            .withOpacity(0.3 + (activityIntensity * 0.4)),
                    width: borderWidth,
                  ),
                  boxShadow: [
                    if (isActiveSpeaker || activityIntensity > 0.5)
                      BoxShadow(
                        color: speakerColor.withOpacity(0.3),
                        blurRadius: 8 + (activityIntensity * 8),
                        spreadRadius: 1 + (activityIntensity * 2),
                      ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header with participant name and activity indicator
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: speakerColor
                            .withOpacity(0.1 + (activityIntensity * 0.1)),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(11),
                          topRight: Radius.circular(11),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Username aligned to the left
                          Expanded(
                            child: Text(
                              participant.name,
                              style: TextStyle(
                                fontSize: nameSize,
                                fontWeight: FontWeight.bold,
                                color: speakerColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
                            ),
                          ),
                          // For pending participants, show seeking admission and buttons
                          if (isPending) ...[
                            Text(
                              '• Seeking Admission',
                              style: TextStyle(
                                fontSize: nameSize * 0.8,
                                color: speakerColor.withOpacity(0.8),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Compact approve button
                            GestureDetector(
                              onTap: () => onApproveJoin(participant.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Admit',
                                  style: TextStyle(
                                    fontSize: nameSize * 0.7,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Compact decline button
                            GestureDetector(
                              onTap: () => onDeclineJoin(participant.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Decline',
                                  style: TextStyle(
                                    fontSize: nameSize * 0.7,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          // Timestamp and status indicators (only for non-pending, non-current users)
                          if (!isPending && !isCurrentUser)
                            Consumer<RoomService>(
                              builder: (context, roomService, child) {
                                // IMPORTANT: Current user has interactive interface, don't show activity indicators
                                if (isCurrentUser) {
                                  return const SizedBox
                                      .shrink(); // No header indicators for current user
                                }

                                final isTyping =
                                    roomService.participantTextingStates[
                                            participant.id] ??
                                        false;
                                final hasMessages = messages.isNotEmpty;
                                final hasLiveText = roomService
                                    .getTextForParticipant(participant.id)
                                    .isNotEmpty;
                                final isConcurrent = roomService
                                    .isParticipantSpeaking(participant.id);
                                final isSingle = participant.id ==
                                    roomService.activeSpeakerId;
                                final isButtonPressed =
                                    roomService.participantButtonStates[
                                            participant.id] ??
                                        false;
                                final isSpeakingRobustly =
                                    isConcurrent || isSingle || isButtonPressed;

                                // Show activity indicator when actively speaking or typing
                                // When NOT active → show timestamp + dismissible tick
                                final showActivityIndicator =
                                    isSpeakingRobustly || isTyping;

                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (showActivityIndicator) ...[
                                      // Speaking/typing indicator
                                      if (isSpeakingRobustly) ...[
                                        Icon(
                                          Icons.mic,
                                          size: 14,
                                          color: speakerColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'speaking...',
                                          style: TextStyle(
                                            fontSize: nameSize * 0.6,
                                            color: speakerColor,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ] else if (isTyping) ...[
                                        SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: speakerColor,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'typing...',
                                          style: TextStyle(
                                            fontSize: nameSize * 0.6,
                                            color: speakerColor,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ] else ...[
                                      // Show timestamp and dismiss button when not actively speaking/typing
                                      if (hasMessages || hasLiveText) ...[
                                        // Timestamp for latest message
                                        if (hasMessages) ...[
                                          Text(
                                            DateFormat.jm().format(
                                                messages.last.timestamp),
                                            style: TextStyle(
                                              fontSize: nameSize * 0.6,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.5),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        // Dismiss/clear button
                                        if (!isCurrentUser)
                                          GestureDetector(
                                            onTap: () {
                                              // Clear both live text content and latest message
                                              if (hasLiveText) {
                                                roomService
                                                    .clearParticipantTextContent(
                                                        participant.id);
                                              }
                                              if (hasMessages) {
                                                onDismissMessage(
                                                    messages.last.id);
                                              }
                                            },
                                            child: Container(
                                              width: 18,
                                              height: 18,
                                              decoration: BoxDecoration(
                                                color: Colors.green
                                                    .withOpacity(0.8),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.check,
                                                size: 12,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ],
                                    // Remove button (X) when participant is inactive (always at the end)
                                    if (!isCurrentUser &&
                                        _shouldShowRemoveButton(
                                            context, participant.id)) ...[
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () => roomService
                                            .removeParticipant(participant.id),
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),

                    // Content area - scrollable messages or interaction area
                    Expanded(
                      child: _buildContentArea(context, speakerColor, nameSize,
                          captionStyle, activityIntensity),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Calculate opacity based on heartbeat timing
  double _calculateHeartbeatOpacity(
      BuildContext context, String participantId) {
    final roomService = Provider.of<RoomService>(context, listen: false);
    final secondsSinceHeartbeat =
        roomService.getSecondsSinceLastHeartbeat(participantId);

    if (secondsSinceHeartbeat <= 2) {
      return 1.0; // Full opacity for recent heartbeat
    } else if (secondsSinceHeartbeat <= 10) {
      // Fade from 1.0 to 0.3 over 8 seconds (2s to 10s)
      final fadeProgress = (secondsSinceHeartbeat - 2) / 8.0;
      return 1.0 - (fadeProgress * 0.7); // Goes from 1.0 to 0.3
    } else {
      return 0.3; // Minimum opacity when very stale
    }
  }

  // Check if X button should be shown (after 10 seconds)
  bool _shouldShowRemoveButton(BuildContext context, String participantId) {
    final roomService = Provider.of<RoomService>(context, listen: false);
    final secondsSinceHeartbeat =
        roomService.getSecondsSinceLastHeartbeat(participantId);
    return secondsSinceHeartbeat > 10;
  }

  Widget _buildContentArea(BuildContext context, Color speakerColor,
      double nameSize, TextStyle captionStyle, double activityIntensity) {
    // For pending participants, show minimal empty content since approval interface is in header
    if (isPending) {
      return const SizedBox.shrink(); // Completely minimal - just header
    } else {
      // Always use the interactive single-bubble approach for current user
      // or show latest message for others
      return _buildSingleBubbleArea(
          context, speakerColor, nameSize, captionStyle, activityIntensity);
    }
  }

  Widget _buildSingleBubbleArea(BuildContext context, Color speakerColor,
      double nameSize, TextStyle captionStyle, double activityIntensity) {
    // For current user: always show interactive bubble
    if (isCurrentUser && isAudioInitialized) {
      final currentMessage = messages.isNotEmpty ? messages.last : null;

      return Consumer<RoomService>(
        builder: (context, roomService, child) {
          return _SimpleUserTextBox(
            speakerColor: speakerColor,
            nameSize: nameSize,
            isActiveSpeaker: isActiveSpeaker,
            isSTTReady: isSTTReady,
            onMicPress: onMicPress,
            onMicRelease: onMicRelease,
            onSendMessage: onSendMessage,
            currentMessage: currentMessage,
            currentSTTText: roomService.currentSTTText,
            isReceivingSTT: roomService.isCurrentlyReceivingSTT,
            isMicrophoneAvailable:
                isSTTReady, // Use isSTTReady as microphone availability indicator
          );
        },
      );
    }

    // For other users: unified display of all content (STT, text, messages)
    return Consumer<RoomService>(
      builder: (context, roomService, child) {
        final liveText = roomService.getTextForParticipant(participant.id);

        // Unified content: prioritize live text, then latest message
        // Note: STT content for other participants would also come through liveText
        // since both text and STT updates are synced via the same mechanism
        String displayText = '';
        if (liveText.isNotEmpty) {
          displayText = liveText;
        } else if (messages.isNotEmpty) {
          displayText = messages.last.text;
        }

        if (displayText.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    physics:
                        const AlwaysScrollableScrollPhysics(), // Enable touch scrolling
                    child: SizedBox(
                      width: double.infinity,
                      child: SelectableText(
                        displayText,
                        style: captionStyle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Empty state - check if this participant should be collapsed
        // For collapsed participants, show minimal UI (just name is in header)
        return Container(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: SelectionContainer.disabled(
              child: Text(
                isCurrentUser
                    ? 'Speech recognition unavailable'
                    : 'Waiting for ${participant.name} to speak...',
                style: TextStyle(
                  fontSize: nameSize * 0.8, // Smaller text for collapsed state
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }
}

// Simple text box with separate mic button
class _SimpleUserTextBox extends StatefulWidget {
  const _SimpleUserTextBox({
    required this.speakerColor,
    required this.nameSize,
    required this.isActiveSpeaker,
    required this.isSTTReady,
    this.onMicPress,
    this.onMicRelease,
    this.onSendMessage,
    this.currentMessage,
    this.currentSTTText = '',
    this.isReceivingSTT = false,
    this.isMicrophoneAvailable = false,
  });
  final Color speakerColor;
  final double nameSize;
  final bool isActiveSpeaker;
  final bool isSTTReady;
  final VoidCallback? onMicPress;
  final VoidCallback? onMicRelease;
  final Function(String)? onSendMessage;
  final RoomMessage? currentMessage;
  final String currentSTTText;
  final bool isReceivingSTT;
  final bool isMicrophoneAvailable;

  @override
  State<_SimpleUserTextBox> createState() => _SimpleUserTextBoxState();
}

class _SimpleUserTextBoxState extends State<_SimpleUserTextBox> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isListening = false;
  bool _hasBeenCleared = false;
  bool _isEditing = false; // Start in view mode, require explicit edit button
  bool _isFlipped = false; // For upside-down text mode in single user scenarios

  @override
  void initState() {
    super.initState();
    // Initialize text field with current message if available
    if (widget.currentMessage != null) {
      _textController.text = widget.currentMessage!.text;
    }
  }

  @override
  void didUpdateWidget(_SimpleUserTextBox oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reset listening state if we're no longer the active speaker (e.g., due to timeout)
    if (_isListening && oldWidget.isActiveSpeaker && !widget.isActiveSpeaker) {
      setState(() {
        _isListening = false;
        _hasBeenCleared = false;
      });
    }

    // Reset flip state when no longer in single user mode
    final roomService = Provider.of<RoomService>(context, listen: false);
    final isSingleUser = roomService.allParticipants.length <= 1;
    if (_isFlipped && !isSingleUser) {
      setState(() {
        _isFlipped = false;
      });
    }

    // Update text field with real-time STT text when listening
    if (_isListening && widget.isReceivingSTT) {
      // Make text field read-only during STT and show live transcription
      final newText = widget.currentSTTText;
      if (newText != _textController.text) {
        _textController.text = newText;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
        _scrollToBottom();
      }
    }

    // When STT finishes, just stop listening (don't auto-enter edit mode)
    if (oldWidget.isReceivingSTT && !widget.isReceivingSTT && _isListening) {
      setState(() {
        _isListening = false;
        _hasBeenCleared = false;
        // Don't automatically enter edit mode - let user choose explicitly
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    // Scroll to bottom to follow new STT content
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _startListening() {
    setState(() {
      _isListening = true;
      _hasBeenCleared = true;
      _isEditing = false; // Disable editing during voice recording
    });
    // Clear text field and start STT
    _textController.clear();

    // Unfocus text field during voice recording
    _focusNode.unfocus();

    // Update room service with cleared text
    final roomService = Provider.of<RoomService>(context, listen: false);
    roomService.setCurrentTextContent('');

    widget.onMicPress?.call();
  }

  void _stopListening() {
    setState(() {
      _isListening = false;
      _hasBeenCleared = false; // Reset flag when stopping
      // Don't automatically enter edit mode - let user choose explicitly
    });
    widget.onMicRelease?.call();
  }

  void _onTextChanged(String text) {
    // Update the room service with current text content for heartbeat sync
    final roomService = Provider.of<RoomService>(context, listen: false);
    roomService.setCurrentTextContent(text);

    // Send message when user types (for live updates)
    if (text.trim().isNotEmpty && !_isListening) {
      widget.onSendMessage?.call(text.trim());
    }
  }

  void _toggleEditMode(bool editing) {
    // Update the room service with current texting state
    final roomService = Provider.of<RoomService>(context, listen: false);
    roomService.setCurrentlyTexting(editing);
  }

  String? _lastDebugState;

  @override
  Widget build(BuildContext context) {
    // Text is editable only when in edit mode and not listening
    final isReadOnly = !(_isEditing && !_isListening);

    // Only log when state changes
    final currentState =
        '_isEditing=$_isEditing, _isListening=$_isListening, isReceivingSTT=${widget.isReceivingSTT}, isReadOnly=$isReadOnly';
    if (_lastDebugState != currentState) {
      debugPrint('🏗️ Text field state: $currentState');
      _lastDebugState = currentState;
    }

    // Show minimal view when not editing, full view when editing
    if (!_isEditing && !_isListening) {
      return _buildMinimalView(context);
    }

    return Container(
      margin: const EdgeInsets.all(8),
      child: Stack(
        children: [
          // Text field - takes full available space with optional flip transform
          Transform.rotate(
            angle: _isFlipped ? 3.14159 : 0, // π radians = 180 degrees
            child: TextField(
              controller: _textController,
              scrollController: _scrollController,
              focusNode: _focusNode,
              onChanged: _onTextChanged,
              readOnly: isReadOnly,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: _isListening
                    ? (widget.isSTTReady
                        ? '🎤 Ready! Speak now...'
                        : '⏳ Starting speech recognition...')
                    : 'Type your message here...',
                hintStyle: TextStyle(
                  color: _isListening
                      ? widget.speakerColor
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                  fontStyle: FontStyle.italic,
                  fontSize: widget.nameSize * 0.9,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: widget.speakerColor,
                    width: 2,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: _isListening || widget.isActiveSpeaker
                        ? widget.speakerColor
                        : Theme.of(context).colorScheme.outline,
                    width: _isListening || widget.isActiveSpeaker ? 2 : 1,
                  ),
                ),
                filled: true,
                fillColor: _isListening || widget.isActiveSpeaker
                    ? widget.speakerColor.withOpacity(0.1)
                    : Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.fromLTRB(
                    16, 16, 80, 16), // Extra right padding for buttons
              ),
              style: TextStyle(
                fontSize: widget.nameSize,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),

          // Floating circular buttons overlay at top-right
          Positioned(
            top: 8,
            right: 8,
            child: Consumer<RoomService>(
              builder: (context, roomService, _) {
                final isSingleUser = roomService.allParticipants.length <= 1;

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flip button (only in single user mode)
                    if (isSingleUser) ...[
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isFlipped = !_isFlipped;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _isFlipped
                                ? Colors.purple
                                : Colors.grey.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.screen_rotation,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],

                    // Voice Button
                    GestureDetector(
                      onTap: _isListening
                          ? _stopListening
                          : (_isEditing
                              ? null // Inactive when in text edit mode
                              : (widget.isMicrophoneAvailable
                                  ? _startListening
                                  : null)),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _isListening
                              ? Colors.red
                              : (_isEditing
                                  ? Colors.grey.withOpacity(
                                      0.6) // Semi-transparent when disabled
                                  : (widget.isMicrophoneAvailable
                                      ? Colors.blue
                                      : Colors.grey)),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isListening
                              ? Icons.stop
                              : (widget.isMicrophoneAvailable
                                  ? Icons.mic
                                  : Icons.mic_off),
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Edit Text Button
                    GestureDetector(
                      onTap: _isListening
                          ? null // Inactive when voice is recording
                          : () {
                              final willBeEditing =
                                  !_isEditing; // Calculate new state first
                              debugPrint(
                                  '🔄 Edit button clicked: willBeEditing = $willBeEditing');

                              // If we're currently listening, stop it first
                              if (_isListening) {
                                _stopListening();
                              }

                              setState(() {
                                _isEditing = willBeEditing; // Toggle edit mode
                                _isListening = false; // Ensure listening is off
                              });

                              // Update room service with editing state
                              _toggleEditMode(willBeEditing);

                              if (willBeEditing) {
                                // Entering edit mode - request focus after widget rebuilds
                                debugPrint(
                                    '📝 Entering edit mode, requesting focus...');
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  debugPrint(
                                      '🎯 Requesting focus now - readOnly should be: ${!_isEditing}');
                                  _focusNode.requestFocus();
                                });
                              } else {
                                // Exiting edit mode - remove focus and hide keyboard
                                debugPrint(
                                    '❌ Exiting edit mode, unfocusing...');
                                _focusNode.unfocus();
                              }
                            },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _isListening
                              ? Colors.grey.withOpacity(
                                  0.6) // Semi-transparent when disabled
                              : (_isEditing ? Colors.orange : Colors.green),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isEditing ? Icons.edit_off : Icons.edit,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalView(BuildContext context) {
    final hasText = _textController.text.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: widget.speakerColor.withOpacity(0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        children: [
          Expanded(
            child: Transform.rotate(
              angle: _isFlipped ? 3.14159 : 0, // π radians = 180 degrees
              child: Text(
                hasText ? _textController.text : 'Your message here...',
                style: TextStyle(
                  fontSize: widget.nameSize * 0.9,
                  color: hasText
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                  fontStyle: hasText ? FontStyle.normal : FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Flip button (only in single user mode)
          Consumer<RoomService>(
            builder: (context, roomService, _) {
              final isSingleUser = roomService.allParticipants.length <= 1;

              if (!isSingleUser) return const SizedBox.shrink();

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isFlipped = !_isFlipped;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _isFlipped
                            ? Colors.purple
                            : Colors.grey.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.screen_rotation,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
          // Compact mic button
          GestureDetector(
            onTap: widget.isMicrophoneAvailable ? _startListening : null,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: widget.isMicrophoneAvailable ? Colors.blue : Colors.grey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                widget.isMicrophoneAvailable ? Icons.mic : Icons.mic_off,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Compact edit button
          GestureDetector(
            onTap: () {
              setState(() {
                _isEditing = true;
              });
              _toggleEditMode(true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _focusNode.requestFocus();
              });
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.edit,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Pulsing indicator for active speaker
class _PulsingSpeakerIndicator extends StatefulWidget {
  const _PulsingSpeakerIndicator({required this.color});
  final Color color;

  @override
  State<_PulsingSpeakerIndicator> createState() =>
      _PulsingSpeakerIndicatorState();
}

class _PulsingSpeakerIndicatorState extends State<_PulsingSpeakerIndicator>
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
    _animation = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(_animation.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(_animation.value * 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}
