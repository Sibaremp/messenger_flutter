import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';
import '../widgets/chat_widgets.dart';
import '../services/auth_service.dart' as svc;
import 'chat_settings_screen.dart';
import 'comments_screen.dart';
import 'contact_profile_screen.dart';
import 'group_profile_screen.dart';

// ── Элементы плоского списка (разделитель дат + сообщение) ───────────────────

sealed class _ListItem {}

/// Визуальный разделитель между группами сообщений с разными датами.
final class _SeparatorItem extends _ListItem {
  final DateTime date;
  _SeparatorItem(this.date);
}

/// Обёртка над сообщением для плоского списка.
final class _MsgItem extends _ListItem {
  final Message message;
  _MsgItem(this.message);
}

// ─────────────────────────────────────────────────────────────────────────────

/// Полноэкранное представление одного чата: список сообщений, панель ввода и выбор медиа.
class ChatScreen extends StatefulWidget {
  final Chat chat;
  final ChatService service;
  final ValueChanged<Chat> onChatUpdated;
  final List<AppContact> contacts;
  /// Если true — экран встроен в панель (desktop), кнопка «назад» скрыта.
  final bool embedded;
  final svc.AuthService? auth;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.service,
    required this.onChatUpdated,
    this.contacts = const [],
    this.embedded = false,
    this.auth,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late List<Message> _messages;
  /// Плоский список для ListView: содержит _SeparatorItem и _MsgItem.
  List<_ListItem> _items = [];
  late Chat _currentChat;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _myAvatarPath;

  // ── Режим выделения ───────────────────────────────────
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  bool _isUploadingFile = false;

  // ── Режим редактирования ──────────────────────────────
  Message? _editingMessage;

  // ── Ответ на сообщение (reply) ───────────────────────
  Message? _replyingTo;

  // ── Комментарии (embedded-режим, desktop) ────────────
  Message? _commentsMessage;

  // ── Встроенный профиль (embedded-режим, desktop) ─────
  /// 'group' | 'contact' | null
  String? _embeddedProfileType;

  // ── Закреплённые сообщения ────────────────────────────
  /// Индекс текущего закреплённого сообщения в баре (цикличный).
  int _pinnedBarIndex = 0;
  /// Ключи для GlobalKey-прокрутки к конкретному сообщению.
  final Map<String, GlobalKey> _itemKeys = {};

  // ── @упоминания ───────────────────────────────────────
  /// Поисковый запрос после '@' (null — пикер не показывается).
  String? _mentionQuery;
  /// Позиция символа '@' в тексте поля ввода.
  int? _mentionStart;
  /// Упоминания, накопленные в текущем черновике сообщения.
  final List<Mention> _pendingMentions = [];

  // ── Подписка на realtime-события (SignalR) ───────────
  StreamSubscription<ChatEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _currentChat = widget.chat;
    _setMessages(widget.chat.messages);
    _loadAvatar();
    _controller.addListener(_onTextChanged);
    // Подписка на события от сервера — чтобы новые сообщения, правки
    // и удаления сразу появлялись в открытом чате без повторного входа.
    _eventSub = widget.service.events.listen(_onChatEvent);
    // Отмечаем все чужие сообщения прочитанными при входе в чат — это
    // сработает только в ApiChatService после того, как SignalR подключится,
    // но это нормально: безопасный повтор на сервере (read-status уже есть).
    _markAllUnreadRead();
    // Прокрутить к последнему сообщению после отрисовки первого кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// Отправляет markRead для всех чужих сообщений в текущем чате.
  /// Сервер сам отфильтрует уже прочитанные и разошлёт MessageStatusChanged
  /// только отправителям новых «прочитанных» сообщений.
  void _markAllUnreadRead() {
    final ids = _messages
        .where((m) => !m.isMe && m.status != MessageStatus.read)
        .map((m) => m.id)
        .toList();
    if (ids.isEmpty) return;
    // Запуск без await — это фоновая операция, не должна блокировать UI
    // и падения хаба (например, во время переподключения) не должны
    // просачиваться в экран.
    widget.service.markRead(chatId: _currentChat.id, messageIds: ids);
  }

