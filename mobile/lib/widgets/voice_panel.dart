import 'dart:async';

import 'package:flutter/material.dart';

import '../core/adaptive_open.dart' show isWideLayout;
import '../core/l10n.dart';
import '../providers/call_provider.dart';
import '../providers/server_provider.dart';
import '../providers/voice_channels.dart';
import '../theme/app_theme.dart';
import '../theme/glitch_icons.dart';
import 'call_stage.dart' show callStatusText;
import 'chat_call_area.dart' show openCallChat;
import 'glitch_action_button.dart';
import 'glitch_pressable.dart';
import 'glitch_tooltip.dart';
import 'noise_suppression_menu.dart';
import 'glitch_icon_button.dart';
import 'voice_connection_menu.dart';
import 'voice_controls.dart';



class VoicePanel extends StatefulWidget {
  const VoicePanel({super.key});

  @override
  State<VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends State<VoicePanel> {
  @override
  void initState() {
    super.initState();
    voiceControls.changes.addListener(_onChange);
  }

  @override
  void dispose() {
    voiceControls.changes.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final v = voiceChannels;
    final c = voiceControls;
    if (v.link == VoiceChannelLink.idle || isWideLayout(context)) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GlitchColors.borderCard),
      ),
      child: Row(
        children: [
          Expanded(child: _VoiceStatus(where: VoiceWhere.channel)),
          GlitchIconButton.panel(
            tooltip: c.micOff ? context.s.tipUnmute : context.s.tipMute,
            onTap: () => c.tapMic(context),
            icon: Icon(
              c.micOff ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: c.micOff ? GlitchColors.error : GlitchColors.textPrimary,
            ),
          ),
          GlitchIconButton.panel(
            tooltip: c.deafOff ? context.s.tipUndeafen : context.s.tipDeafen,
            onTap: () => c.tapDeafen(context),
            icon: Icon(
              c.deafOff ? Icons.headset_off_rounded : Icons.headset_rounded,
              color: c.deafOff ? GlitchColors.error : GlitchColors.textPrimary,
            ),
          ),
          const _LeaveButton(),
        ],
      ),
    );
  }
}

class VoiceDock extends StatelessWidget {
  const VoiceDock({super.key});

  static const double _pad = 8;
  static const double _statusHeight = 40;
  static const double _gap = 8;
  static const double _buttonHeight = 32;

  static const double height = _pad + _statusHeight + _gap + _buttonHeight + _pad;

