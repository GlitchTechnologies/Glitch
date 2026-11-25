import 'dart:async';

import '../core/platform_info.dart';
import 'api_service.dart';
import 'desktop_shell.dart';
import 'error_reporter.dart';
import 'websocket_service.dart';

class GameActivity {
  StreamSubscription<List<DesktopRunningGame>>? _sub;

  int _attempt = 0;
  bool _watching = false;
  List<DesktopRunningGame> _running = const [];

  bool _reported = false;
  int? _reportedGameId;

  void startSession() {
    final shell = desktopShell;
    if (!isDesktopApp || shell == null || !shell.hasRunningGames) return;
    _attempt++;
    _sub?.cancel();
    _sub = shell.runningGames.listen(_onRunning);
    wsService.removeConnectListener(_onConnected);
    wsService.addConnectListener(_onConnected);
    unawaited(_watch(_attempt));
  }

  void endSession() {
    _attempt++;
    _sub?.cancel();
    _sub = null;
    wsService.removeConnectListener(_onConnected);
    if (_watching) desktopShell?.watchGames(const []);
    _watching = false;
    _running = const [];
    _reported = false;
    _reportedGameId = null;
  }

  Future<void> _watch(int attempt) async {
    try {
      final games = await api.getDetectableGames();
      if (attempt != _attempt) return;
      desktopShell?.watchGames(games);
      _watching = true;
    } catch (e, s) {
      if (attempt == _attempt) {
        errorReporter.report(e, stack: s, screen: 'gameActivity:watch');
      }
    }
  }

  void _onRunning(List<DesktopRunningGame> games) {
    _running = games;
    _report(force: false);
  }

  void _onConnected() {
    _reported = false;
    if (!_watching) unawaited(_watch(_attempt));
    _report(force: true);
  }

  void _report({required bool force}) {
    if (!wsService.isConnected) return; // скажет [_onConnected]
    final current = _running.isEmpty ? null : _running.last;
    final gameId = current?.id;
    if (!force && _reported && gameId == _reportedGameId) return;
    final elapsed = current == null
        ? 0.0
        : DateTime.now().toUtc().difference(current.startedAt).inMilliseconds / 1000;
    wsService.send({
      'type': 'activity.update',
      'game_id': gameId,
      'elapsed': elapsed < 0 ? 0.0 : elapsed,
    });
    _reported = true;
    _reportedGameId = gameId;
  }
}

final gameActivity = GameActivity();
