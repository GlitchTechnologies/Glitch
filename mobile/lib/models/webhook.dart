import '../core/record_ids.dart';

class Webhook {
  final int id;
  final int channelId;
  final String name;
  final String? avatarUrl;
  final String? creatorNickname;

  final String? url;

  const Webhook({
    required this.id,
    required this.channelId,
    required this.name,
    this.avatarUrl,
    this.creatorNickname,
    this.url,
  });

  DateTime get createdAt => createdAtOfId(id);

  factory Webhook.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>?;
    return Webhook(
      id: int.parse(j['id'] as String),
      channelId: int.parse(j['channel_id'] as String),
      name: j['name'] as String? ?? '',
      avatarUrl: j['avatar_url'] as String?,
      creatorNickname: user?['username'] as String?,
      url: j['url'] as String?,
    );
  }
}
