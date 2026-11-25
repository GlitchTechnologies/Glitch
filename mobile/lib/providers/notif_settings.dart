import '../services/api_service.dart';
import 'toggle_settings.dart';

class NotifSettings extends ToggleSettings {
  bool enabled = true;
  bool personal = true;
  bool groups = true;
  bool servers = true;

  @override
  Future<void> fetch() async {
    final settings = await api.getNotifSettings();
    enabled = settings['notif_enabled']!;
    personal = settings['notif_personal']!;
    groups = settings['notif_groups']!;
    servers = settings['notif_servers']!;
  }

  Future<String?> setEnabled(bool value) => setOptimistic(
        apply: (v) => enabled = v,
        value: value,
        send: () => api.updateNotifSettings(notifEnabled: value),
      );

  Future<String?> setPersonal(bool value) => setOptimistic(
        apply: (v) => personal = v,
        value: value,
        send: () => api.updateNotifSettings(notifPersonal: value),
      );

  Future<String?> setGroups(bool value) => setOptimistic(
        apply: (v) => groups = v,
        value: value,
        send: () => api.updateNotifSettings(notifGroups: value),
      );

  Future<String?> setServers(bool value) => setOptimistic(
        apply: (v) => servers = v,
        value: value,
        send: () => api.updateNotifSettings(notifServers: value),
      );
}
