import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:video_player/video_player.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'auth_screen.dart';
import 'profile_screen.dart';

void main() {
  runApp(const ThemeProvider(child: MyApp()));
}

// ─── Константы ───────────────────────────────────────────────────────────────

class AppColors {
  const AppColors._();

  static const primary = Color(0xFFFF6F00);
  static const background = Color(0xFFF5F5F5);
  static const chatMe = Color(0xFFFF6F00);
  static const chatOther = Color(0xFFFFFFFF);
  static const textDark = Color(0xFF000000);
  static const textLight = Color(0xFFFFFFFF);
  static const subtle = Color(0xFF757575);
}

class AppSizes {
  const AppSizes._();

  static const avatarRadiusSmall = 16.0;
  static const avatarRadiusLarge = 24.0;
  static const bubbleMaxWidthFactor = 0.7;
}

// ─── Модели ───────────────────────────────────────────────────────────────────

enum ChatType { direct, group, community }

// Тип вложения
enum AttachmentType { image, video, document }

const _kVideoExtensions = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', '3gp'};

class Attachment {
  final String path;       // локальный путь к файлу
  final AttachmentType type;
  final String fileName;   // имя файла для документов
  final int? fileSize;     // размер в байтах

  const Attachment({
    required this.path,
    required this.type,
    required this.fileName,
    this.fileSize,
  });

  // Читабельный размер: "1.2 МБ", "340 КБ"
  String get readableSize {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize Б';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} КБ';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}

// ─── Контакт ─────────────────────────────────────────────────────────────────

class AppContact {
  final String name;
  final String? group; // учебная группа
  final String? phone; // номер телефона (из контактов устройства)

  const AppContact({required this.name, this.group, this.phone});
}

class Message {
  static int _nextId = 0;

  final String id;
  final String text;
  final bool isMe;
  final DateTime time;
  final String? senderName;
  final Attachment? attachment; // вложение (фото или документ)
  final bool isEdited;

  Message({
    String? id,
    required this.text,
    required this.isMe,
    required this.time,
    this.senderName,
    this.attachment,
    this.isEdited = false,
  }) : id = id ?? 'msg_${++_nextId}';

  Message copyWith({String? text, bool? isEdited}) => Message(
    id: id,
    text: text ?? this.text,
    isMe: isMe,
    time: time,
    senderName: senderName,
    attachment: attachment,
    isEdited: isEdited ?? this.isEdited,
  );
}

class Chat {
  final String name;
  final List<Message> messages;
  final ChatType type;
  final List<String> members;
  final String? adminName;

  const Chat({
    required this.name,
    required this.messages,
    this.type = ChatType.direct,
    this.members = const [],
    this.adminName,
  });

  String get lastMessage {
    if (messages.isEmpty) return '';
    final msg = messages.last;
    String content = msg.text;
    if (content.isEmpty && msg.attachment != null) {
      content = switch (msg.attachment!.type) {
        AttachmentType.image    => '📷 Фото',
        AttachmentType.video    => '🎬 Видео',
        AttachmentType.document => '📎 ${msg.attachment!.fileName}',
      };
    }
    if (type != ChatType.direct && msg.senderName != null && !msg.isMe) {
      return '${msg.senderName}: $content';
    }
    return content;
  }

  DateTime get lastTime =>
      messages.isNotEmpty ? messages.last.time : DateTime(0);

  bool get canWrite =>
      type != ChatType.community || adminName == 'Я';

  Chat copyWith({List<Message>? messages}) {
    return Chat(
      name: name,
      messages: messages ?? this.messages,
      type: type,
      members: members,
      adminName: adminName,
    );
  }
}

// ─── ThemeProvider ───────────────────────────────────────────────────────────
// Хранит выбранную тему и сохраняет её в SharedPreferences.

enum AppThemeMode { light, dark, system }

class ThemeProvider extends StatefulWidget {
  final Widget child;
  const ThemeProvider({super.key, required this.child});

  static ThemeProviderState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ThemeInherited>()!.state;

  @override
  State<ThemeProvider> createState() => ThemeProviderState();
}

class ThemeProviderState extends State<ThemeProvider> {
  AppThemeMode _mode = AppThemeMode.system;
  static const _key = 'app_theme_mode';

  AppThemeMode get mode => _mode;

  ThemeMode get themeMode => switch (_mode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    final mode = AppThemeMode.values.firstWhere(
          (e) => e.name == saved,
      orElse: () => AppThemeMode.system,
    );
    if (mounted) setState(() => _mode = mode);
  }

