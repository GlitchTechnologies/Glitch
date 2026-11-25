import 'package:flutter/material.dart';

import '../core/collectibles.dart';
import '../core/l10n.dart';
import '../core/own_account_open.dart';
import '../models/user.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/glitch_icons.dart';
import 'glitch_avatar.dart';
import 'glitch_plus_badge.dart';
import 'glitch_hover_row.dart';
import 'glitch_icon_button.dart';
import 'own_account_card.dart';
import 'theme_workspace.dart';
import 'voice_audio_menu.dart';
import 'voice_controls.dart';
import 'voice_panel.dart';

class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key});

  static const double height = 56;
  static const double _margin = 8;

  static const double _voiceHeight = VoiceDock.height + 1;

  static bool get _inVoice => voiceControls.where != VoiceWhere.none;

  static double get footprint => height + _margin + (_inVoice ? _voiceHeight : 0);

  static Listenable get changes => voiceControls.changes;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> with ThemeAwareState<AccountPanel> {
  Future<void> _showProfileCard(BuildContext rowContext) {
    final panelBox = context.findRenderObject() as RenderBox;
    final rowBox = rowContext.findRenderObject() as RenderBox;
    final rowRect = rowBox.localToGlobal(Offset.zero) & rowBox.size;
    final panelLeft = panelBox.localToGlobal(const Offset(AccountPanel._margin, 0)).dx;
    return showOwnAccountCard(
      rowContext,
      anchorRect: Rect.fromLTRB(panelLeft, rowRect.top, rowRect.right, rowRect.bottom),
      horizontalScreenMargin: AccountPanel._margin,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<User?>(
      valueListenable: authService.currentUserListenable,
      builder: (context, me, _) => ListenableBuilder(
        listenable: AccountPanel.changes,
        builder: (context, _) {
          final inVoice = AccountPanel._inVoice;
          final micOff = voiceControls.micOff;
          final deafOff = voiceControls.deafOff;
          return Container(
            height: AccountPanel.height + (inVoice ? AccountPanel._voiceHeight : 0),
            margin: const EdgeInsets.fromLTRB(AccountPanel._margin, 0, AccountPanel._margin, AccountPanel._margin),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: GlitchColors.bgCard,
              gradient: ThemeWorkspace.bottomLeftSurface(
                context,
                inset: const Offset(AccountPanel._margin, AccountPanel._margin),
              ),
              border: Border.all(color: ThemeWorkspace.outline(context, GlitchColors.borderCard)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                if (inVoice) ...[
                  VoiceDock(),
                  Container(height: 1, color: ThemeWorkspace.dividerColor(context)),
                ],
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 4, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (anchorContext) => GlitchHoverRow(
                              onTap: me == null ? null : () => _showProfileCard(anchorContext),
                              highlightInset: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                              builder: (active) => _identity(me, hovered: active),
                            ),
                          ),
                        ),
                        VoiceAudioSplitButton(
                          kind: VoiceAudioMenuKind.input,
                          icon: micOff ? Icons.mic_off_rounded : Icons.mic_rounded,
                          color: micOff ? GlitchColors.error : null,
                          tooltip: micOff ? context.s.tipUnmute : context.s.tipMute,
                          onTap: () => voiceControls.tapMic(context),
                        ),
                        VoiceAudioSplitButton(
                          kind: VoiceAudioMenuKind.output,
                          icon: deafOff ? Icons.headset_off_rounded : Icons.headset_rounded,
                          color: deafOff ? GlitchColors.error : null,
                          tooltip: deafOff ? context.s.tipUndeafen : context.s.tipDeafen,
                          onTap: () => voiceControls.tapDeafen(context),
                        ),
                        _PanelButton(
                          icon: GlitchIcons.settings,
                          tooltip: context.s.tipUserSettings,
                          onTap: () => openMySettings(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _identity(User? me, {required bool hovered}) {
    final name = me?.displayName ?? '';
    return Row(
      children: [
        GlitchAvatar(
          initials: GlitchAvatar.initialsFromName(name),
          size: 36,
          colorIndex: GlitchAvatar.colorFromNickname(me?.nickname ?? ''),
          imageUrl: me?.avatar != null ? api.mediaUrl(me!.avatar!) : null,
          avatarSizes: me?.avatarSizes,
          showOnline: me != null,
          presenceUserId: me?.id,
          // Своё украшение — оживает при наведении на строку
          // (core/collectibles.dart).
          decoration: me?.avatarDecoration,
          animateDecoration: animateInList(hovered),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserDisplayName(
                displayName: name,
                isGlitchPlus: me?.isGlitchPlus ?? false,
                ellipsis: true,
                badgeSize: 14,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
              ),
              if (me != null)
                Text(
                  '@${me.nickname}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: GlitchColors.textSecond),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  final String? tooltip;

  const _PanelButton({required this.icon, this.color, this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) => GlitchIconButton.panel(
        onTap: onTap,
        tooltip: tooltip,
        icon: Icon(icon, color: color),
      );
}
