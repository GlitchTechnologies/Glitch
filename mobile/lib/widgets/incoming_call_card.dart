import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../providers/call_provider.dart';
import '../theme/app_theme.dart';
import 'call_stage.dart' show CallButton;
import 'chat_call_area.dart' show openCallChat;
import 'glitch_avatar.dart';

const double _kCardMaxWidth = 380;
const double _kCardAvatar = 44;
const double _kCardButton = 40;

class IncomingCallCard extends StatelessWidget {
  const IncomingCallCard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: callProvider,
        builder: (context, _) {
          final p = callProvider;
          final waiting = p.waitingCall;
          final _Incoming? call;
          if (waiting != null) {
            call = _Incoming(
              chatId: waiting.chatId,
              title: waiting.title,
              group: waiting.group,
              avatar: waiting.avatar,
              avatarColor: waiting.avatarColor,
              accept: p.acceptWaiting,
              decline: p.declineWaiting,
            );
          } else if (p.state == CallState.incoming && p.chatId != null) {
            call = _Incoming(
              chatId: p.chatId!,
              title: p.peerName,
              group: p.isGroup,
              avatar: p.peerAvatar,
              avatarColor: p.peerAvatarColor,
              accept: p.accept,
              decline: p.decline,
            );
          } else {
            call = null;
          }
          if (call == null) return const SizedBox.shrink();
          return _Card(call: call);
        },
      );
}

class _Incoming {
  final int chatId;
  final String title;
  final bool group;
  final String? avatar;
  final Color? avatarColor;
  final Future<void> Function() accept;
  final void Function() decline;

  const _Incoming({
    required this.chatId,
    required this.title,
    required this.group,
    required this.avatar,
    required this.avatarColor,
    required this.accept,
    required this.decline,
  });
}

class _Card extends StatelessWidget {
  final _Incoming call;

  const _Card({required this.call});

  void _accept() {
    final chatId = call.chatId;
    unawaited(call.accept());
    unawaited(openCallChat(chatId));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = math.min(_kCardMaxWidth, mq.size.width - 24);
    return Positioned(
      top: mq.padding.top + 12,
      left: (mq.size.width - width) / 2,
      width: width,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: GlitchColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GlitchColors.borderCard),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              GlitchAvatar(
                initials: GlitchAvatar.initialsFromName(call.title),
                size: _kCardAvatar,
                colorIndex: GlitchAvatar.colorFromNickname(call.title),
                imageUrl: call.avatar,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      call.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      call.group ? context.s.groupCallTitle : context.s.callIncoming,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CallButton(
                key: const ValueKey('incoming-decline'),
                size: _kCardButton,
                icon: Icons.call_end_rounded,
                background: GlitchColors.error,
                onTap: call.decline,
              ),
              const SizedBox(width: 10),
              CallButton(
                key: const ValueKey('incoming-accept'),
                size: _kCardButton,
                icon: Icons.call_rounded,
                background: GlitchColors.online,
                onTap: _accept,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
