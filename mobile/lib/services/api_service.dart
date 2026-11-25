import '../models/file_audio.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
// XFile вместо File: это «файл» в том виде, который понимают ОБЕ платформы.
// На телефоне за ним стоит файл на диске, в браузере — содержимое в памяти,
// но и там и там есть имя, размер и чтение потоком, а больше отсюда ничего и
// не нужно. Именно этот тип уже отдают выбор фото, выбор документа и камера —
// раньше код превращал его в File и тем самым выбрасывал совместимость с вебом.
import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../models/user.dart';
import '../models/presence.dart';
import '../models/collectible.dart';
import '../models/shop.dart';
import '../models/voice_pass.dart';
import '../models/chat.dart';
import '../models/folder.dart';
import '../models/invite.dart';
import '../models/list_page.dart';
import '../models/mention.dart' show MentionCandidates;
import '../models/notification_settings.dart';
import '../models/server.dart';
import '../models/sticker.dart';
import '../models/webhook.dart';
import '../models/search.dart';
import '../models/message.dart';
import '../models/poll.dart';
import '../models/profile.dart';
import '../models/relationship.dart';
import '../models/gif.dart';
import '../models/glitchplus.dart';
import '../core/platform_info.dart';
import '../core/net_error_web.dart' if (dart.library.io) '../core/net_error_native.dart';
import 'auth_service.dart';
import 'desktop_shell.dart' show DesktopWatchedGame;
import 'error_reporter.dart';
import 'upload_limits.dart';
import '../core/avatar_sizes.dart';
import '../core/collectibles.dart';
import '../models/achievement.dart';
import '../core/l10n.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  final Map<String, String> fieldErrors;

  ApiException(this.message, {this.statusCode, this.fieldErrors = const {}});
  @override
  String toString() => message;
}

abstract class LocalizedError implements Exception {
  String describe(S s);
}

String errorMessage(Object e) {
  if (e is ApiException) return e.message;
  if (e is LocalizedError) return e.describe(appStrings);

  errorReporter.report(e);

  final text = e.toString();
  if (text.startsWith('Exception: ')) return text.substring(11);
  return text;
}

class ApiService {
  static const _base = 'https://glitchapp.online';
  static const baseUrl = _base;

  static const publicApiBase = 'https://api.glitchapp.online/v10';

  String? _token;
  final userPreviewCache = <String, User>{};

  final invitePreviewCache = <String, InvitePreview?>{};

  void setToken(String token) { _token = token; errorReporter.token = token; _clearPreviews(); }
  void clearToken() { _token = null; errorReporter.token = null; _clearPreviews(); }

  void _clearPreviews() {
    userPreviewCache.clear();
    invitePreviewCache.clear();
  }

  String? viewAs;
  static const viewAsHeader = 'X-Glitch-View-As';

