import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ColumnWidth {
  final String id;
  final double initial;
  final double min;
  final double max;

  const ColumnWidth({
    required this.id,
    required this.initial,
    required this.min,
    required this.max,
  });

  double clamp(double width) => width.clamp(min, max).toDouble();
}

const double kMinCenterWidth = 400;

const double kDetailsPanelWidth = 418;

class ShellColumns {
  final double list;

  final double details;

  const ShellColumns(this.list, this.details);

  factory ShellColumns.fit({
    required double space,
    required ColumnWidth list,
    required double? details,
  }) {
    var l = columnWidths.of(list);
    var r = details ?? 0.0;
    if (l + r + kMinCenterWidth > space) r = 0;
    final over = l + r + kMinCenterWidth - space;
    if (over > 0) {
      l -= (l - list.min).clamp(0.0, over).toDouble();
    }
    return ShellColumns(l, r);
  }
}

class ColumnWidths extends ChangeNotifier {
  final Map<String, double> _chosen = {};

  static String _key(String id) => 'column_width_${id}_v1';

  double of(ColumnWidth column) => column.clamp(_chosen[column.id] ?? column.initial);

  void set(ColumnWidth column, double width) {
    final value = column.clamp(width);
    if (_chosen[column.id] == value) return;
    _chosen[column.id] = value;
    notifyListeners();
  }

  Future<void> save(ColumnWidth column) async {
    final value = _chosen[column.id];
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key(column.id), value);
  }

  Future<void> reset(ColumnWidth column) async {
    if (_chosen.remove(column.id) != null) notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(column.id));
  }

  static const _retired = ['details', 'dm_profile', 'roster'];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final id in _retired) {
      if (prefs.containsKey(_key(id))) await prefs.remove(_key(id));
    }
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('column_width_') || !key.endsWith('_v1')) continue;
      final value = prefs.getDouble(key);
      if (value == null) continue;
      _chosen[key.substring('column_width_'.length, key.length - '_v1'.length)] = value;
    }
  }
}

final columnWidths = ColumnWidths();
