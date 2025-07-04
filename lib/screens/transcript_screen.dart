import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:closed_caption_companion/services/caption_service.dart';
import 'package:closed_caption_companion/models/caption_entry.dart';

class TranscriptScreen extends StatefulWidget {
  const TranscriptScreen({super.key});

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> {
  String? _editingId;
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocusNode = FocusNode();

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final captionService = context.watch<CaptionService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Transcripts',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            size: Theme.of(context).iconTheme.size,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (captionService.captions.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () => _copyAllTranscripts(context, captionService),
              tooltip: 'Copy all',
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => _shareTranscripts(context, captionService),
              tooltip: 'Share',
            ),
          ],
        ],
      ),
      body: captionService.captions.isEmpty
          ? _buildEmptyState(context)
          : _buildTranscriptList(context, captionService),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No Transcripts Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use the push-to-talk button on the main screen to create your first transcript.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptList(
      BuildContext context, CaptionService captionService) {
    return Column(
      children: [
        // Header with count and editing tip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withOpacity(0.3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${captionService.captions.length} transcripts (kept for 24 hours)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap any transcript to edit it. Long press for quick actions.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
              ),
            ],
          ),
        ),

        // Transcript list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: captionService.captions.length,
            itemBuilder: (context, index) {
              final caption = captionService.captions[index];
              return _buildTranscriptCard(context, caption, captionService);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTranscriptCard(BuildContext context, CaptionEntry caption,
      CaptionService captionService) {
    final isEditing = _editingId == caption.id;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with timestamp and actions
            Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  caption.formattedTime,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (caption.latencyMs != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .secondary
                          .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${caption.latencyMs}ms',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                    ),
                  ),
                ],
                const Spacer(),
                if (isEditing) ...[
                  IconButton(
                    icon: const Icon(Icons.check, size: 20),
                    onPressed: () => _saveEdit(captionService),
                    tooltip: 'Save',
                    color: Colors.green,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: _cancelEdit,
                    tooltip: 'Cancel',
                    color: Colors.red,
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _startEdit(caption),
                    tooltip: 'Edit',
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) => _handleMenuAction(
                        value, caption, captionService, context),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'copy',
                        child: Row(
                          children: [
                            Icon(Icons.copy, size: 16),
                            SizedBox(width: 8),
                            Text('Copy'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 16, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Transcript text (editable or display)
            if (isEditing) ...[
              TextField(
                controller: _editController,
                focusNode: _editFocusNode,
                maxLines: null,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Edit transcript...',
                  helperText: 'Tap checkmark to save, X to cancel',
                ),
                onSubmitted: (_) => _saveEdit(captionService),
              ),
            ] else ...[
              GestureDetector(
                onTap: () => _startEdit(caption),
                onLongPress: () =>
                    _showQuickActions(context, caption, captionService),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.1),
                    ),
                  ),
                  child: Text(
                    caption.text,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _startEdit(CaptionEntry caption) {
    final captionService = context.read<CaptionService>();
    // Clear any current caption state to prevent interference
    captionService.clearCurrentCaption();
    captionService.setEditMode(false); // Ensure main screen edit mode is off

    setState(() {
      _editingId = caption.id;
      _editController.text = caption.text;
    });

    // Focus and select all text for easy editing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _saveEdit(CaptionService captionService) {
    if (_editingId != null) {
      final newText = _editController.text.trim();
      if (newText.isNotEmpty) {
        captionService.editCaption(_editingId!, newText);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transcript updated'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      _cancelEdit();
    }
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _editController.clear();
    });
    _editFocusNode.unfocus();
  }

  void _handleMenuAction(String action, CaptionEntry caption,
      CaptionService captionService, BuildContext context) {
    switch (action) {
      case 'copy':
        _copyTranscript(context, caption);
        break;
      case 'delete':
        _deleteTranscript(context, caption, captionService);
        break;
    }
  }

  void _showQuickActions(BuildContext context, CaptionEntry caption,
      CaptionService captionService) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Transcript'),
              onTap: () {
                Navigator.pop(context);
                _startEdit(caption);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                _copyTranscript(context, caption);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteTranscript(context, caption, captionService);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTranscript(BuildContext context, CaptionEntry caption,
      CaptionService captionService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transcript?'),
        content: Text(
          'This will permanently delete this transcript:\n\n"${caption.text.length > 100 ? '${caption.text.substring(0, 100)}...' : caption.text}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              captionService.deleteCaption(caption.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Transcript deleted'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _copyTranscript(BuildContext context, CaptionEntry caption) {
    final text = '[${caption.formattedTime}] ${caption.text}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transcript copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copyAllTranscripts(
      BuildContext context, CaptionService captionService) {
    final allText = captionService.exportCaptions();
    Clipboard.setData(ClipboardData(text: allText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${captionService.captions.length} transcripts copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareTranscripts(BuildContext context, CaptionService captionService) {
    // Copy to clipboard as fallback since share_plus isn't available
    _copyAllTranscripts(context, captionService);
  }
}
