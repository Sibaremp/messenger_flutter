import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';
import '../widgets/chat_widgets.dart';
import '../profile_screen.dart' show ProfileStorage;
import 'chat_settings_screen.dart';
import 'comments_screen.dart';
import 'contact_profile_screen.dart';
import 'group_profile_screen.dart';

/// Полноэкранное представление одного чата: список сообщений, панель ввода и выбор медиа.
class ChatScreen extends StatefulWidget {
  final Chat chat;
  final ChatService service;
  final ValueChanged<Chat> onChatUpdated;
  final List<AppContact> contacts;
  /// Если true — экран встроен в панель (desktop), кнопка «назад» скрыта.
  final bool embedded;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.service,
    required this.onChatUpdated,
    this.contacts = const [],
    this.embedded = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late List<Message> _messages;
  late Chat _currentChat;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _myAvatarPath;

  // ── Режим выделения ───────────────────────────────────
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  // ── Режим редактирования ──────────────────────────────
  Message? _editingMessage;

  // ── Ответ на сообщение (reply) ───────────────────────
  Message? _replyingTo;

  // ── Комментарии (embedded-режим, desktop) ────────────
  Message? _commentsMessage;

  // ── Встроенный профиль (embedded-режим, desktop) ─────
  /// 'group' | 'contact' | null
  String? _embeddedProfileType;

  @override
  void initState() {
    super.initState();
    _currentChat = widget.chat;
    _messages = List.from(widget.chat.messages);
    _loadAvatar();
    // Прокрутить к последнему сообщению после отрисовки первого кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadAvatar() async {
    final profile = await ProfileStorage.loadProfile();
    if (mounted) setState(() => _myAvatarPath = profile.avatarPath);
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

    final updated = await widget.service.sendMessage(
      chatId: _currentChat.id,
      text: text,
      attachment: attachment,
      replyTo: reply,
    );
    if (!mounted) return;
    setState(() {
      _messages = List.from(updated.messages);
      _currentChat = updated;
      _replyingTo = null;
    });
    widget.onChatUpdated(updated);
    _scrollToBottom();
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

    final updated = await widget.service.editMessage(
      chatId: _currentChat.id,
      messageId: editedId,
      newText: text,
    );
    if (!mounted) return;
    setState(() {
      _messages = List.from(updated.messages);
      _currentChat = updated;
    });
    widget.onChatUpdated(updated);
  }

  void _cancelEdit() {
    setState(() => _editingMessage = null);
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
      _messages = List.from(updated.messages);
      _currentChat = updated;
    });
    widget.onChatUpdated(updated);
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });

    final updated = await widget.service.deleteMessages(
      chatId: _currentChat.id,
      messageIds: ids,
    );
    if (!mounted) return;
    setState(() {
      _messages = List.from(updated.messages);
      _currentChat = updated;
    });
    widget.onChatUpdated(updated);
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
      attachment: attachment,
      replyTo: replyTo,
    );
    if (!mounted) return null;
    setState(() {
      _messages = List.from(updated.messages);
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
      _messages = List.from(updated.messages);
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
      _messages = List.from(updated.messages);
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
        builder: (_) => GroupProfileScreen(chat: _currentChat),
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
  /// Доступ только для создателя или админа.
  bool _canAccessSettings(Chat chat) {
    // Если текущий пользователь — создатель (adminName == 'Я')
    if (chat.adminName == 'Я') return true;
    // Проверяем роль в списке участников
    // Текущий пользователь не является участником members — он создатель по-умолчанию
    // Если нет adminName, значит создатель — текущий пользователь
    if (chat.adminName == null) return true;
    return false;
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
      // Чат удалён — возвращаемся в список
      Navigator.of(context).pop();
    } else if (result is Chat) {
      final saved = await widget.service.updateChatSettings(result);
      if (!mounted) return;
      setState(() => _currentChat = saved);
      widget.onChatUpdated(saved);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return MessageBubble(
                  message: msg,
                  showSenderName: chat.type != ChatType.direct,
                  myAvatarPath: _myAvatarPath,
                  // Аватар и его показ — только для личных чатов
                  showInterlocutorAvatar: chat.type == ChatType.direct,
                  interlocutorAvatarPath: chat.type == ChatType.direct
                      ? chat.avatarPath
                      : null,
                  isSelected: _selectedIds.contains(msg.id),
                  isSelectionMode: _isSelectionMode,
                  onLongPress: () => _showMessageActions(msg),
                  onTap: () => _toggleSelect(msg.id),
                  // Комментарии — только для сообществ
                  showComments: chat.type == ChatType.community,
                  onOpenComments: chat.type == ChatType.community
                      ? () => _openComments(msg)
                      : null,
                  onReply: () => _startReply(msg),
                );
              },
            ),
          ),
          if (!_isSelectionMode) ...[
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
            if (chat.canWrite)
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
