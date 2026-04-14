import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:signalr_netcore/signalr_client.dart';
import '../models.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'chat_service.dart';

/// Реализация [ChatService] для работы с удалённым сервером через REST API + SignalR.
class ApiChatService implements ChatService {
  final AuthService _auth;
  final _eventController = StreamController<ChatEvent>.broadcast();

  HubConnection? _hub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  ApiChatService(this._auth) {
    _connectSignalR();
  }

  // ── HTTP-хелперы ──────────────────────────────────────────────────────────

  String get _base => ApiConfig.baseUrl;
  Map<String, String> get _headers => _auth.authHeaders;
  String get _uid => _auth.currentUser?.id ?? '';

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      Uri.parse('$_base$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(ApiConfig.httpTimeout);
    return _handleResponse(r);
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    final r = await http.put(
      Uri.parse('$_base$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(ApiConfig.httpTimeout);
    return _handleResponse(r);
  }

  Future<Map<String, dynamic>> _delete(String path, [Map<String, dynamic>? body]) async {
    final request = http.Request('DELETE', Uri.parse('$_base$path'));
    request.headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await request.send().timeout(ApiConfig.httpTimeout);
    final r = await http.Response.fromStream(streamed);
    return _handleResponse(r);
  }

  Map<String, dynamic> _handleResponse(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return {};
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    final msg = r.body.isNotEmpty
        ? (jsonDecode(r.body) as Map<String, dynamic>)['message'] ?? 'Ошибка сервера'
        : 'Ошибка сервера (${r.statusCode})';
    throw ApiException(msg as String, r.statusCode);
  }

  Chat _chatFromJson(Map<String, dynamic> j) =>
      Chat.fromJson(j, currentUserId: _uid);

  // ── SignalR ───────────────────────────────────────────────────────────────

  void _connectSignalR() {
    if (_disposed || _auth.token == null) return;
    try {
      _hub = HubConnectionBuilder()
          .withUrl(
            ApiConfig.hubUrl,
            options: HttpConnectionOptions(
              accessTokenFactory: () async => _auth.token ?? '',
            ),
          )
          .build();

      _hub!.on('ReceiveEvent', _onHubEvent);
      _hub!.onclose(({error}) => _scheduleReconnect());

      _hub!.start()?.catchError((_) {
        _scheduleReconnect();
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(ApiConfig.wsReconnectDelay, _connectSignalR);
  }

  void _onHubEvent(List<Object?>? args) {
    try {
      final data = args?.first as Map<String, dynamic>?;
      if (data == null) return;
      final type = data['type'] as String;
      switch (type) {
        case 'message_received':
          final chatId = data['chatId'] as String;
          final msg = Message.fromJson(
            data['message'] as Map<String, dynamic>,
            currentUserId: _uid,
          );
          _eventController.add(MessageReceived(chatId, msg));
        case 'message_edited':
          _eventController.add(MessageEdited(
            data['chatId'] as String,
            data['messageId'] as String,
            data['newText'] as String,
          ));
        case 'message_deleted':
          _eventController.add(MessageDeleted(
            data['chatId'] as String,
            (data['messageIds'] as List<dynamic>).cast<String>(),
          ));
        case 'chat_updated':
          _eventController.add(ChatUpdated(
            _chatFromJson(data['chat'] as Map<String, dynamic>),
          ));
        case 'chat_deleted':
          _eventController.add(ChatDeleted(data['chatId'] as String));
      }
    } catch (_) {
      // Некорректный пакет — игнорируем
    }
  }

  // ── ChatService API ───────────────────────────────────────────────────────

  Future<List<dynamic>> _getList(String path) async {
    final r = await http.get(Uri.parse('$_base$path'), headers: _headers)
        .timeout(ApiConfig.httpTimeout);
    if (r.statusCode != 200) throw ApiException('Ошибка запроса', r.statusCode);
    return jsonDecode(r.body) as List<dynamic>;
  }

  @override
  Future<List<Chat>> loadChats() async {
    final list = await _getList('/chats');
    return list.map((j) => _chatFromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<Chat> sendMessage({
    required String chatId,
    required String text,
    Attachment? attachment,
    String senderName = 'Я',
    String? senderGroup,
    ReplyInfo? replyTo,
  }) async {
    final body = <String, dynamic>{
      'text': text,
      if (attachment != null) 'attachment': attachment.toJson(),
      if (replyTo != null) 'replyTo': replyTo.toJson(),
    };
    final data = await _post('/chats/$chatId/messages', body);
    return _chatFromJson(data);
  }

  @override
  Future<Chat> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  }) async {
    final data = await _put('/chats/$chatId/messages/$messageId', {'text': newText});
    return _chatFromJson(data);
  }

  @override
  Future<Chat> deleteMessages({
    required String chatId,
    required List<String> messageIds,
  }) async {
    final data = await _delete('/chats/$chatId/messages', {'ids': messageIds});
    return _chatFromJson(data);
  }

  @override
  Future<Chat> forwardMessages({
    required String targetChatId,
    required List<Message> messages,
  }) async {
    final data = await _post('/chats/$targetChatId/forward', {
      'messageIds': messages.map((m) => m.id).toList(),
    });
    return _chatFromJson(data);
  }

  @override
  Future<Chat> createDirectChat({required String contactName, bool isAcademic = false}) async {
    final data = await _post('/chats/direct', {
      'contactName': contactName,
      'isAcademic': isAcademic,
    });
    return _chatFromJson(data);
  }

  @override
  Future<Chat> createGroupOrCommunity({
    required String name,
    required ChatType type,
    required List<ChatMember> members,
    String? adminName,
  }) async {
    final data = await _post('/chats/group', {
      'name': name,
      'type': type.name,
      'members': members.map((m) => m.toJson()).toList(),
      if (adminName != null) 'adminName': adminName,
    });
    return _chatFromJson(data);
  }

  @override
  Future<Chat> updateChatSettings(Chat chat) async {
    final data = await _put('/chats/${chat.id}/settings', chat.toJson());
    return _chatFromJson(data);
  }

  @override
  Future<void> deleteChat(String chatId) async {
    await _delete('/chats/$chatId');
    _eventController.add(ChatDeleted(chatId));
  }

  @override
  Future<Chat> addComment({
    required String chatId,
    required String messageId,
    required String text,
    String senderName = 'Я',
    String? senderGroup,
    Attachment? attachment,
    ReplyInfo? replyTo,
  }) async {
    final data = await _post('/chats/$chatId/messages/$messageId/comments', {
      'text': text,
      if (attachment != null) 'attachment': attachment.toJson(),
      if (replyTo != null) 'replyTo': replyTo.toJson(),
    });
    return _chatFromJson(data);
  }

  @override
  Future<Chat> editComment({
    required String chatId,
    required String messageId,
    required String commentId,
    required String newText,
  }) async {
    final data = await _put(
      '/chats/$chatId/messages/$messageId/comments/$commentId',
      {'text': newText},
    );
    return _chatFromJson(data);
  }

  @override
  Future<Chat> deleteComments({
    required String chatId,
    required String messageId,
    required List<String> commentIds,
  }) async {
    final data = await _delete(
      '/chats/$chatId/messages/$messageId/comments',
      {'ids': commentIds},
    );
    return _chatFromJson(data);
  }

  @override
  Future<List<Chat>> searchChats(String query) async {
    final r = await http.get(
      Uri.parse('$_base/chats/search?q=${Uri.encodeQueryComponent(query)}'),
      headers: _headers,
    ).timeout(ApiConfig.httpTimeout);
    if (r.statusCode != 200) return [];
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((j) => _chatFromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<SearchMessageResult>> searchMessages(String query) async {
    final r = await http.get(
      Uri.parse('$_base/messages/search?q=${Uri.encodeQueryComponent(query)}'),
      headers: _headers,
    ).timeout(ApiConfig.httpTimeout);
    if (r.statusCode != 200) return [];
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((j) {
      final item = j as Map<String, dynamic>;
      return SearchMessageResult(
        chat: _chatFromJson(item['chat'] as Map<String, dynamic>),
        message: Message.fromJson(item['message'] as Map<String, dynamic>, currentUserId: _uid),
      );
    }).toList();
  }

  @override
  Future<List<SearchFileResult>> searchFiles({
    AttachmentType? type,
    String? nameQuery,
  }) async {
    final params = <String, String>{};
    if (type != null) params['type'] = type.name;
    if (nameQuery != null && nameQuery.isNotEmpty) params['q'] = nameQuery;
    final uri = Uri.parse('$_base/files/search').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(ApiConfig.httpTimeout);
    if (r.statusCode != 200) return [];
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((j) {
      final item = j as Map<String, dynamic>;
      return SearchFileResult(
        chat: _chatFromJson(item['chat'] as Map<String, dynamic>),
        message: Message.fromJson(item['message'] as Map<String, dynamic>, currentUserId: _uid),
        attachment: Attachment.fromJson(item['attachment'] as Map<String, dynamic>),
      );
    }).toList();
  }

  @override
  Stream<ChatEvent> get events => _eventController.stream;

  @override
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _hub?.stop();
    await _eventController.close();
  }
}

/// Ошибка при работе с API сервера.
class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
