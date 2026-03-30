import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_constants.dart';
import '../auth_screen.dart' show AuthService;

// ─── Экран профиля собеседника ────────────────────────────────────────────────

/// Открывается при нажатии на имя / аватар собеседника в личном чате.
/// Показывает аватар (с возможностью открыть на весь экран), ник,
/// «О себе» и телефон с пометкой «В приложении» если номер зарегистрирован.
class ContactProfileScreen extends StatefulWidget {
  final String name;
  final String? avatarPath;
  final String? description;
  final String? phone;

  const ContactProfileScreen({
    super.key,
    required this.name,
    this.avatarPath,
    this.description,
    this.phone,
  });

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  bool _phoneInApp = false;

  @override
  void initState() {
    super.initState();
    if (widget.phone?.isNotEmpty == true) _checkPhone();
  }

  /// Проверяем, зарегистрирован ли номер телефона в приложении.
  Future<void> _checkPhone() async {
    final phones     = await AuthService.getRegisteredPhones();
    final normalized = AuthService.normalizePhone(widget.phone!);
    if (mounted) setState(() => _phoneInApp = phones.contains(normalized));
  }

  bool get _hasPhoto =>
      widget.avatarPath != null && File(widget.avatarPath!).existsSync();

  void _openFullPhoto() {
    if (!_hasPhoto) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (ctx, a, b) =>
            _FullScreenPhoto(path: widget.avatarPath!, heroTag: _heroTag),
        transitionsBuilder: (ctx, anim, a, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  String get _heroTag => 'contact_photo_${widget.name}';

  @override
  Widget build(BuildContext context) {
    final hasDesc  = widget.description?.isNotEmpty == true;
    final hasPhone = widget.phone?.isNotEmpty == true;

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
            // ── Растягиваемый AppBar с аватаркой ──────────────────────
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 14),
                title: Text(
                  widget.name,
                  style: const TextStyle(
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
                background: _hasPhoto
                    ? GestureDetector(
                        onTap: _openFullPhoto,
                        child: Hero(
                          tag: _heroTag,
                          child: Image.file(
                            File(widget.avatarPath!),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        ),
                      )
                    : Container(
                        color: AppColors.primary,
                        child: Center(
                          child: Icon(
                            Icons.person,
                            size: 96,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
              ),
            ),

            // ── Информация ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Подсказка «нажмите на фото для просмотра»
                  if (_hasPhoto)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.touch_app_outlined,
                              size: 14, color: AppColors.subtle),
                          const SizedBox(width: 6),
                          const Text(
                            'Нажмите на фото для просмотра',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.subtle),
                          ),
                        ],
                      ),
                    ),

                  // О себе
                  if (hasDesc)
                    _InfoTile(
                      icon: Icons.info_outline,
                      label: 'О себе',
                      value: widget.description!,
                    ),

                  // Телефон
                  if (hasPhone)
                    _InfoTile(
                      icon: Icons.phone_outlined,
                      label: 'Телефон',
                      value: widget.phone!,
                      trailing: _phoneInApp
                          ? _InAppBadge()
                          : null,
                    ),

                  // Пустое состояние если нет доп. данных
                  if (!hasDesc && !hasPhone)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'Дополнительная информация не указана',
                          style: TextStyle(color: AppColors.subtle),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Строка с иконкой, подписью и значением ──────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

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
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ─── Бейдж «В приложении» ─────────────────────────────────────────────────────

class _InAppBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 12, color: Colors.green),
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
  }
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
          // Фото с масштабированием
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
          // Кнопка закрытия
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
