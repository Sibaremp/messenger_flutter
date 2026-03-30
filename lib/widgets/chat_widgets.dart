import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../models.dart';
import '../app_constants.dart';
import '../profile_screen.dart' show ProfileAvatar;

// ─── Аватар ───────────────────────────────────────────────────────────────────

class ChatAvatar extends StatelessWidget {
  final ChatType type;
  final double radius;

  const ChatAvatar({
    super.key,
    this.type = ChatType.direct,
    this.radius = AppSizes.avatarRadiusLarge,
  });

  IconData get _icon => switch (type) {
    ChatType.direct => Icons.person,
    ChatType.group => Icons.group,
    ChatType.community => Icons.campaign,
  };

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary,
      child: Icon(_icon, size: radius, color: AppColors.textLight),
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

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool showSenderName;
  final String? myAvatarPath;
  /// Аватар собеседника (для личных чатов — левая сторона)
  final String? interlocutorAvatarPath;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  const MessageBubble({
    super.key,
    required this.message,
    this.showSenderName = false,
    this.myAvatarPath,
    this.interlocutorAvatarPath,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.onLongPress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
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

    return GestureDetector(
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
                  if (!isMe) ...[
                    ProfileAvatar(
                      avatarPath: interlocutorAvatarPath,
                      radius: AppSizes.avatarRadiusSmall,
                    ),
                    const SizedBox(width: 6),
                  ],
                  bubble,
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
  }
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
  // ── Видео ──────────────────────────────────────────────────────────────────
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

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Постройка UI ───────────────────────────────────────────────────────────

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

  // ── Просмотр изображения ───────────────────────────────────────────────────

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

// ─── Re-export helpers used by screens ───────────────────────────────────────

// Expose internal widgets needed by chat_screen.dart
// ignore: library_private_types_in_public_api
typedef EditingIndicator = _EditingIndicator;
// ignore: library_private_types_in_public_api
typedef LockedInput = _LockedInput;
