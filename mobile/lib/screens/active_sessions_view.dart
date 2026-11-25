import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/glitch_toast.dart';
import '../providers/theme_provider.dart';
import 'qr_scanner_screen.dart';
import '../widgets/glitch_dialog.dart';

class ActiveSessionsView extends StatefulWidget {
  const ActiveSessionsView({super.key});

  @override
  State<ActiveSessionsView> createState() => _ActiveSessionsViewState();
}

class _ActiveSessionsViewState extends State<ActiveSessionsView> with ThemeAwareState<ActiveSessionsView> {
  List<UserSession>? _sessions;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sessions = await api.getSessions();
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } on ApiException catch (e) {
      if (mounted) GlitchToast.show(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _terminate(UserSession session) async {
    final confirm = await glitchConfirm(context,
        title: context.s.securitySessionsTerminateConfirmTitle,
        body: context.s.securitySessionsTerminateConfirmBody(session.deviceName),
        confirmLabel: context.s.securitySessionsTerminate);
    if (!confirm || !mounted) return;

    setState(() => _busy = true);
    try {
      await api.revokeSession(session.id);
      if (!mounted) return;
      setState(() => _sessions = _sessions?.where((s) => s.id != session.id).toList());
      GlitchToast.show(context, context.s.securitySessionsTerminated);
    } on ApiException catch (e) {
      if (mounted) GlitchToast.show(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _terminateAll() async {
    final confirm = await glitchConfirm(context,
        title: context.s.securitySessionsTerminateAllConfirmTitle,
        body: context.s.securitySessionsTerminateAllConfirmBody,
        confirmLabel: context.s.securitySessionsTerminateAll);
    if (!confirm || !mounted) return;

    setState(() => _busy = true);
    try {
      await api.revokeOtherSessions();
      if (!mounted) return;
      setState(() => _sessions = _sessions?.where((s) => s.isCurrent).toList());
      GlitchToast.show(context, context.s.securitySessionsTerminatedAll);
    } on ApiException catch (e) {
      if (mounted) GlitchToast.show(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatLastActive(UserSession s) {
    if (DateTime.now().difference(s.lastActiveAt).inMinutes < 3) {
      return context.s.securitySessionsActiveNow;
    }
    return context.s.securitySessionsLastSeenAt(DateFormat('dd.MM.yyyy HH:mm').format(s.lastActiveAt));
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions ?? [];
    final hasOthers = sessions.any((s) => !s.isCurrent);

    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      children: [
        _connectDeviceCard(),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: GlitchColors.bgCard,
            border: Border.all(color: GlitchColors.borderCard),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              for (int i = 0; i < sessions.length; i++)
                _sessionRow(sessions[i], border: i < sessions.length - 1),
            ],
          ),
        ),
        if (hasOthers) ...[
          const SizedBox(height: 16),
          GlitchActionButton(
            label: context.s.securitySessionsTerminateAll,
            onTap: _terminateAll,
            destructive: true,
            loading: _busy,
          ),
        ],
      ],
    );
  }

  Future<void> _openScanner() async {
    final result = await withDimmedStatusBar(
      () => Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const QrScannerScreen())),
    );
    if (result == true) {
      if (!mounted) return;
      GlitchToast.show(context, context.s.qrConnectDeviceSuccess);
      _load(); // подтянуть новое устройство в список
    }
  }

  Widget _connectDeviceCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        border: Border.all(color: GlitchColors.borderCard),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(Icons.devices_outlined, color: GlitchColors.textSecond, size: 44),
          const SizedBox(height: 14),
          Text(
            context.s.qrConnectDeviceHint,
            style: TextStyle(fontSize: 14.5, color: GlitchColors.textSecond),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _openScanner,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(gradient: GlitchColors.gradientAccent, borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(context.s.qrConnectDeviceButton, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionRow(UserSession s, {bool border = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: border ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.borderMuted))) : null,
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: GlitchColors.bgInput, shape: BoxShape.circle),
            child: Icon(Icons.phone_android_rounded, color: GlitchColors.accentBlue, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.deviceName,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (s.isCurrent) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: GlitchColors.online.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                        child: Text(context.s.securitySessionsCurrent, style: TextStyle(fontSize: 11, color: GlitchColors.online)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(_formatLastActive(s), style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
              ],
            ),
          ),
          if (!s.isCurrent)
            GlitchMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, size: 22),
              size: 34,
              onSelected: (value) {
                if (_busy) return; // уже идёт отзыв другой сессии — не запускаем второй параллельно
                if (value == 'terminate') _terminate(s);
              },
              itemBuilder: (ctx) => [
                GlitchMenuItem<String>(
                  value: 'terminate',
                  child: Row(children: [
                    const Icon(Icons.logout_rounded, color: GlitchColors.error, size: 20),
                    const SizedBox(width: 12),
                    Text(context.s.securitySessionsTerminate, style: const TextStyle(fontSize: 15, color: GlitchColors.error)),
                  ]),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
