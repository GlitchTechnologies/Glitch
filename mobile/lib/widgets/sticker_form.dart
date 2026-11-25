import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/sticker_limits.dart';
import '../models/sticker.dart';
import '../services/api_service.dart';
import '../services/avatar_service.dart' show mimeFromFileName, pickStickerImage;
import '../theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'content_picker.dart';
import 'glitch_action_button.dart';
import 'glitch_bar_buttons.dart';
import 'glitch_form_field.dart';
import 'glitch_toast.dart';
import 'local_image_web.dart' if (dart.library.io) 'local_image_native.dart';
import 'reaction_emoji.dart';
import 'sticker_view.dart';

Future<Sticker?> openStickerForm(BuildContext context, {required int serverId, Sticker? sticker}) =>
    showAdaptiveSheet<Sticker>(
      context,
      title: sticker == null ? context.s.stickerAdd : context.s.stickerEdit,
      bodyBuilder: (ctx, _) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: _StickerForm(
          serverId: serverId,
          sticker: sticker,
          onDone: (saved) => Navigator.pop(ctx, saved),
        ),
      ),
    );

class _StickerForm extends StatefulWidget {
  final int serverId;
  final Sticker? sticker;
  final ValueChanged<Sticker> onDone;

  const _StickerForm({required this.serverId, required this.sticker, required this.onDone});

  @override
  State<_StickerForm> createState() => _StickerFormState();
}

class _StickerFormState extends State<_StickerForm> {
  late final _name = TextEditingController(text: widget.sticker?.name ?? '');
  late final _description = TextEditingController(text: widget.sticker?.description ?? '');
  late String? _emoji = widget.sticker?.emoji;
  XFile? _file;
  bool _saving = false;

  bool get _editing => widget.sticker != null;

  bool get _valid =>
      (_editing || _file != null) &&
      _name.text.trim().length >= kStickerNameMin &&
      (_emoji?.isNotEmpty ?? false);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await pickStickerImage(context);
    if (file == null || !mounted) return;
    setState(() => _file = file);
  }

  void _pickEmoji(BuildContext anchor) => openEmojiPicker(
        anchor,
        growRight: true,
        onEmoji: (emoji) {
          if (mounted) setState(() => _emoji = emoji);
        },
      );

  Future<void> _submit() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    try {
      final name = _name.text.trim();
      final description = _description.text.trim();
      final file = _file;
      final saved = _editing
          ? await api.updateSticker(widget.serverId, widget.sticker!.id,
              name: name, description: description, emoji: _emoji!)
          : await api.addSticker(widget.serverId,
              file: file!, fileMime: mimeFromFileName(file.name),
              name: name, description: description, emoji: _emoji!);
      if (!mounted) return;
      widget.onDone(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      GlitchToast.show(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlitchFormLabel(label: s.stickerFile),
        Row(
          children: [
            _Preview(file: _file, sticker: widget.sticker),
            const SizedBox(width: 16),
            Expanded(
              child: _editing
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlitchActionButton(
                          label: s.stickerFilePick,
                          icon: Icons.upload_rounded,
                          soft: true,
                          compact: true,
                          onTap: _saving ? null : _pickFile,
                        ),
                        const SizedBox(height: 8),
                        Text(s.stickerFileHint, style: TextStyle(fontSize: 13, color: GlitchColors.textSecond)),
                      ],
                    ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GlitchFormField(
          label: s.stickerName,
          controller: _name,
          placeholder: s.stickerNameHint,
          maxLength: kStickerNameMax,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        GlitchFormField(
          label: s.stickerDescription,
          controller: _description,
          placeholder: s.stickerDescriptionHint,
          maxLength: kStickerDescriptionMax,
          maxLines: 2,
        ),
        const SizedBox(height: 18),
        GlitchFormLabel(label: s.stickerEmoji),
        Row(
          children: [
            Builder(
              builder: (anchor) => GlitchActionButton(
                label: s.stickerEmojiPick,
                icon: Icons.sentiment_satisfied_alt_rounded,
                soft: true,
                compact: true,
                onTap: _saving ? null : () => _pickEmoji(anchor),
              ),
            ),
            if (_emoji != null) ...[
              const SizedBox(width: 12),
              ReactionEmoji(_emoji!, size: 26),
            ],
          ],
        ),
        const SizedBox(height: 22),
        Align(
          alignment: Alignment.centerRight,
          child: Opacity(
            opacity: _valid ? 1 : 0.5,
            child: GlitchFilledButton(
              label: _editing ? s.save : s.stickerUpload,
              loading: _saving,
              onTap: _valid && !_saving ? _submit : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  final XFile? file;
  final Sticker? sticker;

  const _Preview({required this.file, required this.sticker});

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final f = file;
    final st = sticker;
    return Container(
      width: _size,
      height: _size,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        border: Border.all(color: GlitchColors.borderCard),
        borderRadius: BorderRadius.circular(14),
      ),
      child: f != null
          ? localImage(f.path, fit: BoxFit.contain)
          : st != null
              ? StickerView(sticker: st.toParsed(), size: _size - 16)
              : Icon(Icons.image_outlined, size: 32, color: GlitchColors.textSecond),
    );
  }
}
