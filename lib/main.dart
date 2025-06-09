import 'package:closed_caption_companion/screens/home_screen.dart';
import 'package:closed_caption_companion/services/audio_streaming_service.dart';
import 'package:closed_caption_companion/services/caption_service.dart';
import 'package:closed_caption_companion/services/room_service.dart';
import 'package:closed_caption_companion/services/settings_service.dart';
import 'package:closed_caption_companion/utils/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Lock orientation to portrait for better accessibility
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize services
  final settingsService = SettingsService();
  await settingsService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => settingsService),
        ChangeNotifierProvider(create: (_) => CaptionService()),
        Provider(create: (_) => AudioStreamingService()),
        ChangeNotifierProvider(create: (_) => RoomService()),
      ],
      child: const CCCApp(),
    ),
  );
}

class CCCApp extends StatelessWidget {
  const CCCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'Closed-Caption Companion',
          debugShowCheckedModeBanner: false,

          // Theme configuration
          theme: ThemeConfig.getLightTheme(),
          darkTheme: ThemeConfig.getDarkTheme(),
          themeMode: settings.themeMode,

          // Accessibility
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(
                    0.9), // Aggressive text scaling for compactness
              ),
              child: child!,
            );
          },

          home: const HomeScreen(),
        );
      },
    );
  }
}
