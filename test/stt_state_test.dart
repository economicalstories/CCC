import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:closed_caption_companion/services/audio_streaming_service.dart';
import 'package:closed_caption_companion/services/settings_service.dart';

@GenerateMocks([SettingsService])
import 'stt_state_test.mocks.dart';

void main() {
  group('STT State Management Tests', () {
    late AudioStreamingService audioService;
    late MockSettingsService mockSettingsService;

    setUp(() {
      audioService = AudioStreamingService();
      mockSettingsService = MockSettingsService();
      when(mockSettingsService.speechLocale).thenReturn('en_AU');
    });

    test('onListeningStarted callback should be triggered when STT starts',
        () async {
      bool listenerStartedCalled = false;

      audioService.onListeningStarted = () {
        listenerStartedCalled = true;
      };

      // Simulate STT status change to 'listening'
      audioService.handleSpeechStatus('listening');

      expect(listenerStartedCalled, isTrue);
    });

    test('onListeningStarted should not be called for other status changes',
        () {
      bool listenerStartedCalled = false;

      audioService.onListeningStarted = () {
        listenerStartedCalled = true;
      };

      // Test other statuses
      audioService.handleSpeechStatus('notListening');
      expect(listenerStartedCalled, isFalse);

      audioService.handleSpeechStatus('done');
      expect(listenerStartedCalled, isFalse);
    });

    test('multiple listening status calls should trigger callback each time',
        () {
      int callCount = 0;

      audioService.onListeningStarted = () {
        callCount++;
      };

      audioService.handleSpeechStatus('listening');
      audioService.handleSpeechStatus('listening');
      audioService.handleSpeechStatus('listening');

      expect(callCount, equals(3));
    });
  });
}
