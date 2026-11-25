import '../core/time_json.dart';

enum PresenceStatus { online, idle, dnd, invisible, offline }

PresenceStatus presenceStatusFrom(dynamic raw, {bool online = false}) => switch (raw) {
      'online' => PresenceStatus.online,
      'idle' => PresenceStatus.idle,
      'dnd' => PresenceStatus.dnd,
      'invisible' => PresenceStatus.invisible,
      'offline' => PresenceStatus.offline,
      _ => online ? PresenceStatus.online : PresenceStatus.offline,
    };

extension PresenceStatusState on PresenceStatus {
  bool get isOnline => this == PresenceStatus.online || this == PresenceStatus.idle || this == PresenceStatus.dnd;
}

class AccountPresence {
  final PresenceStatus status;
  final DateTime? expiresAt;

  const AccountPresence({this.status = PresenceStatus.online, this.expiresAt});

  factory AccountPresence.fromJson(Map<String, dynamic> j) => AccountPresence(
        status: presenceStatusFrom(j['status'], online: true),
        expiresAt: j['expires_at'] == null ? null : parseUtcLocal(j['expires_at']),
      );
}

class PresenceSettings {
  final AccountPresence account;
  final List<int> durationsMinutes;

  const PresenceSettings({required this.account, required this.durationsMinutes});

  factory PresenceSettings.fromJson(Map<String, dynamic> j) => PresenceSettings(
        account: AccountPresence.fromJson(j),
        durationsMinutes: List<int>.unmodifiable((j['durations_minutes'] as List).cast<int>()),
      );
}
