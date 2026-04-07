import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme.dart';
import 'services/chat_service.dart';
import 'responsive_shell.dart';
import 'auth_screen.dart';

/// Точка входа: оборачивает приложение в [ThemeProvider], чтобы состояние темы
/// было доступно до первого кадра, затем монтирует [MyApp] с [LocalChatService].
void main() {
  runApp(ThemeProvider(child: MyApp(service: LocalChatService())));
}

/// Корневой виджет: настраивает [MaterialApp] с темой, локализацией и авторизационным шлюзом.
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
      home: AuthGate(homeScreen: ResponsiveShell(service: service)),
    );
  }
}
