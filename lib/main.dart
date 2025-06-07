import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/caption_service.dart';
import 'services/settings_service.dart';
import 'services/audio_streaming_service.dart';
import 'utils/theme_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      ],
      child: const CCCApp(),
    ),
  );
}

class CCCApp extends StatelessWidget {
  const CCCApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'Closed-Caption Companion',
          debugShowCheckedModeBanner: false,

          // Theme configuration
          theme: ThemeConfig.getLightTheme(settings.fontSize),
          darkTheme: ThemeConfig.getDarkTheme(settings.fontSize),
          themeMode: settings.themeMode,

          // Accessibility
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaleFactor: 1.0, // Prevent system text scaling
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
