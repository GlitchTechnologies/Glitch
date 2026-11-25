import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../providers/message_composer.dart';
import 'glitch_toast.dart';

mixin RecordHandlers<T extends StatefulWidget> on State<T> {
  MessageComposer get recordComposer;

  Future<void> onVoiceRecorded(PendingVoice pv);

  Future<void> onVideoNoteRecorded(PendingVideoNote note);

  bool get canRecord => true;

  bool _releasedBeforeStart = false;

  bool get isVideoCapture => recordComposer.captureMode == CaptureMode.video;

  void bindVideoNoteLimit() {
    recordComposer.onVideoNoteLimit = () {
      if (mounted) handleRecordEnd();
    };
  }

  Future<void> handleRecordStart() async {
    if (!canRecord) return;
    _releasedBeforeStart = false;
    final video = isVideoCapture;
    final ok = video ? await recordComposer.startVideoNote() : await recordComposer.startRecording();
    if (!ok) {
      if (mounted) {
        GlitchToast.show(
          context,
          video ? context.s.cameraPermissionDenied : context.s.micPermissionDenied,
          type: ToastType.info,
        );
      }
      return;
    }
    if (_releasedBeforeStart) handleRecordEnd();
  }

  Future<void> handleRecordEnd() async {
    if (!recordComposer.isRecording) {
      _releasedBeforeStart = true;
      return;
    }
    if (isVideoCapture) {
      final note = await recordComposer.stopVideoNote();
      if (note != null && mounted) await onVideoNoteRecorded(note);
      return;
    }
    final pv = await recordComposer.stopRecording();
    if (pv != null && mounted) await onVoiceRecorded(pv);
  }

  Future<void> handleRecordCancel() async {
    if (isVideoCapture) {
      await recordComposer.cancelVideoNote();
      return;
    }
    await recordComposer.cancelRecording();
  }
}
