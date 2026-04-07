import 'package:flutter/material.dart';
import '../app_constants.dart';

/// Модель уведомления
class AppNotification {
  final String id;
  final String senderName;
  final String senderRole;
  final String message;
  final DateTime time;
  final String? avatarPath;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.senderName,
    required this.senderRole,
    required this.message,
    required this.time,
    this.avatarPath,
    this.isRead = false,
  });
}

/// Панель уведомлений для desktop-режима.
class NotificationsPanel extends StatefulWidget {
  const NotificationsPanel({super.key});

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  int _selectedFilter = 0; // 0 = все, 1 = за последние сутки

  // Демо-данные
  final List<AppNotification> _notifications = [
    AppNotification(
      id: '1',
      senderName: 'Профессор Иванов А. С.',
      senderRole: 'Преподаватель кафедры математики • Прикладная информатика',
      message: '+3 012 345 2345',
      time: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    AppNotification(
      id: '2',
      senderName: 'Марина Филипова',
      senderRole: 'Заведующая отделением «Техническое направление ОНО»',
      message: '«Студенты, имеющие долги, не будут допущены к написанию дипломной работы»',
      time: DateTime.now().subtract(const Duration(hours: 5)),
    ),
  ];

  List<AppNotification> get _filtered {
    if (_selectedFilter == 1) {
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      return _notifications.where((n) => n.time.isAfter(cutoff)).toList();
    }
    return _notifications;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Заголовок ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
          child: Text(
            'Центр уведомлений',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Следите за актуальными данными преподавателей и результатами',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.subtle,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Фильтр ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            children: [
              _FilterChip(
                label: 'Все',
                selected: _selectedFilter == 0,
                onTap: () => setState(() => _selectedFilter = 0),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'За последние сутки',
                selected: _selectedFilter == 1,
                onTap: () => setState(() => _selectedFilter = 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Divider(
          height: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.2),
        ),

        // ── Список уведомлений ─────────────────────────────────────
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'Нет уведомлений',
                    style: TextStyle(color: AppColors.subtle, fontSize: 15),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 32,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.grey.withValues(alpha: 0.15),
                  ),
                  itemBuilder: (context, index) {
                    final n = items[index];
                    return _NotificationCard(notification: n);
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Чип-фильтр ────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.subtle.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.subtle,
          ),
        ),
      ),
    );
  }
}

// ─── Карточка уведомления ───────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;

  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Аватарка
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: const Icon(Icons.person, color: AppColors.primary, size: 24),
        ),
        const SizedBox(width: 14),
        // Содержимое
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.senderName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                notification.senderRole,
                style: TextStyle(fontSize: 12, color: AppColors.subtle),
              ),
              const SizedBox(height: 8),
              if (notification.message.isNotEmpty)
                Text(
                  notification.message,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Кнопка «Прочитать» и время
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('Прочитать', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 6),
            Text(
              formatTime(notification.time),
              style: TextStyle(fontSize: 11, color: AppColors.subtle),
            ),
          ],
        ),
      ],
    );
  }
}
