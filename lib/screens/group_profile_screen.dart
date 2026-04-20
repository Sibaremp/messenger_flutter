import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../app_constants.dart';
import '../services/api_config.dart' show ApiConfig;

// ─── Экран профиля группы / сообщества ───────────────────────────────────────

class GroupProfileScreen extends StatefulWidget {
  final Chat chat;
  /// Если true — встроен в панель (desktop).
  final bool embedded;
  final VoidCallback? onBack;
  /// Имя текущего авторизованного пользователя — нужно для определения его роли в группе.
  final String? currentUserName;

  const GroupProfileScreen({
    super.key,
    required this.chat,
    this.embedded = false,
    this.onBack,
    this.currentUserName,
  });

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  bool _imageError = false;

  Chat get chat => widget.chat;
  bool get embedded => widget.embedded;
  VoidCallback? get onBack => widget.onBack;
  String? get currentUserName => widget.currentUserName;

  @override
  void didUpdateWidget(GroupProfileScreen old) {
    super.didUpdateWidget(old);
    if (old.chat.avatarPath != widget.chat.avatarPath) {
      setState(() => _imageError = false);
    }
  }

  bool get _hasPhoto {
    if (_imageError) return false;
    final p = chat.avatarPath;
    if (p == null || p.isEmpty) return false;
    if (ApiConfig.isServerMediaPath(p)) return true;
    if (kIsWeb) return false;
    return File(p).existsSync();
  }

  String get _heroTag => 'group_photo_${chat.id}';

  /// Цвета аватаров участников.
  static const _memberColors = [
    Color(0xFFE57373),
    Color(0xFF81C784),
    Color(0xFF64B5F6),
    Color(0xFFFFB74D),
    Color(0xFFBA68C8),
    Color(0xFF4DD0E1),
    Color(0xFFF06292),
    Color(0xFFAED581),
  ];

