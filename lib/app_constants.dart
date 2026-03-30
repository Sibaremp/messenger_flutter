import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();
  static const primary    = Color(0xFFFF6F00);
  static const background = Color(0xFFF5F5F5);
  static const chatMe     = Color(0xFFFF6F00);
  static const chatOther  = Color(0xFFFFFFFF);
  static const textDark   = Color(0xFF000000);
  static const textLight  = Color(0xFFFFFFFF);
  static const subtle     = Color(0xFF757575);
}

class AppSizes {
  const AppSizes._();
  static const avatarRadiusSmall      = 16.0;
  static const avatarRadiusLarge      = 24.0;
  static const bubbleMaxWidthFactor   = 0.7;
}

const kVideoExtensions = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', '3gp'};

String formatTime(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String formatChatTime(DateTime time) {
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final day   = DateTime(time.year, time.month, time.day);

  if (day == today)     return formatTime(time);
  if (day == yesterday) return 'Вчера';
  if (today.difference(day).inDays < 7) {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return days[time.weekday - 1];
  }
  const months = ['янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
  return '${time.day} ${months[time.month - 1]}';
}
