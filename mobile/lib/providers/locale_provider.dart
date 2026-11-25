import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Названия НЕ локализуются намеренно: язык в списке всегда подписан на самом
/// себе (как в Telegram/iOS/Discord), иначе выбравший незнакомый язык не найдёт
/// дорогу обратно. Элемент — запись (название, код, флаг).
const kAppLanguages = [
  ('Русский',    'ru', '🇷🇺'),
  ('English',    'en', '🇬🇧'),
  ('Українська', 'uk', '🇺🇦'),
  ('中文',        'zh', '🇨🇳'),
];

String appLanguageName(String code) =>
    kAppLanguages.firstWhere((l) => l.$2 == code, orElse: () => kAppLanguages.first).$1;


class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('ru');

  Locale get locale => _locale;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('locale') ?? 'ru';
      _locale = Locale(code);
    } catch (e) {
      debugPrint('LocaleProvider.load: $e');
    }
    notifyListeners();
  }

  void follow(Locale locale) {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('locale', locale.languageCode);
    } catch (e) {
      debugPrint('LocaleProvider.setLocale: $e');
    }
    notifyListeners();
  }
}

final localeProvider = LocaleProvider();
