// ─── Models ───────────────────────────────────────────────────────────────────

/// Discriminates between personal, group, and broadcast (community) chats.
enum ChatType { direct, group, community }

/// File attachment categories used for rendering and MIME handling.
enum AttachmentType { image, video, document }

/// Статус доставки сообщения (отображается только у своих сообщений)
enum MessageStatus {
  sending,   // ⏱ отправляется
  sent,      // ✓  отправлено
  delivered, // ✓✓ доставлено
  error,     // ✗  ошибка
}

/// A file attached to a [Message] (image, video, or document).
class Attachment {
  final String path;
  final AttachmentType type;
  final String fileName;
  final int? fileSize;

  const Attachment({
    required this.path,
    required this.type,
    required this.fileName,
    this.fileSize,
  });

  /// Human-readable file size: bytes → КБ → МБ.
  String get readableSize {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize Б';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} КБ';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}

/// A contact visible in the contact-picker (app-side registry, not device book).
class AppContact {
  final String name;
  final String? group;
  final String? phone;

  const AppContact({required this.name, this.group, this.phone});
}

/// An individual chat message with optional attachment and delivery status.
class Message {
  // Auto-incremented fallback used when no explicit id is provided.
  static int _nextId = 0;

  final String id;
  final String text;
  final bool isMe;
  final DateTime time;
  final String? senderName;
  final Attachment? attachment;
  final bool isEdited;
  final MessageStatus status;

  Message({
    String? id,
    required this.text,
    required this.isMe,
    required this.time,
    this.senderName,
    this.attachment,
    this.isEdited = false,
    this.status = MessageStatus.sent,
  }) : id = id ?? 'msg_${++_nextId}';

  Message copyWith({String? text, bool? isEdited, MessageStatus? status}) => Message(
    id: id,
    text: text ?? this.text,
    isMe: isMe,
    time: time,
    senderName: senderName,
    attachment: attachment,
    isEdited: isEdited ?? this.isEdited,
    status: status ?? this.status,
  );
}

/// Privilege level of a participant inside a group or community chat.
enum MemberRole { creator, admin, member }

/// A participant in a [Chat] with an associated [MemberRole].
class ChatMember {
  final String name;
  final MemberRole role;

  const ChatMember({required this.name, this.role = MemberRole.member});

  ChatMember copyWith({String? name, MemberRole? role}) => ChatMember(
    name: name ?? this.name,
    role: role ?? this.role,
  );
}

/// Core chat entity containing messages, members, and metadata.
class Chat {
  // Auto-incremented fallback used when no explicit id is provided.
  static int _nextId = 0;

  final String id;
  final String name;
  final List<Message> messages;
  final ChatType type;
  final List<ChatMember> members;
  final String? adminName;
  final String? avatarPath;
  final String? description;
  final DateTime? createdAt;

  Chat({
    String? id,
    required this.name,
    required this.messages,
    this.type = ChatType.direct,
    this.members = const [],
    this.adminName,
    this.avatarPath,
    this.description,
    this.createdAt,
  }) : id = id ?? 'chat_${++_nextId}';

  String get lastMessage {
    if (messages.isEmpty) return '';
    final msg = messages.last;
    String content = msg.text;
    if (content.isEmpty && msg.attachment != null) {
      content = switch (msg.attachment!.type) {
        AttachmentType.image    => '📷 Фото',
        AttachmentType.video    => '🎬 Видео',
        AttachmentType.document => '📎 ${msg.attachment!.fileName}',
      };
    }
    if (type != ChatType.direct && msg.senderName != null && !msg.isMe) {
      return '${msg.senderName}: $content';
    }
    return content;
  }

  DateTime get lastTime =>
      messages.isNotEmpty ? messages.last.time : DateTime(0);

  /// Community chats are read-only unless the current user is the admin.
  bool get canWrite =>
      type != ChatType.community || adminName == 'Я';

  // Sentinel value used to detect "not provided" for nullable fields in copyWith
  static const _keep = Object();

  Chat copyWith({
    String? name,
    List<Message>? messages,
    ChatType? type,
    List<ChatMember>? members,
    Object? adminName = _keep,
    Object? avatarPath = _keep,
    Object? description = _keep,
    DateTime? createdAt,
  }) {
    return Chat(
      id: id,
      name: name ?? this.name,
      messages: messages ?? this.messages,
      type: type ?? this.type,
      members: members ?? this.members,
      adminName: identical(adminName, _keep) ? this.adminName : adminName as String?,
      avatarPath: identical(avatarPath, _keep) ? this.avatarPath : avatarPath as String?,
      description: identical(description, _keep) ? this.description : description as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
