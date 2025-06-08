import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/settings_service.dart';
import '../services/caption_service.dart';
import '../utils/theme_config.dart';
import 'transcript_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double? _previewFontSize; // Temporary font size while sliding
  bool _isSliding = false;
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            size: Theme.of(context).iconTheme.size,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Font Size Section
            _SectionCard(
              title: 'Font Size',
              child: Column(
                children: [
                  // Font size slider with range labels
                  Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            'Small',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Expanded(
                            child: Slider(
                              value: _previewFontSize ?? settings.fontSize,
                              min: ThemeConfig.minFontSize,
                              max: ThemeConfig.maxFontSize,
                              divisions: ((ThemeConfig.maxFontSize -
                                          ThemeConfig.minFontSize) ~/
                                      4)
                                  .toInt(),
                              label:
                                  '${(_previewFontSize ?? settings.fontSize).toInt()}pt',
                              onChangeStart: (value) {
                                setState(() {
                                  _isSliding = true;
                                  _previewFontSize = value;
                                });
                              },
                              onChanged: (value) {
                                setState(() {
                                  _previewFontSize = value;
                                });
                              },
                              onChangeEnd: (value) {
                                setState(() {
                                  _isSliding = false;
                                  _previewFontSize = null;
                                });
                                // Apply the final font size to UI
                                settings.setFontSize(value);
                              },
                            ),
                          ),
                          Text(
                            'Large',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(_previewFontSize ?? settings.fontSize).toInt()}pt',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Preview text (below slider so it doesn't shift the controls)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
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
                      'This is how captions will look',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontSize: _previewFontSize ?? settings.fontSize,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            // Theme Section
            _SectionCard(
              title: 'Theme',
              child: Column(
                children: [
                  _SettingsTile(
                    title: 'Dark Mode',
                    subtitle: 'High contrast white-on-black text',
                    trailing: Switch(
                      value: settings.themeMode == ThemeMode.dark,
                      onChanged: (value) {
                        settings.setThemeMode(
                            value ? ThemeMode.dark : ThemeMode.light);
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Transcript Section
            _SectionCard(
              title: 'Transcripts',
              child: Consumer<CaptionService>(
                builder: (context, captionService, child) {
                  return Column(
                    children: [
                      _SettingsTile(
                        title: 'Save Transcripts',
                        subtitle:
                            'Keep captions temporarily while app is running',
                        trailing: Switch(
                          value: settings.saveTranscripts,
                          onChanged: settings.setSaveTranscripts,
                        ),
                      ),
                      if (settings.saveTranscripts) ...[
                        const Divider(),
                        _SettingsTile(
                          title: 'View Transcripts',
                          subtitle: captionService.captions.isEmpty
                              ? 'No captions saved'
                              : '${captionService.captions.length} captions saved',
                          trailing: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const TranscriptScreen(),
                                ),
                              );
                            },
                            child: const Text('VIEW'),
                          ),
                        ),
                        const Divider(),
                        _SettingsTile(
                          title: 'Clear History',
                          subtitle: 'Delete all saved transcripts',
                          trailing: TextButton(
                            onPressed: captionService.captions.isEmpty
                                ? null
                                : () {
                                    _showClearHistoryDialog(
                                        context, captionService);
                                  },
                            child: const Text('CLEAR'),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),

            // Speech Service Section
            _SectionCard(
              title: 'Speech Recognition',
              child: Column(
                children: [
                  Text(
                    'Choose your preferred speech recognition service. Cloud services provide better accuracy but require internet connection.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  _SettingsTile(
                    title: 'Device Speech Recognition',
                    subtitle: 'Use built-in speech recognition (works offline)',
                    trailing: Radio<String>(
                      value: 'device',
                      groupValue: settings.speechService,
                      onChanged: (value) {
                        if (value != null) {
                          settings.setSpeechService(value);
                        }
                      },
                    ),
                  ),
                  const Divider(),
                  _SettingsTile(
                    title: 'Google Speech-to-Text',
                    subtitle: 'Enhanced accuracy with cloud processing',
                    trailing: Radio<String>(
                      value: 'google',
                      groupValue: settings.speechService,
                      onChanged: (value) {
                        if (value != null) {
                          settings.setSpeechService(value);
                        }
                      },
                    ),
                  ),
                  const Divider(),
                  _SettingsTile(
                    title: 'Azure Speech Service',
                    subtitle: 'Microsoft\'s cloud speech recognition',
                    trailing: Radio<String>(
                      value: 'azure',
                      groupValue: settings.speechService,
                      onChanged: (value) {
                        if (value != null) {
                          settings.setSpeechService(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Language/Locale Section
            _SectionCard(
              title: 'Language & Region',
              child: Column(
                children: [
                  Text(
                    'Select the language and region for speech recognition.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  _SettingsTile(
                    title: 'Australian English',
                    subtitle: 'en_AU - Best for Australian accents',
                    trailing: Radio<String>(
                      value: 'en_AU',
                      groupValue: settings.speechLocale,
                      onChanged: (value) {
                        if (value != null) {
                          settings.setSpeechLocale(value);
                        }
                      },
                    ),
                  ),
                  const Divider(),
                  _SettingsTile(
                    title: 'US English',
                    subtitle: 'en_US - Best for American accents',
                    trailing: Radio<String>(
                      value: 'en_US',
                      groupValue: settings.speechLocale,
                      onChanged: (value) {
                        if (value != null) {
                          settings.setSpeechLocale(value);
                        }
                      },
                    ),
                  ),
                  const Divider(),
                  _SettingsTile(
                    title: 'British English',
                    subtitle: 'en_GB - Best for British accents',
                    trailing: Radio<String>(
                      value: 'en_GB',
                      groupValue: settings.speechLocale,
                      onChanged: (value) {
                        if (value != null) {
                          settings.setSpeechLocale(value);
                        }
                      },
                    ),
                  ),
                  const Divider(),
                  _SettingsTile(
                    title: 'Canadian English',
                    subtitle: 'en_CA - Best for Canadian accents',
                    trailing: Radio<String>(
                      value: 'en_CA',
                      groupValue: settings.speechLocale,
                      onChanged: (value) {
                        if (value != null) {
                          settings.setSpeechLocale(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Privacy & Data Management Section
            _SectionCard(
              title: 'Privacy & Data Management',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your privacy matters. Here\'s how we handle your data:',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 16),

                  // Audio Processing
                  _PrivacyItem(
                    icon: Icons.mic,
                    title: 'Audio Processing',
                    description:
                        'Audio is processed in real-time for speech recognition. Audio data is never stored on your device or transmitted to our servers.',
                  ),

                  // Speech Recognition
                  _PrivacyItem(
                    icon: Icons.cloud_outlined,
                    title: 'Speech Recognition Services',
                    description:
                        'When using cloud services (Google, Azure), audio is sent securely to their servers for processing. We don\'t store this data.',
                  ),

                  // Local Storage
                  _PrivacyItem(
                    icon: Icons.storage,
                    title: 'Local Storage',
                    description:
                        'Captions are only stored locally on your device when enabled. You can clear this data anytime in the Transcripts section.',
                  ),

                  // No Analytics
                  _PrivacyItem(
                    icon: Icons.analytics_outlined,
                    title: 'No Analytics or Tracking',
                    description:
                        'We don\'t collect usage data, analytics, or personal information. Your conversations remain private.',
                  ),

                  // Open Source
                  _PrivacyItem(
                    icon: Icons.code,
                    title: 'Open Source',
                    description:
                        'This app is open source. You can review the code to verify our privacy practices.',
                  ),

                  const SizedBox(height: 16),

                  // Contact and Links
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceVariant
                          .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.help_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _launchURL(
                                'https://github.com/economicalstories/CCC'),
                            child: Text(
                              'View Source Code',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // About Section
            _SectionCard(
              title: 'About',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Closed-Caption Companion (CCC)',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version 1.1.0',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Making stories accessible to everyone. Real-time captions help those who are hard of hearing participate fully in conversations, presentations, and the stories happening around them.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Attribution footer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'A personal project by PC Hubbard',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _launchURL('https://economicalstories.com'),
                    child: Text(
                      'economicalstories.com',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w500,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showClearHistoryDialog(
      BuildContext context, CaptionService captionService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Clear History?',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        content: Text(
          'This will delete all saved captions. This action cannot be undone.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              captionService.clearHistory();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('History cleared')),
              );
            },
            child: Text(
              'CLEAR',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: try platform default
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      // Fallback: show a snackbar if URL can't be launched
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $url - Error: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

// Responsive button row that switches to column layout when buttons don't fit
class _ResponsiveButtonRow extends StatelessWidget {
  final List<Widget> buttons;
  final MainAxisAlignment alignment;
  final double spacing;

  const _ResponsiveButtonRow({
    required this.buttons,
    this.alignment = MainAxisAlignment.spaceEvenly,
    this.spacing = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate approximate button widths to determine if they fit
        final screenWidth = constraints.maxWidth;
        final buttonPadding = 16.0; // Estimated button padding
        final iconWidth = 24.0; // Icon width
        final textWidth = _estimateTextWidth(context);
        final totalButtonWidth =
            buttons.length * (buttonPadding * 2 + iconWidth + textWidth);
        final totalSpacing = (buttons.length - 1) * spacing;

        // If buttons don't fit comfortably, use column layout
        if (totalButtonWidth + totalSpacing > screenWidth * 0.9) {
          return Column(
            crossAxisAlignment: alignment == MainAxisAlignment.end
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.center,
            children: buttons
                .map((button) => Padding(
                      padding: EdgeInsets.only(bottom: spacing),
                      child: button,
                    ))
                .toList(),
          );
        } else {
          // Use row layout when buttons fit comfortably
          return Row(
            mainAxisAlignment: alignment,
            children: buttons.map((button) {
              if (button == buttons.last) return button;
              return Padding(
                padding: EdgeInsets.only(right: spacing),
                child: button,
              );
            }).toList(),
          );
        }
      },
    );
  }

  double _estimateTextWidth(BuildContext context) {
    // Estimate the maximum text width for the buttons
    final textStyle = Theme.of(context).textTheme.labelLarge;
    final fontSize = textStyle?.fontSize ?? 14.0;

    // Rough estimate: 8 characters * font size * 0.6 (character width ratio)
    return 8 * fontSize * 0.6;
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize:
                        Theme.of(context).textTheme.headlineMedium!.fontSize! *
                            0.8,
                  ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;

  const _SettingsTile({
    required this.title,
    this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                  ),
                ],
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _PrivacyItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _PrivacyItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
