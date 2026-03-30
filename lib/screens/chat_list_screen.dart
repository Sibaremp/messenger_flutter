import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import '../models.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';
import '../auth_screen.dart' show AuthService;
import '../profile_screen.dart' show ProfileStorage, ProfileAvatar, ProfileScreen;
import '../widgets/chat_widgets.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  final ChatService service;
  const ChatListScreen({super.key, required this.service});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  String? _myAvatarPath;
  List<Chat> _chats = [];
  late StreamSubscription<ChatEvent> _eventSub;

  final List<AppContact> _contacts = [
    AppContact(name: 'Алексей',   group: 'ИС-22'),
    AppContact(name: 'Мария',     group: 'ПИ-21'),
    AppContact(name: 'Иван',      group: 'КБ-23'),
    AppContact(name: 'Екатерина', group: 'ВТ-21'),
    AppContact(name: 'Дмитрий',   group: 'ИС-21'),
  ];

  @override
  void initState() {
    super.initState();
    _loadChats();
    _loadAvatar();
    _eventSub = widget.service.events.listen(_handleEvent);
  }

  void _handleEvent(ChatEvent event) {
    if (!mounted) return;
    _loadChats();
  }

  Future<void> _loadChats() async {
    final chats = await widget.service.loadChats();
    if (mounted) setState(() => _chats = List.from(chats));
  }

  Future<void> _loadAvatar() async {
    final profile = await ProfileStorage.loadProfile();
    if (mounted) setState(() => _myAvatarPath = profile.avatarPath);
  }

  @override
  void dispose() {
    _eventSub.cancel();
    super.dispose();
  }

  List<Chat> get _sortedChats =>
      [..._chats]..sort((a, b) => b.lastTime.compareTo(a.lastTime));

  void _onChatUpdated(Chat updated) {
    setState(() {
      final i = _chats.indexWhere((c) => c.id == updated.id);
      if (i != -1) _chats[i] = updated;
    });
  }

  void _showCreateOptions() {
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
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.chat, color: AppColors.textLight),
              ),
              title: const Text('Новый чат',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Личное сообщение'),
              onTap: () {
                Navigator.pop(context);
                _openNewDirectChat();
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.group, color: AppColors.textLight),
              ),
              title: const Text('Создать группу',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Все участники могут писать'),
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
              subtitle: const Text('Только администратор пишет'),
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
    final name = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _ContactPickerScreen(
          contacts: _contacts,
          existingChats: _chats,
        ),
      ),
    );
    if (name == null || !mounted) return;

    final chat = await widget.service.createDirectChat(contactName: name);
    if (!mounted) return;

    // Add to contacts if not present
    if (!_contacts.any((c) => c.name == name)) {
      setState(() => _contacts.add(AppContact(name: name)));
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chat: chat,
          service: widget.service,
          onChatUpdated: _onChatUpdated,
          contacts: _contacts,
        ),
      ),
    );
    _loadChats();
  }

  void _openCreateDialog(ChatType type) {
    showDialog(
      context: context,
      builder: (_) => _CreateChatDialog(
        type: type,
        contacts: _contacts,
        onCreated: (name, members, adminName) async {
          final chat = await widget.service.createGroupOrCommunity(
            name: name,
            type: type,
            members: members,
            adminName: adminName,
          );
          if (mounted) {
            setState(() => _chats.add(chat));
          }
        },
      ),
    );
  }

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    _loadAvatar();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedChats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _openProfile,
              child: ProfileAvatar(avatarPath: _myAvatarPath, radius: 18),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateOptions,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: AppColors.textLight),
      ),
      body: ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final chat = sorted[index];

          return Column(
            key: ValueKey(chat.id),
            children: [
              InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        chat: chat,
                        service: widget.service,
                        onChatUpdated: _onChatUpdated,
                        contacts: _contacts,
                      ),
                    ),
                  );
                  _loadChats();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      ChatAvatar(type: chat.type),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    chat.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (chat.type != ChatType.direct)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      chat.type == ChatType.group
                                          ? 'Группа'
                                          : 'Сообщество',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              chat.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.subtle),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatChatTime(chat.lastTime),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.subtle),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: Colors.grey[300]),
            ],
          );
        },
      ),
    );
  }
}

