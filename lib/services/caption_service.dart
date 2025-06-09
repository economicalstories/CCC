import 'package:flutter/material.dart';
import 'dart:async';
import 'package:closed_caption_companion/models/caption_entry.dart';
import 'package:closed_caption_companion/services/settings_service.dart';

class CaptionService extends ChangeNotifier {
  // Caption history (last 24 hours)
  final List<CaptionEntry> _captions = [];

  // Settings service reference
  SettingsService? _settingsService;

  // Current caption being displayed
  String _currentCaption = '';
  String?
      _lastRecordingTranscriptId; // Track the most recent transcript from recording

  // Streaming state
  bool _isStreaming = false;
  bool _isConnecting = false;
  bool _isEditMode = false;
  bool _isEditingExistingTranscript = false; // Track if editing existing vs new
  String? _errorMessage;

  // Performance metrics
  DateTime? _speechStartTime;
  DateTime? _captionStartTime;

  // Stream controller for caption updates
  final StreamController<String> _captionStreamController =
      StreamController<String>.broadcast();

  // Getters
  List<CaptionEntry> get captions => List.unmodifiable(_captions);
  String get currentCaption => _currentCaption;
  bool get isStreaming => _isStreaming;
  bool get isConnecting => _isConnecting;
  bool get isEditMode => _isEditMode;
  String? get errorMessage => _errorMessage;
  Stream<String> get captionStream => _captionStreamController.stream;

  // Set settings service reference
  void setSettingsService(SettingsService settingsService) {
    _settingsService = settingsService;
  }

  // Add new caption text
  void addCaptionText(String text, {bool isFinal = false}) {
    print('CaptionService: Adding text "$text" (final: $isFinal)');
    if (text.isEmpty) return;

    // Replace any carriage returns or newlines with " / " for continuous flow
    final cleanText = text.replaceAll(RegExp(r'[\r\n]+'), ' / ');
    _currentCaption = cleanText;
    _captionStreamController.add(cleanText);

    // Track performance
    if (_speechStartTime != null && _captionStartTime == null) {
      _captionStartTime = DateTime.now();
      final latency =
          _captionStartTime!.difference(_speechStartTime!).inMilliseconds;
      print('Caption latency: ${latency}ms');
    }

    // If final, add to history (only if save transcripts is enabled)
    if (isFinal && _settingsService?.saveTranscripts == true) {
      final entry = CaptionEntry(
        text: cleanText,
        timestamp: DateTime.now(),
        latencyMs: _captionStartTime != null && _speechStartTime != null
            ? _captionStartTime!.difference(_speechStartTime!).inMilliseconds
            : null,
      );
      _captions.insert(0, entry);
      _lastRecordingTranscriptId =
          entry.id; // Track this transcript for potential editing
      _cleanupOldCaptions();
    }

    notifyListeners();
  }

  // Clear current caption
  void clearCurrentCaption() {
    _currentCaption = '';
    _captionStreamController.add('');
    _speechStartTime = null;
    _captionStartTime = null;
    _lastRecordingTranscriptId = null; // Clear transcript tracking
    notifyListeners();
  }

  // Set streaming state
  void setStreaming(bool streaming) {
    _isStreaming = streaming;
    if (streaming) {
      // Only clear timing when starting, not the caption text
      _speechStartTime = DateTime.now();
      _captionStartTime = null;
    }
    // Don't clear caption when stopping - keep it visible until next press
    notifyListeners();
  }

  // Set connecting state
  void setConnecting(bool connecting) {
    _isConnecting = connecting;
    if (connecting) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  // Set error message
  void setError(String? error) {
    _errorMessage = error;
    _isConnecting = false;
    _isStreaming = false;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Set edit mode
  void setEditMode(bool editing, {bool editingExisting = false}) {
    _isEditMode = editing;
    _isEditingExistingTranscript = editingExisting;
    notifyListeners();
  }

  // Finish editing and save current caption
  void finishEditing() {
    if (_isEditMode && _currentCaption.isNotEmpty) {
      // If we have a recent recording transcript, update it instead of creating new one
      if (_lastRecordingTranscriptId != null && !_isEditingExistingTranscript) {
        // Update the existing transcript from the recording
        final success =
            editCaption(_lastRecordingTranscriptId!, _currentCaption);
        if (success) {
          _lastRecordingTranscriptId =
              null; // Clear the tracking since we've updated it
        }
      } else if (!_isEditingExistingTranscript &&
          _settingsService?.saveTranscripts == true) {
        // Only create new transcript if this is completely new content (not from recording)
        final entry = CaptionEntry(
          text: _currentCaption,
          timestamp: DateTime.now(),
          latencyMs: null, // No latency for edited content
        );
        _captions.insert(0, entry);
        _cleanupOldCaptions();
      }
    }
    _isEditMode = false;
    _isEditingExistingTranscript = false;
    notifyListeners();
  }

  // Edit a caption by ID
  bool editCaption(String id, String newText) {
    final index = _captions.indexWhere((caption) => caption.id == id);
    if (index != -1) {
      _captions[index].updateText(newText);
      // Don't interfere with current caption or edit mode - this is separate from main screen editing
      notifyListeners();
      return true;
    }
    return false;
  }

  // Delete a caption by ID
  bool deleteCaption(String id) {
    final index = _captions.indexWhere((caption) => caption.id == id);
    if (index != -1) {
      _captions.removeAt(index);
      notifyListeners();
      return true;
    }
    return false;
  }

  // Get a caption by ID
  CaptionEntry? getCaptionById(String id) {
    try {
      return _captions.firstWhere((caption) => caption.id == id);
    } catch (e) {
      return null;
    }
  }

  // Get recent captions as text
  String getRecentCaptionsText({int count = 10}) {
    final recent = _captions.take(count);
    return recent.map((c) => c.text).join('\n');
  }

  // Clear all captions
  void clearHistory() {
    _captions.clear();
    notifyListeners();
  }

  // Export captions as text
  String exportCaptions() {
    final buffer = StringBuffer();
    buffer.writeln('Closed-Caption Companion - Transcript');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln('=' * 40);
    buffer.writeln();

    for (final caption in _captions.reversed) {
      buffer.writeln('[${caption.formattedTime}] ${caption.text}');
    }

    return buffer.toString();
  }

  // Clean up captions older than 24 hours
  void _cleanupOldCaptions() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    _captions.removeWhere((caption) => caption.timestamp.isBefore(cutoff));
  }

  // Update current caption text without saving to history (for editing)
  void updateCurrentCaption(String text) {
    final cleanText = text.replaceAll(RegExp(r'[\r\n]+'), ' / ');
    _currentCaption = cleanText;
    _captionStreamController.add(cleanText);
    notifyListeners();
  }

  @override
  void dispose() {
    _captionStreamController.close();
    super.dispose();
  }
}
