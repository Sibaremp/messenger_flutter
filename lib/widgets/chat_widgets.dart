import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../models.dart';
import '../app_constants.dart';
import '../profile_screen.dart' show ProfileAvatar;

// ─── Аватар ───────────────────────────────────────────────────────────────────

/// Круглый аватар чата.
/// Если [avatarPath] задан и файл существует — показывает изображение,
/// иначе — иконку-заглушку по типу чата.
class ChatAvatar extends StatelessWidget {
  final ChatType type;
  final double radius;
  final String? avatarPath;
  /// Имя чата — используется для генерации уникального цвета аватара.
  final String? chatName;

  const ChatAvatar({
    super.key,
    this.type = ChatType.direct,
    this.radius = AppSizes.avatarRadiusLarge,
    this.avatarPath,
    this.chatName,
  });

  static const _avatarColors = [
    Color(0xFFE57373), Color(0xFF81C784), Color(0xFF64B5F6), Color(0xFFFFB74D),
    Color(0xFFBA68C8), Color(0xFF4DD0E1), Color(0xFFF06292), Color(0xFFAED581),
  ];

  Color get _color {
    if (chatName == null || chatName!.isEmpty) return AppColors.primary;
    final hash = chatName!.codeUnits.fold<int>(0, (h, c) => h + c);
    return _avatarColors[hash % _avatarColors.length];
  }

  IconData get _icon => switch (type) {
    ChatType.direct    => Icons.person,
    ChatType.group     => Icons.group,
    ChatType.community => Icons.campaign,
  };

  @override
  Widget build(BuildContext context) {
    if (avatarPath != null) {
      final file = File(avatarPath!);
      if (file.existsSync()) {
        return CircleAvatar(
          radius: radius,
          backgroundImage: FileImage(file),
        );
      }
    }
    final color = _color;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Icon(_icon, size: radius, color: color),
    );
  }
}

// ─── Иконка статуса сообщения ─────────────────────────────────────────────────

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  final Color color;

  const _StatusIcon({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      MessageStatus.sending  => Icon(Icons.access_time,   size: 12, color: color),
      MessageStatus.sent     => Icon(Icons.done,          size: 12, color: color),
      MessageStatus.delivered => Icon(Icons.done_all,     size: 12, color: color),
      MessageStatus.error    => const Icon(Icons.error_outline, size: 12, color: Colors.red),
    };
  }
}

// ─── Пузырь сообщения ─────────────────────────────────────────────────────────

/// Отображает одно сообщение в виде стилизованного пузырька с необязательным аватаром,
/// подсветкой выделения и превью вложения.
class MessageBubble extends StatefulWidget {
  final Message message;
  final bool showSenderName;
  final String? myAvatarPath;
  /// Путь к аватару собеседника (только для личных чатов).
  final String? interlocutorAvatarPath;
  /// Показывать ли аватар слева от чужих сообщений.
  /// true — личный чат (аватар всегда рисуется, даже если нет фото).
  /// false — группа/сообщество (аватар не рисуется).
  final bool showInterlocutorAvatar;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  /// Показывать ли кнопку комментариев (только для сообществ).
  final bool showComments;
  /// Колбэк при нажатии на «💬 N комментариев».
  final VoidCallback? onOpenComments;
  /// Колбэк ответа на сообщение (свайп вправо).
  final VoidCallback? onReply;

