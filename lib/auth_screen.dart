import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ─────────────────────────────────────────────────────────────────────────────
// pubspec.yaml:
//   dependencies:
//     flutter_secure_storage: ^9.2.2
//
// android/app/build.gradle:
//   minSdkVersion 18
// ─────────────────────────────────────────────────────────────────────────────

// ─── Список учебных групп колледжа ───────────────────────────────────────────
// Публичная константа — используется в auth_screen и profile_screen

const kCollegeGroups = <String>[
  'ИС-21', 'ИС-22', 'ИС-23', 'ИС-24',
  'ПИ-21', 'ПИ-22', 'ПИ-23', 'ПИ-24',
  'КБ-21', 'КБ-22', 'КБ-23',
  'ВТ-21', 'ВТ-22', 'ВТ-23',
  'МТ-21', 'МТ-22', 'МТ-23',
  'ЭМ-21', 'ЭМ-22', 'ЭМ-23',
  'БУ-21', 'БУ-22',
  'ТУ-21', 'ТУ-22',
  'ДИ-21', 'ДИ-22',
];

// ─── Ключи хранилища ─────────────────────────────────────────────────────────

class _StorageKeys {
  const _StorageKeys._();

  static const isLoggedIn = 'is_logged_in';
  static const userName = 'user_name';
  static const userLogin = 'user_login';
  static const registeredName = 'registered_name';
  static const registeredLogin = 'registered_login';
  static const registeredPassword = 'registered_password';
  static const registeredGroup = 'user_group';   // совпадает с ProfileStorage._keyGroup
  static const registeredPhone = 'user_phone';   // совпадает с ProfileStorage._keyPhone
  static const allRegisteredPhones = 'all_registered_phones'; // список всех зарег. номеров
}

// ─── Сервис авторизации ───────────────────────────────────────────────────────

class AuthService {
  static final _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<void> saveSession({
    required String name,
    required String login,
  }) async {
    await _storage.write(key: _StorageKeys.isLoggedIn, value: 'true');
    await _storage.write(key: _StorageKeys.userName, value: name);
    await _storage.write(key: _StorageKeys.userLogin, value: login);
  }

  static Future<bool> isLoggedIn() async {
    final value = await _storage.read(key: _StorageKeys.isLoggedIn);
    return value == 'true';
  }

  static Future<Map<String, String>> getUser() async {
    final name = await _storage.read(key: _StorageKeys.userName) ?? '';
    final login = await _storage.read(key: _StorageKeys.userLogin) ?? '';
    return {'name': name, 'login': login};
  }

  static Future<void> saveRegistration({
    required String name,
    required String login,
    required String password,
    required String group,
    required String phone,
  }) async {
    await _storage.write(key: _StorageKeys.registeredName, value: name);
    await _storage.write(key: _StorageKeys.registeredLogin, value: login);
    await _storage.write(key: _StorageKeys.registeredPassword, value: password);
    await _storage.write(key: _StorageKeys.registeredGroup, value: group);
    await _storage.write(key: _StorageKeys.registeredPhone, value: phone);
    await addRegisteredPhone(phone); // добавляем в общий реестр
  }

  // ── Нормализация номера (только цифры) ───────────────────────────────────
  static String normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'\D'), '');

  // ── Реестр зарегистрированных номеров ─────────────────────────────────────
  // Хранит все номера, когда-либо зарегистрированные на устройстве.
  // В реальном приложении это был бы серверный запрос.

  static Future<void> addRegisteredPhone(String phone) async {
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) return;
    final existing =
        await _storage.read(key: _StorageKeys.allRegisteredPhones) ?? '';
    final phones =
        existing.isEmpty ? <String>[] : existing.split(',');
    if (!phones.contains(normalized)) {
      phones.add(normalized);
      await _storage.write(
          key: _StorageKeys.allRegisteredPhones,
          value: phones.join(','));
    }
  }

  static Future<Set<String>> getRegisteredPhones() async {
    final stored =
        await _storage.read(key: _StorageKeys.allRegisteredPhones) ?? '';
    if (stored.isEmpty) return {};
    return stored.split(',').toSet();
  }

  static Future<bool> checkCredentials({
    required String login,
    required String password,
  }) async {
    final savedLogin =
        await _storage.read(key: _StorageKeys.registeredLogin) ?? '';
    final savedPassword =
        await _storage.read(key: _StorageKeys.registeredPassword) ?? '';
    return login.trim() == savedLogin && password == savedPassword;
  }

  static Future<String> getRegisteredName() async {
    return await _storage.read(key: _StorageKeys.registeredName) ?? '';
  }

  static Future<void> logout() async {
    await _storage.delete(key: _StorageKeys.isLoggedIn);
    await _storage.delete(key: _StorageKeys.userName);
    await _storage.delete(key: _StorageKeys.userLogin);
  }

  // Методы для хранения произвольных данных профиля (используются ProfileStorage)
  static Future<String?> readExtra(String key) async {
    return await _storage.read(key: key);
  }

  static Future<void> writeExtra(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  static Future<void> deleteExtra(String key) async {
    await _storage.delete(key: key);
  }
}

