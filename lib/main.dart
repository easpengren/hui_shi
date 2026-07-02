import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'playback/audio_handler.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'state/reader_state.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Media session — lock screen / notification / headset controls for read-aloud.
  final handler = await AudioService.init(
    builder: () => LuJiAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.lu_ji.playback',
      androidNotificationChannelName: 'Lu Ji read-aloud',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => ReaderState(handler)..init(),
      child: const LuJiApp(),
    ),
  );
}

class LuJiApp extends StatelessWidget {
  const LuJiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lu Ji',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (_) => const LibraryScreen(),
        '/reader': (_) => const ReaderScreen(),
      },
    );
  }
}
