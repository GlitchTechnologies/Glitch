import 'package:flutter/foundation.dart';
import '../models/message.dart';

class PinState {
  PinState({
    required Future<MessagePreview?> Function() fetch,
    required Future<MessagePreview?> Function(int? id) save,
    required VoidCallback onChanged,
  })  : _fetch = fetch,
        _save = save,
        _onChanged = onChanged;

  final Future<MessagePreview?> Function() _fetch;
  final Future<MessagePreview?> Function(int? id) _save;
  // Провайдер сам гасит вызов после своего dispose
  final VoidCallback _onChanged;

  MessagePreview? pinned;

  int _seq = 0;

  bool isPinned(int id) => pinned?.id == id;

  void _set(MessagePreview? value) {
    pinned = value;
    _onChanged();
  }

  // -------------------------
  // ЗАГРУЗКА (открытие экрана, ресинк после переподключения)
  // -------------------------
  Future<void> load() async {
    final seq = ++_seq;
    try {
      final value = await _fetch();
      if (seq != _seq) return;
      _set(value);
    } catch (_) {
      // Нет сети — оставляем показанное. Ресинк после переподключения догонит.
    }
  }

  Future<void> set(MessagePreview? next) async {
    final before = pinned;
    final seq = ++_seq;
    _set(next);
    try {
      final saved = await _save(next?.id);
      if (seq != _seq) return;
      _set(saved);
    } catch (_) {
      if (seq == _seq) _set(before);
      rethrow;
    }
  }

  void applyRemote(MessagePreview? value) {
    _seq++;
    _set(value);
  }

  void onDeleted(int id) {
    if (pinned?.id != id) return;
    _seq++;
    _set(null);
  }

  void onEdited(int id, String text) {
    final p = pinned;
    if (p == null || p.id != id) return;
    _set(p.type == 'text' ? p.copyWith(content: text) : p.copyWith(caption: text));
  }
}
