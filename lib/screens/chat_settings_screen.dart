import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models.dart';
import '../app_constants.dart';

class ChatSettingsScreen extends StatefulWidget {
  final Chat chat;

  const ChatSettingsScreen({super.key, required this.chat});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  String? _avatarPath;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController  = TextEditingController(text: widget.chat.name);
    _descController  = TextEditingController(text: widget.chat.description ?? '');
    _avatarPath      = widget.chat.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _avatarPath = picked.path);
    }
  }

  void _showPickerOptions() {
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
                child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
              ),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.photo_library, color: Colors.white, size: 20),
              ),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_avatarPath != null)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEEEEEE),
                  child: Icon(Icons.delete_outline, color: Colors.red, size: 20),
                ),
                title: const Text('Удалить фото',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _avatarPath = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Название не может быть пустым'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final updated = widget.chat.copyWith(
      name: name,
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      avatarPath: _avatarPath,
    );

    if (!mounted) return;
    Navigator.pop(context, updated);
  }

  Widget _buildAvatar() {
    if (_avatarPath != null) {
      final file = File(_avatarPath!);
      if (file.existsSync()) {
        return CircleAvatar(
          radius: 52,
          backgroundImage: FileImage(file),
        );
      }
    }
    return CircleAvatar(
      radius: 52,
      backgroundColor: AppColors.primary,
      child: Icon(
        switch (widget.chat.type) {
          ChatType.direct    => Icons.person,
          ChatType.group     => Icons.group,
          ChatType.community => Icons.campaign,
        },
        size: 48,
        color: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки чата'),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text(
                    'Сохранить',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 8),
            // ── Аватар ───────────────────────────────────────────────
            Center(
              child: Stack(
                children: [
                  _buildAvatar(),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _showPickerOptions,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // ── Название ─────────────────────────────────────────────
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: widget.chat.type == ChatType.direct ? 'Имя' : 'Название',
                prefixIcon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Описание ─────────────────────────────────────────────
            TextField(
              controller: _descController,
              maxLines: 4,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: 'Описание',
                hintText: 'Добавьте описание...',
                prefixIcon: const Icon(Icons.info_outline, color: AppColors.primary),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Тип чата (только чтение) ─────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    switch (widget.chat.type) {
                      ChatType.direct    => Icons.person_outline,
                      ChatType.group     => Icons.group_outlined,
                      ChatType.community => Icons.campaign_outlined,
                    },
                    color: AppColors.subtle,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Тип',
                          style: TextStyle(fontSize: 11, color: AppColors.subtle),
                        ),
                        Text(
                          switch (widget.chat.type) {
                            ChatType.direct    => 'Личный чат',
                            ChatType.group     => 'Группа',
                            ChatType.community => 'Сообщество',
                          },
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.lock_outline, size: 16, color: AppColors.subtle),
                ],
              ),
            ),
            if (widget.chat.members.isNotEmpty) ...[
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Участники (${widget.chat.members.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.subtle,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...widget.chat.members.map((m) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                color: Theme.of(context).cardColor,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.person, color: Colors.white, size: 18),
                  ),
                  title: Text(m.name),
                  trailing: m.role == MemberRole.creator
                      ? const _RoleBadge(label: 'Создатель', color: AppColors.primary)
                      : m.role == MemberRole.admin
                          ? const _RoleBadge(label: 'Админ', color: Colors.blue)
                          : null,
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _RoleBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
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
}