// ─── AuthGate — точка входа в приложение ─────────────────────────────────────
//
// Используется в main.dart как home:
//   home: AuthGate(homeScreen: const ChatListScreen()),
//
// При запуске проверяет сохранённую сессию:
//   - есть сессия  → сразу открывает homeScreen
//   - нет сессии   → показывает AuthScreen

class AuthGate extends StatelessWidget {
  final Widget homeScreen;

  const AuthGate({super.key, required this.homeScreen});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthService.isLoggedIn(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        if (snapshot.data == true) return homeScreen;
        return AuthScreen(
          onLoginSuccess: () {
            // После успешного входа заменяем AuthScreen на homeScreen
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => homeScreen),
              (_) => false,
            );
          },
        );
      },
    );
  }
}

// ─── Сплэш ───────────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFF6F00),
      body: Center(
        child: Icon(Icons.chat_bubble_rounded, size: 64, color: Colors.white),
      ),
    );
  }
}

// ─── Экран авторизации ────────────────────────────────────────────────────────

class AuthScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;

  const AuthScreen({super.key, this.onLoginSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final subtleColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 48),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6F00),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Messenger',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Войдите или создайте аккаунт',
                style: TextStyle(fontSize: 14, color: subtleColor),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: const Color(0xFFFF6F00),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFF757575),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Вход'),
                    Tab(text: 'Регистрация'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 640,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _LoginForm(
                      tabController: _tabController,
                      onLoginSuccess: widget.onLoginSuccess ?? () {},
                    ),
                    _RegisterForm(tabController: _tabController),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Форма входа ──────────────────────────────────────────────────────────────

class _LoginForm extends StatefulWidget {
  final TabController tabController;
  final VoidCallback onLoginSuccess;

  const _LoginForm({
    required this.tabController,
    required this.onLoginSuccess,
  });

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _usePhone = false;
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final ok = await AuthService.checkCredentials(
      login: _loginController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (ok) {
      final name = await AuthService.getRegisteredName();
      await AuthService.saveSession(
        name: name,
        login: _loginController.text.trim(),
      );
      if (!mounted) return;
      // Сообщаем родителю — он сам откроет нужный экран
      widget.onLoginSuccess();
    } else {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Неверный логин или пароль'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _LoginToggle(
            usePhone: _usePhone,
            onChanged: (val) => setState(() {
              _usePhone = val;
              _loginController.clear();
            }),
          ),
          const SizedBox(height: 16),
          if (_usePhone)
            _PhoneField(controller: _loginController)
          else
            _AuthField(
              controller: _loginController,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
            ),
          const SizedBox(height: 16),
          _AuthField(
            controller: _passwordController,
            label: 'Пароль',
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            suffixIcon: _VisibilityButton(
              obscure: _obscurePassword,
              onTap: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 24),
          _AuthButton(
            label: 'Войти',
            isLoading: _isLoading,
            onPressed: _submit,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => widget.tabController.animateTo(1),
            child: const Text(
              'Нет аккаунта? Зарегистрироваться',
              style: TextStyle(color: Color(0xFFFF6F00)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Форма регистрации ────────────────────────────────────────────────────────

class _RegisterForm extends StatefulWidget {
  final TabController tabController;

  const _RegisterForm({required this.tabController});

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _selectedGroup;
  bool _groupTouched = false; // показывать ошибку группы только после первой попытки сабмита

  bool _usePhone = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _groupTouched = true);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedGroup == null) return; // группа обязательна
    setState(() => _isLoading = true);

    await AuthService.saveRegistration(
      name: _nameController.text.trim(),
      login: _loginController.text.trim(),
      password: _passwordController.text,
      group: _selectedGroup!,
      phone: _phoneController.text.trim(),
    );

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    setState(() => _isLoading = false);
    widget.tabController.animateTo(0);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Аккаунт создан! Теперь войдите.'),
        backgroundColor: Color(0xFFFF6F00),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _AuthField(
            controller: _nameController,
            label: 'Имя пользователя',
            icon: Icons.person_outline,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
          ),
          const SizedBox(height: 12),
          _GroupSelectField(
            value: _selectedGroup,
            showError: _groupTouched && _selectedGroup == null,
            onChanged: (g) => setState(() => _selectedGroup = g),
          ),
          const SizedBox(height: 12),
          _PhoneField(controller: _phoneController),
          const SizedBox(height: 12),
          _LoginToggle(
            usePhone: _usePhone,
            onChanged: (val) => setState(() {
              _usePhone = val;
              _loginController.clear();
            }),
          ),
          const SizedBox(height: 12),
          if (_usePhone)
            _PhoneField(controller: _loginController)
          else
            _AuthField(
              controller: _loginController,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
            ),
          const SizedBox(height: 12),
          _AuthField(
            controller: _passwordController,
            label: 'Пароль',
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            suffixIcon: _VisibilityButton(
              obscure: _obscurePassword,
              onTap: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 12),
          _AuthField(
            controller: _confirmController,
            label: 'Подтвердите пароль',
            icon: Icons.lock_outline,
            obscureText: _obscureConfirm,
            suffixIcon: _VisibilityButton(
              obscure: _obscureConfirm,
              onTap: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            validator: (v) => v != _passwordController.text
                ? 'Пароли не совпадают'
                : null,
          ),
          const SizedBox(height: 20),
          _AuthButton(
            label: 'Зарегистрироваться',
            isLoading: _isLoading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

// ─── Переключатель Email / Телефон ────────────────────────────────────────────

class _LoginToggle extends StatelessWidget {
  final bool usePhone;
  final ValueChanged<bool> onChanged;

  const _LoginToggle({required this.usePhone, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ToggleChip(
          label: 'Email',
          icon: Icons.email_outlined,
          selected: !usePhone,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 8),
        _ToggleChip(
          label: 'Телефон',
          icon: Icons.phone_outlined,
          selected: usePhone,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor   = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final subtleColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF6F00) : cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFFFF6F00) : borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16,
                color: selected ? Colors.white : subtleColor),
            const SizedBox(width: 6),
            Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : subtleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Поле телефона ────────────────────────────────────────────────────────────

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;

  const _PhoneField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
        LengthLimitingTextInputFormatter(16),
      ],
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Введите номер телефона';
        final digits = v.replaceAll(RegExp(r'\D'), '');
        if (digits.length < 10) return 'Некорректный номер';
        return null;
      },
      decoration: _inputDecoration(
        'Номер телефона', Icons.phone_outlined,
        Theme.of(context).cardColor,
        hintText: '+7 (999) 000-00-00',
      ),
    );
  }
}

// ─── Общие виджеты ────────────────────────────────────────────────────────────

InputDecoration _inputDecoration(
  String label,
  IconData icon,
  Color fillColor, {
  String? hintText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    prefixIcon: Icon(icon, color: const Color(0xFFFF6F00)),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: fillColor,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFFF6F00), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
    ),
  );
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _AuthField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: _inputDecoration(
        label, icon, Theme.of(context).cardColor,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class _VisibilityButton extends StatelessWidget {
  final bool obscure;
  final VoidCallback onTap;

  const _VisibilityButton({required this.obscure, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscure ? Icons.visibility_off : Icons.visibility,
        color: const Color(0xFF757575),
      ),
      onPressed: onTap,
    );
  }
}

class _AuthButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  const _AuthButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFF6F00),
          disabledBackgroundColor:
              const Color(0xFFFF6F00).withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

// ─── Поле выбора группы ───────────────────────────────────────────────────────

class _GroupSelectField extends StatelessWidget {
  final String? value;
  final bool showError;
  final ValueChanged<String?> onChanged;

  const _GroupSelectField({
    required this.value,
    required this.showError,
    required this.onChanged,
  });

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GroupPickerSheet(current: value),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final cardColor   = Theme.of(context).cardColor;
    final subtleColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return GestureDetector(
      onTap: () => _openPicker(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: showError
                  ? Border.all(color: const Color(0xFFE53935), width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                const Icon(Icons.school_outlined, color: Color(0xFFFF6F00), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasValue ? value! : 'Учебная группа',
                    style: TextStyle(
                      fontSize: 16,
                      color: hasValue ? null : subtleColor,
                    ),
                  ),
                ),
                Icon(Icons.expand_more, color: subtleColor),
              ],
            ),
          ),
          if (showError)
            const Padding(
              padding: EdgeInsets.only(left: 12, top: 6),
              child: Text(
                'Выберите учебную группу',
                style: TextStyle(fontSize: 12, color: Color(0xFFE53935)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Нижний лист выбора группы ────────────────────────────────────────────────

class _GroupPickerSheet extends StatefulWidget {
  final String? current;
  const _GroupPickerSheet({this.current});

  @override
  State<_GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<_GroupPickerSheet> {
  final _searchController = TextEditingController();
  List<String> _filtered = kCollegeGroups;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchController.text.trim().toUpperCase();
    setState(() {
      _filtered = q.isEmpty
          ? kCollegeGroups
          : kCollegeGroups.where((g) => g.toUpperCase().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return SizedBox(
      height: screenH * 0.7,
      child: Column(
        children: [
          // ── Ручка ────────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Учебная группа',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          // ── Поиск ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Поиск…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // ── Список групп ─────────────────────────────────────────
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('Группа не найдена',
                        style: TextStyle(color: Color(0xFF757575))),
                  )
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final group = _filtered[i];
                      final isSelected = group == widget.current;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? const Color(0xFFFF6F00)
                              : Theme.of(context).scaffoldBackgroundColor,
                          child: Text(
                            group.split('-').first,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF757575),
                            ),
                          ),
                        ),
                        title: Text(
                          group,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: Color(0xFFFF6F00))
                            : null,
                        onTap: () => Navigator.pop(context, group),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Валидаторы ───────────────────────────────────────────────────────────────

String? _validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Введите email';
  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
  if (!emailRegex.hasMatch(value.trim())) return 'Некорректный email';
  return null;
}

String? _validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Введите пароль';
  if (value.length < 6) return 'Минимум 6 символов';
  return null;
}
