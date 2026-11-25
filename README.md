# Glitch

Glitch — платформа для общения в играх. В нём есть личные чаты,
сообщества с текстовыми и голосовыми каналами и демонстрация экрана.

<img width="1024" height="421" alt="logo3" src="https://github.com/user-attachments/assets/c4db4477-0181-4d17-b653-10c6f19c7b61" />

## Исходный код

- [`mobile/`](mobile/) — клиент на Flutter для Android и Web-версии.
- [`desktop/`](desktop/) — оболочка Glitch для Windows на Electron.

## Сборка

- **Android.** Создайте приложение Android в своём проекте Firebase с
  идентификатором из `mobile/android/app/build.gradle`. Поместите
  `google-services.json` в `mobile/android/app/`. В папке `mobile`
  выполните `flutter pub get`, затем `flutter run`.
- **Web-версия.** В папке `mobile` выполните `flutter pub get`, затем `flutter build web`.
- **Windows.** См. [инструкцию по сборке](desktop/README.md).

## Лицензия

Код клиента распространяется по [GPLv3](LICENSE).
Сторонние компоненты распространяются по своим лицензиям.
