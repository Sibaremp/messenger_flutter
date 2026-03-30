import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme.dart';
import 'services/chat_service.dart';
import 'screens/chat_list_screen.dart';
import 'auth_screen.dart';

void main() {
  runApp(ThemeProvider(child: MyApp(service: LocalChatService())));
}

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
