# College Messenger

Мобильный мессенджер для студентов, разработанный на Flutter.

---

## Возможности

### Чаты
- **Личные сообщения** — переписка один на один с аватаром собеседника
- **Группы** — чаты, в которых могут писать все участники
- **Сообщества** — каналы с правом записи только у администратора
- Пересылка сообщений, редактирование и удаление
- Вложения: фото, видео, документы
- Полноэкранный просмотр медиа с видеоплеером

### Статус сообщений
| Иконка | Статус |
|--------|--------|
| ⏱ | Отправляется |
| ✓ | Отправлено |
| ✓✓ | Доставлено |
| ✗ | Ошибка |

### Контакты
- Автоматическая загрузка телефонной книги устройства (Android / iOS)
- Отображение фото контакта, имени и номера телефона
- Маркировка контактов, уже зарегистрированных в приложении
- Поиск по имени и номеру телефона

### Профиль
- Аватарка (камера или галерея)
- Имя, логин, «О себе», учебная группа
- Номер телефона: автозаполнение с SIM-карты (Android) или ручной ввод (iOS)
- Переключатель светлой / тёмной / системной темы

### Авторизация
- Регистрация по Email или номеру телефона (через SIM на Android)
- Выбор учебной группы при регистрации
- Безопасное хранение данных (`flutter_secure_storage`)

---

## Архитектура

```
lib/
├── main.dart                  # Точка входа, MyApp
├── models.dart                # Модели данных (Chat, Message, ChatMember …)
├── app_constants.dart         # Цвета, размеры, вспомогательные функции
├── theme.dart                 # Темы оформления, ThemeProvider
├── auth_screen.dart           # Экраны входа и регистрации
├── profile_screen.dart        # Профиль пользователя
├── services/
│   ├── chat_service.dart      # Абстракция ChatService + LocalChatService
│   └── sim_service.dart       # Чтение SIM-карты (Android / iOS)
├── widgets/
│   └── chat_widgets.dart      # MessageBubble, MessageInput, ChatAvatar …
└── screens/
    ├── chat_list_screen.dart  # Список чатов
    ├── chat_screen.dart       # Экран переписки
    └── chat_settings_screen.dart  # Настройки чата / группы
```

### Слой сервисов

`ChatService` — абстрактный интерфейс с потоком событий `Stream<ChatEvent>`.
В текущей версии используется `LocalChatService` (данные в памяти).
Для подключения реального бэкенда достаточно реализовать интерфейс:

```dart
class MyWebSocketService implements ChatService { … }
class MyFirebaseService implements ChatService { … }
```

---

## Требования

| | Минимум |
|---|---|
| Flutter | 3.x |
| Dart | 3.x |
| Android | API 23 (Android 6.0) |
| iOS | 12.0 |

---

## Зависимости

| Пакет | Назначение |
|---|---|
| `flutter_secure_storage` | Безопасное хранение сессии |
| `image_picker` | Выбор фото/видео |
| `file_picker` | Выбор документов |
| `video_player` | Воспроизведение видео |
| `flutter_contacts` | Доступ к телефонной книге |
| `permission_handler` | Запрос разрешений |

---

## Запуск

```bash
flutter pub get
flutter run
```

### Android — разрешения
Необходимые разрешения уже прописаны в `AndroidManifest.xml`:
- `READ_CONTACTS` — телефонная книга
- `READ_PHONE_STATE` — данные SIM-карты
- `READ_PHONE_NUMBERS` — номер телефона SIM

---

## Подключение бэкенда

Реализуйте `ChatService` под свой сервер и передайте его в `MyApp`:

```dart
void main() {
  runApp(ThemeProvider(
    child: MyApp(service: MyWebSocketService()),
  ));
}
```
