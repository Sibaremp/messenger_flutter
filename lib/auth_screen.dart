import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/sim_service.dart';
import 'services/auth_service.dart' as svc;
import 'theme.dart' show ThemeProvider, AppThemeMode;

// ─── AuthGate — точка входа в приложение ─────────────────────────────────────
//
// При запуске проверяет сохранённую сессию:
//   - есть сессия  → сразу открывает homeScreen
//   - нет сессии   → показывает AuthScreen

class AuthGate extends StatelessWidget {
  final Widget homeScreen;
  final svc.AuthService auth;

  const AuthGate({super.key, required this.homeScreen, required this.auth});

  @override
  Widget build(BuildContext context) {
    // Если сессия восстановлена в main.dart, сразу открываем чат
    if (auth.currentUser != null) return homeScreen;
    return AuthScreen(
      auth: auth,
      onLoginSuccess: () {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => homeScreen),
          (_) => false,
        );
      },
    );
  }
}

// ─── Экран авторизации ────────────────────────────────────────────────────────

class AuthScreen extends StatefulWidget {
  final svc.AuthService auth;
  final VoidCallback? onLoginSuccess;

  const AuthScreen({super.key, required this.auth, this.onLoginSuccess});

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenW = MediaQuery.of(context).size.width;
    final isDesktop = screenW > 600;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 440.0 : double.infinity),
            child: Column(
              children: [
                // ── Шапка ──────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(24, isDesktop ? 24 : 48, 24, 0),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4765B),
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
                        'Caspian Messenger',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Войдите или создайте аккаунт',
                        style: TextStyle(fontSize: 14, color: subtleColor),
                      ),
                      const SizedBox(height: 24),
                      // ── Табы + кнопка темы ─────────────────
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                indicator: BoxDecoration(
                                  color: const Color(0xFFD4765B),
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
                          ),
                          const SizedBox(width: 12),
                          // Переключатель темы
                          GestureDetector(
                            onTap: () {
                              final tp = ThemeProvider.of(context);
                              final next = isDark ? AppThemeMode.light : AppThemeMode.dark;
                              tp.setMode(next);
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                                color: const Color(0xFFD4765B),
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ── Форма (скроллируется) ──────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: _LoginForm(
                          auth: widget.auth,
                          tabController: _tabController,
                          onLoginSuccess: widget.onLoginSuccess ?? () {},
                        ),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: _RegisterForm(
                          auth: widget.auth,
                          tabController: _tabController,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Форма входа ──────────────────────────────────────────────────────────────

class _LoginForm extends StatefulWidget {
  final svc.AuthService auth;
  final TabController tabController;
  final VoidCallback onLoginSuccess;

  const _LoginForm({
    required this.auth,
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

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _snack(String text, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await widget.auth.login(
        name: _loginController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      widget.onLoginSuccess();
    } on svc.AuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack(e.message, color: Colors.red[700]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Ошибка подключения к серверу', color: Colors.red[700]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _AuthField(
            controller: _loginController,
            label: 'Имя пользователя',
            icon: Icons.person_outline,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
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
              style: TextStyle(color: Color(0xFFD4765B)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Форма регистрации ────────────────────────────────────────────────────────

class _RegisterForm extends StatefulWidget {
  final svc.AuthService auth;
  final TabController tabController;

  const _RegisterForm({required this.auth, required this.tabController});

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  String? _selectedGroup;
  String _selectedRole = 'student';
  bool _groupTouched = false;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _simLoading = false;

  /// Группы, загруженные с сервера.
  List<String> _serverGroups = [];
  bool _groupsLoading = true;
  String? _groupsError;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _groupsLoading = true;
      _groupsError = null;
    });
    try {
      final groups = await widget.auth.loadGroups();
      if (!mounted) return;
      setState(() {
        _serverGroups = groups;
        _groupsLoading = false;
        _groupsError = groups.isEmpty ? 'Список групп пуст' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groupsLoading = false;
        _groupsError = 'Не удалось загрузить группы. Проверьте подключение.';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ── Чтение номера из SIM ─────────────────────────────────────────────────

  Future<void> _fillFromSim({TextEditingController? target}) async {
    final ctrl = target ?? _phoneController;
    setState(() => _simLoading = true);
    final result = await SimService.fetchSimCards();
    if (!mounted) return;
    setState(() => _simLoading = false);

    switch (result.status) {
      case SimResult.unsupported:
        _snack('Определение номера SIM недоступно на этой платформе');
      case SimResult.permissionDenied:
        _snack('Нет доступа к данным телефона');
      case SimResult.permissionPermanentlyDenied:
        _snack(
          'Разрешение отклонено. Откройте настройки приложения.',
          action: SnackBarAction(
            label: 'Настройки',
            onPressed: SimService.openSettings,
          ),
        );
      case SimResult.noSimFound:
        _snack('SIM-карта не обнаружена или не вставлена');
      case SimResult.error:
        _snack('Ошибка: ${result.errorMessage ?? "неизвестная"}');
      case SimResult.success:
        final sims = result.simCards;
        if (sims.length == 1) {
          _applySimCard(sims.first, ctrl);
        } else {
          _showSimPickerDialog(sims, ctrl);
        }
    }
  }

  void _applySimCard(SimCard sim, TextEditingController ctrl) {
    if (sim.phoneNumber?.isNotEmpty == true) {
      ctrl.text = sim.phoneNumber!;
      _snack('Номер получен: ${sim.phoneNumber} (${sim.displayInfo})');
    } else {
      _snack('Оператор: ${sim.displayInfo}. Введите номер вручную.');
    }
  }

  void _showSimPickerDialog(List<SimCard> sims, TextEditingController ctrl) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Выберите SIM-карту',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...sims.map((sim) => ListTile(
              leading: const Icon(Icons.sim_card_outlined, color: Color(0xFFD4765B)),
              title: Text(sim.slotLabel),
              subtitle: Text(sim.displayInfo),
              trailing: sim.phoneNumber != null
                  ? Text(sim.phoneNumber!, style: const TextStyle(fontSize: 13))
                  : const Text('номер неизвестен',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _applySimCard(sim, ctrl);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _snack(String text, {SnackBarAction? action, Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      action: action,
    ));
  }

  Future<void> _submit() async {
    setState(() => _groupTouched = true);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRole == 'student' && _selectedGroup == null) return;

    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    if (phone.isEmpty && email.isEmpty) {
      _snack('Укажите телефон или email', color: Colors.red[700]);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.auth.register(
        name: _nameController.text.trim(),
        password: _passwordController.text,
        role: _selectedRole,
        group: _selectedGroup,
        phone: phone.isNotEmpty ? phone : null,
        email: email.isNotEmpty ? email : null,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
      widget.tabController.animateTo(0);
      _snack('Аккаунт создан! Теперь войдите.', color: const Color(0xFFD4765B));
    } on svc.AuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack(e.message, color: Colors.red[700]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Ошибка подключения к серверу', color: Colors.red[700]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // ── Выбор роли ─────────────────────────────────────────
          _AuthRoleSelector(
            value: _selectedRole,
            onChanged: (r) => setState(() {
              _selectedRole = r;
              if (r == 'teacher') _selectedGroup = null;
            }),
          ),
          const SizedBox(height: 12),
          _AuthField(
            controller: _nameController,
            label: 'Имя пользователя',
            icon: Icons.person_outline,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
          ),
          // Учебная группа — только для студентов
          if (_selectedRole == 'student') ...[
            const SizedBox(height: 12),
            _GroupSelectField(
              value: _selectedGroup,
              showError: _groupTouched && _selectedGroup == null,
              groups: _serverGroups,
              isLoading: _groupsLoading,
              errorText: _groupsError,
              onRetry: _loadGroups,
              onChanged: (g) => setState(() => _selectedGroup = g),
            ),
          ],
          // Поле телефона — только на Android (через SIM-карту)
          if (SimService.isSupported) ...[
            const SizedBox(height: 12),
            _PhoneField(
              controller: _phoneController,
              onSimTap: () => _fillFromSim(target: _phoneController),
              simLoading: _simLoading,
            ),
          ],
          // ── Email (альтернатива телефону) ─────────────────────
          const SizedBox(height: 12),
          _AuthField(
            controller: _emailController,
            label: SimService.isSupported
                ? 'Email (или телефон выше)'
                : 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final email = v.trim();
              final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              if (!re.hasMatch(email)) return 'Некорректный email';
              return null;
            },
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

// ─── Валидаторы ──────────────────────────────────────────────────────────────

String? _validatePassword(String? v) {
  if (v == null || v.isEmpty) return 'Введите пароль';
  if (v.length < 6) return 'Минимум 6 символов';
  return null;
}

// ─── Поле телефона ────────────────────────────────────────────────────────────

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onSimTap;
  final bool simLoading;

  const _PhoneField({
    required this.controller,
    this.onSimTap,
    this.simLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final hint = SimService.canReadNumber
        ? 'Нажмите SIM для заполнения'
        : '+7 (999) 000-00-00';

    final base = _inputDecoration(
      'Номер телефона', Icons.phone_outlined,
      Theme.of(context).cardColor,
      hintText: hint,
    );

    final decoration = (onSimTap != null && SimService.isSupported)
        ? base.copyWith(
            suffixIcon: simLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.sim_card_outlined),
                    tooltip: SimService.canReadNumber
                        ? 'Заполнить из SIM-карты'
                        : 'Показать оператора',
                    onPressed: onSimTap,
                  ),
          )
        : base;

    final isReadOnly = SimService.canReadNumber;

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      readOnly: isReadOnly,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
        LengthLimitingTextInputFormatter(16),
      ],
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        final digits = v.replaceAll(RegExp(r'\D'), '');
        if (digits.length < 10) return 'Некорректный номер';
        return null;
      },
      decoration: decoration,
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
    prefixIcon: Icon(icon, color: const Color(0xFFD4765B)),
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
      borderSide: const BorderSide(color: Color(0xFFD4765B), width: 1.5),
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
          backgroundColor: const Color(0xFFD4765B),
          disabledBackgroundColor:
              const Color(0xFFD4765B).withValues(alpha: 0.6),
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
  final List<String> groups;
  final bool isLoading;
  final String? errorText;
  final VoidCallback? onRetry;
  final ValueChanged<String?> onChanged;

  const _GroupSelectField({
    required this.value,
    required this.showError,
    required this.groups,
    required this.isLoading,
    required this.onChanged,
    this.errorText,
    this.onRetry,
  });

  Future<void> _openPicker(BuildContext context) async {
    if (isLoading) return;
    if (groups.isEmpty) {
      // Группы не загружены — пытаемся перезагрузить
      onRetry?.call();
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GroupPickerSheet(current: value, groups: groups),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final cardColor   = Theme.of(context).cardColor;
    final subtleColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final hasLoadError = !isLoading && groups.isEmpty && errorText != null;
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
              border: (showError || hasLoadError)
                  ? Border.all(color: const Color(0xFFE53935), width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                const Icon(Icons.school_outlined, color: Color(0xFFD4765B), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: isLoading
                      ? const Text('Загрузка групп...',
                          style: TextStyle(fontSize: 16, color: Color(0xFF757575)))
                      : Text(
                          hasValue ? value! : 'Учебная группа',
                          style: TextStyle(
                            fontSize: 16,
                            color: hasValue ? null : subtleColor,
                          ),
                        ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (hasLoadError)
                  const Icon(Icons.refresh, color: Color(0xFFE53935))
                else
                  Icon(Icons.expand_more, color: subtleColor),
              ],
            ),
          ),
          if (hasLoadError)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 6),
              child: Text(
                '${errorText!} Нажмите, чтобы повторить.',
                style: const TextStyle(fontSize: 12, color: Color(0xFFE53935)),
              ),
            )
          else if (showError)
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
  final List<String> groups;
  const _GroupPickerSheet({this.current, required this.groups});

  @override
  State<_GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<_GroupPickerSheet> {
  final _searchController = TextEditingController();
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.groups;
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
          ? widget.groups
          : widget.groups.where((g) => g.toUpperCase().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return SizedBox(
      height: screenH * 0.7,
      child: Column(
        children: [
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Поиск...',
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
                              ? const Color(0xFFD4765B)
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
                                color: Color(0xFFD4765B))
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

// ─── Выбор роли при регистрации ────────────────────────────────────────────────

class _AuthRoleSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _AuthRoleSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AuthRoleChip(
          label: 'Студент',
          icon: Icons.person_outline,
          selected: value == 'student',
          onTap: () => onChanged('student'),
        ),
        const SizedBox(width: 8),
        _AuthRoleChip(
          label: 'Преподаватель',
          icon: Icons.school,
          selected: value == 'teacher',
          onTap: () => onChanged('teacher'),
        ),
      ],
    );
  }
}

class _AuthRoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AuthRoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,

        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFD4765B)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFFD4765B)
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18,
                  color: selected ? Colors.white : const Color(0xFF757575)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF757575),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