  /// Обработка realtime-событий от сервера для текущего чата.
  void _onChatEvent(ChatEvent event) {
    if (!mounted) return;
    switch (event) {
      case MessageReceived(:final chatId, :final message):
        if (chatId != _currentChat.id) return;
        // Не дублируем, если сообщение уже есть (например, пришло и в ответе
        // от sendMessage, и через SignalR).
        if (_messages.any((m) => m.id == message.id)) return;
        final wasNearBottom = _isNearBottom();
        setState(() {
          _setMessages([..._messages, message]);
        });
        // Если это чужое сообщение, а чат открыт — сразу помечаем прочитанным.
        if (!message.isMe) {
          widget.service.markRead(
            chatId: _currentChat.id,
            messageIds: [message.id],
          );
        }
        // Скроллим только если пользователь уже был у низа списка —
        // чтобы не выдёргивать его, когда он читает историю выше.
        if (wasNearBottom) _scrollToBottom();
      case MessageEdited(:final chatId, :final messageId, :final newText):
        if (chatId != _currentChat.id) return;
        setState(() {
          _setMessages(_messages
              .map((m) => m.id == messageId
                  ? m.copyWith(text: newText, isEdited: true)
                  : m)
              .toList());
        });
      case MessageDeleted(:final chatId, :final messageIds):
        if (chatId != _currentChat.id) return;
        setState(() {
          _setMessages(_messages.where((m) => !messageIds.contains(m.id)).toList());
          if (_editingMessage != null && messageIds.contains(_editingMessage!.id)) {
            _editingMessage = null;
            _controller.clear();
            _pendingMentions.clear();
            _mentionQuery = null;
            _mentionStart = null;
          }
          if (_replyingTo != null && messageIds.contains(_replyingTo!.id)) {
            _replyingTo = null;
          }
        });
      case ChatUpdated(:final chat):
        if (chat.id != _currentChat.id) return;
        setState(() {
          _currentChat = chat;
          _setMessages(chat.messages);
        });
      case ChatDeleted():
        // Удалили текущий чат — ничего не делаем тут, родитель закроет экран.
        break;
      case MessageStatusChanged(
          :final chatId,
          :final messageId,
          :final status,
        ):
        if (chatId != _currentChat.id) return;
        // Обновляем статус в нашем локальном списке, чтобы галочки
        // перекрасились (✓ → ✓✓ → голубые ✓✓) без перезагрузки чата.
        setState(() {
          _setMessages(_messages
              .map((m) => m.id == messageId ? m.copyWith(status: status) : m)
              .toList());
        });
      case MessagePinned(:final chatId, :final messageId):
        if (chatId != _currentChat.id) return;
        setState(() {
          final ids = List<String>.from(_currentChat.pinnedMessageIds);
          if (!ids.contains(messageId)) ids.add(messageId);
          _currentChat = _currentChat.copyWith(pinnedMessageIds: ids);
        });
      case MessageUnpinned(:final chatId, :final messageId):
        if (chatId != _currentChat.id) return;
        setState(() {
          final ids = _currentChat.pinnedMessageIds
              .where((id) => id != messageId)
              .toList();
          _currentChat = _currentChat.copyWith(pinnedMessageIds: ids);
          _clampPinnedBarIndex(ids.length);
        });
      case PollVoted(:final chatId, :final messageId, :final userId, :final optionIds):
        if (chatId != _currentChat.id) return;
        setState(() {
          _setMessages(_messages.map((m) {
            if (m.id != messageId || m.poll == null) return m;
            final poll    = m.poll!;
            final prev    = poll.userVotes[userId] ?? const [];
            final newOpts = poll.options.map((o) {
              int v = o.votes;
              if (prev.contains(o.id))     v = (v - 1).clamp(0, 999999);
              if (optionIds.contains(o.id)) v++;
              return o.copyWith(votes: v);
            }).toList();
            final newUV = Map<String, List<String>>.from(poll.userVotes)
              ..[userId] = optionIds;
            final isMe = userId == (widget.auth?.currentUser?.name ?? '');
            return m.copyWith(
              poll: poll.copyWith(
                options: newOpts,
                userVotes: newUV,
                myVotes: isMe ? optionIds : poll.myVotes,
              ),
            );
          }).toList());
        });
      case PollClosed(:final chatId, :final messageId):
        if (chatId != _currentChat.id) return;
        setState(() {
          _setMessages(_messages.map((m) {
            if (m.id != messageId || m.poll == null) return m;
            return m.copyWith(poll: m.poll!.copyWith(isClosed: true));
          }).toList());
        });
      case SessionTerminated():
        // Обрабатывается глобально в ChatListScreen / ResponsiveShell.
        // ChatScreen не требует дополнительных действий.
        break;
    }
  }

  void _loadAvatar() {
    final avatarUrl = widget.auth?.currentUser?.avatarUrl;
    if (mounted) setState(() => _myAvatarPath = avatarUrl);
  }

  // ── Отправка или сохранение правки ────────────────────
  void _sendOrEdit({Attachment? attachment}) {
    if (_editingMessage != null) {
      _saveEdit();
    } else {
      _sendMessage(attachment: attachment);
    }
  }

  Future<void> _sendMessage({Attachment? attachment}) async {
    final text = _controller.text.trim();
    if (text.isEmpty && attachment == null) return;
    _controller.clear();

    final reply = _replyingTo != null
        ? ReplyInfo(
            messageId: _replyingTo!.id,
            senderName: _replyingTo!.senderName ?? (_replyingTo!.isMe ? 'Вы' : _currentChat.name),
            text: _replyingTo!.text,
          )
        : null;

    // Перестраиваем позиции упоминаний по финальному тексту
    final mentions = _buildMentionsForText(text);
    // Отправляем серверу только «настоящие» упоминания:
    //   • В личных чатах — никогда: userId собеседника неизвестен, а
    //     уведомление о каждом сообщении и так приходит.
    //   • В группах — только если userId ≠ username (т.е. сервер дал нам
    //     реальный UUID, а не просто отображаемое имя). Это исключает
    //     пинги «призрачных» пользователей, которые сервер находит по
    //     имени вместо ID.
    //   • @all — специальный случай, всегда разрешён.
    final capturedMentions = _currentChat.type == ChatType.direct
        ? const <Mention>[]
        : mentions
            .where((m) => m.userId == 'all' || m.userId != m.username)
            .toList();
    _pendingMentions.clear();

    // Показываем индикатор загрузки при отправке файла.
    final hasLocalFile = attachment != null;
    if (hasLocalFile && mounted) setState(() => _isUploadingFile = true);

    try {
      final updated = await widget.service.sendMessage(
        chatId: _currentChat.id,
        text: text,
        attachment: attachment,
        replyTo: reply,
        mentions: capturedMentions,
      );
      if (!mounted) return;
      setState(() {
        _isUploadingFile = false;
        _setMessages(updated.messages);
        _currentChat = updated;
        _replyingTo = null;
      });
      widget.onChatUpdated(updated);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingFile = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка отправки: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _startReply(Message message) {
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
    });
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  // ── Редактирование ────────────────────────────────────
  void _startEdit(Message message) {
    setState(() => _editingMessage = message);
    _controller.text = message.text;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
  }

  Future<void> _saveEdit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _editingMessage == null) return;
    final editedId = _editingMessage!.id;
    // Сбрасываем состояние редактирования до асинхронного вызова, чтобы исключить двойную отправку.
    setState(() => _editingMessage = null);
    _controller.clear();

