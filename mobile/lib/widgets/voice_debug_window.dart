import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copy_actions.dart';
import '../core/l10n.dart';
import '../providers/call_provider.dart';
import '../providers/theme_provider.dart' show ThemeAwareState, themeProvider;
import '../providers/voice_channels.dart';
import '../services/desktop_popouts.dart';
import '../services/desktop_shell.dart' show DesktopPopout;
import '../services/voice_connection.dart';
import '../services/voice_debug.dart';
import '../theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'glitch_action_button.dart';
import 'glitch_select_field.dart';
import 'settings_page_parts.dart' show SettingsBlockTitle;
import 'settings_two_pane.dart' show SettingsTwoPane;
import 'settings_window.dart';
import 'voice_connection_menu.dart' show kVoicePingBad;
import 'voice_controls.dart';
import 'voice_graph.dart';


const double _kBadLossPct = 5;
const int _kBadJitterMs = 30;
const double _kBadConcealPct = 5;

const List<FontFeature> _kTabular = [FontFeature.tabularFigures()];

Future<void> openVoiceDebugWindow(BuildContext context) async {
  if (desktopPopouts.available) {
    _VoiceDebugPopout.instance.open();
    return;
  }
  await openAdaptiveWindow<void>(
    context,
    wideSize: const Size(980, 760),
    narrowBuilder: (_) => const _VoiceDebugWindow(wide: false),
    wideBuilder: (_) => const _VoiceDebugWindow(wide: true),
  );
}

class VoiceDebugPopoutView extends StatelessWidget {
  const VoiceDebugPopoutView({super.key});

  @override
  Widget build(BuildContext context) => const _VoiceDebugWindow(wide: true, popout: true);
}

enum _DebugSection { general, people, video }

abstract class _Feed extends ChangeNotifier {
  String place = '—';
  VoiceDebugSnapshot? snapshot;

  final Map<String, ({_Series ping, _Series voiceKbps})> history = {};
  final Map<String, ({_Series sentFps, _Series receivedFps})> videoHistory = {};

  String? person;
  String? video;

  void choosePerson(String id) {
    if (person == id) return;
    person = id;
    notifyListeners();
  }

  void chooseVideo(String id) {
    if (video == id) return;
    video = id;
    notifyListeners();
  }

  void accept(VoiceDebugSnapshot next, String where) {
    snapshot = next;
    place = where;
    final people = <String>{};
    for (final p in next.people) {
      people.add(p.id);
      final h = history.putIfAbsent(p.id, () => (ping: _Series(), voiceKbps: _Series()));
      h.ping.add(p.info?.rttMs);
      h.voiceKbps.add(p.micOn ? p.kbps : null);
    }
    history.removeWhere((id, _) => !people.contains(id));

    final videos = <String>{};
    for (final v in [...next.screens, ...next.cameras]) {
      videos.add(v.id);
      final h = videoHistory.putIfAbsent(v.id, () => (sentFps: _Series(), receivedFps: _Series()));
      h.sentFps.add(v.sender?.shownFps?.round());
      h.receivedFps.add(v.isLocal || !v.receiving ? null : v.fps?.round());
    }
    videoHistory.removeWhere((id, _) => !videos.contains(id));
    notifyListeners();
  }
}

const int _kGraphKeep = 120;

class _Series {
  List<int?> values = const [];

  void add(int? value) {
    final next = [...values, value];
    values = List.unmodifiable(next.length > _kGraphKeep ? next.sublist(next.length - _kGraphKeep) : next);
  }
}

