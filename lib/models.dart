// ─── Models ───────────────────────────────────────────────────────────────────

/// Различает личные, групповые и широковещательные (сообщества) чаты.
enum ChatType { direct, group, community }

/// Категории вложений файлов для рендеринга и обработки MIME.
enum AttachmentType { image, video, document }

/// Статус доставки сообщения (отображается только у своих сообщений)
enum MessageStatus {
  sending,   // ⏱ отправляется
  sent,      // ✓  отправлено
  delivered, // ✓✓ доставлено (серые)
  read,      // ✓✓ прочитано (голубые)
  error,     // ✗  ошибка
}

/// Файл, прикреплённый к [Message] (изображение, видео или документ).
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

  /// Читаемый размер файла: байты → КБ → МБ.
  String get readableSize {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize Б';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} КБ';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'type': type.name,
    'fileName': fileName,
    if (fileSize != null) 'fileSize': fileSize,
  };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
    path: j['path'] as String,
    type: AttachmentType.values.byName(j['type'] as String),
    fileName: j['fileName'] as String,
    fileSize: j['fileSize'] as int?,
  );
}

/// Контакт, отображаемый в выборщике контактов (реестр приложения, не книга устройства).
class AppContact {
  final String name;
  final String? group;
  final String? phone;
  /// true — преподаватель (отображается в «Академический»), false — студент (в «Общение»).
  final bool isTeacher;

  const AppContact({required this.name, this.group, this.phone, this.isTeacher = false});

  Map<String, dynamic> toJson() => {
    'name': name,
    if (group != null) 'group': group,
    if (phone != null) 'phone': phone,
    'isTeacher': isTeacher,
  };

  factory AppContact.fromJson(Map<String, dynamic> j) => AppContact(
    name: j['name'] as String,
    group: j['group'] as String?,
    phone: j['phone'] as String?,
    isTeacher: j['isTeacher'] as bool? ?? false,
  );
}

/// Отдельное сообщение чата с необязательным вложением и статусом доставки.
class Message {
  // Автоинкрементный резервный идентификатор, используемый когда явный id не задан.
  static int _nextId = 0;

  final String id;
  final String text;
  final bool isMe;
  final DateTime time;
  final String? senderName;
  /// Учебная группа отправителя (для студентов).
  final String? senderGroup;
  final Attachment? attachment;
  final bool isEdited;
  final MessageStatus status;
  final List<Comment> comments;
  /// Ответ на сообщение (Telegram-style reply).
  final ReplyInfo? replyTo;

  Message({
    String? id,
    required this.text,
    required this.isMe,
    required this.time,
    this.senderName,
    this.senderGroup,
    this.attachment,
    this.isEdited = false,
    this.status = MessageStatus.sent,
    this.comments = const [],
    this.replyTo,
  }) : id = id ?? 'msg_${++_nextId}';

  Message copyWith({
    String? text,
    bool? isEdited,
    MessageStatus? status,
    List<Comment>? comments,
    ReplyInfo? replyTo,
    bool clearReply = false,
  }) => Message(
    id: id,
    text: text ?? this.text,
    isMe: isMe,
    time: time,
    senderName: senderName,
    senderGroup: senderGroup,
    attachment: attachment,
    isEdited: isEdited ?? this.isEdited,
    status: status ?? this.status,
    comments: comments ?? this.comments,
    replyTo: clearReply ? null : (replyTo ?? this.replyTo),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isMe': isMe,
    'time': time.toIso8601String(),
    if (senderName != null) 'senderName': senderName,
    if (senderGroup != null) 'senderGroup': senderGroup,
    if (attachment != null) 'attachment': attachment!.toJson(),
    'isEdited': isEdited,
    'status': status.name,
    if (comments.isNotEmpty) 'comments': comments.map((c) => c.toJson()).toList(),
    if (replyTo != null) 'replyTo': replyTo!.toJson(),
  };

  factory Message.fromJson(Map<String, dynamic> j, {required String currentUserId}) => Message(
    id: j['id'] as String,
    text: j['text'] as String? ?? '',
    isMe: (j['senderId'] as String?) == currentUserId || (j['isMe'] as bool? ?? false),
    time: DateTime.parse(j['time'] as String),
    senderName: j['senderName'] as String?,
    senderGroup: j['senderGroup'] as String?,
    attachment: j['attachment'] != null
        ? Attachment.fromJson(j['attachment'] as Map<String, dynamic>)
        : null,
    isEdited: j['isEdited'] as bool? ?? false,
    status: MessageStatus.values.byName(j['status'] as String? ?? 'sent'),
    comments: (j['comments'] as List<dynamic>?)
        ?.map((c) => Comment.fromJson(c as Map<String, dynamic>, currentUserId: currentUserId))
        .toList() ?? const [],
    replyTo: j['replyTo'] != null
        ? ReplyInfo.fromJson(j['replyTo'] as Map<String, dynamic>)
        : null,
  );
}

/// Комментарий к сообщению (посту) — аналог тредов в Telegram-каналах.
class Comment {
  static int _nextId = 0;

  final String id;
  final String text;
  final String senderName;
  /// Учебная группа отправителя (для студентов).
  final String? senderGroup;
  final DateTime time;
  final bool isMe;
  final bool isEdited;
  final ReplyInfo? replyTo;
  final Attachment? attachment;

