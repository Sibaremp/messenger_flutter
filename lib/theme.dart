import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_constants.dart';

/// User-selectable theme preference (persisted in SharedPreferences).
enum AppThemeMode { light, dark, system }

/// Static factory for the app's light and dark [ThemeData] objects.
class AppTheme {
  static ThemeData get light => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.textLight,
      elevation: 0,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: Brightness.light,
    ),
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE0E0E0),
  );

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1F1F1F),
      foregroundColor: AppColors.textLight,
      elevation: 0,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: Brightness.dark,
    ),
    cardColor: const Color(0xFF1E1E1E),
    dividerColor: const Color(0xFF2C2C2C),
  );
}

/// Wraps the widget tree with theme state and exposes [ThemeProvider.of] for
/// descendants to read or change the active theme.
class ThemeProvider extends StatefulWidget {
  final Widget child;
  const ThemeProvider({super.key, required this.child});

  /// Retrieves the nearest [ThemeProviderState] from the widget tree.
  static ThemeProviderState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ThemeInherited>()!.state;

  @override
  State<ThemeProvider> createState() => ThemeProviderState();
}

class ThemeProviderState extends State<ThemeProvider> {
  AppThemeMode _mode = AppThemeMode.system;
  static const _key = 'app_theme_mode';

  AppThemeMode get mode => _mode;

  ThemeMode get themeMode => switch (_mode) {
    AppThemeMode.light  => ThemeMode.light,
    AppThemeMode.dark   => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads the persisted theme preference; falls back to [AppThemeMode.system].
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    final mode  = AppThemeMode.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => AppThemeMode.system,
    );
    if (mounted) setState(() => _mode = mode);
  }

  Future<void> setMode(AppThemeMode mode) async {
    setState(() => _mode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  @override
  Widget build(BuildContext context) =>
      _ThemeInherited(state: this, mode: _mode, child: widget.child);
}

class _ThemeInherited extends InheritedWidget {
  final ThemeProviderState state;
  final AppThemeMode mode;

  const _ThemeInherited({
    required this.state,
    required this.mode,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ThemeInherited old) => old.mode != mode;
}
