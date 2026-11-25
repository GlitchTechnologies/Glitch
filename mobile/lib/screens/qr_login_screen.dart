import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/form_width_limit.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../providers/theme_provider.dart';
import '../widgets/adaptive_shell.dart';
import '../widgets/glitch_icon_button.dart';

class QrLoginScreen extends StatefulWidget {
  const QrLoginScreen({super.key});

  @override
  State<QrLoginScreen> createState() => _QrLoginScreenState();
}

class _QrLoginScreenState extends State<QrLoginScreen> with ThemeAwareState<QrLoginScreen> {
  String? _qrData;
  String? _code;
  String? _deviceId;
  Timer? _pollTimer;
  bool _expired = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _pollTimer?.cancel();
    setState(() { _loading = true; _expired = false; _error = null; });
    try {
      final deviceId = await authService.getOrCreateDeviceId();
      if (!mounted) return;
      final deviceName = await authService.getDeviceName();
      if (!mounted) return;
      final data = await api.qrStart(deviceId: deviceId, deviceName: deviceName);
      if (!mounted) return;
      final code = data['code'] as String;
      setState(() {
        _deviceId = deviceId;
        _code = code;
        _qrData = jsonEncode({'code': code, 'device_name': deviceName});
        _loading = false;
      });
      _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = context.s.qrLoginStartError; });
    }
  }

  Future<void> _poll() async {
    final code = _code;
    final deviceId = _deviceId;
    if (code == null || deviceId == null) return;
    try {
      final data = await api.qrPoll(code, deviceId);
      if (!mounted) return;
      if (data['status'] == 'confirmed') {
        _pollTimer?.cancel();
        final user = User.fromJson(data['user']);
        await authService.saveSession(data['access_token'], user);
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdaptiveShell()));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        _pollTimer?.cancel();
        setState(() => _expired = true);
      }
    } catch (_) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 16, 14),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
                    onTap: () => Navigator.pop(context),
                  ),
                  Text(s.qrLoginTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: FormWidthLimit(
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loading)
                        const CircularProgressIndicator()
                      else if (_error != null) ...[
                        Icon(Icons.error_outline_rounded, color: GlitchColors.error, size: 48),
                        const SizedBox(height: 16),
                        Text(_error!, style: TextStyle(color: GlitchColors.textSecond, fontSize: 15), textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        _retryButton(s),
                      ] else if (_expired) ...[
                        Icon(Icons.timer_off_outlined, color: GlitchColors.textSecond, size: 48),
                        const SizedBox(height: 16),
                        Text(s.qrLoginExpired, style: TextStyle(color: GlitchColors.textSecond, fontSize: 15), textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        _retryButton(s),
                      ] else if (_qrData != null) ...[
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                          child: QrImageView(
                            data: _qrData!,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF111111)),
                            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF111111)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(s.qrLoginInstructions, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5), textAlign: TextAlign.center),
                      ],
                    ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _retryButton(S s) {
    return TextButton(
      onPressed: _start,
      child: Text(s.qrLoginRetry, style: TextStyle(color: GlitchColors.accentBlue, fontWeight: FontWeight.w600, fontSize: 15)),
    );
  }
}
