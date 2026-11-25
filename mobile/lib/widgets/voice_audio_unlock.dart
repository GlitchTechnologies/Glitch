import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/voice_connection.dart';
import '../theme/app_theme.dart';

/// ЗАЧЕМ. После перезагрузки вкладки приложение само возвращается в звонок
/// или голосовой канал (services/voice_resume.dart), без нажатия человека. А
/// браузер не даёт странице играть звук, пока по ней ни разу не кликнули:
/// в разговоре мы есть, а собеседников не слышно. Любое нажатие В ЛЮБОМ МЕСТЕ
/// окна снимает запрет — подсказка только говорит об этом, а включает звук
/// общий слушатель нажатий вокруг всего приложения.
class VoiceAudioUnlock extends StatelessWidget {
  final Widget child;

  const VoiceAudioUnlock({super.key, required this.child});

  void _onPointerUp(PointerUpEvent _) {
    if (voiceConnection.audioBlocked) unawaited(voiceConnection.unlockAudio());
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: _onPointerUp,
      child: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 16,
            right: 16,
            child: ListenableBuilder(
              listenable: voiceConnection,
              builder: (context, _) => voiceConnection.audioBlocked
                  ? Center(child: _Hint())
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: GlitchColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: GlitchColors.border),
      ),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.volume_off_rounded, size: 20, color: GlitchColors.textPrimary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                context.s.voiceAudioBlocked,
                style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