class _LiveFeed extends _Feed {
  final VoiceDebug _debug = VoiceDebug();
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  _LiveFeed() {
    place = _currentPlace();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_collect()));
    unawaited(_collect());
  }

  Future<void> _collect() async {
    if (_busy) return;
    _busy = true;
    try {
      final next = await _debug.collect();
      if (_disposed || next == null) return;
      accept(next, _currentPlace());
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

class _PopoutFeed extends _Feed {
  StreamSubscription<Map<String, Object?>>? _sub;

  _PopoutFeed() {
    _sub = desktopPopouts.bodies.listen((body) {
      final next = VoiceDebugSnapshot.fromJson(body['snapshot']);
      if (next == null) return;
      final where = body['place'];
      accept(next, where is String ? where : place);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}

class _VoiceDebugPopout {
  _VoiceDebugPopout._() {
    desktopPopouts.readies.where((k) => k == _kind).listen((_) => _post());
    desktopPopouts.closings.where((k) => k == _kind).listen((_) => _stop());
    voiceConnection.addListener(_onVoice);
  }

  static final instance = _VoiceDebugPopout._();
  static const _kind = DesktopPopout.voiceDebug;

  _LiveFeed? _feed;

  void open() {
    if (voiceConnection.state == VoiceLinkState.idle) return;
    if (_feed == null) {
      _feed = _LiveFeed()..addListener(_post);
      themeProvider.addListener(_post);
    }
    desktopPopouts.open(_kind);
  }

  void _post() {
    final feed = _feed;
    final snapshot = feed?.snapshot;
    if (feed == null || snapshot == null) return;
    desktopPopouts.post(_kind, {'place': feed.place, 'snapshot': snapshot.toJson()});
  }

  void _onVoice() {
    if (_feed == null || voiceConnection.state != VoiceLinkState.idle) return;
    desktopPopouts.close(_kind);
    _stop();
  }

  void _stop() {
    final feed = _feed;
    if (feed == null) return;
    _feed = null;
    themeProvider.removeListener(_post);
    feed.removeListener(_post);
    feed.dispose();
  }
}

class _VoiceDebugWindow extends StatefulWidget {
  final bool wide;

  final bool popout;

  const _VoiceDebugWindow({required this.wide, this.popout = false});

  @override
  State<_VoiceDebugWindow> createState() => _VoiceDebugWindowState();
}

class _VoiceDebugWindowState extends State<_VoiceDebugWindow> with ThemeAwareState<_VoiceDebugWindow> {
  late final _Feed _feed = widget.popout ? _PopoutFeed() : _LiveFeed();

  late String _shownPlace = _feed.place;

  @override
  void initState() {
    super.initState();
    _feed.addListener(_onFeed);
    if (!widget.popout) voiceConnection.addListener(_onVoice);
  }

  @override
  void dispose() {
    if (!widget.popout) voiceConnection.removeListener(_onVoice);
    _feed.removeListener(_onFeed);
    _feed.dispose();
    super.dispose();
  }

  void _onFeed() {
    if (mounted && _feed.place != _shownPlace) setState(() => _shownPlace = _feed.place);
  }

  bool _closing = false;

  void _onVoice() {
    if (_closing || !mounted || voiceConnection.state != VoiceLinkState.idle) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    _closing = true;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r == route);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final spec = SettingsWindowSpec<_DebugSection>(
      title: s.voiceDebug,
      objectName: _feed.place,
      narrowHeader: _DebugHeader(feed: _feed, padding: const EdgeInsets.symmetric(vertical: 4)),
      wideMenuHeader: _DebugHeader(feed: _feed, padding: const EdgeInsets.fromLTRB(10, 8, 10, 14)),
      groups: [(s.voiceDebug, _DebugSection.values)],
      label: (section) => switch (section) {
        _DebugSection.general => s.voiceDebugGeneral,
        _DebugSection.people => s.voiceDebugPeople,
        _DebugSection.video => s.voiceDebugVideo,
      },
      icon: (section) => switch (section) {
        _DebugSection.general => Icons.info_outline_rounded,
        _DebugSection.people => Icons.people_outline_rounded,
        _DebugSection.video => Icons.videocam_outlined,
      },
      content: (section, {header, sectionKey, wide = false}) =>
          _DebugSectionView(key: sectionKey, feed: _feed, section: section, header: header),
    );
    return widget.wide
        ? SettingsWindowWide<_DebugSection>(spec: spec, windowed: true, closable: !widget.popout)
        : SettingsWindowNarrow<_DebugSection>(spec: spec);
  }
}

class _DebugHeader extends StatelessWidget {
  final _Feed feed;

  final EdgeInsets padding;

  const _DebugHeader({required this.feed, required this.padding});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: feed,
        builder: (context, _) {
          final s = context.s;
          final snapshot = feed.snapshot;
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feed.place,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                ),
                const SizedBox(height: 12),
                GlitchActionButton(
                  label: s.voiceDebugCopy,
                  soft: true,
                  compact: true,
                  onTap: snapshot == null
                      ? null
                      : () => unawaited(
                          copyToClipboard(context, _asText(context, feed.place, snapshot), s.messageCopied)),
                ),
              ],
            ),
          );
        },
      );
}