  Comment({
    String? id,
    required this.text,
    required this.senderName,
    this.senderGroup,
    required this.time,
    this.isMe = false,
    this.isEdited = false,
    this.replyTo,
    this.attachment,
  }) : id = id ?? 'cmt_${++_nextId}';

  Comment copyWith({
    String? text,
    bool? isEdited,
    ReplyInfo? replyTo,
    bool clearReply = false,
    Attachment? attachment,
    bool clearAttachment = false,
  }) {
    return Comment(
      id: id,
      text: text ?? this.text,
      senderName: senderName,
      senderGroup: senderGroup,
      time: time,
      isMe: isMe,
      isEdited: isEdited ?? this.isEdited,
      replyTo: clearReply ? null : (replyTo ?? this.replyTo),
      attachment: clearAttachment ? null : (attachment ?? this.attachment),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'senderName': senderName,
    if (senderGroup != null) 'senderGroup': senderGroup,
    'time': time.toIso8601String(),
    'isMe': isMe,
    'isEdited': isEdited,
    if (replyTo != null) 'replyTo': replyTo!.toJson(),
    if (attachment != null) 'attachment': attachment!.toJson(),
  };

  factory Comment.fromJson(Map<String, dynamic> j, {required String currentUserId}) => Comment(
    id: j['id'] as String,
    text: j['text'] as String? ?? '',
    senderName: j['senderName'] as String? ?? '',
    senderGroup: j['senderGroup'] as String?,
    time: DateTime.parse(j['time'] as String),
    isMe: (j['senderId'] as String?) == currentUserId || (j['isMe'] as bool? ?? false),
    isEdited: j['isEdited'] as bool? ?? false,
    replyTo: j['replyTo'] != null
        ? ReplyInfo.fromJson(j['replyTo'] as Map<String, dynamic>)
        : null,
    attachment: j['attachment'] != null
        ? Attachment.fromJson(j['attachment'] as Map<String, dynamic>)
        : null,
  );
}

/// Информация об ответе на сообщение (reply).
class ReplyInfo {
  final String messageId;
  final String senderName;
  final String text;

  const ReplyInfo({
    required this.messageId,
    required this.senderName,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'senderName': senderName,
    'text': text,
  };

  factory ReplyInfo.fromJson(Map<String, dynamic> j) => ReplyInfo(
    messageId: j['messageId'] as String,
    senderName: j['senderName'] as String? ?? '',
    text: j['text'] as String? ?? '',
  );
}

/// Уровень привилегий участника в групповом чате или сообществе.
enum MemberRole { creator, admin, member }

/// Участник [Chat] с назначенной ролью [MemberRole].
class ChatMember {
  final String name;
  /// Учебная группа участника (для студентов).
  final String? group;
  final MemberRole role;

  const ChatMember({required this.name, this.group, this.role = MemberRole.member});

  ChatMember copyWith({String? name, String? group, MemberRole? role}) => ChatMember(
    name: name ?? this.name,
    group: group ?? this.group,
    role: role ?? this.role,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (group != null) 'group': group,
    'role': role.name,
  };

  factory ChatMember.fromJson(Map<String, dynamic> j) => ChatMember(
    name: j['name'] as String,
    group: j['group'] as String?,
    role: MemberRole.values.byName(j['role'] as String? ?? 'member'),
  );
}

/// Основная сущность чата, содержащая сообщения, участников и метаданные.
class Chat {
  // Автоинкрементный резервный идентификатор, используемый когда явный id не задан.
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
  /// Флаг: чат принадлежит академическому разделу (преподаватели)
  final bool isAcademic;

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
    this.isAcademic = false,
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
      final prefix = msg.senderGroup != null
          ? '${msg.senderGroup} ${msg.senderName}'
          : msg.senderName!;
      return '$prefix: $content';
    }
    return content;
  }

  DateTime get lastTime =>
      messages.isNotEmpty ? messages.last.time : DateTime(0);

  /// Чаты-сообщества доступны только для чтения, если текущий пользователь не является администратором.
  bool get canWrite =>
      type != ChatType.community || adminName == 'Я';

  // Сигнальное значение для определения «не передано» у nullable-полей в copyWith
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
    bool? isAcademic,
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
      isAcademic: isAcademic ?? this.isAcademic,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'messages': messages.map((m) => m.toJson()).toList(),
    'members': members.map((m) => m.toJson()).toList(),
    if (adminName != null) 'adminName': adminName,
    if (avatarPath != null) 'avatarPath': avatarPath,
    if (description != null) 'description': description,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    'isAcademic': isAcademic,
  };

  factory Chat.fromJson(Map<String, dynamic> j, {required String currentUserId}) => Chat(
    id: j['id'] as String,
    name: j['name'] as String,
    type: ChatType.values.byName(j['type'] as String? ?? 'direct'),
    messages: (j['messages'] as List<dynamic>?)
        ?.map((m) => Message.fromJson(m as Map<String, dynamic>, currentUserId: currentUserId))
        .toList() ?? [],
    members: (j['members'] as List<dynamic>?)
        ?.map((m) => ChatMember.fromJson(m as Map<String, dynamic>))
        .toList() ?? [],
    adminName: j['adminName'] as String?,
    avatarPath: j['avatarPath'] as String?,
    description: j['description'] as String?,
    createdAt: j['createdAt'] != null ? DateTime.parse(j['createdAt'] as String) : null,
    isAcademic: j['isAcademic'] as bool? ?? false,
  );
}
