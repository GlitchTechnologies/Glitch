import 'package:web/web.dart' as web;

String? readTabSession(String key) {
  try {
    return web.window.sessionStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writeTabSession(String key, String value) {
  try {
    web.window.sessionStorage.setItem(key, value);
  } catch (_) {}
}

void removeTabSession(String key) {
  try {
    web.window.sessionStorage.removeItem(key);
  } catch (_) {}
}
