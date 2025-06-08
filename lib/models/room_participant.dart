class RoomParticipant {
  final String id;
  final String name;
  final DateTime joinedAt;

  RoomParticipant({
    required this.id,
    required this.name,
    required this.joinedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomParticipant &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
