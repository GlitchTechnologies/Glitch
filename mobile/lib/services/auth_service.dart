import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart'; // debugPrint (лог сбоя чистки), ValueNotifier (currentUser)
import '../core/platform_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_id/android_id.dart';
import '../models/user.dart';
import '../providers/call_provider.dart';
import 'api_service.dart';
import 'cache_service.dart';
import 'websocket_service.dart';

class AuthService {
  static const _tokenKey      = 'aero_token';
  static const _userCacheKey  = 'aero_user_cache';
  static const _deviceIdKey   = 'glitch_device_id';

  User? get currentUser => currentUserListenable.value;
  set currentUser(User? user) {
    currentUserListenable.value = user;
    unawaited(_persistUser(user));
  }

  Future<void> _persistUser(User? user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (user == null) {
        await prefs.remove(_userCacheKey);
      } else {
        await prefs.setString(_userCacheKey, jsonEncode(user.toJson()));
      }
    } catch (e) {
      debugPrint('AuthService._persistUser: $e');
    }
  }

  final ValueNotifier<User?> currentUserListenable = ValueNotifier<User?>(null);
  String? token;
  String? _deviceId;

  Future<String> getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_deviceIdKey);
    if (id == null) {
      if (isAndroidPlatform) {
        try {
          final androidId = await const AndroidId().getId();
          if (androidId != null && androidId.isNotEmpty) {
            id = 'hw_$androidId';
          }
        } catch (_) {
        }
      }
      id ??= () {
        final rand = Random.secure();
        final hex = List.generate(32, (_) => rand.nextInt(16).toRadixString(16)).join();
        if (isDesktopPlatform) return 'desktop_$hex';
        if (isWebPlatform) return 'web_$hex';
        return hex;
      }();
      await prefs.setString(_deviceIdKey, id);
    }
    _deviceId = id;
    return id;
  }

  // Человекочитаемое название устройства для списка сессий, напр. "Xiaomi Redmi Note 12",
  // а в браузере — "Chrome (Win32)".
  Future<String> getDeviceName() async {
    // Версия для Windows проверяется первой, поскольку она тоже использует браузерную сборку.
    if (isDesktopApp) return 'Glitch для Windows';
    if (isWebPlatform) {
      try {
        final info = await DeviceInfoPlugin().webBrowserInfo;
        // browserName — перечисление (chrome/firefox/safari/...), .name даёт
        // его строкой в нижнем регистре.
        final browser = info.browserName.name;
        final pretty = browser.isEmpty
            ? 'Браузер'
            : browser[0].toUpperCase() + browser.substring(1);
        final os = (info.platform ?? '').trim();
        return os.isEmpty ? pretty : '$pretty ($os)';
      } catch (_) {
        return 'Браузер';
      }
    }
    if (isAndroidPlatform) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        final manufacturer = info.manufacturer;
        final capitalized = manufacturer.isEmpty
            ? ''
            : manufacturer[0].toUpperCase() + manufacturer.substring(1);
        return capitalized.isEmpty ? info.model : '$capitalized ${info.model}';
      } catch (_) {
        return 'Android';
      }
    }

    return 'Компьютер';
  }

  final _loggedOutCtrl = StreamController<void>.broadcast();
  Stream<void> get onLoggedOut => _loggedOutCtrl.stream;

  final _loggedInCtrl = StreamController<void>.broadcast();
  Stream<void> get onLoggedIn => _loggedInCtrl.stream;

  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_tokenKey);
    if (token == null) return false;

    api.setToken(token!);

    final cached = prefs.getString(_userCacheKey);
    if (cached != null) {
      try {
        currentUser = User.fromJson(jsonDecode(cached));
      } catch (_) {}
    }

    unawaited(_refreshUserInBackground());

    return currentUser != null;
  }

  Future<bool> refreshCurrentUser() => _refreshUserInBackground();

  Future<bool> _refreshUserInBackground() async {
    final sessionToken = token;
    try {
      final fresh = await api.getMe();
      if (token != sessionToken) return false;
      currentUser = fresh;
      return true;
    } catch (e) {
      return false;
    }
  }

  static const _pendingLogoutKey = 'glitch_pending_logout_tokens';
  static const _maxPendingLogouts = 5;

  Future<void> _rememberPendingLogout(int userId, String token) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = List<String>.from(prefs.getStringList(_pendingLogoutKey) ?? const <String>[]);
    final entry = '$userId:$token';
    if (pending.contains(entry)) return;
    pending.add(entry);
    while (pending.length > _maxPendingLogouts) {
      pending.removeAt(0);
    }
    await prefs.setStringList(_pendingLogoutKey, pending);
  }

  Future<void> _dropPendingLogoutsFor(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingLogoutKey) ?? const <String>[];
    if (pending.isEmpty) return;
    final left = pending.where((e) => e.split(':').first != '$userId').toList();
    if (left.length == pending.length) return;
    if (left.isEmpty) {
      await prefs.remove(_pendingLogoutKey);
    } else {
      await prefs.setStringList(_pendingLogoutKey, left);
    }
  }

  Future<void> flushPendingLogouts() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingLogoutKey) ?? const <String>[];
    if (pending.isEmpty) return;

    final left = <String>[];
    for (final entry in pending) {
      final sep = entry.indexOf(':');
      if (sep <= 0) continue; // битая запись — просто выбрасываем
      final done = await api.revokeSessionByToken(entry.substring(sep + 1));
      if (!done) left.add(entry); // сети всё ещё нет — попробуем в следующий раз
    }

    if (left.isEmpty) {
      await prefs.remove(_pendingLogoutKey);
    } else {
      await prefs.setStringList(_pendingLogoutKey, left);
    }
  }

  // Раньше чистка была только в logout(): при отзыве сессии с другого устройства
  // (forceLogout — ровно тот случай, ради которого «Активные сессии» и нужны)
  // кэш чатов, переписки и черновики оставались лежать на телефоне. Ключи у них
  // общие на всё приложение, не по пользователям, поэтому следующий вошедший
  // человек видел чужой список чатов, а при совпадении chat_id — и чужие
  // сообщения. Дубль в saveSession — страховка: даже если выход прошёл мимо
  // чистки (приложение убили сразу после отзыва), новый вход начинается с нуля.
  Future<void> _wipeAccountData() async {
    try {
      await cache.clearAccountData();
    } catch (e) {
      debugPrint('AuthService._wipeAccountData: $e');
    }
  }

  Future<void> forceLogout() async {
    callProvider.endForAccountChange();
    token = null;
    currentUser = null;
    api.clearToken();
    await _wipeAccountData();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _loggedOutCtrl.add(null);
  }

  Future<void> saveSession(String token, User user) async {
    await _wipeAccountData();
    await _dropPendingLogoutsFor(user.id);
    this.token = token;
    currentUser = user;
    api.setToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    _loggedInCtrl.add(null);
  }

  Future<void> logout() async {
    callProvider.endForAccountChange();
    await wsService.disconnect();
    final leavingToken = token;
    final leavingUserId = currentUser?.id;
    try {
      await api.logout();
    } catch (e) {
      final alreadyDead = e is ApiException && e.statusCode == 401;
      if (!alreadyDead && leavingToken != null) {
        await _rememberPendingLogout(leavingUserId ?? -1, leavingToken);
      }
    }
    token = null;
    currentUser = null;
    api.clearToken();
    await _wipeAccountData();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _loggedOutCtrl.add(null);
  }
}

final authService = AuthService();
