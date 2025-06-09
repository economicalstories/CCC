import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:closed_caption_companion/services/caption_service.dart';
import 'package:closed_caption_companion/services/audio_streaming_service.dart';
import 'package:closed_caption_companion/services/settings_service.dart';

class StatusIndicator extends StatelessWidget {
  const StatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final captionService = context.watch<CaptionService>();
    final audioService = context.read<AudioStreamingService>();
    final settingsService = context.read<SettingsService>();

    return Semantics(
      label: _getStatusLabel(captionService, audioService, settingsService),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getStatusColor(captionService, audioService).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _getStatusColor(captionService, audioService),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _getStatusColor(captionService, audioService),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),

            // Status text
            Text(
              _getStatusText(captionService, audioService, settingsService),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _getStatusColor(captionService, audioService),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(
      CaptionService captionService, AudioStreamingService audioService) {
    if (captionService.errorMessage != null) {
      return Colors.red;
    }
    if (captionService.isStreaming) {
      return Colors.green;
    }
    if (captionService.isConnecting) {
      return Colors.orange;
    }
    if (audioService.isConnected) {
      return Colors.blue;
    }
    return Colors.grey;
  }

  String _getStatusText(CaptionService captionService,
      AudioStreamingService audioService, SettingsService settingsService) {
    if (captionService.errorMessage != null) {
      return 'ERROR';
    }
    if (captionService.isStreaming) {
      return 'LIVE';
    }
    if (captionService.isConnecting) {
      return 'CONNECTING';
    }
    if (settingsService.speechService == 'device') {
      return 'DEVICE';
    }
    if (audioService.isConnected) {
      return 'READY';
    }
    return 'NOT READY';
  }

  String _getStatusLabel(CaptionService captionService,
      AudioStreamingService audioService, SettingsService settingsService) {
    final status =
        _getStatusText(captionService, audioService, settingsService);

    String serviceDescription;
    switch (settingsService.speechService) {
      case 'google':
        serviceDescription = 'Using Google Speech-to-Text';
        break;
      case 'azure':
        serviceDescription = 'Using Azure Speech Service';
        break;
      case 'device':
        serviceDescription = 'Using device speech recognition';
        break;
      default:
        serviceDescription = 'Using Google Speech-to-Text';
        break;
    }

    return 'Status: $status - $serviceDescription';
  }
}
