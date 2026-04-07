import 'dart:async';
import 'package:flutter/material.dart';
import 'models.dart';
import 'app_constants.dart';
import 'services/chat_service.dart';
import 'auth_screen.dart' show AuthService, AuthScreen;
import 'profile_screen.dart' show ProfileStorage, ProfileAvatar;
import 'widgets/sidebar.dart';
import 'widgets/chat_widgets.dart';
import 'screens/chat_screen.dart';
import 'screens/chat_list_screen.dart';
import 'widgets/profile_panel.dart';
import 'widgets/notifications_panel.dart';
import 'screens/search_screen.dart';

/// Адаптивная оболочка приложения.
/// - Узкий экран (<800): стандартная мобильная навигация (ChatListScreen).
/// - Широкий экран (>=800): трёх панельный desktop-режим (sidebar + список + чат/профиль).
class ResponsiveShell extends StatefulWidget {
  final ChatService service;
  const ResponsiveShell({super.key, required this.service});

  @override
  State<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends State<ResponsiveShell>
    with TickerProviderStateMixin {
  SidebarNav _nav = SidebarNav.chat;
  Chat? _selectedChat;
  String? _myAvatarPath;
  List<Chat> _chats = [];
  bool _isSearching = false;
  late StreamSubscription<ChatEvent> _eventSub;
  late final TabController _chatTabController;
  late final TabController _academicTabController;

  /// Возвращает активный TabController для текущего раздела.
  TabController get _activeTabController =>
      _nav == SidebarNav.academic ? _academicTabController : _chatTabController;

  final List<AppContact> _contacts = [
    // Студенты
    const AppContact(name: 'Алексей', group: 'ИС-22'),
    const AppContact(name: 'Мария', group: 'ПИ-21'),
    const AppContact(name: 'Иван', group: 'КБ-23'),
    const AppContact(name: 'Екатерина', group: 'ВТ-21'),
    const AppContact(name: 'Дмитрий', group: 'ИС-21'),
    // Преподаватели
    const AppContact(name: 'Проф. Петров', group: 'Физика', isTeacher: true),
    const AppContact(name: 'Доц. Сулейменова', group: 'История', isTeacher: true),
    const AppContact(name: 'Ст. преп. Ким', group: 'Математика', isTeacher: true),
    const AppContact(name: 'Проф. Жумабаев', group: 'Информатика', isTeacher: true),
  ];

  @override
  void initState() {
    super.initState();
    _chatTabController = TabController(length: 2, vsync: this);
    _academicTabController = TabController(length: 2, vsync: this);
    _loadChats();
    _loadAvatar();
    _eventSub = widget.service.events.listen((_) => _loadChats());
  }

  @override
  void dispose() {
    _chatTabController.dispose();
    _academicTabController.dispose();
    _eventSub.cancel();
    super.dispose();
  }

  Future<void> _loadChats() async {
    final chats = await widget.service.loadChats();
    if (!mounted) return;
    setState(() {
      _chats = List.from(chats);
      if (_selectedChat != null) {
        final idx = _chats.indexWhere((c) => c.id == _selectedChat!.id);
        if (idx != -1) {
          _selectedChat = _chats[idx];
        } else {
          _selectedChat = null;
        }
      }
    });
  }

  Future<void> _loadAvatar() async {
    final profile = await ProfileStorage.loadProfile();
    if (mounted) setState(() => _myAvatarPath = profile.avatarPath);
  }

  List<Chat> get _sortedChats =>
      [..._chats]..sort((a, b) => b.lastTime.compareTo(a.lastTime));

  // ── Обычные чаты (раздел «Общение») ────────────────────────────
  List<Chat> get _regularChats =>
      _sortedChats.where((c) => !c.isAcademic).toList();

  List<Chat> get _personalChats =>
      _regularChats.where((c) => c.type == ChatType.direct).toList();

  List<Chat> get _groupChats =>
      _regularChats.where((c) => c.type != ChatType.direct).toList();

  // ── Академические чаты (раздел «Академический») ────────────────
  List<Chat> get _academicChats =>
      _sortedChats.where((c) => c.isAcademic).toList();

  List<Chat> get _academicPersonal =>
      _academicChats.where((c) => c.type == ChatType.direct).toList();

  List<Chat> get _academicGroups =>
      _academicChats.where((c) => c.type != ChatType.direct).toList();

  void _onChatUpdated(Chat updated) {
    setState(() {
      final i = _chats.indexWhere((c) => c.id == updated.id);
      if (i != -1) _chats[i] = updated;
      if (_selectedChat?.id == updated.id) _selectedChat = updated;
    });
  }

  /// Показывать ли кнопку действия в sidebar
  bool get _showActionButton {
    // В академическом разделе на вкладке «Группы» — кнопки нет
    if (_nav == SidebarNav.academic && _activeTabController.index == 1) return false;
    // В остальных случаях: только для чатов (Общение / Академический)
    return _nav == SidebarNav.chat || _nav == SidebarNav.academic;
  }

  /// Текст и иконка кнопки в sidebar зависят от вкладки
  String get _sidebarActionLabel {
    if (_nav == SidebarNav.chat && _activeTabController.index == 1) {
      return 'Создать группу';
    }
    return 'Новый чат';
  }

  IconData get _sidebarActionIcon => Icons.add;

  /// Обработчик нажатия кнопки
  void _showCreateOptions() {
    final isGroupsTab = _nav == SidebarNav.chat && _activeTabController.index == 1;

    // На вкладке «Личные» — сразу новый чат
    if (!isGroupsTab) {
      _openNewDirectChat();
      return;
    }

    // На вкладке «Группы» (только Общение) — выбор: группа или сообщество
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
                child: Icon(Icons.group, color: AppColors.textLight),
              ),
              title: const Text('Создать группу',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _openCreateDialog(ChatType.group);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.campaign, color: AppColors.textLight),
              ),
              title: const Text('Создать сообщество',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _openCreateDialog(ChatType.community);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openNewDirectChat() async {
    setState(() {
      _selectedChat = null;
      _showContactPicker = true;
      _contactPickerInitialTab = _nav == SidebarNav.academic ? 1 : 0;
    });
  }

  bool _showContactPicker = false;
  int _contactPickerInitialTab = 0;

  Future<void> _onContactPicked(AppContact contact) async {
    final chat = await widget.service.createDirectChat(
      contactName: contact.name,
      isAcademic: contact.isTeacher,
    );
    if (!mounted) return;
    if (!_contacts.any((c) => c.name == contact.name)) {
      _contacts.add(contact);
    }
    setState(() {
      _selectedChat = chat;
      _showContactPicker = false;
    });
    _loadChats();
  }

  void _openCreateDialog(ChatType type) {
    showDialog(
      context: context,
      builder: (_) => _DesktopCreateChatDialog(
        type: type,
        contacts: _contacts,
        onCreated: (name, members, adminName) async {
          final chat = await widget.service.createGroupOrCommunity(
            name: name, type: type, members: members, adminName: adminName,
          );
          if (!mounted) return;
          setState(() {
            _chats.add(chat);
            _selectedChat = chat;
          });
        },
      ),
    );
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (ctx) => AuthScreen(
          onLoginSuccess: () {
            Navigator.of(ctx).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => ResponsiveShell(service: widget.service),
              ),
              (_) => false,
            );
          },
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < AppSizes.desktopBreakpoint) {
      return ChatListScreen(service: widget.service);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        children: [
          // ── Sidebar (полная высота) ─────────────────────────────
          Sidebar(
            selected: _nav,
            onSelect: (nav) => setState(() {
              _nav = nav;
              _isSearching = false;
            }),
            onNewChat: _showCreateOptions,
            onLogout: _logout,
            actionLabel: _sidebarActionLabel,
            actionIcon: _sidebarActionIcon,
            showActionButton: _showActionButton,
          ),
          VerticalDivider(
              width: 1, thickness: 1,
              color: Theme.of(context).dividerColor),

          // ── Контент (поиск сверху + панели) ─────────────────────
          Expanded(
            child: Column(
              children: [
                // Строка поиска + аватар
                _TopBar(
                  avatarPath: _myAvatarPath,
                  isDark: isDark,
                  onAvatarTap: () => setState(() {
                    _nav = SidebarNav.profile;
                    _isSearching = false;
                  }),
                  onSearchTap: () => setState(() => _isSearching = true),
                  isSearching: _isSearching,
                  onSearchClose: () => setState(() => _isSearching = false),
                ),
                Divider(height: 1, thickness: 1,
                    color: Theme.of(context).dividerColor),

                // Основное содержимое
                Expanded(
                  child: Row(
                    children: [
                      // ── Средняя панель ─────────────────────────
                      if (_nav == SidebarNav.chat || _nav == SidebarNav.academic)
                        SizedBox(
                          width: AppSizes.middlePanelWidth,
                          child: _nav == SidebarNav.academic
                              ? _buildAcademicListPanel()
                              : _buildChatListPanel(),
                        ),
                      if (_nav == SidebarNav.chat || _nav == SidebarNav.academic)
                        VerticalDivider(
                            width: 1, thickness: 1,
                            color: Theme.of(context).dividerColor),

                      // ── Правая панель ──────────────────────────
                      Expanded(
                        child: _buildRightPanel(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    // Режим поиска — показываем SearchScreen вместо чата
    if (_isSearching) {
      return SearchScreen(
        service: widget.service,
        contacts: _contacts,
        embedded: true,
        onChatSelected: (chat) {
          setState(() {
            _selectedChat = chat;
            _isSearching = false;
          });
        },
      );
    }

    switch (_nav) {
      case SidebarNav.profile:
        return ProfilePanel(
          onAvatarChanged: _loadAvatar,
          onLogout: _logout,
        );
      case SidebarNav.notifications:
        return const NotificationsPanel();
      case SidebarNav.academic:
      case SidebarNav.chat:
        if (_showContactPicker) {
          return _SimpleContactPicker(
            key: ValueKey('picker_$_contactPickerInitialTab'),
            contacts: _contacts,
            existingChats: _chats,
            embedded: true,
            initialTab: _contactPickerInitialTab,
            onBack: () => setState(() => _showContactPicker = false),
            onContactPicked: _onContactPicked,
          );
        }
        if (_selectedChat != null) {
          return ChatScreen(
            key: ValueKey(_selectedChat!.id),
            chat: _selectedChat!,
            service: widget.service,
            onChatUpdated: _onChatUpdated,
            contacts: _contacts,
            embedded: true,
          );
        }
        return const _EmptyPanel();
    }
  }

  // ── Средняя панель: список чатов ───────────────────────────────────────

  Widget _buildChatListPanel() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Общение',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        TabBar(
          controller: _chatTabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.subtle,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: const [Tab(text: 'Личные'), Tab(text: 'Группы')],
          onTap: (_) => setState(() {}), // обновить sidebar label
        ),
        Expanded(
          child: TabBarView(
            controller: _chatTabController,
            children: [
              _buildDesktopChatList(_personalChats),
              _buildDesktopChatList(_groupChats),
            ],
          ),
        ),
      ],
    );
  }

  // ── Средняя панель: академический раздел ─────────────────────────────────

  Widget _buildAcademicListPanel() {
    // Академический — отдельные чаты с преподавателями
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Академический',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        TabBar(
          controller: _academicTabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.subtle,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: const [Tab(text: 'Личные'), Tab(text: 'Группы')],
          onTap: (_) => setState(() {}), // обновить showActionButton
        ),
        Expanded(
          child: TabBarView(
            controller: _academicTabController,
            children: [
              _buildDesktopChatList(_academicPersonal),
              _buildDesktopChatList(_academicGroups),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopChatList(List<Chat> chats) {
    if (chats.isEmpty) {
      return const Center(
        child: Text('Нет чатов', style: TextStyle(color: AppColors.subtle)),
      );
    }
    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats[index];
        final isSelected = _selectedChat?.id == chat.id;
        return Column(
          children: [
            Material(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              child: InkWell(
                onTap: () => setState(() {
                  _selectedChat = chat;
                  _isSearching = false;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      ChatAvatar(
                          type: chat.type, avatarPath: chat.avatarPath, chatName: chat.name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chat.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              chat.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.subtle, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
          ],
        );
      },
    );
  }
}

// ─── Верхняя панель (поиск + аватар) ────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String? avatarPath;
  final bool isDark;
  final VoidCallback onAvatarTap;
  final VoidCallback onSearchTap;
  final bool isSearching;
  final VoidCallback onSearchClose;

  const _TopBar({
    required this.avatarPath,
    required this.isDark,
    required this.onAvatarTap,
    required this.onSearchTap,
    required this.isSearching,
    required this.onSearchClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Поле поиска (ограничено по ширине)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: GestureDetector(
              onTap: onSearchTap,
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: isSearching
                      ? Border.all(color: AppColors.primary, width: 1.5)
                      : null,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Icon(Icons.search,
                        size: 18,
                        color: isSearching
                            ? AppColors.primary
                            : AppColors.subtle.withValues(alpha: 0.6)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Поиск',
                        style: TextStyle(
                          color: AppColors.subtle.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (isSearching)
                      GestureDetector(
                        onTap: onSearchClose,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.close,
                              size: 16, color: AppColors.subtle),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          // Аватар пользователя с оранжевой рамкой
          GestureDetector(
            onTap: onAvatarTap,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              padding: const EdgeInsets.all(2),
              child: ProfileAvatar(avatarPath: avatarPath, radius: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Пустое правое окно ──────────────────────────────────────────────────────

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 64,
              color: AppColors.subtle.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text(
            'Выберите чат',
            style: TextStyle(color: AppColors.subtle, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ─── Выборщик контактов с табами Общение/Академический ────────────────────────

class _SimpleContactPicker extends StatefulWidget {
  final List<AppContact> contacts;
  final List<Chat> existingChats;
  final bool embedded;
  final int initialTab;
  final VoidCallback? onBack;
  final ValueChanged<AppContact>? onContactPicked;

  const _SimpleContactPicker({
    super.key,
    required this.contacts,
    required this.existingChats,
    this.embedded = false,
    this.initialTab = 0,
    this.onBack,
    this.onContactPicked,
  });

  @override
  State<_SimpleContactPicker> createState() => _SimpleContactPickerState();
}

class _SimpleContactPickerState extends State<_SimpleContactPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  bool get _showTeachers => widget.initialTab == 1;

  static const _avatarColors = [
    Color(0xFFE57373), Color(0xFF81C784), Color(0xFF64B5F6), Color(0xFFFFB74D),
    Color(0xFFBA68C8), Color(0xFF4DD0E1), Color(0xFFF06292), Color(0xFFAED581),
  ];

  Color _colorFor(String name) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
    return _avatarColors[hash % _avatarColors.length];
  }

  bool _hasChat(String name) => widget.existingChats
      .any((c) => c.name == name && c.type == ChatType.direct);

  List<AppContact> get _filtered {
    var list = widget.contacts.where((c) => c.isTeacher == _showTeachers);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((c) =>
          c.name.toLowerCase().contains(q) ||
          (c.group?.toLowerCase().contains(q) ?? false));
    }
    return list.toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(AppContact contact) {
    if (widget.embedded) {
      widget.onContactPicked?.call(contact);
    } else {
      Navigator.pop(context, contact.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack)
            : null,
        title: Text(
          _showTeachers ? 'Преподаватели' : 'Новый чат',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: _showTeachers ? 'Поиск преподавателей...' : 'Поиск контактов...',
                hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38),
                prefixIcon: Icon(Icons.search,
                    color: isDark ? Colors.white38 : Colors.black38),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            color: isDark ? Colors.white54 : Colors.black45),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFF2F2F2),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildContactList(
        _filtered, isDark,
        _showTeachers ? 'Нет преподавателей' : 'Нет студентов',
      ),
    );
  }

  Widget _buildContactList(List<AppContact> filtered, bool isDark, String emptyText) {
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search, size: 56,
                color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 12),
            Text(
              _query.isEmpty ? emptyText : 'Ничего не найдено',
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38, fontSize: 15),
            ),
          ],
        ),
      );
    }

    // Группируем по первой букве
    final grouped = <String, List<AppContact>>{};
    for (final c in filtered) {
      final letter = c.name.isNotEmpty ? c.name[0].toUpperCase() : '#';
      grouped.putIfAbsent(letter, () => []).add(c);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: sortedKeys.length,
      itemBuilder: (context, sectionIndex) {
        final letter = sortedKeys[sectionIndex];
        final contacts = grouped[letter]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(letter, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: AppColors.primary, letterSpacing: 0.5)),
            ),
            ...contacts.map((c) {
              final color = _colorFor(c.name);
              final hasChat = _hasChat(c.name);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _select(c),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: color.withValues(alpha: 0.18),
                        child: Text(
                          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                          style: TextStyle(color: color,
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15,
                              color: isDark ? Colors.white : Colors.black87)),
                            if (c.group != null)
                              Text(c.group!, style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white54 : Colors.black45)),
                          ],
                        ),
                      ),
                      if (hasChat)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                          child: const Text('Открыть', style: TextStyle(
                            fontSize: 12, color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ),
                ),
              );
            }),
            if (sectionIndex < sortedKeys.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 60, right: 16),
                child: Divider(height: 1,
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
              ),
          ],
        );
      },
    );
  }
}

// ─── Диалог создания группы (desktop) ────────────────────────────────────────

class _DesktopCreateChatDialog extends StatefulWidget {
  final ChatType type;
  final List<AppContact> contacts;
  final Future<void> Function(
          String name, List<ChatMember> members, String? adminName)
      onCreated;

  const _DesktopCreateChatDialog({
    required this.type,
    required this.contacts,
    required this.onCreated,
  });

  @override
  State<_DesktopCreateChatDialog> createState() =>
      _DesktopCreateChatDialogState();
}

class _DesktopCreateChatDialogState
    extends State<_DesktopCreateChatDialog> {
  final _nameController = TextEditingController();
  final Set<String> _selected = {};
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введите название');
      return;
    }
    final members = _selected
        .map((n) => ChatMember(name: n, role: MemberRole.member))
        .toList();
    final adminName = widget.type == ChatType.community ? 'Я' : null;
    Navigator.pop(context);
    await widget.onCreated(name, members, adminName);
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.type == ChatType.group ? 'Новая группа' : 'Новое сообщество';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Название',
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Добавить участников',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                children: widget.contacts.map((c) {
                  final sel = _selected.contains(c.name);
                  return CheckboxListTile(
                    value: sel,
                    title: Text(c.name),
                    activeColor: AppColors.primary,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() {
                      v == true
                          ? _selected.add(c.name)
                          : _selected.remove(c.name);
                    }),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: _submit,
          style:
              FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Создать'),
        ),
      ],
    );
  }
}