  Color _colorFor(String name) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
    return _memberColors[hash % _memberColors.length];
  }

  /// Полный список участников.
  /// Запись текущего пользователя заменяется на «Вы» с правильной ролью.
  List<ChatMember> get _allMembers {
    final me = currentUserName;

    // Определяем роль текущего пользователя
    MemberRole myRole = MemberRole.member;
    if (me != null && me.isNotEmpty) {
      if (chat.isCreatorOrAdmin(me)) {
        myRole = MemberRole.creator;
      } else if (chat.members.any((m) => m.name == me)) {
        // Берём роль из списка участников (вдруг там admin)
        final myMember = chat.members.firstWhere((m) => m.name == me);
        myRole = myMember.role;
      }
    }

    // Список остальных (всех, кроме текущего пользователя)
    final others = me != null && me.isNotEmpty
        ? chat.members.where((m) => m.name != me).toList()
        : List<ChatMember>.from(chat.members);

    // Сортируем: creator → admin → member
    others.sort((a, b) {
      const order = {
        MemberRole.creator: 0,
        MemberRole.admin: 1,
        MemberRole.member: 2,
      };
      return (order[a.role] ?? 2).compareTo(order[b.role] ?? 2);
    });

    final meEntry = ChatMember(name: 'Вы', role: myRole);

    if (myRole == MemberRole.creator || myRole == MemberRole.admin) {
      return [meEntry, ...others];
    } else {
      // Текущий пользователь — обычный участник: ставим после создателей/админов
      final leaders = others.where((m) => m.role != MemberRole.member).toList();
      final rest = others.where((m) => m.role == MemberRole.member).toList();
      return [...leaders, meEntry, ...rest];
    }
  }

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

  /// Инициалы для плейсхолдера шапки: первые буквы двух слов.
  String get _initials {
    final words = chat.name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return chat.name.isNotEmpty ? chat.name[0].toUpperCase() : '?';
  }

  /// Градиентный плейсхолдер с инициалами (когда нет аватара или ошибка загрузки).
  Widget _buildPlaceholder(bool isCommunity) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
            const Color(0xFF8B4000),
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      child: Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          child: Center(
            child: Text(
              _initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasDesc = chat.description?.isNotEmpty == true;
    final allMembers = _allMembers;
    final isCommunity = chat.type == ChatType.community;

    final scaffold = Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      body: CustomScrollView(
        slivers: [
          // ── Шапка с аватаром ──────────────────────────────────
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            automaticallyImplyLeading: !embedded,
            leading: embedded ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ) : null,
            backgroundColor:
                isDark ? const Color(0xFF1E1E1E) : AppColors.primary,
            foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(16, 0, 48, 14),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(blurRadius: 8, color: Colors.black54)
                        ],
                      ),
                    ),
                    Text(
                      isCommunity
                          ? '${allMembers.length} подписчиков'
                          : '${allMembers.length} участников',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: Colors.white.withValues(alpha: 0.8),
                        shadows: const [
                          Shadow(blurRadius: 6, color: Colors.black54)
                        ],
                      ),
                    ),
                  ],
                ),
                background: _hasPhoto
                    ? GestureDetector(
                        onTap: () => _openFullPhoto(context),
                        child: Hero(
                          tag: _heroTag,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ApiConfig.isServerMediaPath(chat.avatarPath)
                                  ? Image.network(
                                      ApiConfig.resolveMediaUrl(
                                          chat.avatarPath)!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (ctx, e, s) {
                                        // При ошибке загрузки — переключаемся на плейсхолдер
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted) {
                                            setState(() => _imageError = true);
                                          }
                                        });
                                        return _buildPlaceholder(isCommunity);
                                      },
                                    )
                                  : Image.file(
                                      File(chat.avatarPath!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (ctx, e, s) {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted) {
                                            setState(() => _imageError = true);
                                          }
                                        });
                                        return _buildPlaceholder(isCommunity);
                                      },
                                    ),
                              // Градиент снизу для читаемости текста
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black54,
                                    ],
                                    stops: [0.5, 1.0],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildPlaceholder(isCommunity),
              ),
            ),

            // ── Контент ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),

                  // ── Блок «Информация» ─────────────────────────
                  _Card(
                    isDark: isDark,
                    children: [
                      // Тип
                      _InfoRow(
                        icon: isCommunity
                            ? Icons.campaign_outlined
                            : Icons.group_outlined,
                        label: 'Тип',
                        value: isCommunity ? 'Сообщество' : 'Группа',
                        isDark: isDark,
                      ),
                      if (hasDesc) ...[
                        _divider(isDark),
                        _InfoRow(
                          icon: Icons.info_outline,
                          label: 'Описание',
                          value: chat.description!,
                          isDark: isDark,
                        ),
                      ],
                      if (chat.createdAt != null) ...[
                        _divider(isDark),
                        _InfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Создан',
                          value: _formatDate(chat.createdAt!),
                          isDark: isDark,
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── Блок «Участники» ──────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
                    child: Text(
                      isCommunity
                          ? 'Подписчики · ${allMembers.length}'
                          : 'Участники · ${allMembers.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  _Card(
                    isDark: isDark,
                    children: [
                      for (int i = 0; i < allMembers.length; i++) ...[
                        if (i > 0) _divider(isDark),
                        _MemberRow(
                          member: allMembers[i],
                          color: _colorFor(allMembers[i].name),
                          isDark: isDark,
                          isCurrentUser: allMembers[i].name == 'Вы',
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
    );

    if (embedded) return scaffold;

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
      child: scaffold,
    );
  }

  Widget _divider(bool isDark) => Padding(
        padding: const EdgeInsets.only(left: 60),
        child: Divider(
          height: 1,
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
      );

  String _formatDate(DateTime dt) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Карточка-контейнер (скруглённая, с тенью)
// ═══════════════════════════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _Card({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Строка информации (тип, описание, дата)
// ═══════════════════════════════════════════════════════════════════════════════

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black45,
                    )),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Строка участника
// ═══════════════════════════════════════════════════════════════════════════════

class _MemberRow extends StatelessWidget {
  final ChatMember member;
  final Color color;
  final bool isDark;
  final bool isCurrentUser;

  const _MemberRow({
    required this.member,
    required this.color,
    required this.isDark,
    this.isCurrentUser = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Аватар
          CircleAvatar(
            radius: 20,
            backgroundColor: isCurrentUser
                ? AppColors.primary
                : color.withValues(alpha: 0.18),
            child: isCurrentUser
                ? const Icon(Icons.person, color: Colors.white, size: 20)
                : Text(
                    member.name.isNotEmpty
                        ? member.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          // Имя
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: isCurrentUser
                        ? AppColors.primary
                        : isDark
                            ? Colors.white
                            : Colors.black87,
                  ),
                ),
                if (member.role != MemberRole.member)
                  Text(
                    member.role == MemberRole.creator
                        ? 'создатель'
                        : 'администратор',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
              ],
            ),
          ),
          // Бейдж роли
          if (member.role != MemberRole.member)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: member.role == MemberRole.creator
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                member.role == MemberRole.creator ? 'Создатель' : 'Админ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: member.role == MemberRole.creator
                      ? AppColors.primary
                      : Colors.blue,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Просмотр фото на весь экран
// ═══════════════════════════════════════════════════════════════════════════════

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
                child: ApiConfig.isServerMediaPath(path)
                    ? Image.network(
                        ApiConfig.resolveMediaUrl(path)!,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, st) => const Icon(
                          Icons.broken_image,
                          color: Colors.white38,
                          size: 64,
                        ),
                      )
                    : Image.file(
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
