import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../app_constants.dart';

// ─── Экран профиля группы / сообщества ───────────────────────────────────────

/// Открывается при нажатии на аватар или имя группы/сообщества в AppBar чата.
/// Отображает аватар (с просмотром на весь экран), описание,
/// дату создания и список участников с их ролями.
class GroupProfileScreen extends StatelessWidget {
  final Chat chat;

  const GroupProfileScreen({super.key, required this.chat});

  bool get _hasPhoto =>
      chat.avatarPath != null && File(chat.avatarPath!).existsSync();

  String get _heroTag => 'group_photo_${chat.id}';

  void _openFullPhoto(BuildContext context) {
    if (!_hasPhoto) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (ctx, a, b) =>
            _FullScreenPhoto(path: chat.avatarPath!, heroTag: _heroTag),
        transitionsBuilder: (ctx, anim, a, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDesc = chat.description?.isNotEmpty == true;
    final hasDate = chat.createdAt != null;
    final members = chat.members;

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
        body: CustomScrollView(
          slivers: [
            // ── Растягиваемый AppBar с аватаром ─────────────────────
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                title: Text(
                  chat.name,
                  style: const TextStyle(
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
                background: _hasPhoto
                    ? GestureDetector(
                        onTap: () => _openFullPhoto(context),
                        child: Hero(
                          tag: _heroTag,
                          child: Image.file(
                            File(chat.avatarPath!),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        ),
                      )
                    : Container(
                        color: AppColors.primary,
                        child: Center(
                          child: Icon(
                            chat.type == ChatType.community
                                ? Icons.campaign
                                : Icons.group,
                            size: 96,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
              ),
            ),

            // ── Информация и участники ───────────────────────────────
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Подсказка о просмотре фото
                  if (_hasPhoto)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: const [
                          Icon(Icons.touch_app_outlined,
                              size: 14, color: AppColors.subtle),
                          SizedBox(width: 6),
                          Text(
                            'Нажмите на фото для просмотра',
                            style: TextStyle(fontSize: 12, color: AppColors.subtle),
                          ),
                        ],
                      ),
                    ),

                  // Тип чата
                  _InfoTile(
                    icon: chat.type == ChatType.community
                        ? Icons.campaign_outlined
                        : Icons.group_outlined,
                    label: 'Тип',
                    value: chat.type == ChatType.community
                        ? 'Сообщество'
                        : 'Группа',
                  ),

                  // Описание
                  if (hasDesc)
                    _InfoTile(
                      icon: Icons.info_outline,
                      label: 'Описание',
                      value: chat.description!,
                    ),

                  // Дата создания
                  if (hasDate)
                    _InfoTile(
                      icon: Icons.calendar_today_outlined,
                      label: 'Создан',
                      value: _formatDate(chat.createdAt!),
                    ),

                  // ── Участники ──────────────────────────────────────
                  if (members.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Участники · ${members.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.subtle,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    ...members.map((m) => _MemberTile(member: m)),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ─── Плитка с иконкой, подписью и значением ──────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).cardColor,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.subtle)),
                const SizedBox(height: 3),
                Text(value, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Строка участника ─────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  final ChatMember member;

  const _MemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).cardColor,
      margin: const EdgeInsets.only(bottom: 1),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.primary,
          child: Icon(Icons.person, color: Colors.white, size: 18),
        ),
        title: Text(member.name),
        trailing: switch (member.role) {
          MemberRole.creator => _badge('Создатель', AppColors.primary),
          MemberRole.admin   => _badge('Админ', Colors.blue),
          MemberRole.member  => null,
        },
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

// ─── Просмотр фото на весь экран ─────────────────────────────────────────────

class _FullScreenPhoto extends StatelessWidget {
  final String path;
  final String heroTag;

  const _FullScreenPhoto({required this.path, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6.0,
              child: Hero(
                tag: heroTag,
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, st) => const Icon(
                    Icons.broken_image,
                    color: Colors.white38,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