    try {
      final updated = await widget.service.editMessage(
        chatId: _currentChat.id,
        messageId: editedId,
        newText: text,
      );
      if (!mounted) return;
      setState(() {
        _setMessages(updated.messages);
        _currentChat = updated;
      });
      widget.onChatUpdated(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Не удалось сохранить изменения: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _pendingMentions.clear();
      _mentionQuery = null;
      _mentionStart = null;
    });
    _controller.clear();
  }

  // ── Удаление ──────────────────────────────────────────
  Future<void> _deleteMessage(Message message) async {
    final updated = await widget.service.deleteMessages(
      chatId: _currentChat.id,
      messageIds: [message.id],
    );
    if (!mounted) return;
    setState(() {
      _setMessages(updated.messages);
      _currentChat = updated;
      // Сбрасываем режим редактирования / ответа, если они указывали на удалённое сообщение.
      if (_editingMessage?.id == message.id) {
        _editingMessage = null;
        _controller.clear();
        _pendingMentions.clear();
        _mentionQuery = null;
        _mentionStart = null;
      }
      if (_replyingTo?.id == message.id) _replyingTo = null;
    });
    widget.onChatUpdated(updated);
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });

    try {
      final updated = await widget.service.deleteMessages(
        chatId: _currentChat.id,
        messageIds: ids,
      );
      if (!mounted) return;
      setState(() {
        _setMessages(updated.messages);
        _currentChat = updated;
        // Сбрасываем режим редактирования / ответа, если их сообщения удалены.
        if (_editingMessage != null && ids.contains(_editingMessage!.id)) {
          _editingMessage = null;
          _controller.clear();
          _pendingMentions.clear();
          _mentionQuery = null;
          _mentionStart = null;
        }
        if (_replyingTo != null && ids.contains(_replyingTo!.id)) {
          _replyingTo = null;
        }
      });
      widget.onChatUpdated(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка удаления: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Выделение ─────────────────────────────────────────
  void _enterSelectionMode(Message first) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(first.id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // ── Пересылка ─────────────────────────────────────────
  void _forwardSelected() {
    final msgs = _messages.where((m) => _selectedIds.contains(m.id)).toList();
    _exitSelectionMode();
    _showForwardDialog(msgs);
  }

  void _showForwardDialog(List<Message> messages) async {
    final allChats = await widget.service.loadChats();
    if (!mounted) return;
    final others = allChats.where((c) => c.id != _currentChat.id).toList();
    if (others.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Нет других чатов для пересылки'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Переслать в...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            ...others.map((c) => ListTile(
              leading: ChatAvatar(type: c.type, chatName: c.name),
              title: Text(c.name),
              onTap: () {
                Navigator.pop(context);
                _forwardTo(c, messages);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _forwardTo(Chat target, List<Message> messages) async {
    final updated = await widget.service.forwardMessages(
      targetChatId: target.id,
      messages: messages,
    );
    if (!mounted) return;
    widget.onChatUpdated(updated);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Переслано в «${target.name}»'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.primary,
    ));
  }

  // ── Контекстное меню по долгому нажатию ──────────────
  void _showMessageActions(Message message) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            // Ответить
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: const Icon(Icons.reply, color: AppColors.primary, size: 20),
              ),
              title: const Text('Ответить'),
              onTap: () { Navigator.pop(context); _startReply(message); },
            ),
            // Редактировать (только своё текстовое сообщение)
            if (message.isMe &&
                message.text.isNotEmpty &&
                message.attachment == null)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                ),
                title: const Text('Редактировать'),
                onTap: () { Navigator.pop(context); _startEdit(message); },
              ),
            // Переслать
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.shortcut, color: Colors.white, size: 20),
              ),
              title: const Text('Переслать'),
              onTap: () { Navigator.pop(context); _showForwardDialog([message]); },
            ),
            // Выделить
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: const Icon(Icons.check_circle_outline,
                    color: AppColors.primary, size: 20),
              ),
              title: const Text('Выделить'),
              onTap: () { Navigator.pop(context); _enterSelectionMode(message); },
            ),
            // Закрепить / открепить
            if (_canPinMessages) ...[
              Builder(builder: (ctx) {
                final isPinned = _currentChat.pinnedMessageIds.contains(message.id);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: Icon(
                      isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(isPinned ? 'Открепить' : 'Закрепить'),
                  onTap: () {
                    Navigator.pop(context);
                    if (isPinned) {
                      _unpinMessage(message.id);
                    } else {
                      _pinMessage(message);
                    }
                  },
                );
              }),
            ],
            // Удалить (только своё)
            if (message.isMe)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFEBEE),
                  child: Icon(Icons.delete_outline, color: Colors.red, size: 20),
                ),
                title: const Text('Удалить',
                    style: TextStyle(color: Colors.red)),
                onTap: () { Navigator.pop(context); _deleteMessage(message); },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1280,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    final size = await file.length();
    _sendMessage(
      attachment: Attachment(
        path: picked.path,
        type: AttachmentType.image,
        fileName: picked.name,
        fileSize: size,
      ),
    );
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    if (file.path == null) return;
    // Переклассифицируем видеофайлы, выбранные через универсальный выборщик документов.
    final ext = file.name.split('.').last.toLowerCase();
    final attachType = kVideoExtensions.contains(ext)
        ? AttachmentType.video
        : AttachmentType.document;
    _sendMessage(
      attachment: Attachment(
        path: file.path!,
        type: attachType,
        fileName: file.name,
        fileSize: file.size,
      ),
    );
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    final size = await file.length();
    _sendMessage(
      attachment: Attachment(
        path: picked.path,
        type: AttachmentType.video,
        fileName: picked.name,
        fileSize: size,
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.photo_library, color: Colors.white),
              ),
              title: const Text('Галерея'),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.camera_alt, color: Colors.white),
              ),
              title: const Text('Камера'),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.videocam, color: Colors.white),
              ),
              title: const Text('Видео'),
              onTap: () { Navigator.pop(context); _pickVideo(); },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.insert_drive_file, color: Colors.white),
              ),
              title: const Text('Документ'),
              onTap: () { Navigator.pop(context); _pickDocument(); },
            ),
            // Опросы — только для групп и сообществ
            if (_currentChat.type != ChatType.direct)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.poll_outlined, color: Colors.white),
                ),
                title: const Text('Создать опрос'),
                onTap: () { Navigator.pop(context); _showCreatePollDialog(); },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Открывает раздел комментариев к [message].
  /// На desktop (embedded) — показывает внутри панели.
  /// На mobile — Navigator.push.
  // ── Общие колбэки для комментариев ──────────────
  Future<Message?> _commentOnSend(Message message, String text, {Attachment? attachment, ReplyInfo? replyTo}) async {
    final updated = await widget.service.addComment(
      chatId: _currentChat.id,
      messageId: message.id,
      text: text,
      senderName: widget.auth?.currentUser?.name ?? 'Я',
      attachment: attachment,
      replyTo: replyTo,
    );
    if (!mounted) return null;
    setState(() {
      _setMessages(updated.messages);
      _currentChat = updated;
      if (_commentsMessage != null) {
        _commentsMessage = updated.messages.firstWhere((m) => m.id == message.id);
      }
    });
    widget.onChatUpdated(updated);
    return updated.messages.firstWhere((m) => m.id == message.id);
  }

  Future<Message?> _commentOnEdit(Message message, String commentId, String newText) async {
    final updated = await widget.service.editComment(
      chatId: _currentChat.id,
      messageId: message.id,
      commentId: commentId,
      newText: newText,
    );
    if (!mounted) return null;
    setState(() {
      _setMessages(updated.messages);
      _currentChat = updated;
      if (_commentsMessage != null) {
        _commentsMessage = updated.messages.firstWhere((m) => m.id == message.id);
      }
    });
    widget.onChatUpdated(updated);
    return updated.messages.firstWhere((m) => m.id == message.id);
  }

  Future<Message?> _commentOnDelete(Message message, List<String> commentIds) async {
    final updated = await widget.service.deleteComments(
      chatId: _currentChat.id,
      messageId: message.id,
      commentIds: commentIds,
    );
    if (!mounted) return null;
    setState(() {
      _setMessages(updated.messages);
      _currentChat = updated;
      if (_commentsMessage != null) {
        _commentsMessage = updated.messages.firstWhere((m) => m.id == message.id);
      }
    });
    widget.onChatUpdated(updated);
    return updated.messages.firstWhere((m) => m.id == message.id);
  }

  void _openComments(Message message) {
    if (widget.embedded) {
      setState(() => _commentsMessage = message);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsScreen(
          message: message,
          chat: _currentChat,
          service: widget.service,
          currentUserName: widget.auth?.currentUser?.name,
          onSend: (text, {attachment, replyTo}) =>
              _commentOnSend(message, text, attachment: attachment, replyTo: replyTo),
          onEdit: (commentId, newText) =>
              _commentOnEdit(message, commentId, newText),
          onDelete: (commentIds) =>
              _commentOnDelete(message, commentIds),
        ),
      ),
    );
  }

  Widget _buildEmbeddedComments(Message message) {
    return CommentsScreen(
      key: ValueKey('comments_${message.id}'),
      message: message,
      chat: _currentChat,
      service: widget.service,
      embedded: true,
      currentUserName: widget.auth?.currentUser?.name,
      onBack: () => setState(() => _commentsMessage = null),
      onSend: (text, {attachment, replyTo}) =>
          _commentOnSend(message, text, attachment: attachment, replyTo: replyTo),
      onEdit: (commentId, newText) =>
          _commentOnEdit(message, commentId, newText),
      onDelete: (commentIds) =>
          _commentOnDelete(message, commentIds),
    );
  }

  /// Открывает профиль группы / сообщества (только для не-личных чатов).
  void _openGroupProfile() {
    if (widget.embedded) {
      setState(() => _embeddedProfileType = 'group');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupProfileScreen(
          chat: _currentChat,
          currentUserName: widget.auth?.currentUser?.name,
        ),
      ),
    );
  }

  /// Открывает экран профиля собеседника (только для личных чатов).
  void _openContactProfile() {
    if (_currentChat.type != ChatType.direct) return;
    if (widget.embedded) {
      setState(() => _embeddedProfileType = 'contact');
      return;
    }
    final contact = widget.contacts
        .where((c) => c.name == _currentChat.name)
        .firstOrNull;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactProfileScreen(
          name: _currentChat.name,
          avatarPath: _currentChat.avatarPath,
          description: _currentChat.description,
          phone: contact?.phone,
          group: contact?.group,
        ),
      ),
    );
  }

  Widget _buildEmbeddedProfile() {
    void backFn() => setState(() => _embeddedProfileType = null);
    if (_embeddedProfileType == 'group') {
      return GroupProfileScreen(
        key: ValueKey('gp_${_currentChat.id}'),
        chat: _currentChat,
        embedded: true,
        onBack: backFn,
        currentUserName: widget.auth?.currentUser?.name,
      );
    }
    // contact
    final contact = widget.contacts
        .where((c) => c.name == _currentChat.name)
        .firstOrNull;
    return ContactProfileScreen(
      key: ValueKey('cp_${_currentChat.name}'),
      name: _currentChat.name,
      avatarPath: _currentChat.avatarPath,
      description: _currentChat.description,
      phone: contact?.phone,
      group: contact?.group,
      embedded: true,
      onBack: backFn,
    );
  }

  /// Проверяет, может ли текущий пользователь открыть настройки группы.
  /// Доступ только для создателя или администратора.
  bool _canAccessSettings(Chat chat) {
    final me = widget.auth?.currentUser?.name;
    if (me == null || me.isEmpty) return false;
    return chat.isCreatorOrAdmin(me);
  }

  Future<void> _openSettings() async {
    // Результат: Chat — сохранить настройки, true — чат удалён, null — отмена.
    final result = await Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatSettingsScreen(
          chat: _currentChat,
          service: widget.service,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      // Чат удалён. На мобильном — pop к списку; на десктопе embedded-виджет
      // не открыт через Navigator, поэтому pop ничего не даст.
      // ResponsiveShell сам очистит _selectedChat через событие ChatDeleted.
      if (!widget.embedded) Navigator.of(context).pop();
    } else if (result is Chat) {
      final saved = await widget.service.updateChatSettings(result);
      if (!mounted) return;
      setState(() => _currentChat = saved);
      widget.onChatUpdated(saved);
    }
  }

  /// Плавный (или мгновенный при больших прыжках) скролл к последнему сообщению.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      // Если мы и так у низа (± небольшой зазор), ничего не делаем —
      // чтобы не вызывать бесконечные переустановки позиции при asynchronous
      // пересчёте высоты (подгрузка картинок и т.п.).
      if ((target - current).abs() < 2) return;
      _scrollController.jumpTo(target);
    });
  }

  /// Считаем пользователя "у низа" в пределах 120px от максимального скролла.
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return (pos.maxScrollExtent - pos.pixels) < 120;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Хелперы списка сообщений ──────────────────────────

  /// Обновляет [_messages] и перестраивает [_items] с разделителями дат.
  /// Вызывать внутри setState() или до первого build (в initState).
  void _setMessages(List<Message> msgs) {
    _messages = List.from(msgs)..sort((a, b) => a.time.compareTo(b.time));
    _items = _buildItemList();
  }

  List<_ListItem> _buildItemList() {
    final items = <_ListItem>[];
    DateTime? lastDay;
    for (final msg in _messages) {
      final day = DateTime(msg.time.year, msg.time.month, msg.time.day);
      if (lastDay == null || day != lastDay) {
        items.add(_SeparatorItem(day));
        lastDay = day;
      }
      items.add(_MsgItem(msg));
    }
    return items;
  }

  /// Возвращает (или создаёт) стабильный GlobalKey для сообщения с [messageId].
  GlobalKey _keyFor(String messageId) =>
      _itemKeys.putIfAbsent(messageId, GlobalKey.new);

  // ── Прокрутка к конкретному сообщению ─────────────────

  void _scrollToMessage(String messageId) {
    // 1. Если виджет уже отрисован — используем Scrollable.ensureVisible
    final key = _itemKeys[messageId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        alignment: 0.3,
      );
      return;
    }
    // 2. Fallback: приблизительная позиция по индексу
    final idx = _items.indexWhere(
        (it) => it is _MsgItem && it.message.id == messageId);
    if (idx < 0 || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final approx = (idx / (_items.length - 1).clamp(1, double.infinity)) * max;
    _scrollController.animateTo(
      approx.clamp(0.0, max),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  // ── Права на закрепление ──────────────────────────────

  /// В личных чатах закрепить может любой участник;
  /// в группах/сообществах — только создатель или администратор.
  bool get _canPinMessages {
    if (_currentChat.type == ChatType.direct) return true;
    return _currentChat.isCreatorOrAdmin(widget.auth?.currentUser?.name);
  }

  // ── Закрепить / открепить сообщение ───────────────────

  Future<void> _pinMessage(Message message) async {
    final pinned = _currentChat.pinnedMessageIds;
    if (pinned.contains(message.id)) return;
    if (pinned.length >= ChatService.maxPinnedMessages) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Можно закрепить не более ${ChatService.maxPinnedMessages} сообщений'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    try {
      final updated = await widget.service.pinMessage(
        chatId: _currentChat.id,
        messageId: message.id,
      );
      if (!mounted) return;
      setState(() => _currentChat = updated);
      widget.onChatUpdated(updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Сообщение закреплено'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _unpinMessage(String messageId) async {
    try {
      final updated = await widget.service.unpinMessage(
        chatId: _currentChat.id,
        messageId: messageId,
      );
      if (!mounted) return;
      setState(() {
        _currentChat = updated;
        _clampPinnedBarIndex(updated.pinnedMessageIds.length);
      });
      widget.onChatUpdated(updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Сообщение откреплено'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _clampPinnedBarIndex(int newLen) {
    if (newLen == 0) {
      _pinnedBarIndex = 0;
    } else if (_pinnedBarIndex >= newLen) {
      _pinnedBarIndex = newLen - 1;
    }
  }

  // ── Tap по бару закреплённых ──────────────────────────

  void _onPinnedBarTap() {
    final pinned = _currentChat.pinnedMessageIds;
    if (pinned.isEmpty) return;
    final messageId = pinned[_pinnedBarIndex];
    _scrollToMessage(messageId);
    setState(() {
      _pinnedBarIndex = (_pinnedBarIndex + 1) % pinned.length;
    });
  }

  // ── @упоминания ───────────────────────────────────────

  /// Слушатель текстового поля: обнаруживает активный ввод @упоминания.
  void _onTextChanged() {
    final text   = _controller.text;
    final cursor = _controller.selection.baseOffset;
    if (cursor < 0) {
      if (_mentionQuery != null) setState(() { _mentionQuery = null; _mentionStart = null; });
      return;
    }
    final before  = cursor <= text.length ? text.substring(0, cursor) : text;
    final atIndex = before.lastIndexOf('@');
    if (atIndex < 0) {
      if (_mentionQuery != null) setState(() { _mentionQuery = null; _mentionStart = null; });
      return;
    }
    // @ должна стоять в начале или после пробела
    if (atIndex > 0 && !RegExp(r'\s').hasMatch(text[atIndex - 1])) {
      if (_mentionQuery != null) setState(() { _mentionQuery = null; _mentionStart = null; });
      return;
    }
    // Между @ и курсором не должно быть пробела
    final afterAt = before.substring(atIndex + 1);
    if (afterAt.contains(' ') || afterAt.contains('\n')) {
      if (_mentionQuery != null) setState(() { _mentionQuery = null; _mentionStart = null; });
      return;
    }
    // Лимит упоминаний
    if (_pendingMentions.length >= ChatService.maxMentionsPerMessage) {
      if (_mentionQuery != null) setState(() { _mentionQuery = null; _mentionStart = null; });
      return;
    }
    setState(() { _mentionQuery = afterAt; _mentionStart = atIndex; });
  }

  /// Вставляет выбранного участника как @упоминание.
  void _insertMention(ChatMember member) {
    if (_mentionStart == null) return;
    if (_pendingMentions.length >= ChatService.maxMentionsPerMessage) return;
    // Предпочитаем серверный userId; при его отсутствии используем отображаемое имя.
    _doInsertMention(member.userId ?? member.name, member.name);
  }

  /// Вставляет @all (только для администраторов).
  void _insertMentionAll() {
    if (_mentionStart == null) return;
    if (_pendingMentions.length >= ChatService.maxMentionsPerMessage) return;
    _doInsertMention('all', 'all');
  }

  void _doInsertMention(String userId, String username) {
    final text   = _controller.text;
    final cursor = _controller.selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, _mentionStart!);
    final after  = cursor < text.length ? text.substring(cursor) : '';
    final token  = '@$username';
    final newText = '$before$token $after';
    setState(() {
      _pendingMentions.add(Mention(
        userId:   userId,
        username: username,
        offset:   _mentionStart!,
        length:   token.length,
      ));
      _mentionQuery = null;
      _mentionStart = null;
    });
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: before.length + token.length + 1),
    );
  }

  /// Перестраивает список упоминаний на основе финального текста сообщения.
  /// Поддерживает как упоминания, выбранные из пикера (через [_pendingMentions]),
  /// так и вручную набранные @username (матчатся по участникам чата).
  List<Mention> _buildMentionsForText(String text) {
    // userId участников, уже выбранных через пикер
    final pendingByName = <String, String>{
      for (final m in _pendingMentions) m.username: m.userId,
    };

    // Fallback: все участники чата (вручную набранные упоминания)
    final membersByName = <String, String>{};
    for (final m in _currentChat.members) {
      // Предпочитаем серверный userId; при его отсутствии — имя
      membersByName[m.name] = m.userId ?? m.name;
    }
    // В личном чате: добавляем собеседника как виртуального участника.
    // Серверного userId нет — упоминания в direct-чате не отправляются на сервер
    // (метаданные не нужны: получатель и так уведомляется о каждом сообщении).
    if (_currentChat.type == ChatType.direct) {
      membersByName[_currentChat.name] = _currentChat.name;
    }
    // @all — специальное упоминание
    membersByName['all'] = 'all';

    final result = <Mention>[];
    final regex  = RegExp(r'@(\S+)');
    for (final match in regex.allMatches(text)) {
      final raw  = match.group(1)!;
      final name = raw.replaceAll(RegExp(r'[.,!?;:\n]+$'), '');
      // Приоритет: пикер → участники чата
      final userId = pendingByName[name] ?? membersByName[name];
      if (userId == null) continue;
      result.add(Mention(
        userId:   userId,
        username: name,
        offset:   match.start,
        length:   match.end - match.start,
      ));
      if (result.length >= ChatService.maxMentionsPerMessage) break;
    }
    return result;
  }

  /// Тап по @упоминанию → открывает профиль пользователя.
  void _onMentionTap(Mention mention) {
    if (mention.userId == 'all') return;
    final contact = widget.contacts
        .where((c) => c.name == mention.username)
        .firstOrNull;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactProfileScreen(
          name:        mention.username,
          avatarPath:  _currentChat.type == ChatType.direct ? _currentChat.avatarPath : null,
          description: null,
          phone:       contact?.phone,
          group:       contact?.group,
        ),
      ),
    );
  }

  /// Виджет-пикер участников для @упоминания (появляется над полем ввода).
  Widget _buildMentionPicker() {
    final query = (_mentionQuery ?? '').toLowerCase();

    // Для личных чатов показываем собеседника как виртуального участника
    final baseMembers = _currentChat.type == ChatType.direct &&
            _currentChat.members.isEmpty
        ? [ChatMember(name: _currentChat.name, role: MemberRole.member)]
        : _currentChat.members;

    final members = baseMembers
        .where((m) => m.name.toLowerCase().contains(query))
        .toList();
    final showAll = _canPinMessages &&
        ('all'.contains(query) || 'everyone'.contains(query) || query.isEmpty);
    if (members.isEmpty && !showAll) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          if (showAll)
            ListTile(
              dense: true,
              leading: const CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.alternate_email, size: 16, color: Colors.white),
              ),
              title: const Text('@all',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Упомянуть всех',
                  style: TextStyle(fontSize: 11)),
              onTap: _insertMentionAll,
            ),
          ...members.map((m) {
            // Есть ли реальный серверный ID? Если нет — пинг не дойдёт.
            final hasServerId = m.userId != null && m.userId != m.name;
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              title: Text(m.name),
              subtitle: m.group != null || !hasServerId
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (m.group != null)
                          Text(m.group!, style: const TextStyle(fontSize: 11)),
                        if (!hasServerId)
                          const Text(
                            'Упоминание только визуальное (сервер не выдал ID)',
                            style: TextStyle(fontSize: 10, color: AppColors.subtle),
                          ),
                      ],
                    )
                  : null,
              trailing: hasServerId
                  ? null
                  : const Icon(Icons.notifications_off_outlined,
                      size: 16, color: AppColors.subtle),
              onTap: () => _insertMention(m),
            );
          }),
        ],
      ),
    );
  }

  // ── Опросы ───────────────────────────────────────────

  Future<void> _votePoll(String messageId, List<String> optionIds) async {
    try {
      final updated = await widget.service.votePoll(
        chatId:    _currentChat.id,
        messageId: messageId,
        optionIds: optionIds,
        userId:    widget.auth?.currentUser?.name ?? 'me',
      );
      if (!mounted) return;
      setState(() { _setMessages(updated.messages); _currentChat = updated; });
      widget.onChatUpdated(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка голосования: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _closePoll(String messageId) async {
    try {
      final updated = await widget.service.closePoll(
        chatId:    _currentChat.id,
        messageId: messageId,
      );
      if (!mounted) return;
      setState(() { _setMessages(updated.messages); _currentChat = updated; });
      widget.onChatUpdated(updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Опрос завершён'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _sendPoll(_PollDraft draft) async {
    try {
      final updated = await widget.service.sendPoll(
        chatId:        _currentChat.id,
        question:      draft.question,
        options:       draft.options,
        type:          draft.type,
        isAnonymous:   draft.isAnonymous,
        canChangeVote: draft.canChangeVote,
        deadline:      draft.deadline,
      );
      if (!mounted) return;
      setState(() { _setMessages(updated.messages); _currentChat = updated; });
      widget.onChatUpdated(updated);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка создания опроса: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showCreatePollDialog() {
    showDialog<_PollDraft>(
      context: context,
      builder: (_) => const _CreatePollDialog(),
    ).then((draft) { if (draft != null) _sendPoll(draft); });
  }

  @override
  Widget build(BuildContext context) {
    // Desktop embedded: показываем вложенные экраны вместо чата
    if (widget.embedded) {
      if (_embeddedProfileType != null) return _buildEmbeddedProfile();
      if (_commentsMessage != null) return _buildEmbeddedComments(_commentsMessage!);
    }

    final chat = _currentChat;

    return Scaffold(
      appBar: _isSelectionMode
          ? AppBar(
              automaticallyImplyLeading: false,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              ),
              title: Text('${_selectedIds.length} выбрано'),
              actions: [
                if (_selectedIds.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.reply),
                    tooltip: 'Переслать',
                    onPressed: _forwardSelected,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Удалить',
                    onPressed: _deleteSelected,
                  ),
                ],
              ],
            )
          : AppBar(
              // Аватар чата слева от заголовка
              automaticallyImplyLeading: false,
              leadingWidth: widget.embedded ? 48 : 90,
              leading: widget.embedded
                  ? Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: GestureDetector(
                        onTap: chat.type == ChatType.direct
                            ? _openContactProfile
                            : _openGroupProfile,
                        child: ChatAvatar(
                          type: chat.type,
                          avatarPath: chat.avatarPath,
                          chatName: chat.name,
                          radius: AppSizes.avatarRadiusSmall,
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 40,
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back, size: 22),
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                          GestureDetector(
                            onTap: chat.type == ChatType.direct
                                ? _openContactProfile
                                : _openGroupProfile,
                            child: ChatAvatar(
                              type: chat.type,
                              avatarPath: chat.avatarPath,
                              chatName: chat.name,
                              radius: AppSizes.avatarRadiusSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
              title: GestureDetector(
                onTap: chat.type == ChatType.direct
                    ? _openContactProfile
                    : _openGroupProfile,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chat.name),
                    if (chat.type != ChatType.direct)
                      Text(
                        chat.type == ChatType.group
                            ? '${chat.members.length + 1} участников'
                            : 'Сообщество · ${chat.members.length + 1} подписчиков',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.normal),
                      ),
                  ],
                ),
              ),
              actions: [
                if (chat.type != ChatType.direct && _canAccessSettings(chat))
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Настройки',
                    onPressed: _openSettings,
                  ),
              ],
            ),
      body: Column(
        children: [
          // ── Индикатор загрузки файла ──────────────────────────────────
          if (_isUploadingFile)
            const LinearProgressIndicator(),

          // ── Бар закреплённых сообщений (Telegram-style) ──
          if (_currentChat.pinnedMessageIds.isNotEmpty)
            PinnedMessagesBar(
              pinnedMessages: _currentChat.pinnedMessageIds
                  .map((id) => _messages.where((m) => m.id == id).firstOrNull)
                  .whereType<Message>()
                  .toList(),
              currentIndex: _pinnedBarIndex,
              onTap: _onPinnedBarTap,
              onUnpin: _canPinMessages ? _unpinMessage : null,
            ),
          Expanded(
            child: Builder(
              builder: (context) {
                // Собираем все медиа-вложения (фото + видео) для Telegram-style галереи
                final allMedia = _messages
                    .where((m) => m.attachment != null &&
                        (m.attachment!.type == AttachmentType.image || m.attachment!.type == AttachmentType.video))
                    .map((m) => m.attachment!)
                    .toList();
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  controller: _scrollController,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return switch (item) {
                      _SeparatorItem(:final date) => DateSeparator(date: date),
                      _MsgItem(:final message) => MessageBubble(
                          key: _keyFor(message.id),
                          message: message,
                          showSenderName: chat.type != ChatType.direct,
                          myAvatarPath: _myAvatarPath,
                          showInterlocutorAvatar: chat.type == ChatType.direct,
                          interlocutorAvatarPath: chat.type == ChatType.direct
                              ? chat.avatarPath
                              : null,
                          isSelected: _selectedIds.contains(message.id),
                          isSelectionMode: _isSelectionMode,
                          onLongPress: () => _showMessageActions(message),
                          onTap: () => _toggleSelect(message.id),
                          showComments: chat.type == ChatType.community,
                          onOpenComments: chat.type == ChatType.community
                              ? () => _openComments(message)
                              : null,
                          onReply: () => _startReply(message),
                          allMedia: allMedia,
                          // ── Упоминания ─────────────────
                          onMentionTap: _onMentionTap,
                          // ── Опросы ─────────────────────
                          currentUserId: widget.auth?.currentUser?.name,
                          onVotePoll: message.poll != null
                              ? (ids) => _votePoll(message.id, ids)
                              : null,
                          onClosePoll: (message.poll != null && _canPinMessages)
                              ? () => _closePoll(message.id)
                              : null,
                          canClosePoll: message.poll != null && _canPinMessages,
                        ),
                    };
                  },
                );
              },
            ),
          ),
          if (!_isSelectionMode) ...[
            // ── Пикер @упоминаний ──────────────────────
            if (_mentionQuery != null) _buildMentionPicker(),
            if (_replyingTo != null)
              _ReplyIndicator(
                message: _replyingTo!,
                chatName: _currentChat.name,
                onCancel: _cancelReply,
              ),
            if (_editingMessage != null)
              EditingIndicator(
                message: _editingMessage!,
                onCancel: _cancelEdit,
              ),
            if (chat.canWriteAs(widget.auth?.currentUser?.name))
              MessageInput(
                controller: _controller,
                onSend: _sendOrEdit,
                onAttach: _showAttachmentOptions,
                isEditing: _editingMessage != null,
              )
            else
              const LockedInput(),
          ],
        ],
      ),
    );
  }
}

