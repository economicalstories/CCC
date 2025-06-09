class RoomParticipant {
  final String id;
  final String name;
  final DateTime? joinedAt;

  RoomParticipant({
    required this.id,
    required this.name,
    this.joinedAt,
  });

  factory RoomParticipant.fromJson(Map<String, dynamic> json) {
    return RoomParticipant(
      id: json['id'],
      name: json['name'],
      joinedAt: json['joinedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['joinedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'joinedAt': joinedAt?.millisecondsSinceEpoch,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomParticipant &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RoomParticipant($name)';
}