  Future<void> setMode(AppThemeMode mode) async {
    setState(() => _mode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  @override
  Widget build(BuildContext context) =>
      _ThemeInherited(state: this, mode: _mode, child: widget.child);
}

class _ThemeInherited extends InheritedWidget {
  final ThemeProviderState state;
  final AppThemeMode mode;

  const _ThemeInherited({
    required this.state,
    required this.mode,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ThemeInherited old) => old.mode != mode;
}

// ─── Приложение ───────────────────────────────────────────────────────────────

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  // Светлая тема
  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.textLight,
      elevation: 0,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: Brightness.light,
    ),
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE0E0E0),
  );

  // Тёмная тема
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1F1F1F),
      foregroundColor: AppColors.textLight,
      elevation: 0,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: Brightness.dark,
    ),
    cardColor: const Color(0xFF1E1E1E),
    dividerColor: const Color(0xFF2C2C2C),
  );

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messenger',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeProvider.of(context).themeMode,
      theme: MyApp.lightTheme,
      darkTheme: MyApp.darkTheme,
      // ── Локализация
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru', 'RU'),
        Locale('en', 'US'),
        Locale('kk', 'KZ'),
      ],
      home: AuthGate(homeScreen: const ChatListScreen()),
    );
  }
}

// ─── Вспомогательные функции ─────────────────────────────────────────────────

String formatTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatChatTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final messageDay = DateTime(time.year, time.month, time.day);

  if (messageDay == today) return formatTime(time);
  if (messageDay == yesterday) return 'Вчера';

  if (today.difference(messageDay).inDays < 7) {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return days[time.weekday - 1];
  }

  const months = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  return '${time.day} ${months[time.month - 1]}';
}

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

// ─── Экран списка чатов ───────────────────────────────────────────────────────

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  String? _myAvatarPath;

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
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final profile = await ProfileStorage.loadProfile();
    if (mounted) setState(() => _myAvatarPath = profile.avatarPath);
  }

  List<Chat> chats = [
    Chat(
      name: 'Алексей',
      type: ChatType.direct,
      messages: [
        Message(
          text: 'Привет!',
          isMe: false,
          time: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        Message(
          text: 'Здорово',
          isMe: true,
          time: DateTime.now().subtract(const Duration(minutes: 4)),
        ),
      ],
    ),
    Chat(
      name: 'Мария',
      type: ChatType.direct,
      messages: [
        Message(
          text: 'Ты где?',
          isMe: false,
          time: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
      ],
    ),
    Chat(
      name: 'Иван',
      type: ChatType.direct,
      messages: [
        Message(
          text: 'Ок',
          isMe: false,
          time: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
    ),
  ];

  List<Chat> get _sortedChats =>
      [...chats]..sort((a, b) => b.lastTime.compareTo(a.lastTime));

  void _onChatUpdated(Chat updatedChat) {
    setState(() {
      final index = chats.indexWhere((c) => c.name == updatedChat.name);
      if (index != -1) chats[index] = updatedChat;
    });
  }

  void _addChat(Chat chat) => setState(() => chats.add(chat));

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
          existingChats: chats,
        ),
      ),
    );
    if (name == null || !mounted) return;

    // Если личный чат с этим именем уже есть — просто открываем его
    final existingIdx = chats.indexWhere(
      (c) => c.name == name && c.type == ChatType.direct,
    );

    Chat targetChat;
    if (existingIdx != -1) {
      targetChat = chats[existingIdx];
    } else {
      // Добавляем контакт в список, если нового нет
      if (!_contacts.any((c) => c.name == name)) {
        setState(() => _contacts.add(AppContact(name: name)));
      }
      targetChat = Chat(name: name, type: ChatType.direct, messages: []);
      setState(() => chats.add(targetChat));
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chat: targetChat,
          onChatUpdated: _onChatUpdated,
          allChats: List.from(chats),
          onAnyChatsUpdated: _onChatUpdated,
        ),
      ),
    );
  }

  void _openCreateDialog(ChatType type) {
    showDialog(
      context: context,
      builder: (_) => _CreateChatDialog(
        type: type,
        contacts: _contacts,
        onCreated: _addChat,
      ),
    );
  }

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    _loadAvatar(); // обновляем аватарку в AppBar после возврата
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
            key: ValueKey(chat.name),
            children: [
              InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        chat: chat,
                        onChatUpdated: _onChatUpdated,
                        allChats: List.from(chats),
                        onAnyChatsUpdated: _onChatUpdated,
                      ),
                    ),
                  );
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
  final ValueChanged<Chat> onCreated;

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

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введите название');
      return;
    }

    widget.onCreated(Chat(
      name: name,
      type: widget.type,
      members: _selectedContacts.toList(),
      adminName: widget.type == ChatType.community ? 'Я' : null,
      messages: [],
    ));
    Navigator.pop(context);
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

