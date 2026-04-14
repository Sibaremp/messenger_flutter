import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';

/// Полноэкранный раздел комментариев к посту (стиль Telegram).
class CommentsScreen extends StatefulWidget {
  final Message message;
  final Chat chat;
  final ChatService service;
  /// Колбэк, возвращающий обновлённое сообщение после добавления/правки/удаления.
  final Future<Message?> Function(String text, {Attachment? attachment, ReplyInfo? replyTo}) onSend;
  final Future<Message?> Function(String commentId, String newText)? onEdit;
  final Future<Message?> Function(List<String> commentIds)? onDelete;
  /// Если true — встроен в панель (desktop), кнопка «назад» вызывает onBack.
  final bool embedded;
  final VoidCallback? onBack;

  const CommentsScreen({
    super.key,
    required this.message,
    required this.chat,
    required this.service,
    required this.onSend,
    this.onEdit,
    this.onDelete,
    this.embedded = false,
    this.onBack,
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late Message _message;

  // ── Режим ответа ─────────────────────────────────
  Comment? _replyingTo;

  // ── Режим редактирования ─────────────────────────
  Comment? _editingComment;

  // ── Режим выделения ──────────────────────────────
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  static const _senderColors = [
    Color(0xFFD32F2F), Color(0xFF388E3C), Color(0xFF1976D2), Color(0xFFE64A19),
    Color(0xFF7B1FA2), Color(0xFF00838F), Color(0xFFC2185B), Color(0xFF455A64),
  ];

  /// Фиксированные цвета имён пользователей (как в Telegram).
  static const _nameColors = [
    Color(0xFFE57373), Color(0xFF81C784), Color(0xFF64B5F6), Color(0xFFFFB74D),
    Color(0xFFBA68C8), Color(0xFF4DD0E1), Color(0xFFF06292), Color(0xFFAED581),
  ];

  Color _colorForName(String name) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
    return _nameColors[hash % _nameColors.length];
  }

  Color _senderColor(String name) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => h * 31 + c);
    return _senderColors[hash.abs() % _senderColors.length];
  }

  @override
  void initState() {
    super.initState();
    _message = widget.message;
    _scrollToEnd();
  }

  @override
  void didUpdateWidget(covariant CommentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message != oldWidget.message) {
      _message = widget.message;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  // ── Отправка / сохранение ────────────────────────
  void _sendOrEdit({Attachment? attachment}) {
    if (_editingComment != null) {
      _saveEdit();
    } else {
      _sendComment(attachment: attachment);
    }
  }

  Future<void> _sendComment({Attachment? attachment}) async {
    final text = _controller.text.trim();
    if (text.isEmpty && attachment == null) return;
    _controller.clear();

    final reply = _replyingTo != null
        ? ReplyInfo(
            messageId: _replyingTo!.id,
            senderName: _replyingTo!.senderName,
            text: _replyingTo!.text,
          )
        : null;

    final updated = await widget.onSend(
      text,
      attachment: attachment,
      replyTo: reply,
    );
    if (updated != null && mounted) {
      setState(() {
        _message = updated;
        _replyingTo = null;
      });
      _scrollToEnd();
    }
  }

  // ── Ответ ────────────────────────────────────────
  void _startReply(Comment comment) {
    setState(() {
      _replyingTo = comment;
      _editingComment = null;
    });
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  // ── Редактирование ───────────────────────────────
  void _startEdit(Comment comment) {
    setState(() {
      _editingComment = comment;
      _replyingTo = null;
    });
    _controller.text = comment.text;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
  }

  Future<void> _saveEdit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _editingComment == null) return;
    final editedId = _editingComment!.id;
    setState(() => _editingComment = null);
    _controller.clear();

    if (widget.onEdit != null) {
      final updated = await widget.onEdit!(editedId, text);
      if (updated != null && mounted) {
        setState(() => _message = updated);
      }
    }
  }

  void _cancelEdit() {
    setState(() => _editingComment = null);
    _controller.clear();
  }

  // ── Удаление ─────────────────────────────────────
  Future<void> _deleteComment(Comment comment) async {
    if (widget.onDelete != null) {
      final updated = await widget.onDelete!([comment.id]);
      if (updated != null && mounted) {
        setState(() => _message = updated);
      }
    }
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    _exitSelectionMode();
    if (widget.onDelete != null) {
      final updated = await widget.onDelete!(ids);
      if (updated != null && mounted) {
        setState(() => _message = updated);
      }
    }
  }

  // ── Пересылка ────────────────────────────────────
  void _forwardComment(Comment comment) {
    _showForwardDialog([comment]);
  }

  void _forwardSelected() {
    final comments = _message.comments
        .where((c) => _selectedIds.contains(c.id))
        .toList();
    _exitSelectionMode();
    _showForwardDialog(comments);
  }

  void _showForwardDialog(List<Comment> comments) async {
    final allChats = await widget.service.loadChats();
    if (!mounted) return;
    final others = allChats.where((c) => c.id != widget.chat.id).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Нет других чатов для пересылки'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
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
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(c.name.isNotEmpty ? c.name[0] : '?',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
              title: Text(c.name),
              onTap: () async {
                Navigator.pop(context);
                // Пересылаем каждый комментарий как сообщение
                for (final cmt in comments) {
                  await widget.service.sendMessage(
                    chatId: c.id,
                    text: cmt.text,
                    senderName: cmt.senderName,
                    attachment: cmt.attachment,
                  );
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Переслано в «${c.name}»'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.primary,
                  ));
                }
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Выделение ────────────────────────────────────
  void _enterSelectionMode(Comment first) {
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

  // ── Контекстное меню ─────────────────────────────
  void _showCommentActions(Comment comment) {
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
              onTap: () { Navigator.pop(context); _startReply(comment); },
            ),
            // Редактировать (только своё)
            if (comment.isMe && comment.text.isNotEmpty && comment.attachment == null)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                ),
                title: const Text('Редактировать'),
                onTap: () { Navigator.pop(context); _startEdit(comment); },
              ),
            // Переслать
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.shortcut, color: Colors.white, size: 20),
              ),
              title: const Text('Переслать'),
              onTap: () { Navigator.pop(context); _forwardComment(comment); },
            ),
            // Выделить
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: const Icon(Icons.check_circle_outline,
                    color: AppColors.primary, size: 20),
              ),
              title: const Text('Выделить'),
              onTap: () { Navigator.pop(context); _enterSelectionMode(comment); },
            ),
            // Удалить (только своё)
            if (comment.isMe)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFEBEE),
                  child: Icon(Icons.delete_outline, color: Colors.red, size: 20),
                ),
                title: const Text('Удалить',
                    style: TextStyle(color: Colors.red)),
                onTap: () { Navigator.pop(context); _deleteComment(comment); },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Вложения ─────────────────────────────────────
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
    _sendComment(
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
    final ext = file.name.split('.').last.toLowerCase();
    final attachType = kVideoExtensions.contains(ext)
        ? AttachmentType.video
        : AttachmentType.document;
    _sendComment(
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
    _sendComment(
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

  // ── UI ───────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final comments = _message.comments;
    final subtitle = comments.isEmpty
        ? 'Комментарии'
        : '${comments.length} ${_commentWord(comments.length)}';

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
                    icon: const Icon(Icons.shortcut),
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
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              foregroundColor: isDark ? Colors.white : Colors.black87,
              surfaceTintColor: Colors.transparent,
              elevation: 0.5,
              automaticallyImplyLeading: !widget.embedded,
              leading: widget.embedded
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: widget.onBack,
                    )
                  : null,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Обсуждение',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: isDark ? Colors.white54 : Colors.black45,
                      )),
                ],
              ),
            ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ── Исходный пост (пузырь) ─────────────────────
                _PostBubble(
                  message: widget.message,
                  chat: widget.chat,
                  isDark: isDark,
                  nameColor: _colorForName(
                      widget.message.senderName ?? widget.chat.name),
                ),
                const SizedBox(height: 4),
                _DividerPill(label: 'Начало обсуждения', isDark: isDark),
                const SizedBox(height: 4),
                // ── Комментарии ────────────────────────────────
                if (comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Center(
                      child: Text('Комментариев пока нет...',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 14,
                          )),
                    ),
                  )
                else
                  ...comments.map((c) => _buildCommentRow(c, isDark)),
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (!_isSelectionMode) ...[
            if (_replyingTo != null)
              _buildReplyIndicator(isDark),
            if (_editingComment != null)
              _buildEditIndicator(isDark),
            _buildInput(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentRow(Comment c, bool isDark) {
    final nameColor = _colorForName(c.senderName);

    Widget bubble = _CommentBubble(
      comment: c,
      isDark: isDark,
      nameColor: nameColor,
      senderColor: _senderColor(c.senderName),
      isSelected: _selectedIds.contains(c.id),
      isSelectionMode: _isSelectionMode,
      onLongPress: () => _showCommentActions(c),
      onTap: () => _toggleSelect(c.id),
      onReply: () => _startReply(c),
    );

    return bubble;
  }

  Widget _buildReplyIndicator(bool isDark) {
    final accentColor = _senderColor(_replyingTo!.senderName);
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
          Container(
            width: 2.5, height: 34,
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
                Text(_replyingTo!.senderName,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  _replyingTo!.text.isEmpty
                      ? (_replyingTo!.attachment != null ? 'Вложение' : '')
                      : _replyingTo!.text,
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
            width: 36, height: 36,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: _cancelReply,
              color: AppColors.subtle,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Редактирование',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  _editingComment!.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: AppColors.subtle),
            onPressed: _cancelEdit,
          ),
        ],
      ),
    );
  }

  Widget _buildInput(bool isDark) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            if (_editingComment == null)
              IconButton(
                icon: const Icon(Icons.attach_file, color: AppColors.subtle),
                onPressed: _showAttachmentOptions,
                splashRadius: 20,
              ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendOrEdit(),
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: 'Сообщение',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: AppColors.primary,
              child: IconButton(
                icon: Icon(
                  _editingComment != null ? Icons.check : Icons.send,
                  color: AppColors.textLight,
                ),
                onPressed: _sendOrEdit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Пузырь исходного поста
// ═══════════════════════════════════════════════════════════════════════════════

class _PostBubble extends StatelessWidget {
  final Message message;
  final Chat chat;
  final bool isDark;
  final Color nameColor;

  const _PostBubble({
    required this.message,
    required this.chat,
    required this.isDark,
    required this.nameColor,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleBg =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF);
    final screenW = MediaQuery.of(context).size.width;
    final maxW = screenW > 600 ? 500.0 : screenW * 0.85;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildAvatar(chat),
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxW),
              decoration: BoxDecoration(
                color: bubbleBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Text(
                      message.senderName ?? chat.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: nameColor,
                      ),
                    ),
                  ),
                  if (message.attachment != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _buildAttachment(message.attachment!),
                    ),
                  if (message.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Text(message.text,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: isDark ? Colors.white : Colors.black87,
                            height: 1.35,
                          )),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility_outlined,
                            size: 13,
                            color: isDark ? Colors.white38 : Colors.black38),
                        const SizedBox(width: 3),
                        Text('—',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38)),
                        const Spacer(),
                        Text(formatTime(message.time),
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(Chat chat) {
    if (chat.avatarPath != null) {
      final file = File(chat.avatarPath!);
      if (file.existsSync()) {
        return CircleAvatar(radius: 18, backgroundImage: FileImage(file));
      }
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: nameColor.withValues(alpha: 0.2),
      child: Text(
        chat.name.isNotEmpty ? chat.name[0].toUpperCase() : '?',
        style: TextStyle(
          color: nameColor,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildAttachment(Attachment att) {
    if (att.type == AttachmentType.image) {
      final file = File(att.path);
      if (file.existsSync()) {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: Image.file(file, fit: BoxFit.cover, width: double.infinity),
        );
      }
    }
    final icon = switch (att.type) {
      AttachmentType.image => Icons.image,
      AttachmentType.video => Icons.videocam,
      AttachmentType.document => Icons.insert_drive_file,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(att.fileName,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Разделитель-пилюля
// ═══════════════════════════════════════════════════════════════════════════════

class _DividerPill extends StatelessWidget {
  final String label;
  final bool isDark;

  const _DividerPill({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Пузырь комментария (с поддержкой свайпа, выделения, вложений, ответов)
// ═══════════════════════════════════════════════════════════════════════════════

class _CommentBubble extends StatefulWidget {
  final Comment comment;
  final bool isDark;
  final Color nameColor;
  final Color senderColor;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  final VoidCallback onReply;

  const _CommentBubble({
    required this.comment,
    required this.isDark,
    required this.nameColor,
    required this.senderColor,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onLongPress,
    required this.onTap,
    required this.onReply,
  });

  @override
  State<_CommentBubble> createState() => _CommentBubbleState();
}

class _CommentBubbleState extends State<_CommentBubble> {
  double _swipeOffset = 0;
  bool _swipeTriggered = false;
  static const _swipeThreshold = 64.0;

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final isDark = widget.isDark;
    final nameColor = widget.nameColor;
    final timeColor = isDark ? Colors.white38 : Colors.black38;

    final bubbleBg = c.isMe
        ? (isDark
            ? AppColors.primary.withValues(alpha: 0.18)
            : AppColors.primary.withValues(alpha: 0.08))
        : (isDark
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFFFFFFF));

    // ── Содержимое пузыря ──────────────────────────
    final bubbleContent = Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
      decoration: BoxDecoration(
        color: bubbleBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Имя отправителя
          Text.rich(
            TextSpan(children: [
              if (c.senderGroup != null)
                TextSpan(
                  text: '${c.senderGroup}  ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: widget.senderColor.withValues(alpha: 0.7),
                  ),
                ),
              TextSpan(
                text: c.senderName,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: widget.senderColor,
                ),
              ),
            ]),
          ),
          // Reply preview
          if (c.replyTo != null)
            _CommentReplyPreview(reply: c.replyTo!, isDark: isDark),
          // Вложение
          if (c.attachment != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _CommentAttachment(attachment: c.attachment!, isDark: isDark),
            ),
          const SizedBox(height: 3),
          // Текст + изм. + время
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (c.text.isNotEmpty)
                Flexible(
                  child: Text(c.text,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: isDark ? Colors.white : Colors.black87,
                        height: 1.3,
                      )),
                ),
              const SizedBox(width: 8),
              if (c.isEdited)
                Text('изм. ', style: TextStyle(fontSize: 10, color: timeColor)),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  formatTime(c.time),
                  style: TextStyle(fontSize: 11, color: timeColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // ── Строка с аватаром + пузырём ────────────────
    Widget row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.isSelectionMode ? widget.onTap : null,
      onLongPress: widget.isSelectionMode ? null : widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: widget.isSelected
            ? AppColors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Чекбокс выделения
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: widget.isSelectionMode
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isSelected ? AppColors.primary : Colors.transparent,
                          border: Border.all(
                            color: widget.isSelected ? AppColors.primary : AppColors.subtle,
                            width: 2,
                          ),
                        ),
                        child: widget.isSelected
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // Аватар
            CircleAvatar(
              radius: 18,
              backgroundColor: nameColor.withValues(alpha: 0.2),
              child: Text(
                c.senderName.isNotEmpty ? c.senderName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: nameColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Пузырь
            Flexible(child: bubbleContent),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );

    // ── Свайп для ответа ───────────────────────────
    if (!widget.isSelectionMode) {
      final swipeProgress = (_swipeOffset / _swipeThreshold).clamp(0.0, 1.0);
      row = GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            _swipeOffset = (_swipeOffset + details.delta.dx).clamp(0.0, _swipeThreshold + 20);
            if (!_swipeTriggered && _swipeOffset >= _swipeThreshold) {
              _swipeTriggered = true;
              HapticFeedback.lightImpact();
            }
          });
        },
        onHorizontalDragEnd: (_) {
          if (_swipeTriggered) widget.onReply();
          setState(() {
            _swipeOffset = 0;
            _swipeTriggered = false;
          });
        },
        onHorizontalDragCancel: () {
          setState(() {
            _swipeOffset = 0;
            _swipeTriggered = false;
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_swipeOffset > 4)
              Positioned(
                left: _swipeOffset - 44,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _swipeTriggered
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      Icons.reply,
                      size: 18 + (swipeProgress * 4),
                      color: _swipeTriggered ? Colors.white : AppColors.primary,
                    ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(_swipeOffset, 0),
              child: row,
            ),
          ],
        ),
      );
    }

    return row;
  }
}

// ── Превью ответа в комментарии ─────────────────────

class _CommentReplyPreview extends StatelessWidget {
  final ReplyInfo reply;
  final bool isDark;

  const _CommentReplyPreview({required this.reply, required this.isDark});

  static const _colors = [
    Color(0xFFD32F2F), Color(0xFF388E3C), Color(0xFF1976D2), Color(0xFFE64A19),
    Color(0xFF7B1FA2), Color(0xFF00838F), Color(0xFFC2185B), Color(0xFF455A64),
  ];

  @override
  Widget build(BuildContext context) {
    final hash = reply.senderName.codeUnits.fold<int>(0, (h, c) => h * 31 + c);
    final accentColor = _colors[hash.abs() % _colors.length];

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: accentColor.withValues(alpha: 0.1),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 2.5, color: accentColor),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(reply.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        )),
                    const SizedBox(height: 1),
                    Text(
                      reply.text.isEmpty ? 'Вложение' : reply.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Превью вложения в комментарии ───────────────────

class _CommentAttachment extends StatelessWidget {
  final Attachment attachment;
  final bool isDark;

  const _CommentAttachment({required this.attachment, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (attachment.type == AttachmentType.image) {
      final file = File(attachment.path);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file, width: 200, height: 200, fit: BoxFit.cover),
        );
      }
    }
    final icon = switch (attachment.type) {
      AttachmentType.image => Icons.image,
      AttachmentType.video => Icons.videocam,
      AttachmentType.document => Icons.insert_drive_file,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attachment.fileName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (attachment.fileSize != null)
                  Text(attachment.readableSize,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Склонение слова «комментарий».
String _commentWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 19) return 'комментариев';
  if (mod10 == 1) return 'комментарий';
  if (mod10 >= 2 && mod10 <= 4) return 'комментария';
  return 'комментариев';
}