  const MessageBubble({
    super.key,
    required this.message,
    this.showSenderName = false,
    this.myAvatarPath,
    this.interlocutorAvatarPath,
    this.showInterlocutorAvatar = false,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.onLongPress,
    required this.onTap,
    this.showComments = false,
    this.onOpenComments,
    this.onReply,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  double _swipeOffset = 0;
  bool _swipeTriggered = false;
  static const _swipeThreshold = 64.0;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final showSenderName = widget.showSenderName;
    final myAvatarPath = widget.myAvatarPath;
    final interlocutorAvatarPath = widget.interlocutorAvatarPath;
    final showInterlocutorAvatar = widget.showInterlocutorAvatar;
    final isSelected = widget.isSelected;
    final isSelectionMode = widget.isSelectionMode;
    final onLongPress = widget.onLongPress;
    final onTap = widget.onTap;
    final showComments = widget.showComments;
    final onOpenComments = widget.onOpenComments;
    final onReply = widget.onReply;
    final isMe = message.isMe;
    final timeColor = isMe
        ? const Color(0xB3FFFFFF)
        : AppColors.subtle;

    // ── Пузырь с контентом ──────────────────────────────
    final bubble = IntrinsicWidth(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * AppSizes.bubbleMaxWidthFactor,
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isMe ? AppColors.chatMe : Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSenderName && !isMe && message.senderName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.senderName!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _senderColor(message.senderName!),
                  ),
                ),
              ),
            // ── Ответ (reply preview) ────────────────────
            if (message.replyTo != null)
              _ReplyPreview(reply: message.replyTo!, isMe: isMe),
            // ── Вложение ─────────────────────────────────
            if (message.attachment != null)
              _AttachmentPreview(attachment: message.attachment!, isMe: isMe),
            // ── Текст + метка (изм.) + время + статус ─────
            if (message.text.isNotEmpty || message.attachment == null)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: isMe ? AppColors.textLight : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (message.isEdited)
                    Text('изм. ',
                        style: TextStyle(fontSize: 10, color: timeColor)),
                  Text(formatTime(message.time),
                      style: TextStyle(fontSize: 10, color: timeColor)),
                  if (isMe) ...[
                    const SizedBox(width: 3),
                    _StatusIcon(status: message.status, color: timeColor),
                  ],
                ],
              )
            else
              // Время под вложением без текста
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isEdited)
                        Text('изм. ',
                            style: TextStyle(fontSize: 10, color: timeColor)),
                      Text(formatTime(message.time),
                          style: TextStyle(fontSize: 10, color: timeColor)),
                      if (isMe) ...[
                        const SizedBox(width: 3),
                        _StatusIcon(status: message.status, color: timeColor),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // В режиме выделения касания переключают выбор; вне него долгое нажатие открывает меню действий.
    Widget row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isSelectionMode ? onTap : null,
      onLongPress: isSelectionMode ? null : onLongPress,
      onSecondaryTap: isSelectionMode ? null : onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Чекбокс выделения ─────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: isSelectionMode
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.subtle,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // ── Содержимое сообщения ──────────────────────
            Expanded(
              child: Row(
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Аватар собеседника: только в личном чате
                  if (!isMe && showInterlocutorAvatar) ...[
                    ProfileAvatar(
                      avatarPath: interlocutorAvatarPath,
                      radius: AppSizes.avatarRadiusSmall,
                    ),
                    const SizedBox(width: 6),
                  ],
                  // В групповых чатах отступ, чтобы пузырь не прижимался к краю
                  if (!isMe && !showInterlocutorAvatar)
                    const SizedBox(width: 4),
                  Flexible(
                    child: Column(
                      crossAxisAlignment:
                          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        bubble,
                        // ── Кнопка комментариев ────────────────
                        if (showComments)
                          GestureDetector(
                            onTap: onOpenComments,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.mode_comment_outlined,
                                      size: 14, color: AppColors.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    message.comments.isEmpty
                                        ? 'Комментировать'
                                        : '${message.comments.length} комментари${_commentSuffix(message.comments.length)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 6),
                    ProfileAvatar(
                      avatarPath: myAvatarPath,
                      radius: AppSizes.avatarRadiusSmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Свайп вправо для ответа (Telegram-style с пружинящей иконкой)
    if (onReply != null && !isSelectionMode) {
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
          if (_swipeTriggered) onReply();
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
            // Иконка-индикатор свайпа
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
            // Само сообщение, сдвигается вправо
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

/// Превью ответа внутри пузыря сообщения (Telegram-style).
class _ReplyPreview extends StatelessWidget {
  final ReplyInfo reply;
  final bool isMe;

  const _ReplyPreview({required this.reply, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final accentColor = _senderColor(reply.senderName);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      // TODO: можно прокрутить к цитируемому сообщению
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: isMe
              ? Colors.black.withValues(alpha: 0.1)
              : accentColor.withValues(alpha: 0.1),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Цветная полоска слева (2px, скруглена с контейнером)
              Container(
                width: 2.5,
                color: isMe ? Colors.white.withValues(alpha: 0.85) : accentColor,
              ),
              // Текст
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        reply.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isMe ? Colors.white : accentColor,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        reply.text.isEmpty ? 'Вложение' : reply.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.7)
                              : isDark
                                  ? Colors.white70
                                  : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Генерирует уникальный цвет для имени отправителя (контрастный на светлом фоне).
Color _senderColor(String name) {
  const colors = [
    Color(0xFFD32F2F), // red
    Color(0xFF388E3C), // green
    Color(0xFF1976D2), // blue
    Color(0xFFE64A19), // deep orange
    Color(0xFF7B1FA2), // purple
    Color(0xFF00838F), // cyan
    Color(0xFFC2185B), // pink
    Color(0xFF455A64), // blue grey
  ];
  final hash = name.codeUnits.fold<int>(0, (h, c) => h * 31 + c);
  return colors[hash.abs() % colors.length];
}

/// Склонение слова «комментарий» по числу.
String _commentSuffix(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 19) return 'ев';
  if (mod10 == 1) return 'й';
  if (mod10 >= 2 && mod10 <= 4) return 'я';
  return 'ев';
}

// ─── Превью вложения ─────────────────────────────────────────────────────────

class _AttachmentPreview extends StatelessWidget {
  final Attachment attachment;
  final bool isMe;

  const _AttachmentPreview({required this.attachment, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return switch (attachment.type) {
      AttachmentType.image    => _ImagePreview(attachment: attachment),
      AttachmentType.video    => _VideoPreview(attachment: attachment),
      AttachmentType.document => _DocumentPreview(attachment: attachment, isMe: isMe),
    };
  }
}

class _ImagePreview extends StatelessWidget {
  final Attachment attachment;

  const _ImagePreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final file = File(attachment.path);
    if (!file.existsSync()) {
      return Container(
        width: 220, height: 100,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    }
    return GestureDetector(
      onTap: () => MediaViewerScreen.open(context, attachment),
      child: Hero(
        tag: 'media_${attachment.path}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file, width: 220, height: 220, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  final Attachment attachment;
  const _VideoPreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => MediaViewerScreen.open(context, attachment),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Тёмный прямоугольник-превью
          Container(
            width: 220,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.movie, color: Colors.white24, size: 56),
          ),
          // Кнопка воспроизведения
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white54, width: 2),
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 34),
          ),
          // Плашка с именем файла снизу
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(8)),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.videocam, color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      attachment.fileName,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (attachment.fileSize != null)
                    Text(
                      attachment.readableSize,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 10),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentPreview extends StatelessWidget {
  final Attachment attachment;
  final bool isMe;

  const _DocumentPreview({required this.attachment, required this.isMe});

  // Иконка по расширению файла
  IconData _iconForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf,
      'doc' || 'docx' => Icons.description,
      'xls' || 'xlsx' => Icons.table_chart,
      'zip' || 'rar' || '7z' => Icons.folder_zip,
      'mp3' || 'wav' || 'ogg' => Icons.audio_file,
      'mp4' || 'mov' || 'avi' => Icons.video_file,
      _ => Icons.insert_drive_file,
    };
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isMe ? AppColors.textLight : AppColors.textDark;
    final subtleColor = isMe ? const Color(0xB3FFFFFF) : AppColors.subtle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.15)
            : AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconForFile(attachment.fileName), color: textColor, size: 28),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (attachment.fileSize != null)
                  Text(
                    attachment.readableSize,
                    style: TextStyle(fontSize: 11, color: subtleColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Поле ввода сообщения ─────────────────────────────────────────────────────

/// Панель ввода текста в нижней части экрана чата.
/// Переключается между режимом написания и режимом редактирования в зависимости от [isEditing].
class MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool isEditing;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    this.isEditing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          // Кнопка прикрепления (скрыта при редактировании)
          if (!isEditing)
            IconButton(
              icon: const Icon(Icons.attach_file, color: AppColors.subtle),
              onPressed: onAttach,
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
                controller: controller,
                onSubmitted: (_) => onSend(),
                textInputAction: TextInputAction.send,
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
                isEditing ? Icons.check : Icons.send,
                color: AppColors.textLight,
              ),
              onPressed: onSend,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Индикатор редактирования над полем ввода ────────────────────────────────

class _EditingIndicator extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;

  const _EditingIndicator({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
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
            width: 3,
            height: 36,
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
                const Text(
                  'Редактирование',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: AppColors.subtle),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

// ─── Заглушка для не-админов в сообществе ────────────────────────────────────

class _LockedInput extends StatelessWidget {
  const _LockedInput();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      color: Theme.of(context).cardColor,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 16, color: AppColors.subtle),
          SizedBox(width: 6),
          Text(
            'Только администратор может писать',
            style: TextStyle(color: AppColors.subtle, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Полноэкранный просмотр медиа ────────────────────────────────────────────

class MediaViewerScreen extends StatefulWidget {
  final Attachment attachment;

  const MediaViewerScreen({super.key, required this.attachment});

  /// Открывает [attachment] в полноэкранном просмотрщике с переходом через затухание.
  static void open(BuildContext context, Attachment attachment) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) =>
            MediaViewerScreen(attachment: attachment),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  // ── Видеоплеер ────────────────────────────────────────────────────────────
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  bool _showControls = true;

  bool get _isVideo => widget.attachment.type == AttachmentType.video;

  @override
  void initState() {
    super.initState();
    if (_isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    final ctrl = VideoPlayerController.file(File(widget.attachment.path));
    _videoCtrl = ctrl;
    await ctrl.initialize();
    if (!mounted) return;
    setState(() => _videoReady = true);
    ctrl.play();
    _scheduleHideControls();
    // Слушаем завершение видео — показываем управление снова
    ctrl.addListener(() {
      if (mounted && ctrl.value.position >= ctrl.value.duration &&
          ctrl.value.duration > Duration.zero) {
        setState(() => _showControls = true);
      }
    });
  }

  void _scheduleHideControls() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && (_videoCtrl?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls && (_videoCtrl?.value.isPlaying ?? false)) {
      _scheduleHideControls();
    }
  }

  void _togglePlay() {
    final ctrl = _videoCtrl!;
    setState(() {
      if (ctrl.value.isPlaying) {
        ctrl.pause();
      } else {
        // Перемотать в начало если видео закончилось
        if (ctrl.value.position >= ctrl.value.duration) {
          ctrl.seekTo(Duration.zero);
        }
        ctrl.play();
        _scheduleHideControls();
      }
    });
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  /// Форматирует [Duration] как mm:ss для индикатора прогресса видео.
  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Построение UI ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Контент ─────────────────────────────────────────────────────
          if (_isVideo)
            _buildVideo()
          else
            _buildImage(),

          // ── AppBar поверх контента ───────────────────────────────────────
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                  stops: [0.0, 1.0],
                ),
              ),
              child: SafeArea(
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  title: Text(
                    widget.attachment.fileName,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    )); // Focus + Scaffold
  }

  // ── Просмотр изображений ──────────────────────────────────────────────────

  Widget _buildImage() {
    return GestureDetector(
      onTap: _toggleControls,
      child: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6.0,
          child: Hero(
            tag: 'media_${widget.attachment.path}',
            child: Image.file(
              File(widget.attachment.path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image,
                color: Colors.white38,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Видеоплеер ─────────────────────────────────────────────────────────────

  Widget _buildVideo() {
    if (!_videoReady) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    final ctrl = _videoCtrl!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Видео
          Center(
            child: AspectRatio(
              aspectRatio: ctrl.value.aspectRatio,
              child: VideoPlayer(ctrl),
            ),
          ),

          // Кнопка play/pause по центру
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white38, width: 1.5),
                ),
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: ctrl,
                  builder: (_, v, _) => Icon(
                    v.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ),
            ),
          ),

          // Нижняя панель: прогресс + время
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16,
                    MediaQuery.of(context).padding.bottom + 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Прогресс-бар с возможностью перемотки
                    VideoProgressIndicator(
                      ctrl,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      colors: VideoProgressColors(
                        playedColor: AppColors.primary,
                        bufferedColor: Colors.white30,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Время: текущее / полное
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: ctrl,
                      builder: (_, v, _) => Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(v.position),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12)),
                          Text(_fmt(v.duration),
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom sheet комментариев ─────────────────────────────────────────────────

/// Показывает тред комментариев к [message] в модальном bottom sheet.
/// При отправке комментария вызывает [onSend] с текстом.
void showCommentsSheet({
  required BuildContext context,
  required Message message,
  required Future<Message?> Function(String text) onSend,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => _CommentsSheetContent(
        message: message,
        scrollController: scrollCtrl,
        onSend: onSend,
      ),
    ),
  );
}

class _CommentsSheetContent extends StatefulWidget {
  final Message message;
  final ScrollController scrollController;
  final Future<Message?> Function(String text) onSend;

  const _CommentsSheetContent({
    required this.message,
    required this.scrollController,
    required this.onSend,
  });

  @override
  State<_CommentsSheetContent> createState() => _CommentsSheetContentState();
}

class _CommentsSheetContentState extends State<_CommentsSheetContent> {
  final _controller = TextEditingController();
  late Message _message;

  @override
  void initState() {
    super.initState();
    _message = widget.message;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final updated = await widget.onSend(text);
    if (updated != null && mounted) {
      setState(() => _message = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = _message.comments;
    return Column(
      children: [
        // ── Хэндл ──────────────────────────────────────────
        const SizedBox(height: 8),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.mode_comment_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Комментарии (${comments.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
        const Divider(height: 16),
        // ── Исходное сообщение (превью) ────────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            widget.message.text.length > 200
                ? '${widget.message.text.substring(0, 200)}…'
                : widget.message.text,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        // ── Список комментариев (Telegram-стиль) ───────────
        Expanded(
          child: comments.isEmpty
              ? const Center(
                  child: Text('Пока нет комментариев',
                      style: TextStyle(color: AppColors.subtle)),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  itemCount: comments.length,
                  itemBuilder: (ctx, i) {
                    final c = comments[i];
                    final isDark =
                        Theme.of(ctx).brightness == Brightness.dark;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Аватар
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: c.isMe
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.2),
                            child: Text(
                              c.senderName.isNotEmpty
                                  ? c.senderName[0]
                                  : '?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: c.isMe
                                    ? Colors.white
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Пузырь сообщения
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                  12, 8, 12, 6),
                              decoration: BoxDecoration(
                                color: c.isMe
                                    ? AppColors.primary
                                        .withValues(alpha: 0.15)
                                    : isDark
                                        ? Colors.white
                                            .withValues(alpha: 0.08)
                                        : const Color(0xFFF0F0F0),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomRight: const Radius.circular(14),
                                  bottomLeft: const Radius.circular(4),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  // Имя отправителя
                                  Text(
                                    c.senderName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: _senderColor(c.senderName),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  // Текст + время
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Flexible(
                                        child: Text(c.text,
                                            style: const TextStyle(
                                                fontSize: 14)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        formatTime(c.time),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.subtle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        // ── Поле ввода ─────────────────────────────────────
        SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Написать комментарий…',
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.send, color: AppColors.primary),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Реэкспорт вспомогательных элементов для экранов ────────────────────────

// Открываем внутренние виджеты, необходимые chat_screen.dart
// ignore: library_private_types_in_public_api
typedef EditingIndicator = _EditingIndicator;
// ignore: library_private_types_in_public_api
typedef LockedInput = _LockedInput;
