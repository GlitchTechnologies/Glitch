import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/chat.dart';
import '../models/invite.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_icon_button.dart';
import 'server_members_section.dart' show InvitesSection;

class GroupInvitesScreen extends StatelessWidget {
  final Chat chat;

  const GroupInvitesScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 16, 0),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
                    onTap: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(context.s.invitesTitle,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InvitesSection(
                target: InviteTarget.group(chat.id, chat.name ?? context.s.group),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
