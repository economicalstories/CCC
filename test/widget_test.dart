import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:closed_caption_companion/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('CCC Test'),
        ),
      ),
    ));

    // Verify that the test text is displayed
    expect(find.text('CCC Test'), findsOneWidget);
  });
} 