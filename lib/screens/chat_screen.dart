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

/// Full-screen view for a single chat: message list, input bar, and media picker.
class ChatScreen extends StatefulWidget {
  final Chat chat;
  final ChatService service;
  final ValueChanged<Chat> onChatUpdated;
  final List<AppContact> contacts;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.service,
    required this.onChatUpdated,
    this.contacts = const [],
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

  @override
  void initState() {
    super.initState();
    _currentChat = widget.chat;
    _messages = List.from(widget.chat.messages);
    _loadAvatar();
    // Scroll to the latest message once the first frame is rendered.
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

    final updated = await widget.service.sendMessage(
      chatId: _currentChat.id,
      text: text,
      attachment: attachment,
    );
    if (!mounted) return;
    setState(() {
      _messages = List.from(updated.messages);
      _currentChat = updated;
    });
    widget.onChatUpdated(updated);
    _scrollToBottom();
  }

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
    // Clear editing state before the async call to prevent double-submit.
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
              leading: ChatAvatar(type: c.type),
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
                child: Icon(Icons.reply, color: Colors.white, size: 20),
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
    // Reclassify video files picked through the generic document picker.
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

  Future<void> _openSettings() async {
    final updated = await Navigator.push<Chat>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatSettingsScreen(chat: _currentChat),
      ),
    );
    if (updated == null || !mounted) return;
    final saved = await widget.service.updateChatSettings(updated);
    if (!mounted) return;
    setState(() => _currentChat = saved);
    widget.onChatUpdated(saved);
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
    final chat = _currentChat;

    return Scaffold(
      appBar: _isSelectionMode
          ? AppBar(
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
              title: Column(
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
              actions: [
                if (chat.type != ChatType.direct)
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
                  interlocutorAvatarPath: chat.type == ChatType.direct
                      ? chat.avatarPath
                      : null,
                  isSelected: _selectedIds.contains(msg.id),
                  isSelectionMode: _isSelectionMode,
                  onLongPress: () => _showMessageActions(msg),
                  onTap: () => _toggleSelect(msg.id),
                );
              },
            ),
          ),
          if (!_isSelectionMode) ...[
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