// ─── Диалог создания группы / сообщества ─────────────────────────────────────

class _CreateChatDialog extends StatefulWidget {
  final ChatType type;
  final List<AppContact> contacts;
  final Future<void> Function(String name, List<ChatMember> members, String? adminName) onCreated;

  const _CreateChatDialog({
    required this.type,
    required this.contacts,
    required this.onCreated,
  });

  @override
  State<_CreateChatDialog> createState() => _CreateChatDialogState();
}

class _CreateChatDialogState extends State<_CreateChatDialog> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedContacts = {};
  String? _nameError;

  String get _title =>
      widget.type == ChatType.group ? 'Новая группа' : 'Новое сообщество';

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введите название');
      return;
    }

    final members = _selectedContacts
        .map((n) => ChatMember(name: n, role: MemberRole.member))
        .toList();
    final adminName = widget.type == ChatType.community ? 'Я' : null;

    Navigator.pop(context);
    await widget.onCreated(name, members, adminName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const Text(
              'Добавить участников',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: widget.contacts.map((contact) {
                  final selected = _selectedContacts.contains(contact.name);
                  return CheckboxListTile(
                    value: selected,
                    title: Text(contact.name),
                    subtitle: contact.group != null
                        ? Text(contact.group!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.subtle))
                        : null,
                    secondary: const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.person,
                          color: AppColors.textLight, size: 18),
                    ),
                    activeColor: AppColors.primary,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() {
                      val == true
                          ? _selectedContacts.add(contact.name)
                          : _selectedContacts.remove(contact.name);
                    }),
                  );
                }).toList(),
              ),
            ),
            if (_selectedContacts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Выбрано: ${_selectedContacts.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

// ─── Экран выбора контакта для нового чата ───────────────────────────────────

class _ContactPickerScreen extends StatefulWidget {
  final List<AppContact> contacts;
  final List<Chat> existingChats;

  const _ContactPickerScreen({
    required this.contacts,
    required this.existingChats,
  });

  @override
  State<_ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<_ContactPickerScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  // Контакты устройства: null = не загружены, [] = загружены (пусто)
  List<fc.Contact>? _deviceContacts;
  bool _loadingDevice = false;

  // Реестр зарегистрированных номеров (только цифры)
  Set<String> _registeredPhones = {};

  @override
  void initState() {
    super.initState();
    _loadRegisteredPhones();
  }

  Future<void> _loadRegisteredPhones() async {
    final phones = await AuthService.getRegisteredPhones();
    if (mounted) setState(() => _registeredPhones = phones);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  // Проверяем, зарегистрирован ли контакт устройства в приложении
  bool _isInApp(fc.Contact contact) {
    for (final p in contact.phones) {
      final normalized = AuthService.normalizePhone(p.number);
      if (normalized.isNotEmpty && _registeredPhones.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  // ── Фильтрация по имени И по группе ────────────────────────────────
  List<AppContact> get _filteredApp {
    if (_query.isEmpty) return widget.contacts;
    final q = _query.toLowerCase();
    return widget.contacts.where((c) =>
      c.name.toLowerCase().contains(q) ||
      (c.group?.toLowerCase().contains(q) ?? false)
    ).toList();
  }

  // ── Фильтрация контактов устройства ────────────────────────────────
  List<fc.Contact> get _filteredDevice {
    final all = _deviceContacts ?? [];
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((c) => c.displayName.toLowerCase().contains(q)).toList();
  }

  bool _hasChat(String name) => widget.existingChats
      .any((c) => c.name == name && c.type == ChatType.direct);

  Future<void> _loadDeviceContacts() async {
    setState(() => _loadingDevice = true);
    final granted = await fc.FlutterContacts.requestPermission(readonly: true);
    if (!mounted) return;
    if (!granted) {
      setState(() => _loadingDevice = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет доступа к контактам'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final contacts = await fc.FlutterContacts.getContacts(withProperties: true);
    if (mounted) setState(() { _deviceContacts = contacts; _loadingDevice = false; });
  }

  void _showAddContactDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Новый контакт'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Имя пользователя',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final name = v.trim();
            if (name.isEmpty) return;
            Navigator.of(dlg).pop();
            if (mounted) Navigator.of(context).pop(name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlg).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dlg).pop();
              if (mounted) Navigator.of(context).pop(name);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  Widget _openBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Text(
      'Открыть',
      style: TextStyle(
        fontSize: 11,
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _inAppBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.green.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.check_circle_outline, size: 11, color: Colors.green),
        SizedBox(width: 4),
        Text(
          'В приложении',
          style: TextStyle(
            fontSize: 11,
            color: Colors.green,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final filteredApp = _filteredApp;
    final filteredDevice = _filteredDevice;
    final deviceLoaded = _deviceContacts != null;
    final showSectionHeaders = deviceLoaded || _isMobile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый чат'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Поиск по имени или группе…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).cardColor,
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
      body: ListView(
        children: [
          // ── Добавить вручную ─────────────────────────────────────────
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Icon(Icons.person_add_alt_1, color: Colors.white),
            ),
            title: const Text('Новый контакт',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Добавить пользователя по имени'),
            onTap: _showAddContactDialog,
          ),

          // ── Импорт из телефона (только Android/iOS) ──────────────────
          if (_isMobile && !deviceLoaded)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: _loadingDevice
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(Icons.contacts_outlined,
                        color: AppColors.primary),
              ),
              title: const Text('Из телефона',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Импортировать контакты устройства'),
              onTap: _loadingDevice ? null : _loadDeviceContacts,
            ),

          const Divider(height: 1),

          // ── Заголовок «Мои контакты» (если показаны два раздела) ─────
          if (showSectionHeaders)
            _SectionHeader(
              title: _query.isEmpty
                  ? 'Мои контакты'
                  : 'Мои контакты (${filteredApp.length})',
            ),

          // ── Список контактов приложения ───────────────────────────────
          if (filteredApp.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('Контакты не найдены',
                    style: TextStyle(color: AppColors.subtle)),
              ),
            )
          else
            ...filteredApp.map((contact) {
              final hasChat = _hasChat(contact.name);
              return Column(
                children: [
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                    title: Text(contact.name),
                    subtitle: contact.group != null
                        ? Text(contact.group!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.subtle))
                        : null,
                    trailing: hasChat ? _openBadge() : null,
                    onTap: () => Navigator.of(context).pop(contact.name),
                  ),
                  const Divider(height: 1, indent: 72),
                ],
              );
            }),

          // ── Контакты устройства ───────────────────────────────────────
          if (deviceLoaded) ...[
            _SectionHeader(
              title: _query.isEmpty
                  ? 'Из телефона'
                  : 'Из телефона (${filteredDevice.length})',
              action: TextButton(
                onPressed: () =>
                    setState(() => _deviceContacts = null),
                child: const Text('Скрыть',
                    style: TextStyle(color: AppColors.subtle, fontSize: 12)),
              ),
            ),
            if (filteredDevice.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('Контакты не найдены',
                      style: TextStyle(color: AppColors.subtle)),
                ),
              )
            else
              ...filteredDevice.map((dc) {
                final displayName = dc.displayName;
                final phone = dc.phones.isNotEmpty
                    ? dc.phones.first.number
                    : null;
                final hasChat   = _hasChat(displayName);
                final inApp     = _isInApp(dc);
                return Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: inApp
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : AppColors.primary.withValues(alpha: 0.10),
                        child: Icon(
                          inApp ? Icons.check : Icons.smartphone,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      title: Text(displayName),
                      subtitle: phone != null
                          ? Text(phone,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.subtle))
                          : null,
                      trailing: hasChat
                          ? _openBadge()
                          : inApp
                              ? _inAppBadge()
                              : null,
                      onTap: () =>
                          Navigator.of(context).pop(displayName),
                    ),
                    const Divider(height: 1, indent: 72),
                  ],
                );
              }),
          ],
        ],
      ),
    );
  }
}

// ── Заголовок секции ──────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.subtle,
                letterSpacing: 0.6,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
