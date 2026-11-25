import '../core/l10n.dart';
import '../services/api_service.dart';
import '../services/desktop_shell.dart';
import 'toggle_settings.dart';

class SystemSettings extends ToggleSettings {
  bool openAtLogin = false;

  bool closeToTray = true;

  DesktopShell get _shell => desktopShell!;

  @override
  Future<void> fetch() async => _take(await _shell.getSystemSettings());

  Future<String?> setOpenAtLogin(bool value) => setOptimistic(
        apply: (v) => openAtLogin = v,
        value: value,
        send: () async {
          final now = await _shell.setOpenAtLogin(value);
          if (now.openAtLogin != value) throw const _NotApplied();
          _take(now);
        },
      );

  Future<String?> setCloseToTray(bool value) => setOptimistic(
        apply: (v) => closeToTray = v,
        value: value,
        send: () async {
          final now = await _shell.setCloseToTray(value);
          if (now.closeToTray != value) throw const _NotApplied();
          _take(now);
        },
      );

  void _take(DesktopSystemSettings now) {
    openAtLogin = now.openAtLogin;
    closeToTray = now.closeToTray;
  }
}

class _NotApplied implements LocalizedError {
  const _NotApplied();

  @override
  String describe(S s) => s.systemSettingFailed;
}
