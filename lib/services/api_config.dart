/// Конфигурация подключения к серверу.
///
/// При разработке используйте локальный адрес (10.0.2.2 для Android-эмулятора,
/// localhost для десктопа). В продакшене замените на реальный URL сервера.
class ApiConfig {
  /// Базовый URL REST API (без завершающего слеша).
  /// Для Android-эмулятора используйте 10.0.2.2, для десктопа — localhost.
  static String baseUrl = 'http://localhost:5216/api';

  /// URL SignalR-хаба для получения событий в реальном времени.
  static String hubUrl = 'http://localhost:5216/hub/chat';

  /// Таймаут HTTP-запросов.
  static const Duration httpTimeout = Duration(seconds: 30);

  /// Интервал переподключения SignalR при обрыве связи.
  static const Duration wsReconnectDelay = Duration(seconds: 3);

  /// Максимальный размер загружаемого файла (100 МБ).
  static const int maxUploadSize = 100 * 1024 * 1024;
}
