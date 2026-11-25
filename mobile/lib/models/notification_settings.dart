import '../core/time_json.dart';

enum NotifLevel {
  all,
  mentions,
  none;

  static NotifLevel parse(dynamic raw) => switch (raw) {
        'mentions' => NotifLevel.mentions,
        'none' => NotifLevel.none,
        _ => NotifLevel.all,
      };
}

/// Допустимые сроки заглушения в минутах.
const List<int> kMuteMinutes = [15, 60, 180, 480, 1440];

/// Сервер учитывает настройку сообщества и срок заглушения на момент ответа.
class ServerNotifSettings {
  final NotifLevel level;

  final bool suppressEveryone;

  final bool suppressRoles;

  /// Заглушено (на момент ответа сервера).
  final bool muted;

  final DateTime? mutedUntil;

  const ServerNotifSettings({
    this.level = NotifLevel.all,
    this.suppressEveryone = false,
    this.suppressRoles = false,
    this.muted = false,
    this.mutedUntil,
  });

  factory ServerNotifSettings.fromJson(Map<String, dynamic> j) => ServerNotifSettings(
        level: NotifLevel.parse(j['level']),
        suppressEveryone: j['suppress_everyone'] == true,
        suppressRoles: j['suppress_roles'] == true,
        muted: j['muted'] == true,
        mutedUntil: j['muted_until'] == null ? null : parseUtcLocal(j['muted_until']),
      );

  bool mutedAt(DateTime now) => muted && (mutedUntil == null || mutedUntil!.isAfter(now));
}
