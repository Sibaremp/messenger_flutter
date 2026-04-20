import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import '../models.dart' show DeviceSession;

/// Данные текущего пользователя, полученные после аутентификации.
class AuthUser {
  final String id;
  final String name;
  final String? group;
  final String? phone;
  final String? email;
  final String role; // 'student' | 'teacher'
  final String token;
  final String? bio;
  final String? avatarUrl;

  const AuthUser({
    required this.id,
    required this.name,
    this.group,
    this.phone,
    this.email,
    required this.role,
    required this.token,
    this.bio,
    this.avatarUrl,
  });

  bool get isTeacher => role == 'teacher';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (group != null) 'group': group,
    if (phone != null) 'phone': phone,
    if (email != null) 'email': email,
    'role': role,
    'token': token,
    if (bio != null) 'bio': bio,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
  };

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id: j['id'] as String,
    name: j['name'] as String,
    group: j['group'] as String?,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
    role: j['role'] as String? ?? 'student',
    token: j['token'] as String,
    bio: j['bio'] as String?,
    avatarUrl: j['avatarUrl'] as String?,
  );

  AuthUser copyWith({
    String? name,
    String? phone,
    String? email,
    String? bio,
    String? avatarUrl,
    bool clearAvatar = false,
  }) => AuthUser(
    id: id,
    name: name ?? this.name,
    group: group,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    role: role,
    token: token,
    bio: bio ?? this.bio,
    avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
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
    String? email,
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
        if (email != null) 'email': email,
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

  /// Обновление профиля на сервере.
  Future<AuthUser> updateProfile({
    String? name,
    String? bio,
    String? phone,
    String? email,
    String? avatarUrl,
  }) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/users/me'),
      headers: authHeaders,
      body: jsonEncode({
        if (name != null) 'name': name,
        if (bio != null) 'bio': bio,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      }),
    ).timeout(ApiConfig.httpTimeout);

    if (response.statusCode != 200) {
      throw AuthException('Ошибка обновления профиля');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    // Сервер возвращает обновлённый профиль, сохраняем токен
    _currentUser = AuthUser.fromJson({...data, 'token': token!});
    await _persistUser();
    return _currentUser!;
  }

  /// Загрузка списка контактов (всех пользователей).
  Future<List<Map<String, dynamic>>> loadContacts() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/contacts'),
      headers: authHeaders,
    ).timeout(ApiConfig.httpTimeout);

    if (response.statusCode != 200) return [];
    return (jsonDecode(response.body) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  /// Загрузка списка учебных групп с сервера.
  Future<List<String>> loadGroups() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/groups'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(ApiConfig.httpTimeout);

    if (response.statusCode != 200) return [];
    return (jsonDecode(response.body) as List<dynamic>).cast<String>();
  }

  /// Загрузка аватара на сервер.
  ///
  /// Загружает файл по пути [filePath] через `POST /api/users/me/avatar`,
  /// обновляет `AvatarPath` в профиле пользователя и синхронизирует
  /// [currentUser]. Возвращает новый серверный путь (`/uploads/...`).
  Future<String> uploadAvatar(String filePath) async {
    if (token == null) throw const AuthException('Не авторизован');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}/users/me/avatar'),
    );
    // Только Authorization — Content-Type multipart/form-data добавит сам MultipartRequest
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await request.send().timeout(const Duration(minutes: 2));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200 && response.statusCode != 201) {
      String msg = 'Ошибка загрузки аватара';
      try {
        msg = (jsonDecode(response.body) as Map<String, dynamic>)['message']?.toString() ?? msg;
      } catch (_) {}
      throw AuthException(msg);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final newAvatar = (data['avatarUrl'] ?? data['avatarPath']) as String?;

    // Синхронизируем currentUser с обновлённым аватаром
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(
        avatarUrl: newAvatar,
        clearAvatar: newAvatar == null,
      );
      await _persistUser();
    }
    return newAvatar ?? '';
  }

  // ── Управление устройствами ────────────────────────────────────────────────

  /// Синтетическая сессия для текущего устройства — показывается
  /// как fallback, если сервер недоступен или ещё не реализован.
  DeviceSession _syntheticCurrentSession() {
    String deviceName;
    String? platform;
    if (kIsWeb) {
      deviceName = 'Браузер (Web)';
      platform   = 'Web';
    } else if (Platform.isAndroid) {
      deviceName = 'Android';
      platform   = 'Android';
    } else if (Platform.isIOS) {
      deviceName = 'iPhone / iPad';
      platform   = 'iOS';
    } else if (Platform.isWindows) {
      deviceName = 'Windows PC';
      platform   = 'Windows';
    } else if (Platform.isMacOS) {
      deviceName = 'Mac';
      platform   = 'macOS';
    } else if (Platform.isLinux) {
      deviceName = 'Linux';
      platform   = 'Linux';
    } else {
      deviceName = 'Это устройство';
      platform   = null;
    }
    return DeviceSession(
      sessionId:    'current',
      deviceName:   deviceName,
      platform:     platform,
      lastActivity: DateTime.now(),
      isCurrent:    true,
    );
  }

  /// Возвращает список всех активных сессий текущего пользователя.
  /// Если API недоступен — возвращает список с синтетической текущей сессией.
  Future<List<DeviceSession>> getDevices() async {
    if (token == null) return [_syntheticCurrentSession()];
    try {
      final r = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/auth/sessions'),
        headers: authHeaders,
      ).timeout(ApiConfig.httpTimeout);
      if (r.statusCode != 200) return [_syntheticCurrentSession()];
      final list = (jsonDecode(r.body) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(DeviceSession.fromJson)
          .toList();
      // Если сервер не вернул ни одной «current» сессии — добавляем fallback
      if (list.isEmpty || !list.any((s) => s.isCurrent)) {
        return [_syntheticCurrentSession(), ...list];
      }
      return list;
    } catch (_) {
      return [_syntheticCurrentSession()];
    }
  }

  /// Завершает конкретный сеанс [sessionId].
  /// Если [sessionId] — текущий, сервер завершит его и пришлёт
  /// `session_terminated` с `isCurrent: true` — клиент должен разлогиниться.
  Future<void> terminateSession(String sessionId) async {
    if (token == null) return;
    final r = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/auth/sessions/$sessionId'),
      headers: authHeaders,
    ).timeout(ApiConfig.httpTimeout);
    if (r.statusCode >= 400) {
      final body = r.body.isNotEmpty
          ? (jsonDecode(r.body) as Map<String, dynamic>)['message']?.toString()
          : null;
      throw AuthException(body ?? 'Ошибка завершения сеанса');
    }
  }

  /// Завершает ВСЕ сеансы, включая текущий, и очищает локальный токен.
  /// После вызова вызывающий код должен перенаправить пользователя на AuthScreen.
  Future<void> terminateAllSessions() async {
    if (token == null) return;
    final r = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/auth/sessions'),
      headers: authHeaders,
    ).timeout(ApiConfig.httpTimeout);
    if (r.statusCode >= 400) {
      final body = r.body.isNotEmpty
          ? (jsonDecode(r.body) as Map<String, dynamic>)['message']?.toString()
          : null;
      throw AuthException(body ?? 'Ошибка выхода со всех устройств');
    }
    await logout();
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
