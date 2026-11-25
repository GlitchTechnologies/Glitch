import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/chat_open.dart';
import '../main.dart' show navigatorKey;
import '../models/voice_pass.dart';
import '../providers/call_provider.dart';
import '../services/api_service.dart';
import '../services/chat_viewing.dart';
import '../services/error_reporter.dart';
import '../services/websocket_service.dart';
import 'call_stage.dart';
import 'resize_handle.dart';
import 'voice_member_menu.dart' show openCallMemberMenu;

const double _kAreaDefaultShare = 0.5;

const double _kAreaMaxShare = 0.75;

const double _kAreaMinHeight = 336;

const double _kResizeHandleHeight = 10;

double _areaShare = _kAreaDefaultShare;

class ChatCallArea extends StatefulWidget {
  final int chatId;

  final String chatName;

  final ValueChanged<bool>? onShownChanged;

  const ChatCallArea({super.key, required this.chatId, required this.chatName, this.onShownChanged});

  @override
  State<ChatCallArea> createState() => _ChatCallAreaState();
}

class _ChatCallAreaState extends State<ChatCallArea> {
  double _dragStartHeight = 0;

  CurrentCall? _call;
  bool _disposed = false;

  bool _reportedShown = false;

  @override
  void initState() {
    super.initState();
    wsService.addListener(_onWsEvent);
    wsService.addReconnectListener(_load);
    callProvider.addListener(_onCallChanged);
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    wsService.removeListener(_onWsEvent);
    wsService.removeReconnectListener(_load);
    callProvider.removeListener(_onCallChanged);
    super.dispose();
  }


  Future<void> _load() async {
    try {
      final call = await api.getCurrentCall(widget.chatId);
      if (_disposed || !mounted) return;
      final known = _call;
      if (call != null && known != null && known.callId == call.callId && known.version > call.version) {
        return;
      }
      setState(() => _call = call);
    } catch (e, s) {
      if (e is! ApiException) errorReporter.report(e, stack: s, screen: 'callArea:current');
    }
  }

  void _onWsEvent(Map<String, dynamic> event) {
    if (event['chat_id'] != widget.chatId) return;
    switch (event['type']) {
      case 'call.ended':
        if (mounted) setState(() => _call = null);
      case 'call.updated':
        final call = CurrentCall.fromJson(event);
        final known = _call;
        if (known != null && known.callId == call.callId && known.version > call.version) return;
        if (mounted) setState(() => _call = call);
    }
  }

  void _onCallChanged() {
    if (mounted) setState(() {});
  }

  void _join() {
    final call = _call;
    if (call == null) return;
    unawaited(callProvider.joinOngoing(
        chat: widget.chatId, call: call.callId, name: widget.chatName, group: call.isGroup));
  }

  void _reportShown(bool shown) {
    if (shown == _reportedShown) return;
    _reportedShown = shown;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) widget.onShownChanged?.call(shown);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _buildStage(context);
    _reportShown(shown != null);
    return shown ?? const SizedBox.shrink();
  }

  Widget? _buildStage(BuildContext context) {
    final p = callProvider;
    final CallStageMode mode;
    final List<CallMember> roster;
    final bool isGroup;
    final call = _call;
    if (p.chatId == widget.chatId && p.isBusy) {
      mode = p.state == CallState.incoming ? CallStageMode.incoming : CallStageMode.inCall;
      roster = p.roster;
      isGroup = p.isGroup;
    } else if (call != null && call.members.any((m) => m.state.inCall)) {
      mode = CallStageMode.outside;
      roster = call.members;
      isGroup = call.isGroup;
    } else {
      return null;
    }
    final mq = MediaQuery.of(context);
    final base = mq.size.height - mq.padding.vertical;
    final height = _heightFor(base);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CallStage(
            mode: mode,
            roster: roster,
            isGroup: isGroup,
            onJoin: mode == CallStageMode.outside ? _join : null,
            onMemberMenu: (userId, position) => openCallMemberMenu(context, userId: userId, position: position),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _kResizeHandleHeight,
            child: ResizeHandle(
              axis: Axis.vertical,
              onDragStart: () => _dragStartHeight = height,
              onDrag: (shift) => setState(() {
                _areaShare = _shareFor(_dragStartHeight + shift, base);
              }),
            ),
          ),
        ],
      ),
    );
  }

  static double _heightFor(double base) => (base * _areaShare).clamp(_kAreaMinHeight, _maxHeight(base));

  static double _shareFor(double height, double base) =>
      base <= 0 ? _areaShare : height.clamp(_kAreaMinHeight, _maxHeight(base)) / base;

  static double _maxHeight(double base) => math.max(base * _kAreaMaxShare, _kAreaMinHeight);
}

Future<void> openCallChat(int chatId) async {
  final nav = navigatorKey.currentState;
  final context = navigatorKey.currentContext;
  if (nav == null || context == null) return;
  final route = chatViewing.routeOf(chatId);
  if (route != null && route.isActive) {
    nav.popUntil((r) => r == route);
    return;
  }
  try {
    await openChatById(context, chatId);
  } catch (e, s) {
    errorReporter.report(e, stack: s, screen: 'call:openChat');
  }
}
