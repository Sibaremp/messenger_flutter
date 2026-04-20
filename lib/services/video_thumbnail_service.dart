import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'api_config.dart';

/// Кэширующий сервис миниатюр для видео.
///
/// Использует [media_kit] для извлечения первого кадра — работает на **всех**
/// платформах (Android, iOS, Windows, Linux, macOS) без внешних зависимостей
/// вроде ffmpeg. Миниатюры сохраняются на диск, чтобы не регенерировать их
/// на каждой перестройке списка.
class VideoThumbnailService {
  VideoThumbnailService._();
  static final VideoThumbnailService instance = VideoThumbnailService._();

  /// In-memory кэш путей к готовым миниатюрам (null = «не удалось сгенерировать»).
  final Map<String, String?> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};

  /// Возвращает локальный путь к JPEG-миниатюре для видео, либо null, если
  /// миниатюра недоступна.
  Future<String?> getThumbnail(String videoPath) async {
    if (kIsWeb) return null;
    if (_cache.containsKey(videoPath)) return _cache[videoPath];
    if (_inFlight.containsKey(videoPath)) return _inFlight[videoPath];

    final future = _generate(videoPath);
    _inFlight[videoPath] = future;
    try {
      final path = await future;
      _cache[videoPath] = path;
      return path;
    } finally {
      _inFlight.remove(videoPath);
    }
  }

  Future<String?> _generate(String videoPath) async {
    try {
      final cachePath = await _cachePathFor(videoPath);
      final file = File(cachePath);
      if (await file.exists()) return cachePath;

      await Directory(file.parent.path).create(recursive: true);

      // Для серверных путей строим полный URL.
      final source = ApiConfig.isServerMediaPath(videoPath)
          ? ApiConfig.resolveMediaUrl(videoPath)!
          : videoPath;

      // Создаём временный Player для захвата скриншота первого кадра.
      // Примечание: на десктопе (Windows/Linux/macOS) player.screenshot()
      // требует активного VideoController (рендер-контекст OpenGL/D3D).
      // Здесь мы работаем без VideoController — это работает на мобильных
      // платформах. Для десктопа превью генерируется из виджета _VideoPreview
      // после первого рендера через [saveScreenshot].
      final player = Player();
      try {
        // Открываем медиа без воспроизведения.
        await player.open(Media(source), play: false);

        // Даём декодеру время подготовить первый кадр.
        await player.stream.width
            .firstWhere((w) => w != null && w > 0)
            .timeout(const Duration(seconds: 8))
            .catchError((_) => null);

        // Перематываем на 0.5 секунды, чтобы поймать осмысленный кадр.
        await player.seek(const Duration(milliseconds: 500));
        await Future.delayed(const Duration(milliseconds: 400));

        final Uint8List? screenshot = await player.screenshot();
        if (screenshot == null || screenshot.isEmpty) return null;

        await file.writeAsBytes(screenshot);
        return cachePath;
      } finally {
        await player.dispose();
      }
    } catch (_) {
      // Нет кодека / файл недоступен — просто отдадим null, UI покажет
      // placeholder. Не хотим валить UI из-за превью.
      return null;
    }
  }

  /// Сохраняет готовые байты скриншота как превью для [videoPath].
  /// Вызывается из виджета просмотра видео после первого рендера,
  /// где VideoController уже есть — это единственный надёжный способ
  /// получить кадр на десктопе.
  Future<void> saveScreenshot(String videoPath, Uint8List bytes) async {
    if (kIsWeb || bytes.isEmpty) return;
    final key = videoPath;
    if (_cache.containsKey(key) && _cache[key] != null) return; // уже есть
    final cachePath = await _cachePathFor(videoPath);
    final file = File(cachePath);
    if (await file.exists()) {
      _cache[key] = cachePath;
      return;
    }
    await Directory(file.parent.path).create(recursive: true);
    await file.writeAsBytes(bytes);
    _cache[key] = cachePath;
  }

  Future<String> _cachePathFor(String videoPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe =
        videoPath.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    return '${dir.path}/thumbnails/$safe.jpg';
  }
}
