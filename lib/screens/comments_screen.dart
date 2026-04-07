import 'dart:io';
import 'package:flutter/material.dart';
import '../models.dart';
import '../app_constants.dart';

/// Полноэкранный раздел комментариев к посту (стиль Telegram).
class CommentsScreen extends StatefulWidget {
  final Message message;
  final Chat chat;
  final Future<Message?> Function(String text) onSend;
  /// Если true — встроен в панель (desktop), кнопка «назад» вызывает onBack.
  final bool embedded;
  final VoidCallback? onBack;

  const CommentsScreen({
    super.key,
    required this.message,
    required this.chat,
    required this.onSend,
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

  /// Фиксированные цвета имён пользователей (как в Telegram).
  static const _nameColors = [
    Color(0xFFE57373), // red
    Color(0xFF81C784), // green
    Color(0xFF64B5F6), // blue
    Color(0xFFFFB74D), // orange
    Color(0xFFBA68C8), // purple
    Color(0xFF4DD0E1), // cyan
    Color(0xFFF06292), // pink
    Color(0xFFAED581), // light green
  ];

  Color _colorForName(String name) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
    return _nameColors[hash % _nameColors.length];
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

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final updated = await widget.onSend(text);
    if (updated != null && mounted) {
      setState(() => _message = updated);
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final comments = _message.comments;
    final subtitle = comments.isEmpty
        ? 'Комментарии'
        : '${comments.length} ${_commentWord(comments.length)}';

    return Scaffold(
      appBar: AppBar(
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
                // ── «Начало обсуждения» ────────────────────────
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
                  ...comments.map((c) => _CommentBubble(
                        comment: c,
                        isDark: isDark,
                        nameColor: _colorForName(c.senderName),
                      )),
                const SizedBox(height: 8),
              ],
            ),
          ),
          _buildInput(isDark),
        ],
      ),
    );
  }

  Widget _buildInput(bool isDark) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : const Color(0xFFE0E0E0),
            ),
          ),
        ),
        child: Row(
          children: [
            // Скрепка
            IconButton(
              icon: Icon(Icons.attach_file,
                  color: isDark ? Colors.white54 : Colors.black45),
              onPressed: () {},
              splashRadius: 20,
            ),
            // Поле ввода
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  maxLines: null,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Сообщение...',
                    hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Эмодзи
            IconButton(
              icon: Icon(Icons.emoji_emotions_outlined,
                  color: isDark ? Colors.white54 : Colors.black45),
              onPressed: () {},
              splashRadius: 20,
            ),
            // Отправить
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.send, color: Colors.white, size: 18),
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
          // Аватар канала/группы
          _buildAvatar(chat),
          const SizedBox(width: 6),
          // Пузырь
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
                  // Имя автора
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
                  // Вложение
                  if (message.attachment != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _buildAttachment(message.attachment!),
                    ),
                  // Текст
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
                  // Время + просмотры
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
                                color: isDark
                                    ? Colors.white38
                                    : Colors.black38)),
                        const Spacer(),
                        Text(formatTime(message.time),
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.black38)),
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
    // Документ / видео — компактная плашка
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
// Пузырь комментария
// ═══════════════════════════════════════════════════════════════════════════════

class _CommentBubble extends StatelessWidget {
  final Comment comment;
  final bool isDark;
  final Color nameColor;

  const _CommentBubble({
    required this.comment,
    required this.isDark,
    required this.nameColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = comment;
    final bubbleBg = c.isMe
        ? (isDark
            ? AppColors.primary.withValues(alpha: 0.18)
            : AppColors.primary.withValues(alpha: 0.08))
        : (isDark
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFFFFFFF));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
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
          Flexible(
            child: Container(
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
                  // Имя (цветное)
                  Text(
                    c.senderName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: c.isMe ? AppColors.primary : nameColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Текст + время
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(c.text,
                            style: TextStyle(
                              fontSize: 14.5,
                              color: isDark ? Colors.white : Colors.black87,
                              height: 1.3,
                            )),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Text(
                          formatTime(c.time),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Правый отступ, чтобы пузырь не прижимался к краю
          const SizedBox(width: 40),
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
