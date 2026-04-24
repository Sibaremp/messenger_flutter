import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'api_config.dart';

/// Кэширующий сервис миниатюр и длительностей видео.
///
/// • Миниатюры сохраняются на диск и переживают перезапуск приложения.
/// • In-memory кэш заполняется лениво при первом обращении.
/// • [isCached] / [getCachedThumb] / [getCachedDuration] — синхронный доступ
///   для использования в [initState], чтобы исключить мерцание при прокрутке.
/// • На десктопе генерация кадра требует активного VideoController —
///   вызов происходит из виджета [_VideoPreview] через [saveScreenshot].
class VideoThumbnailService {
  VideoThumbnailService._();
  static final VideoThumbnailService instance = VideoThumbnailService._();

  /// thumbPath (null = «не удалось»). Содержит ключ → значение для всех
  /// уже обработанных путей (включая null-результат, чтобы не повторять).
  final Map<String, String?> _thumbCache = {};

  /// Кэш длительностей видео.
  final Map<String, Duration> _durationCache = {};

  /// Незавершённые фьючеры генерации (дедупликация параллельных запросов).
  final Map<String, Future<String?>> _inFlight = {};

  // ── Синхронный доступ ────────────────────────────────────────────────────

  /// Возвращает путь к миниатюре, если она уже в памяти; иначе null.
  String? getCachedThumb(String path) =>
      _thumbCache.containsKey(path) ? _thumbCache[path] : null;

  /// Возвращает true, если результат для [path] уже известен (в том числе
  /// null — «не удалось сгенерировать»).
  bool isCached(String path) => _thumbCache.containsKey(path);

  /// Кэшированная длительность видео или null, если ещё не получена.
  Duration? getCachedDuration(String path) => _durationCache[path];

  // ── Асинхронный доступ ──────────────────────────────────────────────────

  /// Возвращает путь к JPEG-миниатюре или null.
  /// На десктопе вернёт null — там генерацию ведёт виджет ([saveScreenshot]).
  Future<String?> getThumbnail(String videoPath) async {
    if (kIsWeb) return null;
    if (_thumbCache.containsKey(videoPath)) return _thumbCache[videoPath];
    if (_inFlight.containsKey(videoPath)) return _inFlight[videoPath];

    // На десктопе без VideoController screenshot недоступен.
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      // Проверяем, есть ли кэш на диске (от предыдущего сеанса).
      final diskPath = await _checkDiskCache(videoPath);
      _thumbCache[videoPath] = diskPath;
      return diskPath;
    }

    final future = _generateMobile(videoPath);
    _inFlight[videoPath] = future;
    try {
      final result = await future;
      _thumbCache[videoPath] = result;
      return result;
    } finally {
      _inFlight.remove(videoPath);
    }
  }

  /// Генерирует миниатюру на мобильных/macOS через Player без VideoController.
  Future<String?> _generateMobile(String videoPath) async {
    try {
      final cachePath = await _cachePathFor(videoPath);
      final file = File(cachePath);

      // Уже сохранено на диске → возвращаем сразу.
      if (await file.exists()) {
        // Попробуем вытащить длительность позже отдельным запросом, если нет.
        return cachePath;
      }

      await Directory(file.parent.path).create(recursive: true);

      final source = ApiConfig.isServerMediaPath(videoPath)
          ? ApiConfig.resolveMediaUrl(videoPath)!
          : videoPath;

      final player = Player();
      try {
        await player.open(Media(source), play: false);

        // Ждём декодирования первого кадра.
        final width = await player.stream.width
            .firstWhere((w) => w != null && w > 0)
            .timeout(const Duration(seconds: 10))
            .catchError((_) => null);

        if ((width ?? 0) <= 0) return null;

        // Кэшируем длительность.
        final dur = player.state.duration;
        if (dur > Duration.zero) _durationCache[videoPath] = dur;

        // Перемотка к первому осмысленному кадру.
        await player.seek(const Duration(milliseconds: 500));
        await Future.delayed(const Duration(milliseconds: 350));

        final Uint8List? bytes = await player.screenshot();
        if (bytes == null || bytes.isEmpty) return null;

        await file.writeAsBytes(bytes);
        return cachePath;
      } finally {
        await player.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Проверяет, существует ли файл миниатюры на диске.
  Future<String?> _checkDiskCache(String videoPath) async {
    try {
      final cachePath = await _cachePathFor(videoPath);
      if (await File(cachePath).exists()) return cachePath;
    } catch (_) {}
    return null;
  }

  // ── Сохранение скриншота (из виджета с VideoController — десктоп) ────────

  /// Сохраняет готовые байты как превью и обновляет кэш.
  Future<String?> saveScreenshot(String videoPath, Uint8List bytes) async {
    if (kIsWeb || bytes.isEmpty) return null;
    // Если уже есть — не перезаписываем.
    if (_thumbCache.containsKey(videoPath) && _thumbCache[videoPath] != null) {
      return _thumbCache[videoPath];
    }
    try {
      final cachePath = await _cachePathFor(videoPath);
      final file = File(cachePath);
      await Directory(file.parent.path).create(recursive: true);
      if (!await file.exists()) await file.writeAsBytes(bytes);
      _thumbCache[videoPath] = cachePath;
      return cachePath;
    } catch (_) {
      return null;
    }
  }

  /// Сохраняет длительность в кэш (вызывается из виджета после захвата кадра).
  void cacheDuration(String videoPath, Duration duration) {
    if (duration > Duration.zero) _durationCache[videoPath] = duration;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String> _cachePathFor(String videoPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = videoPath.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    return '${dir.path}/thumbnails/$safe.jpg';
  }
}