class _DebugSectionView extends StatelessWidget {
  final _Feed feed;
  final _DebugSection section;
  final Widget? header;

  const _DebugSectionView({super.key, required this.feed, required this.section, this.header});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: feed,
        builder: (context, _) {
          final snapshot = feed.snapshot;
          if (snapshot == null) {
            return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
          }
          final header = this.header;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, header != null ? SettingsTwoPane.windowTopPad : 18, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (header != null) ...[header, const SizedBox(height: 24)],
                ..._blocks(context, snapshot),
              ],
            ),
          );
        },
      );

  List<Widget> _blocks(BuildContext context, VoiceDebugSnapshot snapshot) {
    final s = context.s;
    return switch (section) {
      _DebugSection.general => [_GeneralGrid(items: _generalItems(context, feed.place, snapshot.general))],
      _DebugSection.people => [_PeopleView(feed: feed, snapshot: snapshot)],
      _DebugSection.video => [_VideoView(feed: feed, snapshot: snapshot)],
    };
  }
}

class _Block extends StatelessWidget {
  final String title;
  final Widget child;

  const _Block({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [SettingsBlockTitle(title), child],
        ),
      );
}

class _Empty extends StatelessWidget {
  final String text;

  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: GlitchColors.borderCard),
        ),
        child: Text(text, style: TextStyle(fontSize: 13, color: GlitchColors.textSecond)),
      );
}


const double _kTwoColumns = 560;

class _PeopleView extends StatelessWidget {
  final _Feed feed;
  final VoiceDebugSnapshot snapshot;

  const _PeopleView({required this.feed, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final people = snapshot.people;
    if (people.isEmpty) return const SizedBox.shrink();
    final person = people.firstWhere((p) => p.id == feed.person, orElse: () => people.first);
    final history = feed.history[person.id];
    final ping = person.info?.rttMs;
    final voiceKbps = person.micOn ? person.kbps : null;
    final names = {for (final p in people) p.id: _nameOf(context, p)};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: GlitchSelectField<String>(
              value: person.id,
              options: [for (final p in people) p.id],
              label: (id) => names[id] ?? id,
              onChanged: feed.choosePerson,
              expand: true,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _TwoColumns(children: [
          _GraphCard(
            title: s.voiceDebugGraphPing,
            value: ping == null ? null : s.voicePingMs(ping),
            bad: (ping ?? 0) >= kVoicePingBad,
            samples: history?.ping.values ?? const [],
            step: 100,
            badFrom: kVoicePingBad,
          ),
          _GraphCard(
            title: s.voiceDebugGraphVoice,
            value: voiceKbps == null ? null : s.voiceDebugKbps(voiceKbps),
            bad: false,
            samples: history?.voiceKbps.values ?? const [],
            step: 32,
          ),
        ]),
        const SizedBox(height: 28),
        _Block(title: s.voiceDebugSubLink, child: _ParamGrid(_paramsOf(_linkTable(context, [person])))),
        _Block(title: s.voiceDebugSubVoice, child: _ParamGrid(_paramsOf(_peopleTable(context, [person])))),
        _Block(title: s.voiceDebugSubDevice, child: _ParamGrid(_paramsOf(_deviceTable(context, [person])))),
      ],
    );
  }
}

class _VideoView extends StatelessWidget {
  final _Feed feed;
  final VoiceDebugSnapshot snapshot;

