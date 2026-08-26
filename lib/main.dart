import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'playback/audio_handler.dart';
import 'playback/notification_permission.dart';
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
  //
  // ## Why this is guarded, and why it must never be un-guarded
  //
  // This `await` sits in front of `runApp`, so until it returns there is no
  // Flutter UI at all — only the LaunchTheme window, which is to say a black
  // screen. Unguarded, ANY failure or hang in the media session became the
  // whole app failing to start, with nothing on screen to say so.
  //
  // That is not hypothetical. Launched from the launcher LuJi opened fine;
  // launched by an explicit ACTION_SEND from Four Books it showed a black
  // window and never recovered. A share arrives with the process and foreground
  // state in a different condition than a launcher tap, and starting a
  // `mediaPlayback` foreground service is exactly the kind of thing Android
  // permits in one and refuses in the other.
  //
  // `LuJiAudioHandler` was already nullable — `ReaderState` calls it through
  // `?.` everywhere — so a failure here costs the media session and nothing
  // else: read-aloud still works while the app is in front, and only
  // background survival, lock-screen controls and the notification are lost.
  // A degraded reader beats a black screen, and the trade is not close.
  //
  // The timeout matters as much as the catch: a hang produces the identical
  // black screen and `catch` alone would wait for it forever.
  LuJiAudioHandler? handler;
  try {
    handler = await AudioService.init(
      builder: LuJiAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.lu_ji.playback',
        androidNotificationChannelName: 'Lu Ji read-aloud',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    ).timeout(const Duration(seconds: 10));
  } catch (error, stack) {
    // Reported, not swallowed silently: without this the degradation is
    // invisible and the next person debugging "why did background playback
    // stop" has nothing to find.
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'lu_ji',
      context: ErrorDescription(
        'AudioService.init failed; continuing without a media session. '
        'Read-aloud will not survive the screen going off.',
      ),
    ));
    handler = null;
  }
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

  // After the first frame, not before it: this can show a system dialog, and
  // one thrown up over a blank window looks like a crash. The permission it
  // asks for is what lets read-aloud survive the screen going off — see
  // playback/notification_permission.dart for why a *notification* permission
  // decides whether audio keeps playing.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    requestNotificationPermission();
  });
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
