import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/shell_controller.dart' show ShellPlace;
import '../widgets/voice_controls.dart' show VoiceWhere;

class StageViewing extends ChangeNotifier {
  final Set<_StageOnScreenState> _marks = {};
  bool _notifyScheduled = false;

  bool isVisible(VoiceWhere where) => where != VoiceWhere.none && _marks.any((m) => m.where == where && m.visible);

  void _changed() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

final stageViewing = StageViewing();

class StageOnScreen extends StatefulWidget {
  final VoiceWhere? where;
  final Widget child;

  const StageOnScreen({super.key, required this.where, required this.child});

  @override
  State<StageOnScreen> createState() => _StageOnScreenState();
}

class _StageOnScreenState extends State<StageOnScreen> {
  ValueListenable<bool>? _ticker;
  bool _levelVisible = true;

  VoiceWhere? get where => widget.where;

  bool get visible => _levelVisible && (_ticker?.value ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _levelVisible = ShellPlace.visibleForBuild(context);
    final ticker = TickerMode.getNotifier(context);
    if (ticker != _ticker) {
      _ticker?.removeListener(stageViewing._changed);
      _ticker = ticker..addListener(stageViewing._changed);
    }
    stageViewing._marks.add(this);
    stageViewing._changed();
  }

  @override
  void didUpdateWidget(StageOnScreen old) {
    super.didUpdateWidget(old);
    if (old.where != widget.where) stageViewing._changed();
  }

  @override
  void dispose() {
    _ticker?.removeListener(stageViewing._changed);
    stageViewing._marks.remove(this);
    stageViewing._changed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
