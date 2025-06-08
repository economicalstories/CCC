import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/room_service.dart';
import '../models/room_message.dart';

class RoomCaptionDisplay extends StatefulWidget {
  const RoomCaptionDisplay({Key? key}) : super(key: key);

  @override
  State<RoomCaptionDisplay> createState() => _RoomCaptionDisplayState();
}

class _RoomCaptionDisplayState extends State<RoomCaptionDisplay> {
  final ScrollController _scrollController = ScrollController();
  RoomService? _lastRoomService;
  int _lastMessageCount = 0;
  String? _lastActiveSpeakerId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RoomService>(
      builder: (context, roomService, _) {
        // Handle haptic feedback for active speaker changes
        if (_lastActiveSpeakerId != roomService.activeSpeaker?.id) {
          if (roomService.activeSpeaker != null && !roomService.isSpeaking) {
            // Someone else started speaking
            HapticFeedback.mediumImpact();
          } else if (_lastActiveSpeakerId != null &&
              roomService.activeSpeaker == null) {
            // Someone stopped speaking - double buzz
            HapticFeedback.lightImpact();
            Future.delayed(const Duration(milliseconds: 50), () {
              HapticFeedback.lightImpact();
            });
          }
          _lastActiveSpeakerId = roomService.activeSpeaker?.id;
        }

        // Handle ongoing speech haptic
        if (roomService.shouldTriggerHaptic &&
            roomService.activeSpeaker != null &&
            !roomService.isSpeaking) {
          HapticFeedback.lightImpact();
        }

        // Auto-scroll on new messages
        if (roomService.messages.length > _lastMessageCount) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottom());
        }
        _lastMessageCount = roomService.messages.length;
        _lastRoomService = roomService;

        final visibleMessages =
            roomService.messages.where((m) => !m.dismissed).toList();

        if (visibleMessages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Captions will appear here',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: visibleMessages.length,
          itemBuilder: (context, index) {
            final message = visibleMessages[index];
            return _MessageBubble(
              message: message,
              isOwnMessage: message.speakerId == roomService.currentUserId,
              onDismiss: () => roomService.dismissMessage(message.id),
            );
          },
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final RoomMessage message;
  final bool isOwnMessage;
  final VoidCallback onDismiss;

  const _MessageBubble({
    Key? key,
    required this.message,
    required this.isOwnMessage,
    required this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat.jm();

    return AnimatedOpacity(
      opacity: message.dismissed ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: EdgeInsets.only(
          bottom: 8,
          left: isOwnMessage ? 48 : 0,
          right: isOwnMessage ? 0 : 48,
        ),
        child: Card(
          elevation: 1,
          color: isOwnMessage
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            message.speakerName,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isOwnMessage
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeFormat.format(message.timestamp),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.5),
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, size: 18),
                      onPressed: onDismiss,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message.text,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (!message.isFinal)
                  Row(
                    children: [
                      Icon(
                        Icons.mic,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Speaking...',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
