import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:closed_caption_companion/services/caption_service.dart';
import 'package:closed_caption_companion/services/settings_service.dart';
import 'package:closed_caption_companion/utils/theme_config.dart';

class CaptionDisplay extends StatefulWidget {
  const CaptionDisplay({super.key});

  @override
  State<CaptionDisplay> createState() => _CaptionDisplayState();
}

class _CaptionDisplayState extends State<CaptionDisplay> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocusNode = FocusNode();
  bool _wasStreamingLastFrame = false;
  bool _userExplicitlyFocused = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _editController.dispose();
    _editFocusNode.dispose();
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

  void _onTextChanged(String text, CaptionService captionService) {
    // Update the current caption text but don't save to history during editing
    // The transcript will be saved when editing is finished via finishEditing()
    captionService.updateCurrentCaption(text);
  }

  @override
  Widget build(BuildContext context) {
    final captionService = context.watch<CaptionService>();
    final settingsService = context.watch<SettingsService>();

    // Check if recording just stopped
    final currentlyStreaming = captionService.isStreaming;
    if (_wasStreamingLastFrame &&
        !currentlyStreaming &&
        captionService.currentCaption.isNotEmpty) {
      // Recording just stopped, update the text field but don't auto-focus
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _editController.text = captionService.currentCaption;
        // Don't auto-focus unless user was explicitly editing
        if (!_userExplicitlyFocused && _editFocusNode.hasFocus) {
          _editFocusNode.unfocus();
        }
      });
    }

    // If recording just started, clear the explicit focus flag and unfocus
    if (!_wasStreamingLastFrame && currentlyStreaming) {
      _userExplicitlyFocused = false;
      if (_editFocusNode.hasFocus) {
        _editFocusNode.unfocus();
      }
    }

    // If edit mode was just exited, remove focus
    if (captionService.isEditMode == false && _editFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _editFocusNode.unfocus();
        _userExplicitlyFocused = false;
      });
    }

    _wasStreamingLastFrame = currentlyStreaming;

    // Update text field when caption changes during streaming
    if (currentlyStreaming &&
        _editController.text != captionService.currentCaption) {
      _editController.text = captionService.currentCaption;
    }

    // Auto-scroll when new text arrives
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (captionService.currentCaption.isNotEmpty) {
        _scrollToBottom();
      }
    });

    return GestureDetector(
      onTap: () {
        // Tap outside text field to dismiss keyboard
        if (_editFocusNode.hasFocus) {
          _editFocusNode.unfocus();
          _userExplicitlyFocused = false;
        }
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
            width: 2,
          ),
        ),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // Error message
              if (captionService.errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          captionService.errorMessage!,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Main content area
              if (captionService.currentCaption.isEmpty &&
                  !captionService.isStreaming)
                // Placeholder when empty - flush with top
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    'Hold the button below and speak, then click to edit',
                    style: ThemeConfig.getCaptionTextStyle(
                      settingsService.fontSize,
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    ).copyWith(fontStyle: FontStyle.italic),
                    textAlign: TextAlign.start,
                  ),
                )
              else
                // Simple text field - editable when not streaming, read-only when streaming
                TextField(
                  controller: _editController,
                  focusNode: _editFocusNode,
                  maxLines: null,
                  readOnly: captionService.isStreaming,
                  enableInteractiveSelection: !captionService.isStreaming,
                  style: ThemeConfig.getCaptionTextStyle(
                    settingsService.fontSize,
                    Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: captionService.isStreaming
                        ? 'Listening...'
                        : 'Tap to edit the transcript',
                    hintStyle: ThemeConfig.getCaptionTextStyle(
                      settingsService.fontSize,
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                  onTap: () {
                    // Only focus when user explicitly taps
                    if (!captionService.isStreaming) {
                      _userExplicitlyFocused = true;
                      _editFocusNode.requestFocus();
                      // Enter edit mode
                      captionService.setEditMode(true);
                    }
                  },
                  onChanged: (text) {
                    if (!captionService.isStreaming) {
                      _onTextChanged(text, captionService);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
