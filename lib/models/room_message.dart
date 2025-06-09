class RoomMessage {
  RoomMessage({
    required this.id,
    required this.speakerId,
    required this.speakerName,
    required this.text,
    required this.timestamp,
    this.isFinal = false,
    this.dismissed = false,
  });
  final String id;
  final String speakerId;
  final String speakerName;
  final String text;
  final DateTime timestamp;
  final bool isFinal;
  final bool dismissed;

  RoomMessage copyWith({
    String? id,
    String? speakerId,
    String? speakerName,
    String? text,
    DateTime? timestamp,
    bool? isFinal,
    bool? dismissed,
  }) {
    return RoomMessage(
      id: id ?? this.id,
      speakerId: speakerId ?? this.speakerId,
      speakerName: speakerName ?? this.speakerName,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isFinal: isFinal ?? this.isFinal,
      dismissed: dismissed ?? this.dismissed,
    );
  }
}
