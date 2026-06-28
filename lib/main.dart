import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'state/reader_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ReaderState(),
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
        '/': (_) => const ReaderScreen(),
        '/library': (_) => const LibraryScreen(),
      },
    );
  }
}
