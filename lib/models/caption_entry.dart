import 'package:intl/intl.dart';

class CaptionEntry {
  CaptionEntry({
    String? id,
    required this.text,
    required this.timestamp,
    this.latencyMs,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  factory CaptionEntry.fromJson(Map<String, dynamic> json) {
    return CaptionEntry(
      id: json['id'] as String?,
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      latencyMs: json['latencyMs'] as int?,
    );
  }
  final String id;
  String text;
  final DateTime timestamp;
  final int? latencyMs;

  String get formattedTime {
    return DateFormat('HH:mm:ss').format(timestamp);
  }

  String get formattedDate {
    return DateFormat('MMM dd, yyyy').format(timestamp);
  }

  String get formattedDateTime {
    return DateFormat('MMM dd, yyyy HH:mm:ss').format(timestamp);
  }

  // Update the text content
  void updateText(String newText) {
    text = newText;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'latencyMs': latencyMs,
    };
  }
}