  const _VideoView({required this.feed, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final videos = [
      for (final v in snapshot.screens) (video: v, screen: true),
      for (final v in snapshot.cameras) (video: v, screen: false),
    ];
    if (videos.isEmpty) return _Empty(s.voiceDebugNoVideo);
    final chosen = videos.firstWhere((e) => e.video.id == feed.video, orElse: () => videos.first);
    final v = chosen.video;
    final history = feed.videoHistory[v.id];
    final sent = v.sender?.shownFps?.round();
    final received = v.isLocal || !v.receiving ? null : v.fps?.round();
    String title(({VoiceDebugVideo video, bool screen}) e) {
      final name = e.video.isLocal ? '${e.video.name} ${s.voiceDebugYou}' : e.video.name;
      return e.screen ? s.voiceDebugScreenOf(name) : s.voiceDebugCameraOf(name);
    }

    final titles = {for (final e in videos) e.video.id: title(e)};
    final params = _paramsOf(_videoTable(context, [v], screen: chosen.screen));
    final hasSound = chosen.screen && params.length > _kSenderColumns;
    final mineParams = params.skip(_kSenderColumns).toList();
    final senderParams = [
      ...params.take(_kSenderColumns),
      if (hasSound) mineParams.removeLast(),
    ];
    final captureParams = chosen.screen ? _paramsOf(_captureTable(context, [v]), omitMissing: true) : const <_Param>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: GlitchSelectField<String>(
              value: v.id,
              options: [for (final e in videos) e.video.id],
              label: (id) => titles[id] ?? id,
              onChanged: feed.chooseVideo,
              expand: true,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _TwoColumns(children: [
          _GraphCard(
            title: s.voiceDebugSubSender,
            value: sent == null ? null : s.voiceDebugFps(sent),
            bad: false,
            samples: history?.sentFps.values ?? const [],
            step: 10,
          ),
          _GraphCard(
            title: s.voiceDebugSubMine,
            value: received == null ? null : s.voiceDebugFps(received),
            bad: false,
            samples: history?.receivedFps.values ?? const [],
            step: 10,
          ),
        ]),
        const SizedBox(height: 28),
        _Block(title: s.voiceDebugSubSender, child: _ParamGrid(senderParams)),
        captureParams.isEmpty
            ? const SizedBox.shrink()
            : _Block(title: s.voiceDebugCaptureDetails, child: _ParamGrid(captureParams, wrapLabels: true)),
        _Block(title: s.voiceDebugSubMine, child: _ParamGrid(mineParams)),
      ],
    );
  }
}

class _TwoColumns extends StatelessWidget {
  final List<Widget> children;

  const _TwoColumns({required this.children});

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => box.maxWidth >= _kTwoColumns
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(child: children[i]),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(height: _gap),
                    children[i],
                  ],
                ],
              ),
      );
}

class _GraphCard extends StatelessWidget {
  final String title;

  final String? value;
  final bool bad;
  final List<int?> samples;
  final int step;
  final int? badFrom;

  const _GraphCard({
    required this.title,
    required this.value,
    required this.bad,
    required this.samples,
    required this.step,
    this.badFrom,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: GlitchColors.borderCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  value ?? '—',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: _kTabular,
                    color: value == null
                        ? GlitchColors.textHint
                        : bad
                            ? GlitchColors.error
                            : GlitchColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: VoiceGraph(samples: samples, keep: _kGraphKeep, step: step, badFrom: badFrom),
            ),
          ],
        ),
      );
}

typedef _Param = ({String label, _Cell cell});

List<_Param> _paramsOf(_TableData t, {bool omitMissing = false}) {
  if (t.rows.isEmpty) return const [];
  final row = t.rows.first;
  return [
    for (var i = 1; i < row.length && i < t.header.length; i++)
      if (!omitMissing || row[i] != _Cell.none) (label: t.header[i], cell: row[i]),
  ];
}

class _ParamGrid extends StatelessWidget {
  final List<_Param> params;
  final bool wrapLabels;

  const _ParamGrid(this.params, {this.wrapLabels = false});

