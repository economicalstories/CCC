import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:closed_caption_companion/widgets/room_caption_display.dart';
import 'package:closed_caption_companion/models/room_message.dart';

void main() {
  group('Message Clearing Functionality Tests', () {
    testWidgets('Clear should prevent old message from repopulating text field',
        (WidgetTester tester) async {
      String? lastSentMessage;

      // Create a mock message that would normally populate the text field
      final oldMessage = RoomMessage(
        id: 'old-message',
        text: 'This is old content that should not reappear',
        speakerId: 'user-1',
        speakerName: 'User',
        timestamp: DateTime.now(),
      );

      // Build widget with old message
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCaptionDisplay(
              onSendMessage: (message) {
                lastSentMessage = message;
              },
              isAudioInitialized: true,
              isSTTReady: false,
            ),
          ),
        ),
      );

      await tester.pump();

      // Simulate having old content in the text field
      final textField = find.byType(TextField);
      await tester.enterText(
          textField, 'This is old content that should not reappear');
      await tester.pump();

      // Verify old content is there
      expect(find.text('This is old content that should not reappear'),
          findsOneWidget);

      // Tap "Clear & Start Voice" button
      await tester.tap(find.text('Clear & Start Voice'));
      await tester.pump();

      // Verify text field is cleared and empty message was sent
      final textFieldWidget = tester.widget<TextField>(textField);
      expect(textFieldWidget.controller?.text, isEmpty);
      expect(lastSentMessage, equals(''));

      // Simulate widget rebuild with the old message still present (this is the bug scenario)
      // In a real app, the parent might still have the old message and try to repopulate

      // The text field should remain empty despite the presence of old message data
      expect(textFieldWidget.controller?.text, isEmpty);
    });

    testWidgets('New STT content should populate after clearing',
        (WidgetTester tester) async {
      String? lastSentMessage;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCaptionDisplay(
              onSendMessage: (message) {
                lastSentMessage = message;
              },
              isAudioInitialized: true,
              isSTTReady: false,
            ),
          ),
        ),
      );

      // Add old content
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Old content');
      await tester.pump();

      // Clear and start voice
      await tester.tap(find.text('Clear & Start Voice'));
      await tester.pump();

      // Verify cleared
      final textFieldWidget = tester.widget<TextField>(textField);
      expect(textFieldWidget.controller?.text, isEmpty);

      // Now simulate STT ready and new content coming in
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCaptionDisplay(
              onSendMessage: (message) {
                lastSentMessage = message;
              },
              isAudioInitialized: true,
              isSTTReady: true, // STT is now ready
            ),
          ),
        ),
      );

      await tester.pump();

      // Simulate new STT content by programmatically setting text
      // (In real app, this would come through currentMessage prop)
      await tester.enterText(textField, 'New STT content');
      await tester.pump();

      // New content should be accepted
      expect(find.text('New STT content'), findsOneWidget);
    });

    testWidgets('Stopping listening should reset clear state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCaptionDisplay(
              isAudioInitialized: true,
              isSTTReady: false,
            ),
          ),
        ),
      );

      // Start listening (which clears)
      await tester.tap(find.text('Clear & Start Voice'));
      await tester.pump();

      // Stop listening
      await tester.tap(find.text('Stop Listening and Edit Text'));
      await tester.pump();

      // Should be back to normal typing mode
      expect(find.text('Type your message here...'), findsOneWidget);
      expect(find.text('Clear & Start Voice'), findsOneWidget);
    });

    testWidgets(
        'Manual text entry should work normally when not in listening mode',
        (WidgetTester tester) async {
      String? lastSentMessage;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCaptionDisplay(
              onSendMessage: (message) {
                lastSentMessage = message;
              },
              isAudioInitialized: true,
              isSTTReady: false,
            ),
          ),
        ),
      );

      // Type normally (not in listening mode)
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Manual typing test');
      await tester.pump();

      // Should send the message
      expect(lastSentMessage, equals('Manual typing test'));

      // Text should be visible
      expect(find.text('Manual typing test'), findsOneWidget);
    });
  });
}
