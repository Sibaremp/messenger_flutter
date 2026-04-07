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

class ChatDeleted extends ChatEvent {
  final String chatId;
  ChatDeleted(this.chatId);
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
    ReplyInfo? replyTo,
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

  Future<Chat> createDirectChat({required String contactName, bool isAcademic = false});

  Future<Chat> createGroupOrCommunity({
    required String name,
    required ChatType type,
    required List<ChatMember> members,
    String? adminName,
  });

  Future<Chat> updateChatSettings(Chat chat);

  /// Удаляет чат полностью. Эмитит [ChatDeleted] для подписчиков.
  Future<void> deleteChat(String chatId);

  /// Добавляет комментарий к сообщению (посту) в группе/сообществе.
  Future<Chat> addComment({
    required String chatId,
    required String messageId,
    required String text,
    String senderName = 'Я',
  });

  /// Поиск чатов/групп по имени.
  Future<List<Chat>> searchChats(String query);

  /// Поиск сообщений по тексту. Возвращает пары (чат, сообщение).
  Future<List<SearchMessageResult>> searchMessages(String query);

  /// Поиск вложений по типу файла и (опционально) имени.
  Future<List<SearchFileResult>> searchFiles({
    AttachmentType? type,
    String? nameQuery,
  });

  Stream<ChatEvent> get events;

  Future<void> dispose();
}

/// Результат поиска сообщения — чат + конкретное сообщение.
class SearchMessageResult {
  final Chat chat;
  final Message message;
  const SearchMessageResult({required this.chat, required this.message});
}

/// Результат поиска файла — чат + сообщение с вложением.
class SearchFileResult {
  final Chat chat;
  final Message message;
  final Attachment attachment;
  const SearchFileResult({
    required this.chat,
    required this.message,
    required this.attachment,
  });
}

// ── Локальная (in-memory) реализация ──────────────────────────────────────────
class LocalChatService implements ChatService {
  final List<Chat> _chats;
  final _controller = StreamController<ChatEvent>.broadcast();

  LocalChatService() : _chats = _seedChats();

  static List<Chat> _seedChats() => [
    // ── Обычные чаты (раздел «Общение») ──────────────────────────
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
    // ── Академические чаты (раздел «Академический») ──────────────
    Chat(
      name: 'Проф. Иванов А.С.',
      type: ChatType.direct,
      isAcademic: true,
      messages: [
        Message(text: 'Добрый день! Когда можно подойти на консультацию?', isMe: true,
            time: DateTime.now().subtract(const Duration(hours: 2))),
        Message(text: 'Завтра с 14:00 до 16:00, аудитория 305', isMe: false,
            senderName: 'Проф. Иванов А.С.',
            time: DateTime.now().subtract(const Duration(hours: 1))),
      ],
    ),
    Chat(
      name: 'Физика и оптика ФО 22-1',
      type: ChatType.community,
      isAcademic: true,
      adminName: 'Проф. Петров',
      description: 'Учебная группа по физике и оптике',
      messages: [
        Message(text: 'Конспект лекции №14: Введение в квантовую электродинамику', isMe: false,
            senderName: 'Проф. Петров',
            time: DateTime.now().subtract(const Duration(hours: 3))),
      ],
      members: [
        const ChatMember(name: 'Проф. Петров', role: MemberRole.creator),
        const ChatMember(name: 'Студент 1', role: MemberRole.member),
      ],
    ),
    Chat(
      name: 'История Казахстана ФО 22',
      type: ChatType.community,
      isAcademic: true,
      adminName: 'Доц. Сулейменова',
      description: 'Курс истории Казахстана',
      messages: [
        Message(text: 'Домашнее задание на следующую неделю опубликовано', isMe: false,
            senderName: 'Доц. Сулейменова',
            time: DateTime.now().subtract(const Duration(days: 1))),
      ],
      members: [
        const ChatMember(name: 'Доц. Сулейменова', role: MemberRole.creator),
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
    ReplyInfo? replyTo,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final msg = Message(
      text: text, isMe: true, time: DateTime.now(),
      senderName: senderName, attachment: attachment,
      replyTo: replyTo,
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
  Future<Chat> createDirectChat({required String contactName, bool isAcademic = false}) async {
    // Повторно использует существующий чат вместо создания дубликата.
    final existing = _chats.where(
      (c) => c.name == contactName && c.type == ChatType.direct,
    ).firstOrNull;
    if (existing != null) return existing;
    final c = Chat(name: contactName, type: ChatType.direct, messages: [], isAcademic: isAcademic);
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
  Future<void> deleteChat(String chatId) async {
    final i = _idx(chatId);
    if (i == -1) return;
    _chats.removeAt(i);
    _controller.add(ChatDeleted(chatId));
  }

  @override
  Future<Chat> addComment({
    required String chatId,
    required String messageId,
    required String text,
    String senderName = 'Я',
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final comment = Comment(
      text: text,
      senderName: senderName,
      time: DateTime.now(),
      isMe: true,
    );
    final msgs = _chats[i].messages.map((m) {
      if (m.id == messageId) {
        return m.copyWith(comments: [...m.comments, comment]);
      }
      return m;
    }).toList();
    final updated = _chats[i].copyWith(messages: msgs);
    _chats[i] = updated;
    _controller.add(ChatUpdated(updated));
    return updated;
  }

  @override
  Future<List<Chat>> searchChats(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];
    return _chats.where((c) {
      return c.name.toLowerCase().contains(q) ||
          (c.description?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Future<List<SearchMessageResult>> searchMessages(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];
    final results = <SearchMessageResult>[];
    for (final chat in _chats) {
      for (final msg in chat.messages) {
        if (msg.text.toLowerCase().contains(q)) {
          results.add(SearchMessageResult(chat: chat, message: msg));
        }
      }
    }
    // Сортировка: новые сообщения первыми
    results.sort((a, b) => b.message.time.compareTo(a.message.time));
    return results;
  }

  @override
  Future<List<SearchFileResult>> searchFiles({
    AttachmentType? type,
    String? nameQuery,
  }) async {
    final q = nameQuery?.toLowerCase().trim() ?? '';
    final results = <SearchFileResult>[];
    for (final chat in _chats) {
      for (final msg in chat.messages) {
        final att = msg.attachment;
        if (att == null) continue;
        if (type != null && att.type != type) continue;
        if (q.isNotEmpty && !att.fileName.toLowerCase().contains(q)) continue;
        results.add(SearchFileResult(
          chat: chat, message: msg, attachment: att,
        ));
      }
    }
    results.sort((a, b) => b.message.time.compareTo(a.message.time));
    return results;
  }

  @override
  Stream<ChatEvent> get events => _controller.stream;

  @override
  Future<void> dispose() async => _controller.close();
}