  static const double _rowHeight = 40;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final columns = box.maxWidth >= _kTwoColumns ? 2 : 1;
          final rows = <List<_Param>>[
            for (var i = 0; i < params.length; i += columns)
              params.sublist(i, i + columns > params.length ? params.length : i + columns),
          ];
          final line = BorderSide(color: GlitchColors.borderCard);
          return Container(
            decoration: BoxDecoration(
              color: GlitchColors.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.fromBorderSide(line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var r = 0; r < rows.length; r++)
                  Container(
                    height: _rowHeight,
                    decoration: BoxDecoration(border: r == 0 ? null : Border(top: line)),
                    child: Row(
                      children: [
                        for (var c = 0; c < columns; c++) ...[
                          if (c > 0) VerticalDivider(width: 1, thickness: 1, color: GlitchColors.borderCard),
                          Expanded(
                            child: c < rows[r].length
                                ? _ParamCell(rows[r][c], wrapLabel: wrapLabels)
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

class _ParamCell extends StatelessWidget {
  final _Param param;
  final bool wrapLabel;

  const _ParamCell(this.param, {required this.wrapLabel});

  @override
  Widget build(BuildContext context) {
    final cell = param.cell;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              param.label,
              maxLines: wrapLabel ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              cell.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: _kTabular,
                color: cell.bad
                    ? GlitchColors.error
                    : cell.dim
                        ? GlitchColors.textHint
                        : GlitchColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


typedef _Item = ({String label, String value, bool bad});

List<_Item> _generalItems(BuildContext context, String place, VoiceDebugGeneral g) {
  final s = context.s;
  return [
    (label: s.voiceDebugPlace, value: place, bad: false),
    (label: s.voiceDebugServer, value: _server(g), bad: false),
  ];
}

String _server(VoiceDebugGeneral g) {
  final version = g.serverVersion ?? '';
  final region = g.serverRegion;
  final name = region == null || region.isEmpty ? 'LiveKit' : region;
  return version.isEmpty ? name : '$name $version';
}

String _currentPlace() => switch (voiceControls.where) {
      VoiceWhere.call => callProvider.peerName,
      VoiceWhere.channel => voiceChannels.roomName,
      VoiceWhere.none => '—',
    };

String _duration(int? seconds) {
  if (seconds == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  final h = seconds ~/ 3600;
  final m = seconds ~/ 60 % 60;
  final sec = seconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

String _route(BuildContext context, VoicePeerInfo i) {
  final s = context.s;
  final protocol = i.protocol?.toUpperCase();
  if (i.candidateType == null && protocol == null) return '—';
  final relay = i.candidateType == 'relay';
  final how = relay ? s.voiceDebugRouteRelay : s.voiceDebugRouteDirect;
  final relayProtocol = i.relayProtocol;
  final via = relay && relayProtocol != null ? ' (${relayProtocol.toUpperCase()})' : '';
  return [if (protocol != null) protocol, '$how$via'].join(' · ');
}

class _GeneralGrid extends StatelessWidget {
  final List<_Item> items;

  const _GeneralGrid({required this.items});

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final columns = box.maxWidth >= 720 ? 4 : (box.maxWidth >= 420 ? 3 : 2);
          final width = ((box.maxWidth - _gap * (columns - 1)) / columns).floorToDouble();
          return Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [
              for (final item in items)
                Container(
                  width: width,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: GlitchColors.bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: GlitchColors.borderCard),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: GlitchColors.textSecond),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: _kTabular,
                          color: item.bad ? GlitchColors.error : GlitchColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}


class _Cell {
  final String text;
  final bool bad;
  final bool dim;

  const _Cell(this.text, {this.bad = false, this.dim = false});

  static const none = _Cell('—', dim: true);
}

typedef _TableData = ({List<String> header, List<List<_Cell>> rows});

String _pct(double v) => v < 10 ? v.toStringAsFixed(1) : v.round().toString();

_Cell _num(int? v, {bool bad = false}) => v == null ? _Cell.none : _Cell('$v', bad: bad);

_Cell _percent(double? v, double badFrom) => v == null ? _Cell.none : _Cell('${_pct(v)} %', bad: v >= badFrom);

String _nameOf(BuildContext context, VoiceDebugAudio p) => p.isLocal ? '${p.name} ${context.s.voiceDebugYou}' : p.name;

_TableData _linkTable(BuildContext context, List<VoiceDebugAudio> people) {
  final s = context.s;
  return (
    header: [
      s.voiceDebugColName,
      s.voiceDebugColLink,
      s.voiceDebugRoute,
      s.voiceDebugColPing,
      s.voiceDebugColPingAvg,
      s.voiceDebugReconnects,
      s.voiceDebugInVoice,
      s.voiceDebugColSend,
      s.voiceDebugColRecv,
    ],
    rows: [
      for (final p in people)
        [
          _Cell(_nameOf(context, p)),
          _quality(context, p.quality),
          ...switch (p.info) {
            null => [_Cell(s.voiceDebugNoAnswer, dim: true), for (var i = 0; i < 6; i++) _Cell.none],
            final VoicePeerInfo i => [
                _Cell(_route(context, i), bad: i.candidateType == 'relay'),
                _num(i.rttMs, bad: (i.rttMs ?? 0) >= kVoicePingBad),
                _num(i.avgRttMs, bad: (i.avgRttMs ?? 0) >= kVoicePingBad),
                _num(i.reconnects, bad: i.reconnects > 0),
                _Cell(_duration(i.inVoiceSeconds)),
                _num(i.sendKbps),
                _num(i.recvKbps),
              ],
          },
        ],
    ],
  );
}

_TableData _deviceTable(BuildContext context, List<VoiceDebugAudio> people) {
  final s = context.s;
  String device(String? label) => label ?? s.voiceDebugDefaultDevice;
  return (
    header: [
      s.voiceDebugColName,
      s.voiceDebugNoise,
      s.voiceDebugInput,
      s.voiceDebugOutput,
      s.voiceDebugDevice,
      s.voiceDebugApp,
    ],
    rows: [
      for (final p in people)
        [
          _Cell(_nameOf(context, p)),
          ...switch (p.info) {
            null => [_Cell(s.voiceDebugNoAnswer, dim: true), for (var i = 0; i < 4; i++) _Cell.none],
            final VoicePeerInfo i => [
                _Cell(switch (i.noise) {
                  'on' => s.voiceDebugOn,
                  'off' => s.voiceDebugOff,
                  _ => s.voiceDebugUnavailable,
                }),
                _Cell(device(i.mic)),
                _Cell(device(i.speaker)),
                _Cell(i.device),
                _Cell(i.app),
              ],
          },
        ],
    ],
  );
}

_TableData _peopleTable(BuildContext context, List<VoiceDebugAudio> people) {
  final s = context.s;
  return (
    header: [
      s.voiceDebugColName,
      s.voiceDebugColCodec,
      s.voiceDebugColKbps,
      s.voiceDebugColLoss,
      s.voiceDebugColJitter,
      s.voiceDebugColDelay,
      s.voiceDebugColConceal,
    ],
    rows: [
      for (final p in people)
        [
          _Cell(_nameOf(context, p)),
          if (!p.micOn) ...[
            _Cell(s.voiceDebugMicOff, dim: true),
            _Cell.none,
            _Cell.none,
            _Cell.none,
            _Cell.none,
            _Cell.none,
          ] else ...[
            p.codec == null ? _Cell.none : _Cell(p.codec!),
            _num(p.kbps),
            _percent(p.lossPct, _kBadLossPct),
            _num(p.jitterMs, bad: (p.jitterMs ?? 0) >= _kBadJitterMs),
            _num(p.delayMs, bad: (p.delayMs ?? 0) >= kVoicePingBad),
            p.isLocal ? _Cell.none : _percent(p.concealPct, _kBadConcealPct),
          ],
        ],
    ],
  );
}

_Cell _quality(BuildContext context, VoiceLinkQuality q) {
  final s = context.s;
  return switch (q) {
    VoiceLinkQuality.excellent => _Cell(s.voiceDebugQualityExcellent),
    VoiceLinkQuality.good => _Cell(s.voiceDebugQualityGood),
    VoiceLinkQuality.poor => _Cell(s.voiceDebugQualityPoor, bad: true),
    VoiceLinkQuality.lost => _Cell(s.voiceDebugQualityLost, bad: true),
    VoiceLinkQuality.unknown => _Cell.none,
  };
}

const int _kSenderColumns = 7;

_TableData _videoTable(BuildContext context, List<VoiceDebugVideo> videos, {required bool screen}) {
  final s = context.s;
  _Cell fps(double? v) => v == null ? _Cell.none : _Cell(v.round().toString());
  return (
    header: [
      s.voiceDebugColName,
      s.voiceDebugColCaptured,
      s.voiceDebugColEncoded,
      s.voiceDebugColEncoder,
      s.voiceDebugColLimit,
      s.voiceDebugColLayers,
      s.voiceDebugColTarget,
      s.voiceDebugColChannel,
      s.voiceDebugColReceived,
      s.voiceDebugColSize,
      s.voiceDebugColKbps,
      s.voiceDebugColCodec,
      s.voiceDebugColDecoder,
      s.voiceDebugColDropped,
      s.voiceDebugColFreezes,
      s.voiceDebugColLoss,
      if (screen) s.voiceDebugColSound,
    ],
    rows: [
      for (final v in videos)
        [
          _Cell(v.isLocal ? '${v.name} ${s.voiceDebugYou}' : v.name),
          ...switch (v.sender) {
            final VoiceVideoSender o => [
                fps(o.captureFps),
                fps(o.fps),
                _coder(context, o.coder, o.hardware),
                _limit(context, o.limit),
                _num(o.layers),
                _num(o.targetKbps),
                _num(o.channelKbps),
              ],
            null when !v.answered => [_Cell(s.voiceDebugNoAnswer, dim: true), for (var i = 0; i < 6; i++) _Cell.none],
            null => [for (var i = 0; i < 7; i++) _Cell.none],
          },
          if (!v.receiving) ...[
            _Cell(s.voiceDebugNotReceiving, dim: true),
            for (var i = 0; i < 7; i++) _Cell.none,
          ] else ...[
            v.isLocal ? _Cell.none : fps(v.fps),
            v.width == null || v.height == null ? _Cell.none : _Cell('${v.width}×${v.height}'),
            _num(v.kbps),
            v.codec == null ? _Cell.none : _Cell(v.codec!),
            _coder(context, v.coder, v.hardware),
            _num(v.framesDropped),
            _num(v.freezes, bad: (v.freezes ?? 0) > 0),
            _percent(v.lossPct, _kBadLossPct),
          ],
          if (screen)
            v.withAudio == null
                ? _Cell.none
                : _Cell(v.withAudio! ? s.voiceDebugYes : s.voiceDebugNo),
        ],
    ],
  );
}

_TableData _captureTable(BuildContext context, List<VoiceDebugVideo> videos) {
  final s = context.s;
  return (
    header: [
      s.voiceDebugColName,
      s.voiceDebugCaptureBackend,
      s.voiceDebugCaptureMode,
      s.voiceDebugCaptureAudio,
      s.voiceDebugCaptureConfigured,
      s.voiceDebugCaptureInputFps,
      s.voiceDebugCapturePreparedFps,
      s.voiceDebugCaptureSentFps,
      s.voiceDebugColCaptured,
      s.voiceDebugColEncoded,
      s.voiceDebugCaptureAttempts,
      s.voiceDebugCaptureLowest,
      s.voiceDebugCaptureAcquire,
      s.voiceDebugCapturePrepare,
      s.voiceDebugCaptureInterval,
      s.voiceDebugCaptureAvgPrepare,
      s.voiceDebugCaptureFrameGap,
      s.voiceDebugCapturePaced,
      s.voiceDebugCaptureNoSlot,
      s.voiceDebugCaptureReplaced,
      s.voiceDebugCaptureSendDropped,
      s.voiceDebugCaptureEncode,
    ],
    rows: [
      for (final v in videos)
        if (v.sender?.capture case final ScreenDebugDetails capture)
          _captureRow(context, v, capture),
    ],
  );
}

List<_Cell> _captureRow(BuildContext context, VoiceDebugVideo video, ScreenDebugDetails capture) {
  final s = context.s;
  final timings = capture.timings;
  final source = timings?.source;
  return [
    _Cell(video.isLocal ? '${video.name} ${s.voiceDebugYou}' : video.name),
    switch (source?.backend) {
      'dxgi' => _Cell('DXGI · BGRA · ${s.voiceDebugGpu}'),
      'chromium' => const _Cell('Chromium'),
      _ => _Cell.none,
    },
    switch (source?.mode) {
      'installed' => _Cell(s.voiceDebugCaptureModeInstalled),
      'dev' => _Cell(s.voiceDebugCaptureModeDev),
      _ => _Cell.none,
    },
    switch (source?.audio) {
      'wasapi' => const _Cell('WASAPI'),
      'off' => _Cell(s.voiceDebugNo),
      'unavailable' => _Cell(s.voiceDebugUnavailable),
      _ when source?.backend == 'chromium' && video.withAudio == true => const _Cell('Chromium'),
      _ when video.withAudio == false => _Cell(s.voiceDebugNo),
      _ => _Cell.none,
    },
    _num(capture.configuredFps),
    _num(source?.inputFps),
    _num(source?.preparedFps),
    _num(source?.sentFps),
    _num(video.sender?.captureFps?.round()),
    _num(video.sender?.fps?.round()),
    _num(timings?.attemptsPerSecond),
    _num(capture.lowestFps),
    _num(timings?.acquireMs),
    _num(timings?.prepareMs),
    _num(timings?.intervalMs),
    _num(source?.avgPrepareMs),
    _num(source?.maxFrameGapMs),
    _num(source?.pacedOut),
    _num(source?.noSlot),
    _num(source?.replaced),
    _num(source?.sendDropped),
    capture.encodeMs == null ? _Cell.none : _Cell(capture.encodeMs!.toStringAsFixed(1)),
  ];
}

_Cell _coder(BuildContext context, String? coder, bool? hardware) {
  final s = context.s;
  final parts = [
    if (coder != null) coder,
    if (hardware != null) hardware ? s.voiceDebugGpu : s.voiceDebugCpu,
  ];
  return parts.isEmpty ? _Cell.none : _Cell(parts.join(' · '));
}

_Cell _limit(BuildContext context, String? limit) {
  final s = context.s;
  return switch (limit) {
    null => _Cell.none,
    'none' => _Cell(s.voiceDebugLimitNone),
    'bandwidth' => _Cell(s.voiceDebugLimitBandwidth, bad: true),
    'cpu' => _Cell(s.voiceDebugLimitCpu, bad: true),
    _ => _Cell(s.voiceDebugLimitOther, bad: true),
  };
}


String _asText(BuildContext context, String place, VoiceDebugSnapshot snap) {
  final s = context.s;
  final out = StringBuffer('Glitch — ${s.voiceDebug}\n');
  void section(String title) => out.write('\n[$title]\n');
  void table(_TableData t, {bool omitMissing = false}) {
    for (final row in t.rows) {
      out.writeln([
        for (var i = 0; i < row.length; i++)
          if (!omitMissing || row[i] != _Cell.none) '${t.header[i]}: ${row[i].text}',
      ].join(' | '));
    }
  }

  section(s.voiceDebugGeneral);
  for (final item in _generalItems(context, place, snap.general)) {
    out.writeln('${item.label}: ${item.value}');
  }
  section(s.voiceDebugPeople);
  table(_linkTable(context, snap.people));
  table(_peopleTable(context, snap.people));
  table(_deviceTable(context, snap.people));
  section(s.voiceDebugScreens);
  if (snap.screens.isEmpty) {
    out.writeln(s.voiceDebugNoScreens);
  } else {
    table(_videoTable(context, snap.screens, screen: true));
  }
  final capture = _captureTable(context, snap.screens);
  if (capture.rows.isNotEmpty) {
    section(s.voiceDebugCaptureDetails);
    table(capture, omitMissing: true);
  }
  section(s.voiceDebugCameras);
  if (snap.cameras.isEmpty) {
    out.writeln(s.voiceDebugNoCameras);
  } else {
    table(_videoTable(context, snap.cameras, screen: false));
  }
  return out.toString();
}
