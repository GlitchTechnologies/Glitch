import 'dart:convert';

import 'embed.dart';

class WebhookMessageDraft {
  final String content;
  final String username;
  final String avatarUrl;
  final List<Embed> embeds;

  const WebhookMessageDraft({
    this.content = '',
    this.username = '',
    this.avatarUrl = '',
    this.embeds = const [],
  });

  Map<String, dynamic> toPayload() => {
        if (content.trim().isNotEmpty) 'content': content,
        if (username.trim().isNotEmpty) 'username': username.trim(),
        if (avatarUrl.trim().isNotEmpty) 'avatar_url': avatarUrl.trim(),
        if (embeds.isNotEmpty) 'embeds': [for (final e in embeds) e.toJson()],
      };

  String encode() {
    final payload = toPayload();
    return payload.isEmpty ? '' : jsonEncode(payload);
  }

  factory WebhookMessageDraft.decode(String raw) {
    if (raw.isEmpty) return const WebhookMessageDraft();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return WebhookMessageDraft(
        content: j['content'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String? ?? '',
        embeds: Embed.listFrom(j['embeds']),
      );
    } catch (_) {
      return const WebhookMessageDraft();
    }
  }
}
