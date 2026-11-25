import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/search.dart';
import '../providers/theme_provider.dart' show ThemeAwareState;
import '../theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'glitch_icon_button.dart';
import 'place_picker.dart';

Future<SearchHit?> showSearchWindow(BuildContext context) => openAdaptiveWindow<SearchHit>(
      context,
      wideSize: const Size(570, 480),
      wideBuilder: (_) => const _SearchWindow(windowed: true),
      narrowBuilder: (_) => const _SearchWindow(windowed: false),
    );

class _SearchWindow extends StatefulWidget {
  final bool windowed;

  const _SearchWindow({required this.windowed});

  @override
  State<_SearchWindow> createState() => _SearchWindowState();
}

// ThemeAwareState: цвета берутся при сборке — смена темы перекрашивает окно.
class _SearchWindowState extends State<_SearchWindow> with ThemeAwareState<_SearchWindow> {
  @override
  Widget build(BuildContext context) {
    final windowed = widget.windowed;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PlacePicker(
            hint: context.s.searchWindowHint,
            fieldHeight: 48,
            fieldPadding: EdgeInsets.fromLTRB(windowed ? 20 : 4, windowed ? 20 : 8, 20, 12),
            fieldLeading: windowed
                ? null
                : GlitchIconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: GlitchColors.textPrimary),
                    onTap: () => Navigator.of(context).pop(),
                  ),
            onChoose: (hit) => Navigator.of(context).pop<SearchHit>(hit),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Text(
            context.s.searchTip,
            style: TextStyle(fontSize: 12.5, height: 1.35, color: GlitchColors.textPrimary),
          ),
        ),
      ],
    );
    if (windowed) return Material(color: GlitchColors.bg, child: body);
    return Scaffold(backgroundColor: GlitchColors.bg, body: SafeArea(child: body));
  }
}