// ─── Экран чата ───────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  final Chat chat;
  final ValueChanged<Chat> onChatUpdated;
  final List<Chat> allChats;
  final ValueChanged<Chat> onAnyChatsUpdated;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.onChatUpdated,
    required this.allChats,
    required this.onAnyChatsUpdated,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late List<Message> _messages;
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
    _messages = List.from(widget.chat.messages);
    _loadAvatar();
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

  void _sendMessage({Attachment? attachment}) {
    final text = _controller.text.trim();
    if (text.isEmpty && attachment == null) return;

    final newMessage = Message(
      text: text,
      isMe: true,
      time: DateTime.now(),
      senderName: 'Я',
      attachment: attachment,
    );

    setState(() => _messages = [..._messages, newMessage]);
    widget.onChatUpdated(widget.chat.copyWith(messages: _messages));
    _controller.clear();
    _scrollToBottom();
  }

  // ── Редактирование ────────────────────────────────────
  void _startEdit(Message message) {
    setState(() => _editingMessage = message);
    _controller.text = message.text;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
  }

  void _saveEdit() {
    final text = _controller.text.trim();
    if (text.isEmpty || _editingMessage == null) return;
    final editedId = _editingMessage!.id;
    setState(() {
      _messages = _messages
          .map((m) => m.id == editedId ? m.copyWith(text: text, isEdited: true) : m)
          .toList();
      _editingMessage = null;
    });
    widget.onChatUpdated(widget.chat.copyWith(messages: _messages));
    _controller.clear();
  }

  void _cancelEdit() {
    setState(() => _editingMessage = null);
    _controller.clear();
  }

  // ── Удаление ──────────────────────────────────────────
  void _deleteMessage(Message message) {
    setState(() => _messages = _messages.where((m) => m.id != message.id).toList());
    widget.onChatUpdated(widget.chat.copyWith(messages: _messages));
  }

  void _deleteSelected() {
    setState(() {
      _messages = _messages.where((m) => !_selectedIds.contains(m.id)).toList();
      _selectedIds.clear();
      _isSelectionMode = false;
    });
    widget.onChatUpdated(widget.chat.copyWith(messages: _messages));
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

  void _showForwardDialog(List<Message> messages) {
    final others =
        widget.allChats.where((c) => c.name != widget.chat.name).toList();
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

  void _forwardTo(Chat target, List<Message> messages) {
    final forwarded = messages
        .map((m) => Message(
              text: m.text,
              isMe: true,
              time: DateTime.now(),
              senderName: 'Я',
              attachment: m.attachment,
            ))
        .toList();
    final updated = target.copyWith(messages: [...target.messages, ...forwarded]);
    widget.onAnyChatsUpdated(updated);
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
    final ext = file.name.split('.').last.toLowerCase();
    final attachType = _kVideoExtensions.contains(ext)
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
    final chat = widget.chat;

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
                return _MessageBubble(
                  message: msg,
                  showSenderName: chat.type != ChatType.direct,
                  myAvatarPath: _myAvatarPath,
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
              _EditingIndicator(
                message: _editingMessage!,
                onCancel: _cancelEdit,
              ),
            if (chat.canWrite)
              _MessageInput(
                controller: _controller,
                onSend: _sendOrEdit,
                onAttach: _showAttachmentOptions,
                isEditing: _editingMessage != null,
              )
            else
              const _LockedInput(),
          ],
        ],
      ),
    );
  }
}

// ─── Пузырь сообщения ─────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool showSenderName;
  final String? myAvatarPath;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  const _MessageBubble({
    required this.message,
    this.showSenderName = false,
    this.myAvatarPath,
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
            // ── Текст + метка (изм.) + время ─────────────
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
                    const ChatAvatar(
                        type: ChatType.direct,
                        radius: AppSizes.avatarRadiusSmall),
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

// ─── Поле ввода сообщения ─────────────────────────────────────────────────────

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool isEditing;

  const _MessageInput({
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

// ─── Превью вложения в пузыре ─────────────────────────────────────────────────

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
      onTap: () => _MediaViewerScreen.open(context, attachment),
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
      onTap: () => _MediaViewerScreen.open(context, attachment),
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

// ─── Полноэкранный просмотр медиа ────────────────────────────────────────────

class _MediaViewerScreen extends StatefulWidget {
  final Attachment attachment;

  const _MediaViewerScreen({required this.attachment});

  static void open(BuildContext context, Attachment attachment) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) =>
            _MediaViewerScreen(attachment: attachment),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<_MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<_MediaViewerScreen> {
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