import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'playback/audio_handler.dart';
import 'screens/app_update_ui.dart';
import 'screens/about_screen.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/settings_screen.dart';
import 'state/reader_state.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The media session, and with it the foreground service that keeps
  // read-aloud alive once the screen goes off. Without this Android suspends
  // the app and playback simply stops mid-sentence.
  final handler = await AudioService.init(
    builder: LuJiAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.lu_ji.playback',
      androidNotificationChannelName: 'Lu Ji read-aloud',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(
    ChangeNotifierProvider(
      // #97: pick up text shared from another app — Confucius sends extracted
      // article prose here. `listenForSharedText` covers a share arriving while
      // LuJi is already running, which never goes through a cold start.
      create: (_) => ReaderState(handler: handler)
        ..listenForSharedText()
        ..consumeSharedText(),
      child: const LuJiApp(),
    ),
  );
}

class LuJiApp extends StatefulWidget {
  const LuJiApp({super.key});

  @override
  State<LuJiApp> createState() => _LuJiAppState();
}

class _LuJiAppState extends State<LuJiApp> {
  /// Lets the launch update-check find a context under the MaterialApp without
  /// belonging to any one screen.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // At app start, not on a screen. This check used to live in
    // LibraryScreen.initState — which is where it sits on the other lineage,
    // where '/' IS the library. Here '/' is the reader, so it only ran if you
    // happened to open the library, which is to say usually never.
    //
    // Quiet: silent when already current or when the network is unavailable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _navigatorKey.currentContext;
      if (context != null) checkAndOfferUpdate(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderState>(
      builder: (context, state, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Lu Ji',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: state.themeMode,
        initialRoute: '/',
        routes: {
          '/': (_) => const ReaderScreen(),
          '/library': (_) => const LibraryScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/about': (_) => const AboutScreen(),
        },
      ),
    );
  }
}
