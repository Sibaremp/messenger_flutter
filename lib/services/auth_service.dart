import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Данные текущего пользователя, полученные после аутентификации.
class AuthUser {
  final String id;
  final String name;
  final String? group;
  final String? phone;
  final String role; // 'student' | 'teacher'
  final String token;

  const AuthUser({
    required this.id,
    required this.name,
    this.group,
    this.phone,
    required this.role,
    required this.token,
  });

  bool get isTeacher => role == 'teacher';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (group != null) 'group': group,
    if (phone != null) 'phone': phone,
    'role': role,
    'token': token,
  };

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id: j['id'] as String,
    name: j['name'] as String,
    group: j['group'] as String?,
    phone: j['phone'] as String?,
    role: j['role'] as String? ?? 'student',
    token: j['token'] as String,
  );
}

/// Сервис аутентификации: регистрация, вход, хранение токена.
class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  AuthUser? _currentUser;

  /// Текущий авторизованный пользователь (null — не авторизован).
  AuthUser? get currentUser => _currentUser;

  /// JWT-токен для заголовка Authorization.
  String? get token => _currentUser?.token;

  /// HTTP-заголовки с авторизацией.
  Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// Попытка восстановить сессию из secure storage.
  Future<bool> tryRestoreSession() async {
    final userJson = await _storage.read(key: _userKey);
    if (userJson == null) return false;
    try {
      _currentUser = AuthUser.fromJson(
        jsonDecode(userJson) as Map<String, dynamic>,
      );
      return true;
    } catch (_) {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
      return false;
    }
  }

  /// Регистрация нового пользователя.
  Future<AuthUser> register({
    required String name,
    required String password,
    required String role,
    String? group,
    String? phone,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'password': password,
        'role': role,
        if (group != null) 'group': group,
        if (phone != null) 'phone': phone,
      }),
    ).timeout(ApiConfig.httpTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw AuthException(body['message'] as String? ?? 'Ошибка регистрации');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _currentUser = AuthUser.fromJson(data);
    await _persistUser();
    return _currentUser!;
  }

  /// Вход по имени и паролю.
  Future<AuthUser> login({
    required String name,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'password': password,
      }),
    ).timeout(ApiConfig.httpTimeout);

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw AuthException(body['message'] as String? ?? 'Неверное имя или пароль');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _currentUser = AuthUser.fromJson(data);
    await _persistUser();
    return _currentUser!;
  }

  /// Выход: очистка токена и данных пользователя.
  Future<void> logout() async {
    _currentUser = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }

  Future<void> _persistUser() async {
    if (_currentUser == null) return;
    await _storage.write(key: _userKey, value: jsonEncode(_currentUser!.toJson()));
    await _storage.write(key: _tokenKey, value: _currentUser!.token);
  }
}

/// Ошибка аутентификации (неверные данные, сервер недоступен и т.д.).
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}
