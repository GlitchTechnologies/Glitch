import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class GroupProvider extends ChangeNotifier {
  final int chatId;

  Chat? chat;
  bool loading = true;

  List<Message> mediaItems = [];
  List<Message> fileItems = [];
  bool mediaLoaded = false;
  bool filesLoaded = false;

  bool _disposed = false;

  final _errorCtrl = StreamController<String>.broadcast();
  Stream<String> get errors => _errorCtrl.stream;

  GroupProvider({required this.chatId});

  void init() {
    load();
    loadMedia();
  }

  @override
  void dispose() {
    _disposed = true;
    _errorCtrl.close();
    super.dispose();
  }

  Future<void> load() async {
    try {
      chat = await api.getChat(chatId);
      if (_disposed) return;
      loading = false;
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMedia() async {
    if (mediaLoaded) return;
    try {
      mediaItems = await api.getChatMedia(chatId);
      if (_disposed) return;
      mediaLoaded = true;
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      notifyListeners();
    }
  }

  Future<void> loadFiles() async {
    if (filesLoaded) return;
    try {
      fileItems = await api.getChatFiles(chatId);
      if (_disposed) return;
      filesLoaded = true;
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      notifyListeners();
    }
  }

  Future<void> addMember(String nickname) async {
    await api.addMember(chatId, nickname);
    await load();
  }

  bool get iAmAdmin {
    final me = authService.currentUser;
    if (me == null || chat == null) return false;
    return chat!.members.any((m) => m.id == me.id && (m.role == 'admin' || m.role == 'owner'));
  }

  bool get iAmOwner {
    final me = authService.currentUser;
    if (me == null || chat == null) return false;
    return chat!.members.any((m) => m.id == me.id && m.role == 'owner');
  }
}
