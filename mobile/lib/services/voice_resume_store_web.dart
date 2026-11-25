import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _key = 'glitch_voice_place_v1';
const _atKey = 'glitch_voice_place_at_v1';

Future<({String value, int at})?> readVoicePlace() async {
  try {
    final value = web.window.sessionStorage.getItem(_key);
    final at = int.tryParse(web.window.sessionStorage.getItem(_atKey) ?? '');
    if (value == null || at == null) return null;
    return (value: value, at: at);
  } catch (_) {
    return null;
  }
}

Future<void> writeVoicePlace(String value) async {
  try {
    web.window.sessionStorage.setItem(_key, value);
    _stamp();
    _bindPageHide();
  } catch (_) {}
}

Future<void> clearVoicePlace() async {
  try {
    web.window.sessionStorage.removeItem(_key);
    web.window.sessionStorage.removeItem(_atKey);
  } catch (_) {}
}

void _stamp() {
  try {
    web.window.sessionStorage.setItem(_atKey, '${DateTime.now().millisecondsSinceEpoch}');
  } catch (_) {}
}

// «Дублировать вкладку» копирует и sessionStorage: копия нашла бы свежую
// запись и «вернулась» в разговор, выкинув из него оригинал (для сервера это
// одно устройство). Поэтому вкладка, пока держит голос, ставит отметку в
// localStorage — он общий на все вкладки браузера — и СНИМАЕТ её, когда
// уходит из голоса или страница уходит (`pagehide`, синхронно). Перезагрузка:
// старая страница отметку сняла — новая возвращается. Дубликат: оригинал жив,
// отметка стоит — копия не трогает чужой разговор.
//
// Отметка — про ПРИСУТСТВИЕ, а не про свежесть: подтверждение в фоновой
// вкладке замедлено (см. выше). Срок у неё есть только на случай падения
// вкладки, когда снять её было некому.

const _aliveKey = 'glitch_voice_alive_v1';

void markVoiceAlive() {
  // Страница уже уходит — таймер подтверждения, успевший сработать до
  // выгрузки, не вправе вернуть снятую отметку: новая страница приняла бы
  // себя за дубликат и не вернулась бы в разговор.
  if (_pageHidden) return;
  try {
    web.window.localStorage.setItem(_aliveKey, '${DateTime.now().millisecondsSinceEpoch}');
    _bindPageHide();
  } catch (_) {}
}

void clearVoiceAlive() {
  try {
    web.window.localStorage.removeItem(_aliveKey);
  } catch (_) {}
}

bool otherTabHoldsVoice(Duration within) {
  try {
    final at = int.tryParse(web.window.localStorage.getItem(_aliveKey) ?? '');
    if (at == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) < within;
  } catch (_) {
    return false;
  }
}


bool _pageHideBound = false;
bool _pageHidden = false;

void _bindPageHide() {
  if (_pageHideBound) return;
  _pageHideBound = true;
  web.window.addEventListener('pageshow', ((web.Event _) {
    _pageHidden = false;
  }).toJS);
  web.window.addEventListener(
    'pagehide',
    ((web.Event _) {
      _pageHidden = true;
      clearVoiceAlive();
      try {
        if (web.window.sessionStorage.getItem(_key) != null) _stamp();
      } catch (_) {}
    }).toJS,
  );
}