  @override
  Widget build(BuildContext context) {
    final c = voiceControls;
    final where = c.where;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, _pad, 8, _pad),
        child: Column(
          children: [
            SizedBox(
              height: _statusHeight,
              child: Row(
                children: [
                  Expanded(child: _VoiceStatus(where: where)),
                  _NoiseButton(on: c.noiseOn),
                  const SizedBox(width: 2),
                  const _LeaveButton(),
                ],
              ),
            ),
            const SizedBox(height: _gap),
            SizedBox(
              height: _buttonHeight,
              child: Row(
                children: [
                  Expanded(
                    child: GlitchTooltip(
                      message: c.cameraOn
                          ? context.s.tipCameraOff
                          : c.canUseCamera
                              ? context.s.tipCameraOn
                              : context.s.tipCameraUnavailable,
                      child: GlitchActionButton(
                        soft: true,
                        icon: c.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                        onTap: c.cameraOn || c.canUseCamera ? c.toggleCamera : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GlitchTooltip(
                      message: c.sharingScreen ? context.s.tipStopShare : context.s.tipShareScreen,
                      child: GlitchActionButton(
                        soft: true,
                        icon: c.sharingScreen ? GlitchIcons.screenShareStop : GlitchIcons.screenShare,
                        onTap: c.sharingScreen || c.canShareScreen ? () => c.tapScreenShare(context) : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: GlitchActionButton(soft: true, icon: Icons.rocket_launch_rounded, onTap: null)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaveButton extends StatelessWidget {
  const _LeaveButton();

  @override
  Widget build(BuildContext context) => GlitchIconButton.panel(
        tooltip: context.s.tipDisconnect,
        onTap: voiceControls.leave,
        icon: const Icon(Icons.call_end_rounded),
      );
}

class _VoiceStatus extends StatelessWidget {
  final VoiceWhere where;

  const _VoiceStatus({required this.where});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([voiceChannels, serverRail, callProvider]),
        builder: (context, _) {
          if (where != VoiceWhere.call) return _content(context);
          final p = callProvider;
          final connected = p.state == CallState.active;
          final chatId = p.chatId;
          return _layout(
            connected: connected,
            status: connected ? context.s.voiceConnected : callStatusText(context, p),
            place: p.peerName,
            onPlace: chatId == null ? null : () => unawaited(openCallChat(chatId)),
          );
        },
      );

  static String? _serverName() {
    final id = voiceChannels.serverId;
    for (final item in serverRail.servers) {
      if (item.id == id) return item.name;
    }
    return null;
  }

  Widget _content(BuildContext context) {
    final v = voiceChannels;
    final server = _serverName();
    return _layout(
      connected: v.link == VoiceChannelLink.connected,
      status: v.link == VoiceChannelLink.connected ? context.s.voiceConnected : context.s.voiceConnecting,
      place: server == null ? v.roomName : '${v.roomName} / $server',
    );
  }

  static Widget _layout({
    required bool connected,
    required String status,
    required String place,
    VoidCallback? onPlace,
  }) {
    final statusColor = connected ? GlitchColors.online : GlitchColors.textSecond;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Builder(
          builder: (statusContext) => GlitchPressable(
            onTap: connected ? () => unawaited(showVoiceConnectionMenu(statusContext)) : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.signal_cellular_alt_rounded, size: 20, color: statusColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: statusColor),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 1),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: GlitchPressable(
            onTap: onPlace,
            child: Text(
              place,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: GlitchColors.textSecond),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoiseButton extends StatefulWidget {
  final bool on;

  const _NoiseButton({required this.on});

  @override
  State<_NoiseButton> createState() => _NoiseButtonState();
}

class _NoiseButtonState extends State<_NoiseButton> {
  bool _open = false;

  Future<void> _show(BuildContext anchor) async {
    setState(() => _open = true);
    await showNoiseSuppressionMenu(anchor);
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) => Builder(
        builder: (anchor) => GlitchIconButton.panel(
          selected: _open,
          tooltip: context.s.tipNoiseSuppression,
          onTap: () => unawaited(_show(anchor)),
          icon: _NoiseSuppressionIcon(on: widget.on),
        ),
      );
}

class _NoiseSuppressionIcon extends StatelessWidget {
  final bool on;

  const _NoiseSuppressionIcon({required this.on});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size.square(GlitchIconButton.panelIconSize),
        painter: _NoiseSuppressionPainter(GlitchColors.textPrimary, crossed: !on),
      );
}

class _NoiseSuppressionPainter extends CustomPainter {
  final Color color;
  final bool crossed;

  _NoiseSuppressionPainter(this.color, {required this.crossed});

  static const List<double> _bars = [0.3, 0.6, 0.9, 0.6, 0.3];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.11;
    final line = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.saveLayer(Offset.zero & size, Paint());
    final step = s * 0.7 / (_bars.length - 1);
    for (var i = 0; i < _bars.length; i++) {
      final x = s * 0.15 + step * i;
      final h = s * _bars[i];
      canvas.drawLine(Offset(x, (s - h) / 2), Offset(x, (s + h) / 2), line);
    }
    if (crossed) {
      final a = Offset(s * 0.88, s * 0.1);
      final b = Offset(s * 0.12, s * 0.9);
      canvas.drawLine(a, b, Paint()
        ..blendMode = BlendMode.clear
        ..strokeWidth = stroke * 2.8
        ..strokeCap = StrokeCap.round);
      canvas.drawLine(a, b, line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NoiseSuppressionPainter old) => old.color != color || old.crossed != crossed;
}
