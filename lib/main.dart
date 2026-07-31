import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/about_screen.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/settings_screen.dart';
import 'state/reader_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      // #97: pick up text shared from another app — Confucius sends extracted
      // article prose here. `listenForSharedText` covers a share arriving while
      // LuJi is already running, which never goes through a cold start.
      create: (_) => ReaderState()
        ..listenForSharedText()
        ..consumeSharedText(),
      child: const LuJiApp(),
    ),
  );
}

class LuJiApp extends StatelessWidget {
  const LuJiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderState>(
      builder: (context, state, _) => MaterialApp(
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
