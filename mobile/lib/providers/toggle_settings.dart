import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

abstract class ToggleSettings extends ChangeNotifier {
  bool loading = true;
  bool _disposed = false;

  @protected
  Future<void> fetch();

  Future<String?> load() async {
    try {
      await fetch();
      if (_disposed) return null;
      loading = false;
      notifyListeners();
      return null;
    } catch (e) {
      if (_disposed) return null;
      loading = false;
      notifyListeners();
      return errorMessage(e);
    }
  }

  @protected
  Future<String?> setOptimistic({
    required void Function(bool) apply,
    required bool value,
    required Future<void> Function() send,
  }) async {
    apply(value);
    notifyListeners();
    try {
      await send();
      return null;
    } catch (e) {
      if (_disposed) return null;
      apply(!value);
      notifyListeners();
      return errorMessage(e);
    }
  }

  @protected
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
