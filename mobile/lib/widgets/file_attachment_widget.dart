import '../services/file_open_result.dart';
import '../services/file_open_web.dart' if (dart.library.io) '../services/file_open_native.dart';
import 'package:flutter/material.dart';
import '../models/file_audio.dart';
import 'audio_file_player.dart';
import 'glitch_icon_button.dart';
import '../services/api_service.dart';
import '../core/l10n.dart';
import '../core/file_size.dart';
import '../theme/app_theme.dart';
import 'glitch_toast.dart';
import 'file_badge.dart';

/// [url]      — полный URL для скачивания (уже прошедший через api.mediaUrl)
/// [fileName] — имя файла для отображения и сохранения
/// [fileSize] — размер в байтах (опционально)
class FileAttachmentWidget extends StatefulWidget {
  final String url;
  final String fileName;
  final int? fileSize;
  final FileAudio? audio;

  const FileAttachmentWidget({
    super.key,
    required this.url,
    required this.fileName,
    this.fileSize,
    this.audio,
  });

  @override
  State<FileAttachmentWidget> createState() => _FileAttachmentWidgetState();
}

class _FileAttachmentWidgetState extends State<FileAttachmentWidget> {
  bool _loading = false;

  Future<void> _download() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await downloadAndOpenFile(
        url: widget.url,
        fileName: widget.fileName,
        headers: api.headersFor(widget.url),
      );
      if (!mounted) return;
      if (result == FileOpenResult.failed) {
        GlitchToast.show(context, context.s.fileDownloadError);
      } else if (result == FileOpenResult.noApp) {
        GlitchToast.show(context, context.s.fileNoApp, type: ToastType.info);
      }
    } catch (_) {
      if (mounted) {
        GlitchToast.show(context, context.s.fileDownloadError);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.fileName;
    final textColor = GlitchColors.textPrimary;
    final hintColor = GlitchColors.textHint;
    final iconColor = GlitchColors.textPrimary;

    return Column(mainAxisSize: MainAxisSize.min, children: [Row(
      children: [
        FileBadge(name),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: textColor),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.fileSize != null)
                Text(
                  formatBytes(context.s, widget.fileSize!),
                  style: TextStyle(fontSize: 12, color: hintColor),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _loading
              ? SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: iconColor))
              : GlitchIconButton.panel(icon: Icon(Icons.download_rounded, color: iconColor, size: 22), onTap: _download),
      ],
    ),
      if (FileAudio.canTry(name, widget.audio))
        AudioFilePlayer(url: widget.url, audio: widget.audio),
    ]);
  }
}
