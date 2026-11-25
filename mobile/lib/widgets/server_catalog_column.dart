import 'package:flutter/material.dart';
import '../core/adaptive_open.dart';
import '../core/l10n.dart';
import '../core/shell_controller.dart';
import '../providers/theme_provider.dart' show ThemeAwareState;
import '../screens/server_catalog_screen.dart';
import '../theme/app_theme.dart';
import 'glitch_hover_row.dart';

class ServerCatalogColumn extends StatefulWidget {
  const ServerCatalogColumn({super.key});

  @override
  State<ServerCatalogColumn> createState() => _ServerCatalogColumnState();
}

class _ServerCatalogColumnState extends State<ServerCatalogColumn>
    with ThemeAwareState<ServerCatalogColumn> {
  bool _ensureScheduled = false;

  @override
  void initState() {
    super.initState();
    shellController.addListener(_onShellChange);
    _scheduleEnsure();
  }

  @override
  void dispose() {
    shellController.removeListener(_onShellChange);
    super.dispose();
  }

  void _onShellChange() {
    if (!mounted) return;
    setState(() {});
    _scheduleEnsure();
  }

  void _scheduleEnsure() {
    if (_ensureScheduled) return;
    _ensureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureScheduled = false;
      _ensurePageOpen();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _ensurePageOpen() {
    if (!mounted) return;
    if (ShellPlace.slotOf(context) != ShellSlot.list) return;
    if (shellController.mainScope == catalogScope) return;
    _open(CatalogSection.servers);
  }

  void _open(CatalogSection section) {
    openAdaptive(
      context,
      builder: (_) => catalogSectionScreen(section),
      slotKey: catalogSlotKey(section),
      scope: catalogScope,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GlitchColors.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: GlitchColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: Text(
                context.s.catalogTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: GlitchColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _item(CatalogSection.servers, Icons.public_rounded, context.s.catalogServers),
            _item(CatalogSection.events, Icons.event_rounded, context.s.catalogEvents),
          ],
        ),
      ),
    );
  }

  Widget _item(CatalogSection section, IconData icon, String label) {
    return GlitchHoverRow(
      onTap: () => _open(section),
      selected: shellController.mainKey == catalogSlotKey(section),
      builder: (active) {
        final color = active ? GlitchColors.textPrimary : GlitchColors.textNavIdle;
        return Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: color),
              ),
            ),
          ],
        );
      },
    );
  }
}
