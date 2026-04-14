import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme.dart';
import 'services/chat_service.dart';
import 'services/auth_service.dart' as svc;
import 'services/api_chat_service.dart';
import 'responsive_shell.dart';
import 'auth_screen.dart';

/// Режим работы приложения: локальный (in-memory) или серверный (REST + SignalR).
enum _BackendMode { local, api }

const _mode = _BackendMode.api;

/// Точка входа: оборачивает приложение в [ThemeProvider], чтобы состояние темы
/// было доступно до первого кадра, затем монтирует [MyApp] с выбранным бэкендом.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final ChatService service;
  switch (_mode) {
    case _BackendMode.local:
      service = LocalChatService();
    case _BackendMode.api:
      final auth = svc.AuthService();
      await auth.tryRestoreSession();
      service = ApiChatService(auth);
  }

  runApp(ThemeProvider(child: MyApp(service: service)));
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