/// Индикатор ответа на сообщение (над полем ввода, Telegram-style).
class _ReplyIndicator extends StatelessWidget {
  final Message message;
  final String chatName;
  final VoidCallback onCancel;

  const _ReplyIndicator({
    required this.message,
    required this.chatName,
    required this.onCancel,
  });

  static const _nameColors = [
    Color(0xFFD32F2F), Color(0xFF388E3C), Color(0xFF1976D2), Color(0xFFE64A19),
    Color(0xFF7B1FA2), Color(0xFF00838F), Color(0xFFC2185B), Color(0xFF455A64),
  ];

  @override
  Widget build(BuildContext context) {
    final baseName = message.isMe
        ? 'Вы'
        : (message.senderName ?? chatName);
    final senderName = (!message.isMe && message.senderGroup != null)
        ? '${message.senderGroup} $baseName'
        : baseName;
    final hash = senderName.codeUnits.fold<int>(0, (h, c) => h * 31 + c);
    final accentColor = _nameColors[hash.abs() % _nameColors.length];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          // Цветная полоска (как в Telegram)
          Container(
            width: 2.5,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(senderName,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  message.text.isEmpty
                      ? (message.attachment != null ? 'Вложение' : '')
                      : message.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black45),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onCancel,
              color: AppColors.subtle,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Данные для создания опроса ────────────────────────────────────────────────

class _PollDraft {
  final String question;
  final List<String> options;
  final PollType type;
  final bool isAnonymous;
  final bool canChangeVote;
  final DateTime? deadline;

  const _PollDraft({
    required this.question,
    required this.options,
    this.type = PollType.single,
    this.isAnonymous = false,
    this.canChangeVote = false,
    this.deadline,
  });
}

// ── Диалог создания опроса ───────────────────────────────────────────────────

class _CreatePollDialog extends StatefulWidget {
  const _CreatePollDialog();

  @override
  State<_CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<_CreatePollDialog> {
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];

  PollType  _type          = PollType.single;
  bool      _isAnonymous   = false;
  bool      _canChangeVote = false;
  DateTime? _deadline;

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) c.dispose();
    super.dispose();
  }

  void _addOption() {
    if (_optionCtrls.length >= 10) return;
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      _optionCtrls[index].dispose();
      _optionCtrls.removeAt(index);
    });
  }

  Future<void> _pickDeadline() async {
    final now  = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (!mounted) return;
    setState(() {
      _deadline = time == null
          ? date
          : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _submit() {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Введите вопрос'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final options = _optionCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Добавьте хотя бы 2 варианта'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    Navigator.of(context).pop(_PollDraft(
      question:      question,
      options:       options,
      type:          _type,
      isAnonymous:   _isAnonymous,
      canChangeVote: _canChangeVote,
      deadline:      _deadline,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Заголовок ─────────────────────────────
              Row(children: [
                const Icon(Icons.poll_outlined, color: AppColors.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Создать опрос',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
              const SizedBox(height: 16),
              // ── Вопрос ────────────────────────────────
              TextField(
                controller: _questionCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Вопрос *',
                  hintText: 'Введите вопрос…',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              // ── Варианты ──────────────────────────────
              const Text('Варианты ответа',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              ...List.generate(
                _optionCtrls.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _optionCtrls[i],
                        decoration: InputDecoration(
                          labelText:
                              'Вариант ${i + 1}${i < 2 ? ' *' : ''}',
                          border: const OutlineInputBorder(),
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    if (_optionCtrls.length > 2) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red),
                        onPressed: () => _removeOption(i),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ]),
                ),
              ),
              if (_optionCtrls.length < 10)
                TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить вариант'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: EdgeInsets.zero),
                ),
              const Divider(height: 24),
              // ── Настройки ─────────────────────────────
              const Text('Настройки',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              Row(children: [
                const Expanded(child: Text('Множественный выбор')),
                Switch(
                  value: _type == PollType.multiple,
                  onChanged: (v) => setState(() =>
                      _type = v ? PollType.multiple : PollType.single),
                  activeColor: AppColors.primary,
                ),
              ]),
              Row(children: [
                const Expanded(child: Text('Анонимный опрос')),
                Switch(
                  value: _isAnonymous,
                  onChanged: (v) =>
                      setState(() => _isAnonymous = v),
                  activeColor: AppColors.primary,
                ),
              ]),
              Row(children: [
                const Expanded(
                    child: Text('Разрешить изменить голос')),
                Switch(
                  value: _canChangeVote,
                  onChanged: (v) =>
                      setState(() => _canChangeVote = v),
                  activeColor: AppColors.primary,
                ),
              ]),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule,
                    color: AppColors.primary),
                title: Text(
                  _deadline == null
                      ? 'Без ограничения по времени'
                      : 'До ${_fmtDt(_deadline!)}',
                ),
                trailing: _deadline != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => _deadline = null),
                      )
                    : null,
                onTap: _pickDeadline,
              ),
              const SizedBox(height: 16),
              // ── Кнопки ────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    child: const Text('Создать'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDt(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year} $hh:$mi';
  }
}
