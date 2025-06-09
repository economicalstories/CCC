import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:closed_caption_companion/services/settings_service.dart';
import 'package:closed_caption_companion/utils/theme_config.dart';
import 'package:closed_caption_companion/utils/room_code_generator.dart';
import 'package:closed_caption_companion/services/room_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double? _previewFontSize; // Temporary font size while sliding
  bool _isSliding = false;
  final TextEditingController _roomCodeController = TextEditingController();
  final TextEditingController _accessKeyController = TextEditingController();
  final TextEditingController _userNameController = TextEditingController();
  String? _accessKeyError;
  bool _isTestingConnection = false;
  bool _isEditingUserName = false;
  bool _isEditingAccessKey = false;

  @override
  void initState() {
    super.initState();
    // Don't pre-populate access key for security - user must explicitly choose to edit it
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    _accessKeyController.dispose();
    _userNameController.dispose();
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
            // About Section
            _SectionCard(
              title: 'About',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App icon and name
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/ccc_logo.png',
                            width: 48,
                            height: 48,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (context, error, stackTrace) {
                              // Fallback to icon if image fails to load
                              return Icon(
                                Icons.closed_caption,
                                size: 48,
                                color: Theme.of(context).colorScheme.primary,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Closed Caption Companion',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Version 1.1.0',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.7),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Making stories accessible to everyone. Real-time captions help those who are hard of hearing participate fully in conversations, presentations, and the stories happening around them.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),

            // Profile Section
            _SectionCard(
              title: 'Profile',
              child: Column(
                children: [
                  // Name editing section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Name',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (_isEditingUserName) ...[
                        // Editing mode
                        TextField(
                          controller: _userNameController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Enter your name',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.words,
                          onSubmitted: (value) => _saveUserName(settings),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _cancelEditUserName,
                              child: const Text('CANCEL'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _saveUserName(settings),
                              child: const Text('SAVE'),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Display mode
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.2),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  settings.userName ?? 'Not set',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                              TextButton(
                                onPressed: () => _startEditUserName(settings),
                                child: const Text('EDIT'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This name will be shown when you join group caption rooms',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                  ),
                ],
              ),
            ),

            // Connect to other devices Section
            _SectionCard(
              title: 'Connect to other devices',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Access Key',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (settings.accessKey != null && !_isEditingAccessKey) ...[
                    // Key is set - show connected status
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.green.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.green.withOpacity(0.1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Connected - captions sync across your devices',
                              style: TextStyle(color: Colors.green),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _showForgetKeyDialog(context, settings),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Forget Key'),
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_isEditingAccessKey) ...[
                    // Editing mode
                    TextField(
                      controller: _accessKeyController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText:
                            'Enter 4 words separated by hyphens (e.g. apple-sky-moon-path)',
                        errorText: _accessKeyError,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (value) => _saveAccessKey(settings),
                    ),
                    const SizedBox(height: 8),
                    if (_isTestingConnection) ...[
                      const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Testing connection...'),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isTestingConnection
                              ? null
                              : _cancelEditAccessKey,
                          child: const Text('CANCEL'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isTestingConnection
                              ? null
                              : () => _saveAccessKey(settings),
                          child: const Text('SAVE'),
                        ),
                      ],
                    ),
                  ] else ...[
                    // No key set - show add button
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.2),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Solo use only (offline mode)'),
                          ),
                          TextButton(
                            onPressed: _startEditAccessKey,
                            child: const Text('ADD KEY'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Add an access key to sync captions across your devices in real-time.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                  ),
                ],
              ),
            ),

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
                      style: ThemeConfig.getCaptionTextStyle(
                        _previewFontSize ?? settings.fontSize,
                        Theme.of(context).colorScheme.onSurface,
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
                  const _PrivacyItem(
                    icon: Icons.mic,
                    title: 'Audio Processing',
                    description:
                        'Audio is processed in real-time for speech recognition. Audio data is never stored on your device or transmitted to our servers.',
                  ),

                  // Speech Recognition
                  const _PrivacyItem(
                    icon: Icons.cloud_outlined,
                    title: 'Speech Recognition Services',
                    description:
                        'When using cloud services (Google, Azure), audio is sent securely to their servers for processing. We don\'t store this data.',
                  ),

                  // Local Storage
                  const _PrivacyItem(
                    icon: Icons.storage,
                    title: 'Local Storage',
                    description:
                        'Captions are only stored locally on your device when enabled. You can clear this data anytime in the Transcripts section.',
                  ),

                  // No Analytics
                  const _PrivacyItem(
                    icon: Icons.analytics_outlined,
                    title: 'No Analytics or Tracking',
                    description:
                        'We don\'t collect usage data, analytics, or personal information. Your conversations remain private.',
                  ),

                  // Open Source
                  const _PrivacyItem(
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
                          .surfaceContainerHighest
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

            const SizedBox(height: 32),

            // Attribution footer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
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

  void _startEditUserName(SettingsService settings) {
    setState(() {
      _isEditingUserName = true;
      _userNameController.text = settings.userName ?? '';
    });
  }

  void _cancelEditUserName() {
    setState(() {
      _isEditingUserName = false;
      _userNameController.clear();
    });
  }

  void _saveUserName(SettingsService settings) {
    final newName = _userNameController.text.trim();
    settings.setUserName(newName.isEmpty ? null : newName);
    setState(() {
      _isEditingUserName = false;
      _userNameController.clear();
    });
  }

  void _startEditAccessKey() {
    setState(() {
      _isEditingAccessKey = true;
      _accessKeyController.clear();
      _accessKeyError = null;
    });
  }

  void _cancelEditAccessKey() {
    setState(() {
      _isEditingAccessKey = false;
      _accessKeyController.clear();
      _accessKeyError = null;
    });
  }

  Future<void> _saveAccessKey(SettingsService settings) async {
    final accessKey = _accessKeyController.text.trim();

    // Validate access key format first
    final validationError = settings.validateAccessKey(accessKey);
    if (validationError != null) {
      setState(() {
        _accessKeyError = validationError;
      });
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _accessKeyError = null;
    });

    try {
      // Test the connection using the room service
      final roomService = context.read<RoomService>();
      final testResult = await roomService.testConnectivityWithKey(accessKey);

      if (testResult.success) {
        // Connection successful - save the key and enable sharing
        await settings.setAccessKey(accessKey);
        await settings.setSharingEnabled(true);

        // Exit edit mode
        setState(() {
          _isEditingAccessKey = false;
          _accessKeyController.clear();
        });

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Connected successfully!'),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Connection failed - stay in edit mode and show error
        setState(() {
          _accessKeyError = testResult.error ?? 'Connection failed';
        });
      }
    } catch (e) {
      // Handle unexpected errors - stay in edit mode
      setState(() {
        _accessKeyError = 'Connection test failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
        });
      }
    }
  }

  Future<void> _createNewRoom(
      BuildContext context, SettingsService settings) async {
    final roomService = context.read<RoomService>();

    try {
      // Generate a unique empty room code
      final newCode = await roomService.generateUniqueRoomCode();

      // Switch to the new room
      settings.setRoomCode(newCode);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created new room: $newCode'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating room: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _joinRoom(
      BuildContext context, SettingsService settings, String code) async {
    final upperCode = code.toUpperCase();

    if (upperCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room code')),
      );
      return;
    }

    if (upperCode.length > 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room code must be 6 characters or less'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Clear the text field
    _roomCodeController.clear();

    // This will trigger the approval system if needed
    settings.setRoomCode(upperCode);

    // Show waiting dialog after a brief delay to allow room service to update
    Future.delayed(const Duration(milliseconds: 100), () {
      if (context.mounted) {
        _showWaitingForApprovalDialog(context, upperCode);
      }
    });
  }

  void _showWaitingForApprovalDialog(BuildContext context, String roomCode) {
    final roomService = context.read<RoomService>();

    // Only show dialog if we're awaiting approval
    if (!roomService.isAwaitingApproval) return;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (dialogContext) => Consumer<RoomService>(
        builder: (context, roomService, child) {
          // If we're no longer awaiting approval, close the dialog
          if (!roomService.isAwaitingApproval) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.canPop(dialogContext)) {
                Navigator.pop(dialogContext);
              }
            });
          }

          return AlertDialog(
            title: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Waiting for Approval',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Requesting to join room $roomCode',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Someone in the room needs to approve your request. This may take a moment...',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (roomService.approvalMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      roomService.approvalMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.7),
                          ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  // Close dialog
                  Navigator.pop(dialogContext);

                  // Generate new room and join it (void method, don't await)
                  _createNewRoom(context, context.read<SettingsService>());
                },
                icon: const Icon(Icons.close),
                label: const Text('Abort & Create New Room'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showForgetKeyDialog(BuildContext context, SettingsService settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Forget Access Key',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        content: Text(
          'Are you sure you want to forget the access key? This will immediately disconnect from other devices and switch to offline mode.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final roomService = context.read<RoomService>();

              // STEP 1: IMMEDIATELY remove access key so any reconnection attempts fail
              await settings.setAccessKey(null);

              // STEP 2: Disable sharing to stop background polling
              await settings.setSharingEnabled(false);

              // STEP 3: Clear room code to prevent auto-rejoin attempts
              await settings.setRoomCode(null);

              // STEP 4: Force multiple disconnection attempts to handle race conditions
              for (int i = 0; i < 3; i++) {
                roomService.resetConnectionState();
                await roomService.disconnect();
                roomService.userChooseGoOffline();

                // Short delay between attempts
                if (i < 2) {
                  await Future.delayed(const Duration(milliseconds: 200));
                }
              }

              // STEP 5: Longer delay to let all async operations complete
              await Future.delayed(const Duration(seconds: 1));

              // STEP 6: Final verification - if still connected, log for debugging
              if (roomService.isConnected || !roomService.isOfflineMode) {
                debugPrint('⚠️ STILL CONNECTED AFTER DISCONNECT ATTEMPTS:');
                debugPrint('  - isConnected: ${roomService.isConnected}');
                debugPrint('  - isOfflineMode: ${roomService.isOfflineMode}');
                debugPrint('  - roomCode: ${roomService.roomCode}');
              }

              Navigator.pop(context);

              // Show confirmation
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.offline_bolt, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(roomService.isOfflineMode
                            ? 'Successfully switched to solo offline mode'
                            : 'Disconnection attempted - restart app if issues persist'),
                      ],
                    ),
                    backgroundColor: roomService.isOfflineMode
                        ? Colors.green
                        : Colors.orange,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
            child: const Text('FORGET'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );
  }
}

// Responsive button row that switches to column layout when buttons don't fit
class _ResponsiveButtonRow extends StatelessWidget {
  const _ResponsiveButtonRow({
    required this.buttons,
    this.alignment = MainAxisAlignment.spaceEvenly,
    this.spacing = 8.0,
  });
  final List<Widget> buttons;
  final MainAxisAlignment alignment;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate approximate button widths to determine if they fit
        final screenWidth = constraints.maxWidth;
        const buttonPadding = 16.0; // Estimated button padding
        const iconWidth = 24.0; // Icon width
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
  const _SectionCard({
    required this.title,
    required this.child,
  });
  final String title;
  final Widget child;

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
  const _SettingsTile({
    required this.title,
    this.subtitle,
    required this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget trailing;

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
  const _PrivacyItem({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

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
