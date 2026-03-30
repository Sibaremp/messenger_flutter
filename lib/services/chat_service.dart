import 'dart:async';
import '../models.dart';

// ── События (sealed) ────────────────────────────────────────────────────────
sealed class ChatEvent {}

/// Вызывается при получении нового сообщения (отправленного локально или удалённо).
class MessageReceived extends ChatEvent {
  final String chatId;
  final Message message;
  MessageReceived(this.chatId, this.message);
}

class MessageEdited extends ChatEvent {
  final String chatId;
  final String messageId;
  final String newText;
  MessageEdited(this.chatId, this.messageId, this.newText);
}

class MessageDeleted extends ChatEvent {
  final String chatId;
  final List<String> messageIds;
  MessageDeleted(this.chatId, this.messageIds);
}

class ChatUpdated extends ChatEvent {
  final Chat chat;
  ChatUpdated(this.chat);
}

// ── Абстрактный интерфейс ─────────────────────────────────────────────────────

/// Контракт для всех бэкендов чата (локальный, удалённый, mock).
/// Экраны зависят от этого интерфейса, а не от конкретной реализации.
abstract class ChatService {
  Future<List<Chat>> loadChats();

  Future<Chat> sendMessage({
    required String chatId,
    required String text,
    Attachment? attachment,
    String senderName,
  });

  Future<Chat> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  });

  Future<Chat> deleteMessages({
    required String chatId,
    required List<String> messageIds,
  });

  Future<Chat> forwardMessages({
    required String targetChatId,
    required List<Message> messages,
  });

  Future<Chat> createDirectChat({required String contactName});

  Future<Chat> createGroupOrCommunity({
    required String name,
    required ChatType type,
    required List<ChatMember> members,
    String? adminName,
  });

  Future<Chat> updateChatSettings(Chat chat);

  Stream<ChatEvent> get events;

  Future<void> dispose();
}

// ── Локальная (in-memory) реализация ──────────────────────────────────────────
class LocalChatService implements ChatService {
  final List<Chat> _chats;
  final _controller = StreamController<ChatEvent>.broadcast();

  LocalChatService() : _chats = _seedChats();

  static List<Chat> _seedChats() => [
    Chat(
      name: 'Алексей',
      type: ChatType.direct,
      messages: [
        Message(text: 'Привет!', isMe: false,
            time: DateTime.now().subtract(const Duration(minutes: 5))),
        Message(text: 'Здорово', isMe: true,
            time: DateTime.now().subtract(const Duration(minutes: 4))),
      ],
    ),
    Chat(
      name: 'Мария',
      type: ChatType.direct,
      messages: [
        Message(text: 'Ты где?', isMe: false,
            time: DateTime.now().subtract(const Duration(minutes: 10))),
      ],
    ),
    Chat(
      name: 'Иван',
      type: ChatType.direct,
      messages: [
        Message(text: 'Ок', isMe: false,
            time: DateTime.now().subtract(const Duration(days: 1))),
      ],
    ),
  ];

  /// Возвращает индекс в списке для [chatId] или -1, если не найден.
  int _idx(String chatId) => _chats.indexWhere((c) => c.id == chatId);

  @override
  Future<List<Chat>> loadChats() async => List.unmodifiable(_chats);

  @override
  Future<Chat> sendMessage({
    required String chatId,
    required String text,
    Attachment? attachment,
    String senderName = 'Я',
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final msg = Message(
      text: text, isMe: true, time: DateTime.now(),
      senderName: senderName, attachment: attachment,
    );
    final updated = _chats[i].copyWith(messages: [..._chats[i].messages, msg]);
    _chats[i] = updated;
    _controller.add(MessageReceived(chatId, msg));
    return updated;
  }

  @override
  Future<Chat> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final msgs = _chats[i].messages
        .map((m) => m.id == messageId ? m.copyWith(text: newText, isEdited: true) : m)
        .toList();
    final updated = _chats[i].copyWith(messages: msgs);
    _chats[i] = updated;
    _controller.add(MessageEdited(chatId, messageId, newText));
    return updated;
  }

  @override
  Future<Chat> deleteMessages({
    required String chatId,
    required List<String> messageIds,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final idSet = messageIds.toSet(); // O(1) поиск вместо перебора списка
    final msgs = _chats[i].messages.where((m) => !idSet.contains(m.id)).toList();
    final updated = _chats[i].copyWith(messages: msgs);
    _chats[i] = updated;
    _controller.add(MessageDeleted(chatId, messageIds));
    return updated;
  }

  @override
  Future<Chat> forwardMessages({
    required String targetChatId,
    required List<Message> messages,
  }) async {
    final i = _idx(targetChatId);
    if (i == -1) throw StateError('Chat not found: $targetChatId');
    final forwarded = messages
        .map((m) => Message(text: m.text, isMe: true, time: DateTime.now(),
              senderName: 'Я', attachment: m.attachment))
        .toList();
    final updated = _chats[i].copyWith(
        messages: [..._chats[i].messages, ...forwarded]);
    _chats[i] = updated;
    for (final m in forwarded) { _controller.add(MessageReceived(targetChatId, m)); }
    return updated;
  }

  @override
  Future<Chat> createDirectChat({required String contactName}) async {
    // Повторно использует существующий чат вместо создания дубликата.
    final existing = _chats.where(
      (c) => c.name == contactName && c.type == ChatType.direct,
    ).firstOrNull;
    if (existing != null) return existing;
    final c = Chat(name: contactName, type: ChatType.direct, messages: []);
    _chats.add(c);
    _controller.add(ChatUpdated(c));
    return c;
  }

  @override
  Future<Chat> createGroupOrCommunity({
    required String name,
    required ChatType type,
    required List<ChatMember> members,
    String? adminName,
  }) async {
    final chat = Chat(
      name: name, type: type, members: members,
      adminName: adminName, messages: [],
    );
    _chats.add(chat);
    _controller.add(ChatUpdated(chat));
    return chat;
  }

  @override
  Future<Chat> updateChatSettings(Chat chat) async {
    final i = _idx(chat.id);
    if (i == -1) throw StateError('Chat not found: ${chat.id}');
    _chats[i] = chat;
    _controller.add(ChatUpdated(chat));
    return chat;
  }

  @override
  Stream<ChatEvent> get events => _controller.stream;

  @override
  Future<void> dispose() async => _controller.close();
}