  static String get _language => appStrings.localeName;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept-Language': _language,
    if (_token != null) 'Authorization': 'Bearer $_token',
    if (viewAs != null) viewAsHeader: viewAs!,
  };

  void _authorize(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    request.headers['Accept-Language'] = _language;
    final view = viewAs;
    if (view != null) request.headers[viewAsHeader] = view;
  }

  Map<String, String> get imageHeaders => {
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Map<String, String> headersFor(String url) {
    if (url.contains('s3.regru.cloud')) return const {};
    return imageHeaders;
  }

  static const _timeout = Duration(seconds: 15);

  static ApiException _errorFrom(int status, dynamic data) {
    final s = appStrings;
    final detail = data is Map ? data['detail'] : null;
    final message = data is Map ? data['message'] : null;
    String? msg;
    if (detail is String && detail.isNotEmpty) {
      msg = detail;
    } else if (detail == null && message is String && message.isNotEmpty) {
      msg = message;
    } else if (detail is List) {
      final parts = <String>{
        for (final e in detail)
          if (e is Map && e['msg'] is String && (e['msg'] as String).isNotEmpty) e['msg'] as String,
      };
      msg = parts.isEmpty ? s.errorValidation : parts.join(', ');
    } else if (status == 429) {
      msg = s.errorRateLimited;
    }
    msg ??= data == null ? s.errorServerStatus(status) : s.errorServer;
    return ApiException(msg, statusCode: status, fieldErrors: _fieldErrorsOf(data is Map ? data['errors'] : null));
  }

  static Map<String, String> _fieldErrorsOf(dynamic tree) {
    final out = <String, String>{};
    void walk(dynamic node, List<String> path) {
      if (node is! Map) return;
      node.forEach((key, value) {
        if (key == '_errors') {
          final first = value is List && value.isNotEmpty ? value.first : null;
          final text = first is Map ? first['message'] : null;
          if (text is String) out[path.join('.')] = text;
        } else {
          walk(value, [...path, '$key']);
        }
      });
    }
    walk(tree, const []);
    return out;
  }

  static ApiException _uploadFailure(Object e) {
    if (e is ApiException) return e;
    if (e is TimeoutException) return ApiException(appStrings.errorTimeout);
    if (isNetworkError(e)) return ApiException(appStrings.errorNoConnection);
    return ApiException(appStrings.errorUploadDetail('$e'));
  }

  static const _maxRateLimitWait = Duration(seconds: 5);
  static const _maxRateLimitRetries = 3;

  static Duration? _retryAfter(http.Response res) {
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final exact = data is Map ? data['retry_after'] : null;
      if (exact is num && exact >= 0) {
        return Duration(milliseconds: (exact * 1000).ceil() + 50);
      }
    } catch (_) {}
    final header = int.tryParse(res.headers['retry-after'] ?? '');
    return header != null && header >= 0 ? Duration(seconds: header) : null;
  }

  Future<dynamic> _request(String method, String path, {Map<String, dynamic>? body, String base = _base}) async {
    final uri = Uri.parse('$base$path');
    late http.Response res;

    for (var attempt = 0;; attempt++) {
      try {
        if (method == 'GET') res = await http.get(uri, headers: _headers).timeout(_timeout);
        else if (method == 'POST') res = await http.post(uri, headers: _headers, body: jsonEncode(body)).timeout(_timeout);
        else if (method == 'PUT') res = await http.put(uri, headers: _headers, body: jsonEncode(body)).timeout(_timeout);
        else if (method == 'PATCH') res = await http.patch(uri, headers: _headers, body: body != null ? jsonEncode(body) : null).timeout(_timeout);
        else if (method == 'DELETE') res = await http.delete(uri, headers: _headers).timeout(_timeout);
        else throw ApiException('Unknown method');
      } on TimeoutException {
        throw ApiException(appStrings.errorServerTimeout);
      } catch (e) {
        if (isNetworkError(e)) throw ApiException(appStrings.errorNoConnection);
        rethrow;
      }
      if (res.statusCode != 429 || attempt >= _maxRateLimitRetries) break;
      final wait = _retryAfter(res);
      if (wait == null || wait > _maxRateLimitWait) break;
      await Future<void>.delayed(wait);
    }

    if (res.statusCode == 204 || res.bodyBytes.isEmpty) return null;
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      if (res.statusCode >= 400) throw _errorFrom(res.statusCode, null);
      throw ApiException(appStrings.errorBadResponse, statusCode: res.statusCode);
    }
    if (res.statusCode >= 400) {
      // 401 на любом эндпоинте, КРОМЕ самой авторизации, означает "сессия
      // недействительна/отозвана" — разлогиниваем сразу, а не только на разовой
      // фоновой проверке при запуске. На /auth/login и /auth/register 401 значит
      // совсем другое (неверный пароль), это не про отозванную сессию.
      if (res.statusCode == 401 && !path.startsWith('/auth/')) {
        await authService.forceLogout();
      }

      throw _errorFrom(res.statusCode, data);
    }
    return data;
  }

  // ======== АВТОРИЗАЦИЯ ========

  Future<Map<String, dynamic>> requestEmailCode({
    required String nickname,
    required String email,
  }) async {
    return await _request('POST', '/auth/email/request', body: {
      'nickname': nickname,
      'email': email,
    });
  }

  Future<Map<String, dynamic>> requestEmailChangeCode({
    required String email,
    required String password,
  }) async {
    return await _request('POST', '/users/me/email/request', body: {
      'email': email,
      'password': password,
    });
  }

  Future<String> confirmEmailCode({
    required String verificationId,
    required String code,
  }) async {
    final data = await _request('POST', '/auth/email/confirm', body: {
      'verification_id': verificationId,
      'code': code,
    });
    return data['email_token'] as String;
  }

  Future<Map<String, dynamic>> register({
    required String nickname,
    required String displayName,
    required String password,
    required String email,
    required String emailToken,
  }) async {
    final deviceId = await authService.getOrCreateDeviceId();
    final deviceName = await authService.getDeviceName();
    return await _request('POST', '/auth/register', body: {
      'nickname': nickname,
      'display_name': displayName,
      'password': password,
      'email': email,
      'email_token': emailToken,
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': currentPlatform,
    });
  }

  Future<Map<String, dynamic>> login({
    required String nickname,
    required String password,
  }) async {
    final deviceId = await authService.getOrCreateDeviceId();
    final deviceName = await authService.getDeviceName();
    return await _request('POST', '/auth/login', body: {
      'nickname': nickname,
      'password': password,
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': currentPlatform,
    });
  }

  Future<void> logout() async {
    await _request('POST', '/auth/logout');
  }

  Future<String> wsTicket() async {
    final data = await _request('POST', '/ws/ticket');
    return data['ticket'] as String;
  }

  /// Нужен для отложенного выхода: человек вышел без сети, токен из приложения
  /// уже стёрт (а то и заменён токеном другого аккаунта), но погасить ту сессию
  /// на сервере всё равно надо — иначе на этот телефон продолжают приходить
  /// уведомления с текстом чужих сообщений. Поэтому мимо `_request`: там
  /// заголовок берётся из `_token`.
  Future<bool> revokeSessionByToken(String token) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/auth/logout'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      ).timeout(_timeout);
      const done = {200, 204, 401, 403};
      return done.contains(res.statusCode);
    } catch (_) {
      return false;
    }
  }

  Future<List<UserSession>> getSessions() async {
    final data = await _request('GET', '/users/me/sessions');
    return (data as List).map((j) => UserSession.fromJson(j)).toList();
  }

  Future<void> revokeSession(int sessionId) async {
    await _request('DELETE', '/users/me/sessions/$sessionId');
  }

  Future<void> revokeOtherSessions() async {
    await _request('DELETE', '/users/me/sessions');
  }


  Future<Map<String, dynamic>> qrStart({required String deviceId, required String deviceName}) async {
    return await _request('POST', '/auth/qr/start', body: {
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': currentPlatform,
    });
  }

  Future<Map<String, dynamic>> qrPoll(String code, String deviceId) async {
    return await _request('GET', '/auth/qr/poll/$code?device_id=${Uri.encodeComponent(deviceId)}');
  }

  Future<void> qrApprove(String code) async {
    await _request('POST', '/auth/qr/approve/$code');
  }

  // Код на шаге восстановления пароля. Отдельный от requestEmailCode
  // эндпоинт: там проверяется, что никнейм/почта СВОБОДНЫ (регистрация), здесь —
  // что никнейм+почта уже ПРИНАДЛЕЖАТ одному аккаунту (иначе восстанавливать
  // нечего). Шаг подтверждения кода — общий, confirmEmailCode.
  Future<Map<String, dynamic>> requestRestoreCode({
    required String nickname,
    required String email,
  }) async {
    return await _request('POST', '/auth/restore/email/request', body: {
      'nickname': nickname,
      'email': email,
    });
  }

  Future<void> restorePassword({
    required String nickname,
    required String email,
    required String newPassword,
    required String emailToken,
  }) async {
    await _request('POST', '/auth/restore', body: {
      'nickname': nickname,
      'email': email,
      'new_password': newPassword,
      'email_token': emailToken,
    });
  }

  // Смена пароля залогиненным пользователем (экран «Безопасность»). В отличие от
  // restorePassword выше подтверждение звонком не нужно — вторым фактором служит
  // знание текущего пароля. Сессии при этом не отзываются: устройство остаётся
  // залогиненным, повторный вход не требуется.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _request('POST', '/auth/change-password', body: {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }

  // ======== ДВУХФАКТОРНАЯ АВТОРИЗАЦИЯ (TOTP) ========

  Future<Map<String, dynamic>> getTotpStatus() async {
    return await _request('GET', '/users/me/totp') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> totpSetup({required String password}) async {
    return await _request('POST', '/users/me/totp/setup', body: {
      'password': password,
    }) as Map<String, dynamic>;
  }

  Future<List<String>> totpConfirm({required String code}) async {
    final data = await _request('POST', '/users/me/totp/confirm', body: {'code': code});
    return ((data as Map<String, dynamic>)['backup_codes'] as List).cast<String>();
  }

  Future<void> totpDisable({required String password, required String code}) async {
    await _request('POST', '/users/me/totp/disable', body: {
      'password': password,
      'code': code,
    });
  }

  Future<List<String>> totpRegenerateBackupCodes({
    required String password,
    required String code,
  }) async {
    final data = await _request('POST', '/users/me/totp/backup-codes', body: {
      'password': password,
      'code': code,
    });
    return ((data as Map<String, dynamic>)['backup_codes'] as List).cast<String>();
  }

  Future<Map<String, dynamic>> loginTotp({
    required String loginTicket,
    required String code,
  }) async {
    return await _request('POST', '/auth/login/totp', body: {
      'login_ticket': loginTicket,
      'code': code,
    }) as Map<String, dynamic>;
  }


  Future<User> getMe() async {
    final data = await _request('GET', '/users/me');
    return User.fromJson(data);
  }

  Future<List<Achievement>> getProfileAchievements(int userId) async {
    final data = await _request('GET', '/users/$userId/achievements');
    return (data as List).map((item) => Achievement.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<List<Achievement>> getMyAchievements() async {
    final data = await _request('GET', '/users/me/achievements');
    return (data['items'] as List).map((item) => Achievement.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<User> updateMe({
    String? displayName,
    String? email,
    String? emailToken,
    String? password,
    String? bio,
  }) async {
    final data = await _request('PUT', '/users/me', body: {
      if (displayName != null) 'display_name': displayName,
      if (email != null) 'email': email,
      if (emailToken != null) 'email_token': emailToken,
      if (password != null) 'password': password,
      if (bio != null) 'bio': bio,
    });
    return User.fromJson(data);
  }

  Future<void> updateFcmToken(String token) async {
    await _request('PUT', '/users/me/fcm-token', body: {'fcm_token': token});
  }

  Future<Map<String, bool>> getNotifSettings() async {
    final data = await _request('GET', '/users/me/notifications') as Map<String, dynamic>;
    return _notifSettingsFrom(data);
  }

  Future<Map<String, bool>> updateNotifSettings({
    bool? notifEnabled,
    bool? notifPersonal,
    bool? notifGroups,
    bool? notifServers,
  }) async {
    final data = await _request('PATCH', '/users/me/notifications', body: {
      if (notifEnabled != null) 'notif_enabled': notifEnabled,
      if (notifPersonal != null) 'notif_personal': notifPersonal,
      if (notifGroups != null) 'notif_groups': notifGroups,
      if (notifServers != null) 'notif_servers': notifServers,
    }) as Map<String, dynamic>;
    return _notifSettingsFrom(data);
  }

  static Map<String, bool> _notifSettingsFrom(Map<String, dynamic> data) => {
        'notif_enabled': data['notif_enabled'] as bool? ?? true,
        'notif_personal': data['notif_personal'] as bool? ?? true,
        'notif_groups': data['notif_groups'] as bool? ?? true,
        'notif_servers': data['notif_servers'] as bool? ?? true,
      };

  Future<PresenceSettings> getMyPresence() async =>
      PresenceSettings.fromJson(await _request('GET', '/users/me/presence'));

  Future<AccountPresence> updateMyPresence(PresenceStatus status, int? minutes) async =>
      AccountPresence.fromJson(await _request('PATCH', '/users/me/presence', body: {
        'status': status.name,
        'duration_minutes': minutes,
      }));

  Future<Map<String, bool>> getPrivacySettings() async {
    final data = await _request('GET', '/users/me/privacy') as Map<String, dynamic>;
    return _privacyFrom(data);
  }

  Future<Map<String, bool>> updatePrivacySettings({
    bool? showLastSeen,
    bool? isPublic,
    bool? showPlaying,
    bool? friendReqEveryone,
    bool? friendReqFriends,
    bool? friendReqServers,
  }) async {
    final data = await _request('PATCH', '/users/me/privacy', body: {
      if (showLastSeen != null) 'show_last_seen': showLastSeen,
      if (isPublic != null) 'is_public': isPublic,
      if (showPlaying != null) 'show_playing': showPlaying,
      if (friendReqEveryone != null) 'friend_req_everyone': friendReqEveryone,
      if (friendReqFriends != null) 'friend_req_friends': friendReqFriends,
      if (friendReqServers != null) 'friend_req_servers': friendReqServers,
    }) as Map<String, dynamic>;
    return _privacyFrom(data);
  }

  static Map<String, bool> _privacyFrom(Map<String, dynamic> data) => {
        for (final key in const [
          'show_last_seen', 'is_public', 'show_playing',
          'friend_req_everyone', 'friend_req_friends', 'friend_req_servers',
        ])
          key: data[key] as bool? ?? true,
      };

  Future<User> getUser(String nickname) async {
    final data = await _request('GET', '/users/$nickname');
    return User.fromJson(data);
  }


  Future<List<ChatListItem>> getChats() async {
    final data = await _request('GET', '/chats') as List;
    return data.map((e) => ChatListItem.fromJson(e)).toList();
  }

  Future<({int count, ChatListItem? latest})> getUnreadSummary() async {
    final data = await _request('GET', '/chats/unread') as Map<String, dynamic>;
    final latest = data['latest'];
    return (
      count: ((data['messages'] ?? data['chats']) as num?)?.toInt() ?? 0,
      latest: latest is Map<String, dynamic> ? ChatListItem.fromJson(latest) : null,
    );
  }

  Future<Chat?> findPersonalChat(String targetNickname) async {
    try {
      final data = await _request('GET', '/chats/personal/$targetNickname');
      return Chat.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Chat> createPersonalChat(String targetNickname) async {
    final data = await _request('POST', '/chats', body: {
      'type': 'personal',
      'target_nickname': targetNickname,
    });
    return Chat.fromJson(data);
  }

  Future<Chat> createGroupChat(String name) async {
    final data = await _request('POST', '/chats', body: {
      'type': 'group',
      'name': name,
    });
    return Chat.fromJson(data);
  }

  Future<Chat> getChat(int chatId) async {
    final data = await _request('GET', '/chats/$chatId');
    return Chat.fromJson(data);
  }

  Future<Chat> addMember(int chatId, String nickname) async {
    final data = await _request('POST', '/chats/$chatId/members', body: {'nickname': nickname});
    return Chat.fromJson(data);
  }

  Future<void> removeMember(int chatId, int userId) async {
    await _request('DELETE', '/chats/$chatId/members/$userId');
  }

  Future<Chat> updateChat(int chatId, {String? name, String? description}) async {
    final data = await _request('PUT', '/chats/$chatId', body: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
    });
    return Chat.fromJson(data);
  }

  Future<Chat> setMemberRole(int chatId, int userId, String role) async {
    final data = await _request('PUT', '/chats/$chatId/members/$userId/role', body: {'role': role});
    return Chat.fromJson(data);
  }

  Future<void> deleteChat(int chatId) async {
    await _request('DELETE', '/chats/$chatId');
  }

  Future<void> hideChat(int chatId, {bool forEveryone = false}) async {
    await _request('POST', '/chats/$chatId/hide', body: {'for_everyone': forEveryone});
  }


  Future<CallPass> startCall(int chatId, Map<String, bool> flags, {bool isVideo = false}) async {
    final data = await _request('POST', '/chats/$chatId/calls', body: {...flags, 'is_video': isVideo});
    return CallPass.fromJson(data as Map<String, dynamic>);
  }

  Future<CallPass> joinCall(int chatId, int callId, Map<String, bool> flags) async {
    final data = await _request('POST', '/chats/$chatId/calls/$callId/join', body: flags);
    return CallPass.fromJson(data as Map<String, dynamic>);
  }

  Future<void> leaveCall(int chatId, int callId) =>
      _request('POST', '/chats/$chatId/calls/$callId/leave');

  Future<void> declineCall(int chatId, int callId) =>
      _request('POST', '/chats/$chatId/calls/$callId/decline');

  Future<CurrentCall?> getCurrentCall(int chatId) async {
    final data = await _request('GET', '/chats/$chatId/calls/current');
    return data is Map<String, dynamic> ? CurrentCall.fromJson(data) : null;
  }

  Future<void> setMemberVoice(int serverId, int userId, {bool? mute, bool? deafen}) =>
      _request('PATCH', '/servers/$serverId/members/$userId/voice', body: {
        if (mute != null) 'mute': mute,
        if (deafen != null) 'deafen': deafen,
      });

  Future<void> disconnectMemberVoice(int serverId, int userId) =>
      _request('DELETE', '/servers/$serverId/members/$userId/voice');

  Future<void> moveMemberVoice(int serverId, int userId, int toRoomId) =>
      _request('POST', '/servers/$serverId/members/$userId/voice/move', body: {'chat_id': toRoomId});

  Future<VoicePass> joinVoiceChannel(int serverId, int roomId, Map<String, bool> flags) async {
    final data = await _request('POST', '/servers/$serverId/rooms/$roomId/voice', body: flags);
    return VoicePass.fromJson(data as Map<String, dynamic>);
  }


  Future<List<ServerListItem>> getServers() async {
    final data = await _request('GET', '/servers') as List;
    return data.map((e) => ServerListItem.fromJson(e)).toList();
  }

  Future<MentionCandidates> getMentionCandidates(int chatId, String query) async {
    final data = await _request(
        'GET', '/chats/$chatId/mention-candidates?q=${Uri.encodeQueryComponent(query)}');
    return MentionCandidates.fromJson(data as Map<String, dynamic>);
  }

  Future<({Map<int, int> rooms, int total})> getMentionCounts(int serverId) async {
    final data = await _request('GET', '/servers/$serverId/mentions') as Map<String, dynamic>;
    return (
      rooms: {
        for (final e in ((data['rooms'] as Map?) ?? const {}).entries)
          if (int.tryParse('${e.key}') != null && e.value is int) int.parse('${e.key}'): e.value as int,
      },
      total: data['total'] as int? ?? 0,
    );
  }

  Future<ServerNotifSettings> getServerNotifications(int serverId) async {
    final data = await _request('GET', '/servers/$serverId/notifications') as Map<String, dynamic>;
    return ServerNotifSettings.fromJson(data);
  }

  Future<ServerNotifSettings> updateServerNotifications(
    int serverId, {
    NotifLevel? level,
    bool? suppressEveryone,
    bool? suppressRoles,
    bool? muted,
    int? muteMinutes,
  }) async {
    final data = await _request('PATCH', '/servers/$serverId/notifications', body: {
      if (level != null) 'level': level.name,
      if (suppressEveryone != null) 'suppress_everyone': suppressEveryone,
      if (suppressRoles != null) 'suppress_roles': suppressRoles,
      if (muted != null) 'muted': muted,
      if (muteMinutes != null) 'mute_minutes': muteMinutes,
    }) as Map<String, dynamic>;
    return ServerNotifSettings.fromJson(data);
  }

  Future<ServerDetail> getServer(int serverId) async {
    final data = await _request('GET', '/servers/$serverId');
    return ServerDetail.fromJson(data);
  }

  Future<ServerDetail> moveServerRoom(
    int serverId, int roomId, {required int? categoryId, required int? afterId}) async {
    final data = await _request('POST', '/servers/$serverId/rooms/$roomId/move', body: {
      'category_id': categoryId,
      'after_id': afterId,
    });
    return ServerDetail.fromJson(data);
  }

  Future<ServerDetail> moveServerCategory(int serverId, int categoryId, {required int? afterId}) async {
    final data = await _request('POST', '/servers/$serverId/categories/$categoryId/move', body: {
      'after_id': afterId,
    });
    return ServerDetail.fromJson(data);
  }

  Future<ServerDetail> createServer(String name, {String? description}) async {
    final data = await _request('POST', '/servers', body: {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
    });
    return ServerDetail.fromJson(data);
  }

  Future<Room> createRoom(
    int serverId, {
    required String name,
    RoomKind kind = RoomKind.text,
    int? categoryId,
    bool isPrivate = false,
  }) async {
    final data = await _request('POST', '/servers/$serverId/rooms', body: {
      'name': name,
      'kind': kind.name,
      if (categoryId != null) 'category_id': categoryId,
      if (isPrivate) 'is_private': true,
    });
    return Room.fromJson(data);
  }

  Future<Room> getRoom(int serverId, int roomId) async {
    final data = await _request('GET', '/servers/$serverId/rooms/$roomId');
    return Room.fromJson(data);
  }

  /// [userLimit] — лимит людей ГОЛОСОВОГО канала (0 — без лимита). Уходит,
  /// только если передан: текстовому каналу лимит не шлём вовсе, иначе сервер
  /// ответил бы отказом.
  Future<Room> updateRoom(
    int serverId,
    int roomId, {
    required String name,
    String? description,
    int? userLimit,
  }) async {
    final data = await _request('PATCH', '/servers/$serverId/rooms/$roomId', body: {
      'name': name,
      'description': description,
      if (userLimit != null) 'user_limit': userLimit,
    });
    return Room.fromJson(data);
  }

  Future<void> deleteRoom(int serverId, int roomId) async {
    await _request('DELETE', '/servers/$serverId/rooms/$roomId');
  }

  Future<RoomCategory> createCategory(int serverId, String name, {bool isPrivate = false}) async {
    final data = await _request('POST', '/servers/$serverId/categories', body: {
      'name': name,
      if (isPrivate) 'is_private': true,
    });
    return RoomCategory.fromJson(data);
  }

  Future<RoomCategory> getCategory(int serverId, int categoryId) async {
    final data = await _request('GET', '/servers/$serverId/categories/$categoryId');
    return RoomCategory.fromJson(data);
  }

  Future<RoomCategory> updateCategory(int serverId, int categoryId, {required String name}) async {
    final data = await _request('PATCH', '/servers/$serverId/categories/$categoryId', body: {
      'name': name,
    });
    return RoomCategory.fromJson(data);
  }

  Future<void> deleteCategory(int serverId, int categoryId) async {
    await _request('DELETE', '/servers/$serverId/categories/$categoryId');
  }


  String _overwritesPath(int serverId, int placeId, {required bool isCategory}) =>
      '/servers/$serverId/${isCategory ? 'categories' : 'rooms'}/$placeId/overwrites';

  Future<PlaceOverwrites> getOverwrites(int serverId, int placeId, {required bool isCategory}) async {
    final data = await _request('GET', _overwritesPath(serverId, placeId, isCategory: isCategory));
    return PlaceOverwrites.fromJson(data);
  }

  Future<PlaceOverwrites?> setOverwrites(
    int serverId,
    int placeId,
    Map<int, RoleOverwrite> overwrites,
    Map<int, RoleOverwrite> members, {
    required bool isCategory,
  }) async {
    final data = await _request('PUT', _overwritesPath(serverId, placeId, isCategory: isCategory), body: {
      'overwrites': [
        for (final e in overwrites.entries)
          if (!e.value.isEmpty)
            {'role_id': e.key, 'allow': e.value.allow.toJson(), 'deny': e.value.deny.toJson()},
      ],
      'members': [
        for (final e in members.entries)
          if (!e.value.isEmpty)
            {'user_id': e.key, 'allow': e.value.allow.toJson(), 'deny': e.value.deny.toJson()},
      ],
    });
    return data == null ? null : PlaceOverwrites.fromJson(data);
  }

  Future<List<ServerUser>> searchOverwriteMembers(
    int serverId, int placeId, {required bool isCategory, String? query}) async {
    final q = query?.trim() ?? '';
    final path = '${_overwritesPath(serverId, placeId, isCategory: isCategory)}/members'
        '${q.isEmpty ? '' : '?q=${Uri.encodeQueryComponent(q)}'}';
    final data = await _request('GET', path);
    return [
      for (final e in (data as List? ?? const []))
        if (e is Map<String, dynamic>) ServerUser.fromJson(e),
    ];
  }

  Future<PlaceOverwrites?> syncRoomWithCategory(int serverId, int roomId) async {
    final data = await _request('POST', '/servers/$serverId/rooms/$roomId/overwrites/sync', body: {});
    return data == null ? null : PlaceOverwrites.fromJson(data);
  }


  Future<Invite> createInvite(InviteTarget target) async {
    final data = await _request('POST', target.invitesPath, body: {});
    return Invite.fromJson(data);
  }

  Future<List<Invite>> getInvites(InviteTarget target) async {
    final data = await _request('GET', target.invitesPath) as List;
    return data.map((e) => Invite.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> revokeInvite(String code) async {
    await _request('DELETE', '/invites/$code');
  }

  Future<InvitePreview> getInvitePreview(String code) async {
    final data = await _request('GET', '/invites/$code');
    return InvitePreview.fromJson(data);
  }

  Future<Vanity> getVanity(int serverId) async =>
      Vanity.fromJson(await _request('GET', '/servers/$serverId/vanity'));

  Future<Vanity> setVanity(int serverId, String? code) async =>
      Vanity.fromJson(await _request('PUT', '/servers/$serverId/vanity', body: {'code': code}));

  Future<InviteJoinResult> joinInvite(String code) async {
    final data = await _request('POST', '/invites/$code/join');
    return InviteJoinResult.fromJson(data);
  }

  Future<({List<ServerCatalogItem> items, bool hasMore})> getServerCatalog({
    String? query,
    int offset = 0,
    int limit = 24,
  }) async {
    final q = query?.trim() ?? '';
    final params = <String>[
      'offset=$offset',
      'limit=$limit',
      if (q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
    ];
    final data = await _request('GET', '/servers/catalog?${params.join('&')}');
    return (
      items: [
        for (final j in (data['items'] as List? ?? const []))
          ServerCatalogItem.fromJson(j as Map<String, dynamic>),
      ],
      hasMore: data['has_more'] == true,
    );
  }

  Future<ServerDetail> joinPublicServer(int serverId) async {
    final data = await _request('POST', '/servers/$serverId/join');
    return ServerDetail.fromJson(data);
  }

  Future<void> leaveServer(int serverId) async {
    await _request('POST', '/servers/$serverId/leave');
  }

  Future<void> deleteServer(int serverId) async {
    await _request('DELETE', '/servers/$serverId');
  }


  Future<ListPage<ServerMember>> getServerMembers(
    int serverId, {
    String query = '',
    required int offset,
    required int limit,
  }) async {
    final params = [
      if (query.isNotEmpty) 'q=${Uri.encodeComponent(query)}',
      'offset=$offset',
      'limit=$limit',
    ];
    final data =
        await _request('GET', '/servers/$serverId/members?${params.join('&')}') as Map<String, dynamic>;
    return ListPage(
      items: ((data['members'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ServerMember.fromJson)
          .toList(),
      total: data['total'] as int? ?? 0,
    );
  }

  Future<void> kickServerMember(int serverId, int userId) async {
    await _request('DELETE', '/servers/$serverId/members/$userId');
  }

  Future<void> banServerMember(int serverId, int userId, {String? reason}) async {
    await _request('PUT', '/servers/$serverId/bans/$userId', body: {'reason': reason});
  }

  Future<ListPage<ServerBan>> getServerBans(int serverId, {int? before}) async {
    final qs = before == null ? '' : '?before=$before';
    final data = await _request('GET', '/servers/$serverId/bans$qs') as Map<String, dynamic>;
    return ListPage(
      items: ((data['bans'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ServerBan.fromJson)
          .toList(),
      nextCursor: data['next_cursor'] as int?,
    );
  }

  Future<void> unbanServerMember(int serverId, int userId) async {
    await _request('DELETE', '/servers/$serverId/bans/$userId');
  }


  Future<ServerRoster> getServerRoster(int serverId, {int? roomId}) async {
    final query = roomId == null ? '' : '?room_id=$roomId';
    final data = await _request('GET', '/servers/$serverId/roster$query');
    return ServerRoster.fromJson(data);
  }

  static const int nameColorsLimit = 100;

  Future<Map<int, String?>> getNameColors(int serverId, List<int> userIds) async {
    final query = userIds.map((id) => 'user_ids=$id').join('&');
    final data = await _request('GET', '/servers/$serverId/name-colors?$query');
    final out = <int, String?>{};
    if (data is Map<String, dynamic>) {
      for (final raw in (data['colors'] as List? ?? const [])) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['user_id'];
        if (id is int) out[id] = raw['color'] as String?;
      }
    }
    return out;
  }

  Future<Mutual> getMutual(int userId) async {
    final data = await _request('GET', '/users/$userId/mutual');
    return Mutual.fromJson(data);
  }

  Future<String> getNote(int userId) async {
    final data = await _request('GET', '/users/$userId/note');
    return (data is Map ? data['text'] as String? : null) ?? '';
  }

  Future<String> setNote(int userId, String text) async {
    final data = await _request('PUT', '/users/$userId/note', body: {'text': text});
    return (data is Map ? data['text'] as String? : null) ?? '';
  }

  Future<MemberCard> getMemberCard(int serverId, int userId) async {
    final data = await _request('GET', '/servers/$serverId/members/$userId/card');
    return MemberCard.fromJson(data);
  }

  Future<ServerRolesPage> getServerRoles(int serverId) async {
    final data = await _request('GET', '/servers/$serverId/roles');
    return ServerRolesPage.fromJson(data);
  }

  Future<ServerRole> createServerRole(int serverId, ServerRoleForm form) async {
    final data = await _request('POST', '/servers/$serverId/roles', body: form.toJson());
    return ServerRole.fromJson(data);
  }

  Future<ServerRole> updateServerRole(int serverId, int roleId, ServerRoleForm form) async {
    final data = await _request('PATCH', '/servers/$serverId/roles/$roleId', body: form.toJson());
    return ServerRole.fromJson(data);
  }

  Future<void> deleteServerRole(int serverId, int roleId) async {
    await _request('DELETE', '/servers/$serverId/roles/$roleId');
  }

  Future<ServerRolesPage> reorderServerRoles(int serverId, List<int> roleIds) async {
    final data = await _request(
      'PATCH', '/servers/$serverId/roles/order', body: {'role_ids': roleIds},
    );
    return ServerRolesPage.fromJson(data);
  }

  Future<ServerMember> setServerMemberRole(
    int serverId, int userId, int roleId, {required bool grant}) async {
    final data = await _request(
      grant ? 'PUT' : 'DELETE', '/servers/$serverId/members/$userId/roles/$roleId',
    );
    return ServerMember.fromJson(data);
  }

  Future<ServerDetail> uploadServerAvatar(int serverId, XFile file, String mimeType) async {
    final uri = Uri.parse('$_base/servers/$serverId/avatar');
    final request = http.MultipartRequest('POST', uri);
    _authorize(request);
    request.files.add(await _multipartFrom(file, kind: UploadKind.avatar, mimeType: mimeType));
    return ServerDetail.fromJson(await _sendMultipartRaw(request));
  }

  Future<void> putStreamPreview(int serverId, int roomId, Uint8List jpeg) async {
    final uri = Uri.parse('$_base/servers/$serverId/rooms/$roomId/voice/preview');
    final request = http.MultipartRequest('PUT', uri);
    _authorize(request);
    final file = XFile.fromData(jpeg, name: 'preview.jpg', mimeType: 'image/jpeg');
    request.files.add(await _multipartFrom(file, kind: UploadKind.streamPreview, mimeType: 'image/jpeg'));
    final res = await _bytesCall(() async =>
        http.Response.fromStream(await request.send().timeout(_timeout)).timeout(_timeout));
    if (res.statusCode >= 400) throw _errorFrom(res.statusCode, null);
  }

  Future<Uint8List?> getStreamPreview(int serverId, int roomId, int userId) async {
    final uri = Uri.parse('$_base/servers/$serverId/rooms/$roomId/voice/$userId/preview');
    final res = await _bytesCall(() => http.get(uri, headers: _headers).timeout(_timeout));
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) throw _errorFrom(res.statusCode, null);
    return res.bodyBytes;
  }

  Future<http.Response> _bytesCall(Future<http.Response> Function() call) async {
    try {
      return await call();
    } on TimeoutException {
      throw ApiException(appStrings.errorServerTimeout);
    } catch (e) {
      if (isNetworkError(e)) throw ApiException(appStrings.errorNoConnection);
      rethrow;
    }
  }

  Future<({Map<String, int> bytes, int? maxAttachments})> getUploadLimits() async {
    final data = await _request('GET', '/media/limits') as Map<String, dynamic>;
    final raw = data['limits'] as Map<String, dynamic>;
    return (
      bytes: raw.map((k, v) => MapEntry(k, (v as num).toInt())),
      maxAttachments: (data['max_attachments'] as num?)?.toInt(),
    );
  }

  /// Поиск по справочнику игр — окно выбора игр сообщества (с 2026-11-07:
  /// игр больше десяти тысяч, весь список не качается). Совпадение и порядок
  /// решает сервер; пустой запрос — пустой ответ.
  Future<List<Game>> searchGames(String query) async {
    final path = Uri(path: '/servers/games/search', queryParameters: {'q': query}).toString();
    final data = await _request('GET', path) as List;
    return data.whereType<Map<String, dynamic>>().map(Game.fromJson).toList();
  }

  Future<List<DesktopWatchedGame>> getDetectableGames() async {
    final data = await _request('GET', '/servers/games/executables') as List;
    return [
      for (final g in data.whereType<Map<String, dynamic>>())
        if (g['id'] case final num id)
          (
            id: id.toInt(),
            executables: [for (final e in (g['executables'] as List? ?? const [])) if (e is String) e],
          ),
    ];
  }

  Future<ServerDetail> updateServerProfile(
    int serverId, {
    required String name,
    required String description,
    XFile? avatar,
    String? avatarMime,
    XFile? banner,
    String? bannerMime,
    bool removeBanner = false,
    List<int>? gameIds,
    bool? isPublic,
  }) async {
    final request = http.MultipartRequest('PATCH', Uri.parse('$_base/servers/$serverId'));
    _authorize(request);
    request.fields['name'] = name;
    request.fields['description'] = description;
    if (removeBanner) request.fields['remove_banner'] = 'true';
    if (gameIds != null) request.fields['game_ids'] = jsonEncode(gameIds);
    if (isPublic != null) request.fields['is_public'] = isPublic ? 'true' : 'false';
    if (avatar != null) {
      request.files.add(await _multipartFrom(avatar, kind: UploadKind.avatar, field: 'avatar', mimeType: avatarMime));
    }
    if (banner != null) {
      request.files.add(await _multipartFrom(banner, kind: UploadKind.banner, field: 'banner', mimeType: bannerMime));
    }
    return ServerDetail.fromJson(await _sendMultipartRaw(request));
  }

  Future<ServerDetail> updateServerSystem(
    int serverId, {
    required NotifLevel defaultNotifications,
    required ServerSystemSettings system,
  }) async =>
      ServerDetail.fromJson(await _request('PATCH', '/servers/$serverId/system', body: {
        'default_notifications': defaultNotifications.name,
        'system_room_id': system.roomId,
        'system_join_messages': system.joinMessages,
        'system_leave_messages': system.leaveMessages,
      }));


  Future<List<StickerGroup>> getMyStickers() async {
    final data = await _request('GET', '/servers/stickers') as List;
    return data.whereType<Map<String, dynamic>>().map(StickerGroup.fromJson).toList();
  }


  Future<List<Webhook>> getRoomWebhooks(int roomId) async {
    final data = await _request('GET', '/channels/$roomId/webhooks', base: publicApiBase) as List;
    return data.map((j) => Webhook.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Webhook> createWebhook(int roomId, {required String name, String? avatar}) async =>
      Webhook.fromJson(await _request('POST', '/channels/$roomId/webhooks',
          base: publicApiBase, body: {'name': name, if (avatar != null) 'avatar': avatar}));

  Future<Webhook> updateWebhook(int webhookId, {String? name, ({String? dataUri})? avatar}) async =>
      Webhook.fromJson(await _request('PATCH', '/webhooks/$webhookId', base: publicApiBase, body: {
        if (name != null) 'name': name,
        if (avatar != null) 'avatar': avatar.dataUri,
      }));

  Future<void> deleteWebhook(int webhookId) => _request('DELETE', '/webhooks/$webhookId', base: publicApiBase);

  Future<void> executeWebhook(
    String webhookUrl,
    Map<String, dynamic> payload, {
    List<XFile> photos = const [],
    XFile? file,
  }) async {
    final uri = Uri.parse(webhookUrl).replace(queryParameters: {'wait': 'true'});
    final request = http.MultipartRequest('POST', uri);
    request.headers['Accept-Language'] = _language;
    request.fields['payload_json'] = jsonEncode(payload);
    final files = [
      for (final p in photos) (p, UploadKind.photo),
      if (file != null) (file, UploadKind.file),
    ];
    for (var i = 0; i < files.length; i++) {
      request.files.add(await _multipartFrom(files[i].$1, kind: files[i].$2, field: 'files[$i]'));
    }
    await _sendMultipartRaw(request);
  }

  Future<ServerStickersPage> getServerStickers(int serverId) async {
    return ServerStickersPage.fromJson(await _request('GET', '/servers/$serverId/stickers'));
  }

  Future<Sticker> addSticker(
    int serverId, {
    required XFile file,
    required String fileMime,
    required String name,
    required String description,
    required String emoji,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_base/servers/$serverId/stickers'));
    _authorize(request);
    request.fields['name'] = name;
    request.fields['description'] = description;
    request.fields['emoji'] = emoji;
    request.files.add(await _multipartFrom(file, kind: UploadKind.sticker, mimeType: fileMime));
    return Sticker.fromJson(await _sendMultipartRaw(request));
  }

  Future<Sticker> updateSticker(
    int serverId,
    int stickerId, {
    required String name,
    required String description,
    required String emoji,
  }) async {
    final data = await _request('PATCH', '/servers/$serverId/stickers/$stickerId',
        body: {'name': name, 'description': description, 'emoji': emoji});
    return Sticker.fromJson(data);
  }

  Future<void> deleteSticker(int serverId, int stickerId) async {
    await _request('DELETE', '/servers/$serverId/stickers/$stickerId');
  }


  Future<List<ChatFolder>> getFolders() async {
    final data = await _request('GET', '/folders') as List;
    return data.map((e) => ChatFolder.fromJson(e)).toList();
  }

  Future<ChatFolder> createFolder(String name, List<int> chatIds) async {
    final data = await _request('POST', '/folders', body: {'name': name, 'chat_ids': chatIds});
    return ChatFolder.fromJson(data);
  }

  Future<ChatFolder> updateFolder(int folderId, {String? name, List<int>? chatIds}) async {
    final data = await _request('PATCH', '/folders/$folderId', body: {
      if (name != null) 'name': name,
      if (chatIds != null) 'chat_ids': chatIds,
    });
    return ChatFolder.fromJson(data);
  }

  Future<void> deleteFolder(int folderId) async {
    await _request('DELETE', '/folders/$folderId');
  }

  Future<List<ChatFolder>> reorderFolders(List<int> folderIds) async {
    final data = await _request('PUT', '/folders/order', body: {'folder_ids': folderIds}) as List;
    return data.map((e) => ChatFolder.fromJson(e)).toList();
  }

  Future<List<ChatPin>> getPins() async {
    final data = await _request('GET', '/folders/pins') as List;
    return data.map((e) => ChatPin.fromJson(e)).toList();
  }

  Future<List<ChatPin>> setPins(int folderId, List<int> chatIds, bool pinned) async {
    final data = await _request('PUT', '/folders/pins', body: {
      'folder_id': folderId, 'chat_ids': chatIds, 'pinned': pinned,
    }) as List;
    return data.map((e) => ChatPin.fromJson(e)).toList();
  }


  Future<List<Message>> getMessages(int chatId, {int limit = 50, int? beforeId, int? afterId}) async {
    var path = '/chats/$chatId/messages?limit=$limit';
    if (beforeId != null) path += '&before_id=$beforeId';
    if (afterId != null) path += '&after_id=$afterId';
    final data = await _request('GET', path) as List;
    return data.map((e) => Message.fromJson(e)).toList();
  }

  Future<int?> getLastEditableMessageId(int chatId) async {
    final data = await _request('GET', '/chats/$chatId/messages/last-editable') as Map;
    return (data['message_id'] as num?)?.toInt();
  }

  Future<List<Message>> searchChatMessages(int chatId, String query) async {
    final path = '/chats/$chatId/messages/search?q=${Uri.encodeComponent(query)}';
    final data = await _request('GET', path) as List;
    return data.map((e) => Message.fromJson(e)).toList();
  }

  Future<void> editMessage(int chatId, int messageId, String content) async {
    await _request('PATCH', '/chats/$chatId/messages/$messageId', body: {'content': content});
  }

  Future<bool> deleteMessage(int chatId, int messageId) async {
    final data = await _request('DELETE', '/chats/$chatId/messages/$messageId');
    return data is Map && data['chat_deleted'] == true;
  }

  Future<void> markChatRead(int chatId, {required int upTo}) async {
    await _request('POST', '/chats/$chatId/read?message_id=$upTo');
  }

  // Расшифровка голосового в текст (Yandex SpeechKit) — сервер сам кеширует
  // результат в БД, повторный вызов для уже расшифрованного просто вернёт
  // готовый текст без нового обращения к API распознавания.
  Future<String> transcribeMessage(int chatId, int messageId) async {
    final data = await _request('POST', '/chats/$chatId/messages/$messageId/transcribe') as Map;
    return data['transcript'] as String;
  }

  Future<Message> sendMessage(int chatId, {
    required String type,
    String? text,
    String? imageUrl,
    String? videoUrl,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    FileAudio? fileAudio,
    String? geo,
    String? voiceUrl,
    String? videoNote,
    PollDraft? poll,
    int? stickerId,
    String? caption,
    int? replyToId,
    String? forwardedFrom,
  }) async {
    final body = <String, dynamic>{'type': type};
    if (text != null) body['content'] = text;
    if (imageUrl != null) body['image_url'] = imageUrl;
    if (videoUrl != null) body['video_url'] = videoUrl;
    if (fileUrl != null) body['file_url'] = fileUrl;
    if (fileName != null) body['file_name'] = fileName;
    if (fileSize != null) body['file_size'] = fileSize;
    if (fileAudio != null) body['file_audio'] = fileAudio.toJson();
    if (geo != null) body['geo'] = geo;
    if (voiceUrl != null) body['voice_url'] = voiceUrl;
    if (videoNote != null) body['video_note'] = videoNote;
    if (poll != null) body['poll'] = poll.toJson();
    if (stickerId != null) body['sticker_id'] = stickerId;
    if (caption != null) body['caption'] = caption;
    if (replyToId != null) body['reply_to_id'] = replyToId;
    if (forwardedFrom != null) body['forwarded_from'] = forwardedFrom;
    final data = await _request('POST', '/chats/$chatId/messages', body: body);
    return Message.fromJson(data);
  }

  Future<http.MultipartFile> _multipartFrom(
    XFile file, {
    required UploadKind kind,
    String field = 'file',
    String? filename,
    String? mimeType,
  }) async {
    final length = await file.length();
    await uploadLimits.ensureFits(kind, length);
    return http.MultipartFile(
      field,
      file.openRead(),
      length,
      filename: filename ?? file.name,
      contentType: mimeType != null ? MediaType.parse(mimeType) : null,
    );
  }

  Future<({String url, String name, int size, FileAudio? audio})> _uploadFile(
    String path, XFile file, {
    String? mimeType, String? fileName, void Function(int, int)? onProgress,
  }) async {
    final uri = Uri.parse('$_base$path');
    final request = http.MultipartRequest('POST', uri);
    _authorize(request);
    request.files.add(await _multipartFrom(file, kind: UploadKind.file, filename: fileName, mimeType: mimeType));
    final raw = onProgress != null
        ? await _sendMultipartRawWithProgress(request, onProgress)
        : await _sendMultipartRaw(request);
    return (url: raw['url'] as String, name: raw['name'] as String, size: raw['size'] as int, audio: FileAudio.fromJson(raw['audio']));
  }

  Future<({String url, String name, int size, FileAudio? audio})> uploadChatFile(
    int chatId, XFile file, String mimeType, String fileName, {
    void Function(int, int)? onProgress,
  }) => _uploadFile('/chats/$chatId/upload-file', file,
      mimeType: mimeType, fileName: fileName, onProgress: onProgress);


  Future<Chat> uploadChatAvatar(int chatId, XFile file, String mimeType) async {
    final uri = Uri.parse('$_base/chats/$chatId/avatar');
    final request = http.MultipartRequest('POST', uri);
    _authorize(request);
    request.files.add(await _multipartFrom(file, kind: UploadKind.avatar, mimeType: mimeType));
    return Chat.fromJson(await _sendMultipartRaw(request));
  }

  Future<User> uploadAvatar(XFile file, String mimeType) async {
    final uri = Uri.parse('$_base/users/me/avatar');
    final request = http.MultipartRequest('POST', uri);
    _authorize(request);
    request.files.add(await _multipartFrom(file, kind: UploadKind.avatar, mimeType: mimeType));
    return User.fromJson(await _sendMultipartRaw(request));
  }

  Future<User> updateMyProfile({
    required String displayName,
    required String bio,
    XFile? avatar,
    String? avatarMime,
    XFile? banner,
    String? bannerMime,
    bool removeBanner = false,
    Map<CollectibleKind, int?> equip = const {},
    List<int>? achievementOrder,
  }) async {
    final request = http.MultipartRequest('PATCH', Uri.parse('$_base/users/me/profile'));
    _authorize(request);
    request.fields['display_name'] = displayName;
    request.fields['bio'] = bio;
    if (achievementOrder != null) request.fields['achievement_order'] = jsonEncode(achievementOrder);
    if (removeBanner) request.fields['remove_banner'] = 'true';
    equip.forEach((kind, itemId) => request.fields['${kind.wire}_id'] = itemId?.toString() ?? '');
    if (avatar != null) {
      request.files.add(await _multipartFrom(avatar, kind: UploadKind.avatar, field: 'avatar', mimeType: avatarMime));
    }
    if (banner != null) {
      request.files.add(await _multipartFrom(banner, kind: UploadKind.banner, field: 'banner', mimeType: bannerMime));
    }
    return User.fromJson(await _sendMultipartRaw(request));
  }

  Future<List<CollectionItem>> getMyCollectibles() async {
    final data = await _request('GET', '/users/me/collectibles');
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(CollectionItem.fromJson)
        .whereType<CollectionItem>()
        .toList();
  }

  Future<List<ShopProduct>> getShop() async {
    final data = await _request('GET', '/shop');
    final products = data['products'];
    if (products is! List) return const [];
    return products
        .whereType<Map<String, dynamic>>()
        .map(ShopProduct.fromJson)
        .whereType<ShopProduct>()
        .toList();
  }

  Future<({String paymentId, String confirmationUrl})> shopCheckout(int productId) async {
    final data = await _request('POST', '/shop/products/$productId/checkout');
    return (paymentId: data['payment_id'] as String, confirmationUrl: data['confirmation_url'] as String);
  }

  Future<({String status, int? productId})> confirmPayment(String paymentId) async {
    final data = await _request('POST', '/payments/$paymentId/confirm');
    return (status: data['status'] as String? ?? '', productId: (data['product_id'] as num?)?.toInt());
  }

  Future<MyServerProfile> getMyServerProfile(int serverId) async {
    final data = await _request('GET', '/servers/$serverId/members/me/profile');
    return MyServerProfile.fromJson(data);
  }

  Future<MyServerProfile> updateMyServerProfile(
    int serverId, {
    required String nick,
    required String bio,
    XFile? avatar,
    String? avatarMime,
    XFile? banner,
    String? bannerMime,
    bool removeAvatar = false,
    bool removeBanner = false,
  }) async {
    final request = http.MultipartRequest('PATCH', Uri.parse('$_base/servers/$serverId/members/me/profile'));
    _authorize(request);
    request.fields['nick'] = nick;
    request.fields['bio'] = bio;
    if (removeAvatar) request.fields['remove_avatar'] = 'true';
    if (removeBanner) request.fields['remove_banner'] = 'true';
    if (avatar != null) {
      request.files.add(await _multipartFrom(avatar, kind: UploadKind.avatar, field: 'avatar', mimeType: avatarMime));
    }
    if (banner != null) {
      request.files.add(await _multipartFrom(banner, kind: UploadKind.banner, field: 'banner', mimeType: bannerMime));
    }
    return MyServerProfile.fromJson(await _sendMultipartRaw(request));
  }

  Future<ServerMember> setMemberNick(int serverId, int userId, String? nick) async {
    final data = await _request('PUT', '/servers/$serverId/members/$userId/nick', body: {'nick': nick});
    return ServerMember.fromJson(data);
  }

  // Загрузка голосового без создания сообщения → {url, size}. duration уже
  // известна клиенту из записи — JSON {"url":..,"duration":..} собирается на
  // клиенте перед атомарным sendMessage(type:'voice', ...), как
  // фото/видео/файл/альбом.
  Future<Map<String, dynamic>> _uploadVoice(String path, XFile file, {void Function(int, int)? onProgress}) async {
    final uri = Uri.parse('$_base$path');
    final request = http.MultipartRequest('POST', uri);
    _authorize(request);
    request.files.add(await _multipartFrom(file, kind: UploadKind.voice, mimeType: 'audio/m4a'));
    final data = onProgress != null
        ? await _sendMultipartRawWithProgress(request, onProgress)
        : await _sendMultipartRaw(request);
    return {'url': data['url'] as String, 'size': data['size'] as int};
  }

  Future<Map<String, dynamic>> uploadChatVoice(int chatId, XFile file, {void Function(int, int)? onProgress}) =>
      _uploadVoice('/chats/$chatId/upload-voice', file, onProgress: onProgress);

  // «Кружок»: видео и его превью уходят ОДНИМ запросом. Двумя нельзя — между
  // ними записи ещё нет, и первый файл остался бы в S3 навсегда (чистка S3
  // идёт вслед за удалением записей, а записи нет). Возвращает {url, thumb, size};
  // JSON {"url","thumb","duration"} собирает вызывающий и передаёт в
  // sendMessage с type:'video_note' — тот же атомарный паттерн, что у
  // голосового.
  Future<({String url, String thumb, int size})> _uploadVideoNote(
    String path,
    XFile video,
    XFile thumb, {
    void Function(int, int)? onProgress,
  }) async {
    final uri = Uri.parse('$_base$path');
    final request = http.MultipartRequest('POST', uri);
    _authorize(request);
    request.files.add(await _multipartFrom(video, kind: UploadKind.videoNote, mimeType: 'video/mp4'));
    request.files.add(await _multipartFrom(thumb, kind: UploadKind.photo, field: 'thumb', mimeType: 'image/jpeg'));
    final data = onProgress != null
        ? await _sendMultipartRawWithProgress(request, onProgress)
        : await _sendMultipartRaw(request);
    return (url: data['url'] as String, thumb: data['thumb'] as String, size: data['size'] as int);
  }

  Future<({String url, String thumb, int size})> uploadChatVideoNote(
    int chatId, XFile video, XFile thumb, {void Function(int, int)? onProgress}) =>
      _uploadVideoNote('/chats/$chatId/upload-video-note', video, thumb, onProgress: onProgress);

  Future<List<GifCategory>> getGifCategories() async {
    final data = await _request('GET', '/gifs/categories') as List;
    return data.map((e) => GifCategory.fromJson(e)).toList();
  }

  Future<GifPageResult> getFeaturedGifs({String? pos}) async {
    final qs = pos != null ? '?pos=${Uri.encodeComponent(pos)}' : '';
    final data = await _request('GET', '/gifs/featured$qs') as Map<String, dynamic>;
    return GifPageResult(
      items: (data['results'] as List).map((e) => GifItem.fromJson(e)).toList(),
      next: data['next'] as String?,
    );
  }

  Future<GifPageResult> searchGifs(String query, {String? pos}) async {
    var qs = '?q=${Uri.encodeComponent(query)}';
    if (pos != null) qs += '&pos=${Uri.encodeComponent(pos)}';
    final data = await _request('GET', '/gifs/search$qs') as Map<String, dynamic>;
    return GifPageResult(
      items: (data['results'] as List).map((e) => GifItem.fromJson(e)).toList(),
      next: data['next'] as String?,
    );
  }

  Future<List<GifItem>> getRecentGifs() async {
    final data = await _request('GET', '/gifs/recent') as List;
    return data.map((e) => GifItem.fromJson(e)).toList();
  }

  Future<void> recordRecentGif(String url, String? thumbnailUrl) => _request('POST', '/gifs/recent', body: {
        'url': url,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      });

  // ======== GLITCH+ ========

  Future<GlitchPlusStatus> getGlitchPlusStatus() async {
    final data = await _request('GET', '/glitchplus/status');
    return GlitchPlusStatus.fromJson(data);
  }

  Future<({String paymentId, String confirmationUrl})> createGlitchPlusCheckout() async {
    final data = await _request('POST', '/glitchplus/checkout');
    return (paymentId: data['payment_id'] as String, confirmationUrl: data['confirmation_url'] as String);
  }

  Future<GlitchPlusStatus> confirmGlitchPlusPayment(String paymentId) async {
    final data = await _request('POST', '/glitchplus/confirm', body: {'payment_id': paymentId});
    return GlitchPlusStatus.fromJson(data);
  }

  Future<GlitchPlusStatus> cancelGlitchPlus() async {
    final data = await _request('POST', '/glitchplus/cancel');
    return GlitchPlusStatus.fromJson(data);
  }

  Future<GlitchPlusStatus> resumeGlitchPlus() async {
    final data = await _request('POST', '/glitchplus/resume');
    return GlitchPlusStatus.fromJson(data);
  }

  Future<GlitchPlusStatus> detachGlitchPlusCard() async {
    final data = await _request('POST', '/glitchplus/detach-card');
    return GlitchPlusStatus.fromJson(data);
  }

  Future<List<Message>> getChatMedia(int chatId) async {
    final data = await _request('GET', '/chats/$chatId/media') as List;
    return data.map((e) => Message.fromJson(e)).toList();
  }

  Future<List<Message>> getChatFiles(int chatId) async {
    final data = await _request('GET', '/chats/$chatId/files') as List;
    return data.map((e) => Message.fromJson(e)).toList();
  }

  Future<Map<String, dynamic>> _sendMultipartRaw(http.MultipartRequest request) async {
    try {
      final streamed = await request.send().timeout(const Duration(minutes: 10));
      final res = await http.Response.fromStream(streamed).timeout(const Duration(minutes: 10));
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        data = null;
      }
      if (res.statusCode >= 400) throw _errorFrom(res.statusCode, data);
      if (data is! Map<String, dynamic>) throw ApiException(appStrings.errorBadResponse);
      return data;
    } catch (e) {
      throw _uploadFailure(e);
    }
  }

  Future<Map<String, dynamic>> _sendMultipartRawWithProgress(
    http.MultipartRequest request,
    void Function(int sent, int total) onProgress,
  ) async {
    final client = dio.Dio(dio.BaseOptions(
      sendTimeout: const Duration(minutes: 10),
      receiveTimeout: const Duration(minutes: 10),
      connectTimeout: const Duration(seconds: 30),
    ));
    try {
      final formData = dio.FormData();
      for (final entry in request.fields.entries) {
        formData.fields.add(MapEntry(entry.key, entry.value));
      }
      for (final file in request.files) {
        formData.files.add(MapEntry(
          file.field,
          dio.MultipartFile(file.finalize(), file.length,
            filename: file.filename, contentType: file.contentType),
        ));
      }
      final response = await client.post<Map<String, dynamic>>(
        request.url.toString(),
        data: formData,
        options: dio.Options(headers: {
          'Authorization': request.headers['Authorization'],
          'Accept-Language': _language,
          if (request.headers[viewAsHeader] != null) viewAsHeader: request.headers[viewAsHeader],
        }),
        onSendProgress: onProgress,
      );
      final raw = response.data;
      if (raw == null) throw ApiException(appStrings.errorBadResponse);
      return raw;
    } on dio.DioException catch (e) {
      if (e.type == dio.DioExceptionType.connectionError) throw ApiException(appStrings.errorNoConnection);
      if (e.type == dio.DioExceptionType.sendTimeout || e.type == dio.DioExceptionType.receiveTimeout) {
        throw ApiException(appStrings.errorTimeout);
      }
      final res = e.response;
      if (res != null) throw _errorFrom(res.statusCode ?? 0, res.data is Map ? res.data : null);
      throw ApiException(appStrings.errorUpload);
    } catch (e) {
      throw _uploadFailure(e);
    } finally {
      client.close();
    }
  }


  Future<List<Relationship>> getRelationships() async {
    final data = await _request('GET', '/users/me/relationships');
    return ((data as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Relationship.fromJson)
        .whereType<Relationship>()
        .toList();
  }

  Future<Relationship?> requestFriendByNickname(String nickname) async {
    final data = await _request('POST', '/users/me/relationships', body: {'nickname': nickname});
    return data is Map<String, dynamic> ? Relationship.fromJson(data) : null;
  }

  Future<Relationship?> requestFriend(int userId) async {
    final data = await _request('PUT', '/users/me/relationships/$userId');
    return data is Map<String, dynamic> ? Relationship.fromJson(data) : null;
  }

  Future<void> removeRelationship(int userId) async {
    await _request('DELETE', '/users/me/relationships/$userId');
  }


  Future<void> blockUser(String nickname) async {
    await _request('POST', '/users/$nickname/block');
  }

  Future<void> unblockUser(String nickname) async {
    await _request('DELETE', '/users/$nickname/block');
  }

  Future<List<BlockedUser>> getBlockedUsers() async {
    final data = await _request('GET', '/users/me/blocks') as List;
    return data.map((e) => BlockedUser.fromJson(e)).toList();
  }

  Future<void> muteUserInAdvance(String nickname) async {
    await _request('POST', '/users/$nickname/mute-preference');
  }

  Future<void> unmuteUserInAdvance(String nickname) async {
    await _request('DELETE', '/users/$nickname/mute-preference');
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) =>
      _request('PATCH', path, body: body);

  Future<MessagePreview?> getChatPin(int chatId) async =>
      _pinnedFrom(await _request('GET', '/chats/$chatId/pin'));

  Future<MessagePreview?> setChatPin(int chatId, int? messageId) async => _pinnedFrom(
        messageId == null
            ? await _request('DELETE', '/chats/$chatId/pin')
            : await _request('PUT', '/chats/$chatId/pin', body: {'id': messageId}),
      );

  static MessagePreview? pinnedFrom(dynamic data) {
    final p = data is Map ? data['pinned'] : null;
    return p is Map<String, dynamic> ? MessagePreview.fromJson(p) : null;
  }

  MessagePreview? _pinnedFrom(dynamic data) => pinnedFrom(data);

  Future<List<Reaction>> reactToMessage(int chatId, int messageId, String emoji) async {
    final data = await _request('POST', '/chats/$chatId/messages/$messageId/reactions', body: {'emoji': emoji}) as Map;
    return (data['reactions'] as List).map((r) => Reaction.fromJson(r)).toList();
  }


  Future<PollInfo> votePoll(int chatId, int messageId, List<int> answerIds) async {
    final data = await _request('PUT', '/chats/$chatId/messages/$messageId/poll/votes',
        body: {'answer_ids': answerIds}) as Map<String, dynamic>;
    return PollInfo.fromJson(data);
  }

  Future<void> endPoll(int chatId, int messageId) async {
    await _request('POST', '/chats/$chatId/messages/$messageId/poll/end');
  }

  Future<ListPage<ServerUser>> getPollVoters(int chatId, int messageId, int answerId, {int? before}) async {
    final qs = before == null ? '' : '?before=$before';
    final data = await _request('GET',
        '/chats/$chatId/messages/$messageId/poll/answers/$answerId/voters$qs') as Map<String, dynamic>;
    return ListPage(
      items: ((data['voters'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ServerUser.fromJson)
          .toList(),
      nextCursor: data['next_cursor'] as int?,
    );
  }

  Future<SearchResult> searchAll(String query) async {
    final data = await _request('GET', '/search?q=${Uri.encodeComponent(query)}');
    return SearchResult.fromJson(data);
  }

  Future<List<SearchHit>> searchEverything(String query, {Set<SearchKind>? kinds}) async {
    final params = <String, String>{'q': query};
    if (kinds != null && kinds.isNotEmpty) {
      params['kinds'] = kinds.map((k) => k.name).join(',');
    }
    final data = await _request('GET', Uri(path: '/search/everything', queryParameters: params).toString());
    return SearchHit.listFrom(data as Map<String, dynamic>);
  }

  Future<List<SearchHit>> searchPlaces(List<PlaceRef> refs) async {
    if (refs.isEmpty) return const [];
    final query = Uri(queryParameters: {'refs': refs.map((r) => r.wire).join(',')}).query;
    final data = await _request('GET', '/search/places?$query');
    return SearchHit.listFrom(data as Map<String, dynamic>);
  }


  Future<MediaUploadResult> uploadMediaFile(
    XFile file,
    String mimeType, {
    int? w,
    int? h,
    XFile? thumb,
    int? chatId,
    void Function(int, int)? onProgress,
  }) async {
    final uri = Uri.parse('$_base/media/upload');
    final request = http.MultipartRequest('POST', uri);
    _authorize(request);
    request.files.add(await _multipartFrom(file,
        kind: mimeType.startsWith('video/') ? UploadKind.video : UploadKind.photo, mimeType: mimeType));
    if (thumb != null) {
      request.files.add(await _multipartFrom(thumb, kind: UploadKind.photo, field: 'thumb', mimeType: 'image/jpeg'));
    }
    if (w != null) request.fields['w'] = w.toString();
    if (h != null) request.fields['h'] = h.toString();
    if (chatId != null) request.fields['chat_id'] = chatId.toString();
    final raw = onProgress != null
        ? await _sendMultipartRawWithProgress(request, onProgress)
        : await _sendMultipartRaw(request);
    return MediaUploadResult.fromJson(raw);
  }

  String mediaUrl(String path) => path;
}


class MediaUploadResult {
  final String url;
  final int? w;
  final int? h;
  final String type; // 'photo' или 'video'
  final String? thumb;

  const MediaUploadResult({required this.url, this.w, this.h, required this.type, this.thumb});

  factory MediaUploadResult.fromJson(Map<String, dynamic> j) => MediaUploadResult(
    url: j['url'] as String,
    w: (j['w'] as num?)?.toInt(),
    h: (j['h'] as num?)?.toInt(),
    type: j['type'] as String? ?? 'photo',
    thumb: j['thumb'] as String?,
  );

  Map<String, dynamic> get asMap => {
        'url': url,
        if (w != null && h != null) 'w': w,
        if (w != null && h != null) 'h': h,
        if (thumb != null) 'thumb': thumb,
      };
}


class SearchUserItem {
  final int id;
  final String nickname;
  final String displayName;
  final String? avatar;
  final Map<String, String>? avatarSizes;
  const SearchUserItem({required this.id, required this.nickname, required this.displayName, this.avatar, this.avatarSizes});
  factory SearchUserItem.fromJson(Map<String, dynamic> j) => SearchUserItem(
    id: j['id'], nickname: j['nickname'], displayName: j['display_name'], avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
  );
}

class SearchResult {
  final List<SearchUserItem> users;
  const SearchResult({required this.users});
  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
    users: (j['users'] as List).map((e) => SearchUserItem.fromJson(e)).toList(),
  );
}

final api = ApiService();

class _AuthHttpClient extends http.BaseClient {
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final isS3 = request.url.host.contains('s3.regru.cloud');
    if (!isS3) request.headers.addAll(api.imageHeaders);
    return _inner.send(request);
  }
}

class MediaCacheManager extends CacheManager with ImageCacheManager {
  static const _key = 'glitchMediaCache';

  MediaCacheManager._() : super(Config(
    _key,
    fileService: HttpFileService(httpClient: _AuthHttpClient()),
  ));

  static final instance = MediaCacheManager._();
}

final mediaCacheManager = MediaCacheManager.instance;
