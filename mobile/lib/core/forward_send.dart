import 'package:flutter/widgets.dart';

import '../models/bubble_data.dart';
import '../models/search.dart';
import '../services/api_service.dart';
import '../widgets/glitch_toast.dart';
import 'l10n.dart';

const int kMaxForwardTargets = 5;

Future<void> forwardTo(
  BuildContext context, {
  required List<SearchHit> targets,
  required List<BubbleData> bubbles,
  String note = '',
}) async {
  final copies = bubbles.where((b) => b.isForwardable).toList();
  final text = note.trim();
  if (targets.isEmpty || (copies.isEmpty && text.isEmpty)) return;
  final failed = <String>[];
  for (final target in targets) {
    try {
      final chatId = await _chatIdOf(target);
      for (final b in copies) {
        await _sendCopy(chatId, b);
      }
      if (text.isNotEmpty) await api.sendMessage(chatId, type: 'text', text: text);
    } catch (_) {
      failed.add(placeName(target));
    }
  }
  if (!context.mounted) return;
  if (failed.isEmpty) {
    GlitchToast.show(context, context.s.forwardDone, type: ToastType.success);
  } else {
    GlitchToast.show(context, context.s.forwardFailed(failed.join(', ')));
  }
}

String placeName(SearchHit hit) => switch (hit.kind) {
      SearchKind.person => hit.person!.displayName,
      SearchKind.group => hit.group!.name,
      SearchKind.room => '#${hit.room!.name}',
      SearchKind.server => hit.server!.name,
    };

Future<int> _chatIdOf(SearchHit hit) async => switch (hit.kind) {
      SearchKind.person => hit.chatId ?? (await api.createPersonalChat(hit.person!.nickname)).id,
      SearchKind.group => hit.group!.id,
      SearchKind.room => hit.room!.id,
      SearchKind.server => throw StateError('в сообщество не пересылают'),
    };

Future<void> _sendCopy(int chatId, BubbleData src) {
  final from = src.forwardedFrom ?? src.senderDisplayName;
  final content = src.content;
  return switch (src.type) {
    'photo' => api.sendMessage(chatId, type: 'photo', imageUrl: content, caption: src.caption, forwardedFrom: from),
    'video' => api.sendMessage(chatId, type: 'video', videoUrl: content, caption: src.caption, forwardedFrom: from),
    'album' => api.sendMessage(chatId, type: 'album', imageUrl: content, caption: src.caption, forwardedFrom: from),
    'file' => api.sendMessage(chatId, type: 'file', fileUrl: content, fileName: src.fileName, fileSize: src.fileSize, fileAudio: src.fileAudio,
        caption: src.caption, forwardedFrom: from),
    'voice' => api.sendMessage(chatId, type: 'voice', voiceUrl: content, forwardedFrom: from),
    'video_note' => api.sendMessage(chatId, type: 'video_note', videoNote: content, forwardedFrom: from),
    'geo' => api.sendMessage(chatId, type: 'geo', geo: content, caption: src.caption, forwardedFrom: from),
    _ => api.sendMessage(chatId, type: 'text', text: content ?? '', forwardedFrom: from),
  };
}
