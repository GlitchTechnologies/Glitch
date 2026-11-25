import 'dart:async';

import 'package:flutter/material.dart';

import '../core/shell_metrics.dart';
import '../core/adaptive_open.dart';
import '../core/l10n.dart';
import '../core/shell_controller.dart' show ShellPlace, ShellSlot, shellController;
import '../models/invite.dart';
import '../models/server.dart';
import '../models/voice_pass.dart';
import '../providers/server_provider.dart';
import '../providers/voice_channels.dart';
import '../theme/app_theme.dart';
import 'call_stage.dart';
import 'glitch_avatar.dart';
import 'glitch_bar_buttons.dart' show GlitchFilledButton;
import 'glitch_pressable.dart';
import 'glitch_toast.dart';
import 'invite_sheet.dart';
import 'voice_controls.dart';
import 'voice_member_menu.dart';
import 'glitch_icon_button.dart';

const int _kLobbyAvatars = 6;
const double _kLobbyAvatarSize = 44;

Future<void> openVoiceRoom(BuildContext context, Room room) => openAdaptive(
      context,
      builder: (_) => VoiceRoomView(room: room),
      slotKey: voiceRoomSlotKey(room.id),
      scope: ServerScope(room.serverId),
    );

class VoiceRoomView extends StatefulWidget {
  final Room room;

  const VoiceRoomView({super.key, required this.room});

  @override
  State<VoiceRoomView> createState() => _VoiceRoomViewState();
}

class _VoiceRoomViewState extends State<VoiceRoomView> {
  late String _name = widget.room.name;
  StreamSubscription<ServerRoomEvent>? _roomSub;
  StreamSubscription<ServerGone>? _goneSub;
  bool _closing = false;

  Room get _room => widget.room;

