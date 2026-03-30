import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme.dart';
import 'services/chat_service.dart';
import 'screens/chat_list_screen.dart';
import 'auth_screen.dart';

/// Entry point: wraps the app with [ThemeProvider] so theme state is available
/// before the first frame, then mounts [MyApp] with a [LocalChatService].
void main() {
  runApp(ThemeProvider(child: MyApp(service: LocalChatService())));
}

/// Root widget: configures [MaterialApp] with theme, localization, and auth gate.
class MyApp extends StatelessWidget {
  final ChatService service;
  const MyApp({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messenger',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeProvider.of(context).themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru', 'RU'),
        Locale('en', 'US'),
        Locale('kk', 'KZ'),
      ],
      home: AuthGate(homeScreen: ChatListScreen(service: service)),
    );
  }
}
