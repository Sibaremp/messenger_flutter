import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'theme.dart';
import 'services/chat_service.dart';
import 'services/auth_service.dart';
import 'services/api_chat_service.dart';
import 'responsive_shell.dart';
import 'auth_screen.dart';

/// Точка входа: оборачивает приложение в [ThemeProvider], чтобы состояние темы
/// было доступно до первого кадра, затем монтирует [MyApp] с выбранным бэкендом.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final auth = AuthService();
  await auth.tryRestoreSession();
  final ChatService service = ApiChatService(auth);

  runApp(ThemeProvider(child: MyApp(service: service, auth: auth)));
}

/// Корневой виджет: настраивает [MaterialApp] с темой, локализацией и авторизационным шлюзом.
class MyApp extends StatelessWidget {
  final ChatService service;
  final AuthService auth;
  const MyApp({super.key, required this.service, required this.auth});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caspian Messenger',
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
      home: AuthGate(
        auth: auth,
        homeScreen: ResponsiveShell(service: service, auth: auth),
      ),
    );
  }
}