  @override
  void initState() {
    super.initState();
    _roomSub = serverRail.roomEvents.listen((e) {
      if (e.chatId != _room.id || !mounted) return;
      if (e.deleted) {
        _close(toast: context.s.roomDeleted);
      } else if (e.name != null) {
        setState(() => _name = e.name!);
      }
    });
    _goneSub = serverRail.serverGone.listen((gone) {
      if (gone.id == _room.serverId) _close();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ShellPlace.slotOf(context) != ShellSlot.main) return;
      if (shellController.hasDetails) shellController.close(ShellSlot.details);
    });
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _goneSub?.cancel();
    super.dispose();
  }

  void _close({String? toast}) {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (toast != null) GlitchToast.show(context, toast, type: ToastType.info);
      closeAdaptive(context);
    });
  }

  bool get _inside =>
      voiceControls.where == VoiceWhere.channel &&
      voiceChannels.serverId == _room.serverId &&
      voiceChannels.roomId == _room.id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCallBackground,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: voiceControls.changes,
          builder: (context, _) {
            final people = voiceChannels.inRoom(_room.serverId, _room.id);
            if (_inside) return _stage(context, people);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                Expanded(child: _lobby(context, people)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final inShell = ShellPlace.slotForBuild(context) == ShellSlot.main;
    return SizedBox(
      height: kShellBarHeight,
      child: Padding(
        padding: EdgeInsets.only(left: inShell ? 16 : 4, right: 16),
        child: Align(alignment: Alignment.centerLeft, child: _title(context)),
      ),
    );
  }

  Widget _title(BuildContext context) {
    final inShell = ShellPlace.slotForBuild(context) == ShellSlot.main;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!inShell) ...[
          GlitchIconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue, size: 22),
            onTap: () => closeAdaptive(context),
            size: 32,
            extent: 32,
          ),
          const SizedBox(width: 4),
        ],
        Icon(Icons.volume_up_rounded, size: 22, color: callInk.textSecond),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: callInk.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _stage(BuildContext context, List<VoiceStateInfo> people) {
    return CallStage(
      mode: CallStageMode.inCall,
      title: _title(context),
      place: VoiceWhere.channel,
      isGroup: true,
      roster: [
        for (final v in people)
          CallMember(
            userId: v.userId,
            state: CallMemberState.connected,
            displayName: v.displayName,
            nickname: v.nickname,
            avatar: v.avatar,
            avatarColor: v.avatarColor,
          ),
      ],
      deafened: {
        for (final v in people)
          if (v.selfDeaf || v.serverDeaf) v.userId,
      },
      onMemberMenu: (userId, position) {
        final member = people.where((v) => v.userId == userId).firstOrNull;
        if (member == null) return;
        openVoiceMemberMenu(context, room: _room, member: member, position: position);
      },
      extraTile: _InviteTile(onInvite: _invite),
    );
  }

  void _invite() {
    final server = serverRail.servers.where((s) => s.id == _room.serverId).firstOrNull;
    showInviteSheet(context, InviteTarget.server(_room.serverId, server?.name ?? ''));
  }

  Widget _lobby(BuildContext context, List<VoiceStateInfo> people) {
    final shown = people.take(_kLobbyAvatars).toList();
    final more = people.length - shown.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, 1.4),
          radius: 1.3,
          colors: [GlitchColors.accentBlue.withOpacity(0.35), kCallBackground],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: callInk.textPrimary),
              ),
              const SizedBox(height: 12),
              if (people.isEmpty)
                Text(
                  context.s.voiceRoomEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: callInk.textSecond),
                )
              else
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final v in shown)
                      GlitchAvatar(
                        key: ValueKey('lobby-${v.userId}'),
                        initials: GlitchAvatar.initialsFromName(v.displayName ?? v.nickname ?? ''),
                        size: _kLobbyAvatarSize,
                        colorIndex: GlitchAvatar.colorFromNickname(v.nickname ?? v.displayName ?? ''),
                        imageUrl: v.avatar,
                      ),
                    if (more > 0)
                      Text(
                        '+$more',
                        key: const ValueKey('lobby-more'),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: callInk.textSecond),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              GlitchFilledButton(
                label: context.s.voiceRoomJoin,
                onTap: () => unawaited(voiceChannels.join(_room)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


const double _kInviteArtMinHeight = 150;

class _InviteTile extends StatelessWidget {
  final VoidCallback onInvite;

  const _InviteTile({required this.onInvite});

  @override
  Widget build(BuildContext context) {
    final accent = GlitchColors.accentBlue;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(accent.withOpacity(0.28), kCallBackground),
            kCallBackground,
          ],
          stops: const [0, 0.75],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            Expanded(
              child: box.maxHeight < _kInviteArtMinHeight
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: CustomPaint(painter: _InviteArtPainter(accent: accent), size: Size.infinite),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: _InviteButton(onTap: onInvite),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteButton extends StatelessWidget {
  final VoidCallback onTap;

  const _InviteButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlitchPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: callInk.bgChip,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: callInk.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_alt_1_rounded, size: 18, color: callInk.textPrimary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                context.s.voiceRoomInvite,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: callInk.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteArtPainter extends CustomPainter {
  final Color accent;

  const _InviteArtPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.height / 2.6).clamp(0.0, size.width / 6.2);
    if (r < 8) return;
    final c = Offset(size.width / 2, size.height / 2);

    final side = r * 0.72;
    final dx = r * 1.55;
    _person(canvas, c + Offset(-dx, r * 0.28), side, ring: callInk.bgMenu, fill: callInk.bgChip, ink: 0.55);
    _person(canvas, c + Offset(dx, r * 0.28), side, ring: callInk.bgMenu, fill: callInk.bgChip, ink: 0.55);
    _person(canvas, c, r, ring: accent, fill: Color.alphaBlend(accent.withOpacity(0.35), callInk.bgChip), ink: 0.95);

    final badge = c + Offset(r * 0.74, r * 0.74);
    final br = r * 0.34;
    canvas.drawCircle(badge, br + r * 0.07, Paint()..color = kCallBackground);
    canvas.drawCircle(badge, br, Paint()..color = accent);
    final plus = Paint()
      ..color = Colors.white
      ..strokeWidth = br * 0.32
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(badge - Offset(br * 0.48, 0), badge + Offset(br * 0.48, 0), plus);
    canvas.drawLine(badge - Offset(0, br * 0.48), badge + Offset(0, br * 0.48), plus);

    _sparkle(canvas, c + Offset(-r * 1.2, -r * 0.95), r * 0.2, Colors.white.withOpacity(0.85));
    _sparkle(canvas, c + Offset(r * 1.35, -r * 0.8), r * 0.16, accent);
    _sparkle(canvas, c + Offset(r * 2.35, -r * 0.2), r * 0.11, Colors.white.withOpacity(0.6));
    _sparkle(canvas, c + Offset(-r * 2.3, -r * 0.15), r * 0.12, accent.withOpacity(0.8));
  }

  void _person(Canvas canvas, Offset center, double radius,
      {required Color ring, required Color fill, required double ink}) {
    canvas.drawCircle(center, radius, Paint()..color = fill);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));
    final body = Paint()..color = Colors.white.withOpacity(ink);
    canvas.drawCircle(center + Offset(0, -radius * 0.22), radius * 0.34, body);
    canvas.drawOval(
      Rect.fromCenter(center: center + Offset(0, radius * 0.78), width: radius * 1.35, height: radius * 1.1),
      body,
    );
    canvas.restore();
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.09,
    );
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final w = r * 0.28;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_InviteArtPainter old) => old.accent != accent;
}
