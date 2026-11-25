import 'dart:async';
import 'dart:convert';
import '../core/platform_info.dart';
import '../core/net_error_web.dart' if (dart.library.io) '../core/net_error_native.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_version.dart';
import 'current_screen.dart';

/// ГЛАВНОЕ ПРАВИЛО: отправка никогда ничего не ломает и ничего не показывает.
/// Она не блокирует интерфейс, не бросает исключений, не повторяет попытки и
/// молчит при любой неудаче. Потерять отчёт не страшно — испортить ради отчёта
/// работу приложения недопустимо.
class ErrorReporter {
  ErrorReporter._();
  static final ErrorReporter instance = ErrorReporter._();

  static const _endpoint = 'https://glitchapp.online/logs/client';
  static const _timeout = Duration(seconds: 10);

  /// Потолок на один запуск приложения. Страховка от случая, когда что-то
  /// сыплет ошибками непрерывно (зациклившийся таймер, битый кадр в потоке):
  /// человек и так уже видит, что всё сломано, а сотни одинаковых отчётов
  /// только забьют журнал и упрутся в лимит сервера (20 в минуту).
  static const _maxPerSession = 20;

  static const _dedupWindow = Duration(minutes: 5);

  int _sent = 0;
  final Map<String, DateTime> _recent = {};

  String? _token;
  set token(String? value) => _token = value;

  void report(Object error, {StackTrace? stack, String? screen, String? context}) {
    try {
      if (!_shouldReport(error)) return;
      if (_sent >= _maxPerSession) return;

      final key = _signature(error, stack);
      final now = DateTime.now();
      final last = _recent[key];
      if (last != null && now.difference(last) < _dedupWindow) return;
      _recent[key] = now;
      _sent++;

      final effectiveScreen = screen ?? CurrentScreen.name;

      unawaited(_send(error, stack, effectiveScreen, context));
    } catch (_) {
      // Сам репортёр не имеет права ничего сломать.
    }
  }

  bool _shouldReport(Object error) {
    if (isTransportError(error)) return false;
    if (error is TimeoutException) return false;
    return true;
  }

  /// Подпись ошибки для дедупликации: тип + начало текста + первый кадр стека.
  /// Именно ПЕРВЫЙ кадр, а не весь стек: у одной и той же ошибки хвост вызовов
  /// может отличаться, а место возникновения то же.
  String _signature(Object error, StackTrace? stack) {
    final head = error.toString();
    final short = head.length > 120 ? head.substring(0, 120) : head;
    var firstFrame = '';
    if (stack != null) {
      for (final line in stack.toString().split('\n')) {
        if (line.trim().isNotEmpty) {
          firstFrame = line.trim();
          break;
        }
      }
    }
    return '${error.runtimeType}|$short|$firstFrame';
  }

  Future<void> _send(Object error, StackTrace? stack, String? screen, [String? context]) async {
    try {
      final platform = kReleaseMode ? currentPlatform : '$currentPlatform-debug';

      await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              if (_token != null) 'Authorization': 'Bearer $_token',
            },
            body: jsonEncode({
              'message': _clip(_describe(error), 2000),
              // Контекст идёт ПЕРЕД стеком и в том же поле details — сервер и
              // старые сборки при этом не трогаются вовсе (формат запроса тот
              // же). Впереди он потому, что именно с него начинают разбор:
              // строка «error-causing widget» отвечает на вопрос сразу, а стек
              // у ошибок отрисовки состоит из одного фреймворка и не отвечает
              // ни на что.
              if (stack != null || context != null)
                'details': _clip([
                  if (context != null && context.trim().isNotEmpty) context.trim(),
                  if (stack != null) stack.toString(),
                ].join('\n\n'), 20000),
              if (screen != null) 'screen': _clip(screen, 255),
              'app_version': appVersion,
              'platform': platform,
            }),
          )
          .timeout(_timeout);
    } catch (_) {
    }
  }

  String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

  String _describe(Object error) {
    final s = error.toString().trim();
    return s.isEmpty ? error.runtimeType.toString() : s;
  }
}

final errorReporter = ErrorReporter.instance;
