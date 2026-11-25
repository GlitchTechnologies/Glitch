import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import 'chat_preview_line.dart';
import 'glitch_icon_button.dart';

const double _kBannerRowHeight = 48;

class PinnedBanner extends StatelessWidget {
  final String title;
  final MessagePreview preview;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;

  const PinnedBanner({
    super.key,
    required this.title,
    required this.preview,
    required this.onTap,
    this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GlitchColors.bg,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: GlitchColors.border)),
          ),
          padding: const EdgeInsets.only(left: 14, right: 4),
          child: SizedBox(
            height: _kBannerRowHeight,
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 32,
                  decoration: BoxDecoration(
                    color: GlitchColors.accentBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GlitchColors.accentBlue),
                      ),
                      const SizedBox(height: 1),
                      ChatPreviewLine(
                        preview: preview,
                        style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                if (onUnpin != null)
                  GlitchIconButton(
                    icon: Icon(Icons.close_rounded, size: 20),
                    onTap: onUnpin,
                  )
                else
                  const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
