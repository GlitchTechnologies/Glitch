import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/copy_actions.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../services/media_actions_web.dart' if (dart.library.io) '../services/media_actions_native.dart';
import '../theme/app_theme.dart';
import 'glitch_menu.dart';
import 'glitch_toast.dart';

void showMediaContextMenu(
  BuildContext context, {
  required Offset position,
  required String url,
  required bool isVideo,
  required VoidCallback onSaveToDownloads,
  Map<String, String> headers = const {},
}) {
  final s = context.s;
  showGlitchContextMenuAt<String>(
    context,
    position,
    [
      if (hasBrowserTabs)
        _item(Icons.open_in_new_rounded, s.mediaOpenInNewTab, 'tab'),

      // «Сохранить как…» — только если браузер УМЕЕТ показать окно выбора
      // папки. Это File System Access API: он есть в Chrome и Edge, но не в
      // Firefox и Safari (см. canSaveMediaAs). Пункт, который у половины людей
      // молча ничего не делает, хуже отсутствующего.
      if (canSaveMediaAs)
        _item(
          Icons.save_alt_rounded,
          isVideo ? s.mediaSaveVideoAs : s.mediaSaveImageAs,
          'saveAs',
        ),

      _item(
        Icons.download_rounded,
        saveShowsDialog
            ? (isVideo ? s.mediaSaveVideoAs : s.mediaSaveImageAs)
            : (canSaveToGallery ? s.save : s.mediaSaveToDownloads),
        'save',
      ),

      if (canCopyImage && !isVideo)
        _item(Icons.image_outlined, s.mediaCopyImage, 'copyImage'),

      _item(Icons.link_rounded, s.mediaCopyLink, 'link'),
    ],
    (value) async {
      switch (value) {
        case 'tab':
          {
            final uri = Uri.tryParse(url);
            if (uri != null) await launchUrl(uri);
          }
        case 'saveAs':
          {
            try {
              await saveMediaAs(url: url, isVideo: isVideo, headers: headers);
            } catch (_) {
              if (context.mounted) GlitchToast.show(context, s.saveFailed);
            }
          }
        case 'save':
          onSaveToDownloads();
        case 'copyImage':
          {
            try {
              await copyImageToClipboard(url: url, headers: headers);
              if (context.mounted) {
                GlitchToast.show(context, s.mediaImageCopied, type: ToastType.success);
              }
            } catch (_) {
              if (context.mounted) GlitchToast.show(context, s.mediaCopyImageFailed);
            }
          }
        case 'link':
          await copyToClipboard(context, url, s.linkCopied);
      }
    },
  );
}

GlitchMenuItem<String> _item(
  IconData icon,
  String label,
  String value,
) {
  return GlitchMenuItem<String>(
    value: value,
    child: Row(children: [
      Icon(icon, color: GlitchColors.textPrimary, size: 18),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
    ]),
  );
}
