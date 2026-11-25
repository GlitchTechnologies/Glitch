import 'package:flutter/material.dart';
import 'package:glitch_ringtone/glitch_ringtone.dart';
import '../widgets/glitch_switch.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/l10n.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

/// Переключатели отражают состояние Android. Нажатие открывает системные настройки,
/// а при возвращении на экран значения считываются заново.
class PermissionsView extends StatefulWidget {
  const PermissionsView({super.key});

  @override
  State<PermissionsView> createState() => _PermissionsViewState();
}

class _PermissionsViewState extends State<PermissionsView>
    with ThemeAwareState<PermissionsView>, WidgetsBindingObserver {
  bool _loading = true;

  bool _notifications = false;
  bool _microphone = false;
  bool _camera = false;
  bool _gallery = false;
  bool _location = false;

  bool _background = false;
  bool _fullScreen = false;
  bool _hasFullScreenSetting = false;
  bool _hasAutostart = false;
  bool _hasLockScreen = false;

  @override
  void initState() {
    super.initState();
    // Человек уходит выдавать разрешение в системные настройки и возвращается
    // обратно — состояние надо перечитать. Иначе он увидит старые значения и
    // решит, что нажатие не сработало.
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final notifications = await Permission.notification.isGranted;
    final microphone = await Permission.microphone.isGranted;
    final camera = await Permission.camera.isGranted;
    final gallery =
        await Permission.photos.isGranted || await Permission.storage.isGranted;
    final location = await Permission.location.isGranted;

    final background = await GlitchCallSettings.isBackgroundAllowed();
    final hasFullScreenSetting = await GlitchCallSettings.hasFullScreenSetting();
    final fullScreen = await GlitchCallSettings.isFullScreenAllowed();
    final hasAutostart = await GlitchCallSettings.hasAutostartSettings();
    final hasLockScreen = await GlitchCallSettings.hasLockScreenSettings();

    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _microphone = microphone;
      _camera = camera;
      _gallery = gallery;
      _location = location;
      _background = background;
      _hasFullScreenSetting = hasFullScreenSetting;
      _fullScreen = fullScreen;
      _hasAutostart = hasAutostart;
      _hasLockScreen = hasLockScreen;
      _loading = false;
    });
  }

  Future<void> _tapPermission(Permission permission, bool granted) async {
    if (granted) {
      await openAppSettings();
      return;
    }
    final status = await permission.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    await _load();
  }

  Future<void> _tapGallery(bool granted) async {
    if (granted) {
      await openAppSettings();
      return;
    }
    var status = await Permission.photos.request();
    if (!status.isGranted) status = await Permission.storage.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_loading) return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            s.permissionsSubtitle,
            style: TextStyle(
                fontSize: 13.5, color: GlitchColors.textSecond, height: 1.35),
          ),
        ),

        _header(s.permissionsBasic),
        _section(children: [
          _row(
            iconBg: const Color(0xFF2b7af2),
            icon: Icons.notifications_outlined,
            label: s.permNotifications,
            hint: s.permNotificationsHint,
            value: _notifications,
            onTap: () => _tapPermission(Permission.notification, _notifications),
            border: true,
          ),
          _row(
            iconBg: const Color(0xFF34c759),
            icon: Icons.mic_none_rounded,
            label: s.permMicrophone,
            hint: s.permMicrophoneHint,
            value: _microphone,
            onTap: () => _tapPermission(Permission.microphone, _microphone),
            border: true,
          ),
          _row(
            iconBg: const Color(0xFF8e5af2),
            icon: Icons.photo_camera_outlined,
            label: s.permCamera,
            hint: s.permCameraHint,
            value: _camera,
            onTap: () => _tapPermission(Permission.camera, _camera),
            border: true,
          ),
          _row(
            iconBg: const Color(0xFFff9500),
            icon: Icons.photo_library_outlined,
            label: s.permGallery,
            hint: s.permGalleryHint,
            value: _gallery,
            onTap: () => _tapGallery(_gallery),
            border: true,
          ),
          _row(
            iconBg: const Color(0xFFff375f),
            icon: Icons.location_on_outlined,
            label: s.permLocation,
            hint: s.permLocationHint,
            value: _location,
            onTap: () => _tapPermission(Permission.location, _location),
            border: false,
          ),
        ]),

        const SizedBox(height: 22),
        _header(s.permissionsForCalls),
        _section(children: [
          _row(
            iconBg: const Color(0xFF34c759),
            icon: Icons.battery_charging_full_rounded,
            label: s.permBackground,
            hint: s.permBackgroundHint,
            value: _background,
            onTap: () async {
              if (_background) {
                await openAppSettings();
              } else {
                await GlitchCallSettings.requestBackground();
              }
            },
            border: _hasFullScreenSetting || _hasAutostart,
          ),
          if (_hasFullScreenSetting)
            _row(
              iconBg: const Color(0xFF2b7af2),
              icon: Icons.fullscreen_rounded,
              label: s.permFullScreen,
              hint: s.permFullScreenHint,
              value: _fullScreen,
              onTap: () => GlitchCallSettings.openFullScreenSettings(),
              border: _hasAutostart || _hasLockScreen,
            ),
          if (_hasLockScreen)
            _arrowRow(
              iconBg: const Color(0xFF5856d6),
              icon: Icons.lock_open_rounded,
              label: s.permLockScreen,
              hint: s.permLockScreenHint,
              onTap: () => GlitchCallSettings.openLockScreenSettings(),
              border: _hasAutostart,
            ),
          if (_hasAutostart)
            _arrowRow(
              iconBg: const Color(0xFFff9500),
              icon: Icons.rocket_launch_outlined,
              label: s.permAutostart,
              hint: s.permAutostartHint,
              onTap: () => GlitchCallSettings.openAutostartSettings(),
            ),
        ]),
      ],
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: GlitchColors.textSecond,
            letterSpacing: 0.6,
          ),
        ),
      );

  Widget _section({required List<Widget> children}) => Container(
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          border: Border.all(color: GlitchColors.borderCard),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: children),
      );

  Widget _row({
    required Color iconBg,
    required IconData icon,
    required String label,
    required String hint,
    required bool value,
    required VoidCallback onTap,
    required bool border,
  }) {
    return _baseRow(
      iconBg: iconBg,
      icon: icon,
      label: label,
      hint: hint,
      border: border,
      onTap: onTap,
      trailing: GlitchSwitch(value: value, onChanged: (_) => onTap()),
    );
  }

  Widget _arrowRow({
    required Color iconBg,
    required IconData icon,
    required String label,
    required String hint,
    required VoidCallback onTap,
    bool border = false,
  }) {
    return _baseRow(
      iconBg: iconBg,
      icon: icon,
      label: label,
      hint: hint,
      border: border,
      onTap: onTap,
      trailing: Icon(Icons.chevron_right_rounded, color: GlitchColors.textHint, size: 22),
    );
  }

  Widget _baseRow({
    required Color iconBg,
    required IconData icon,
    required String label,
    required String hint,
    required bool border,
    required VoidCallback onTap,
    required Widget trailing,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: border
            ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.borderSoft)))
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: Icon(icon, color: GlitchColors.textPrimary, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15.5,
                        color: GlitchColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: TextStyle(
                          fontSize: 12.5, color: GlitchColors.textSecond, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
