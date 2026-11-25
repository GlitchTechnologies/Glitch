import '../services/api_service.dart';
import 'toggle_settings.dart';

class PrivacySettings extends ToggleSettings {
  bool showActivity = true;

  bool showPlaying = true;

  bool isPublic = true;

  bool friendReqEveryone = true;
  bool friendReqFriends = true;
  bool friendReqServers = true;

  @override
  Future<void> fetch() async {
    _apply(await api.getPrivacySettings());
  }

  void _apply(Map<String, bool> settings) {
    showActivity = settings['show_last_seen']!;
    isPublic = settings['is_public']!;
    showPlaying = settings['show_playing']!;
    friendReqEveryone = settings['friend_req_everyone']!;
    friendReqFriends = settings['friend_req_friends']!;
    friendReqServers = settings['friend_req_servers']!;
  }

  Future<String?> setFriendRequests({bool? everyone, bool? friends, bool? servers}) async {
    final before = (friendReqEveryone, friendReqFriends, friendReqServers);
    if (everyone != null) {
      friendReqEveryone = everyone;
      if (everyone) friendReqFriends = friendReqServers = true;
    }
    if (friends != null) friendReqFriends = friends;
    if (servers != null) friendReqServers = servers;
    if (!(friendReqFriends && friendReqServers)) friendReqEveryone = false;
    notifyListeners();
    try {
      final saved = await api.updatePrivacySettings(
        friendReqEveryone: everyone,
        friendReqFriends: friends,
        friendReqServers: servers,
      );
      if (isDisposed) return null;
      _apply(saved);
      notifyListeners();
      return null;
    } catch (e) {
      if (isDisposed) return null;
      friendReqEveryone = before.$1;
      friendReqFriends = before.$2;
      friendReqServers = before.$3;
      notifyListeners();
      return errorMessage(e);
    }
  }

  Future<String?> setShowActivity(bool value) => setOptimistic(
        apply: (v) => showActivity = v,
        value: value,
        send: () => api.updatePrivacySettings(showLastSeen: value),
      );

  Future<String?> setShowPlaying(bool value) => setOptimistic(
        apply: (v) => showPlaying = v,
        value: value,
        send: () => api.updatePrivacySettings(showPlaying: value),
      );

  Future<String?> setPublic(bool value) => setOptimistic(
        apply: (v) => isPublic = v,
        value: value,
        send: () => api.updatePrivacySettings(isPublic: value),
      );
}
