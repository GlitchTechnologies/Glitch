import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../models/server.dart';
import '../providers/server_provider.dart';
import '../services/api_service.dart';
import '../services/avatar_service.dart';
import '../theme/app_theme.dart';
import 'local_image_web.dart' if (dart.library.io) 'local_image_native.dart';
import 'adaptive_sheet.dart';
import 'avatar_shape.dart';
import 'glitch_pressable.dart';
import 'image_edit_overlay.dart';
import 'glitch_toast.dart';
import 'glitch_action_button.dart';
import 'glitch_form_field.dart';
import 'glitch_switch.dart';


Future<void> showCreateServerSheet(BuildContext context) async {
  final nameCtrl = TextEditingController();
  bool creating = false;
  XFile? avatarFile;

  await showAdaptiveSheet(
    context,
    title: context.s.serverCreate,
    bodyBuilder: (ctx, setModal) {
      Future<void> pickAvatar() async {
        final file = await pickAndCropAvatar(ctx, shape: AvatarShape.community);
        if (file != null) setModal(() => avatarFile = file);
      }

      Future<void> create() async {
        if (creating) return;
        final name = nameCtrl.text.trim();
        if (name.isEmpty) {
          GlitchToast.show(ctx, context.s.serverCreateNameEmpty);
          return;
        }
        setModal(() => creating = true);
        try {
          var created = await api.createServer(name);
          final avatar = avatarFile;
          if (avatar != null) {
            created = await api.uploadServerAvatar(created.id, avatar, mimeFromFileName(avatar.name));
          }
          serverRail.addCreated(created);
          serverRail.select(created.id);
          if (ctx.mounted) Navigator.pop(ctx);
        } catch (e) {
          if (ctx.mounted) GlitchToast.show(ctx, errorMessage(e));
          setModal(() => creating = false);
        }
      }

      return _SheetBody(
        avatar: _AvatarPicker(file: avatarFile, onTap: pickAvatar),
        field: _NameField(
          controller: nameCtrl,
          hint: context.s.serverCreateNameHint,
          onSubmitted: (_) => create(),
        ),
        submit: _SubmitButton(loading: creating, onTap: create),
      );
    },
  );
  nameCtrl.dispose();
}

Future<void> showCreateRoomSheet(
  BuildContext context, {
  required int serverId,
  int? categoryId,
  required bool canMakePrivate,
  required ValueChanged<Room> onCreated,
}) async {
  final nameCtrl = TextEditingController();
  bool creating = false;
  bool isPrivate = false;
  RoomKind kind = RoomKind.text;

  await showAdaptiveSheet(
    context,
    title: context.s.roomCreateWindowTitle,
    bodyBuilder: (ctx, setModal) {
      final s = context.s;
      Future<void> create() async {
        if (creating) return;
        final name = nameCtrl.text.trim();
        if (name.isEmpty) {
          GlitchToast.show(ctx, s.roomCreateNameEmpty);
          return;
        }
        setModal(() => creating = true);
        try {
          final room = await api.createRoom(serverId,
              name: name, kind: kind, categoryId: categoryId, isPrivate: isPrivate);
          if (ctx.mounted) Navigator.pop(ctx);
          onCreated(room);
        } catch (e) {
          if (ctx.mounted) GlitchToast.show(ctx, errorMessage(e));
          setModal(() => creating = false);
        }
      }

      Widget kindTile(RoomKind k, IconData icon, String title, String subtitle) => GlitchChoiceTile(
            icon: icon,
            title: title,
            subtitle: subtitle,
            selected: kind == k,
            onTap: creating ? null : () => setModal(() => kind = k),
          );

      return _PlaceCreateBody(
        kindPicker: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlitchFormLabel(label: s.roomCreateKind),
            const SizedBox(height: 8),
            kindTile(RoomKind.text, Icons.tag_rounded, s.roomCreateKindText, s.roomCreateKindTextDesc),
            const SizedBox(height: 8),
            kindTile(RoomKind.voice, Icons.volume_up_rounded, s.roomCreateKindVoice, s.roomCreateKindVoiceDesc),
          ],
        ),
        nameLabel: s.roomCreateNameLabel,
        controller: nameCtrl,
        hint: s.roomCreateNameHint,
        prefix: kind == RoomKind.text ? '# ' : null,
        privateTitle: canMakePrivate ? s.placePrivateRoom : null,
        privateDesc: s.roomCreatePrivateDesc,
        isPrivate: isPrivate,
        onPrivate: creating ? null : (v) => setModal(() => isPrivate = v),
        submitLabel: s.roomCreateSubmit,
        creating: creating,
        onSubmit: create,
        onCancel: () => Navigator.pop(ctx),
      );
    },
  );
  nameCtrl.dispose();
}

Future<void> showCreateCategorySheet(
  BuildContext context, {
  required int serverId,
  required bool canMakePrivate,
  required VoidCallback onCreated,
}) async {
  final nameCtrl = TextEditingController();
  bool creating = false;
  bool isPrivate = false;

  await showAdaptiveSheet(
    context,
    title: context.s.categoryCreateWindowTitle,
    bodyBuilder: (ctx, setModal) {
      final s = context.s;
      Future<void> create() async {
        if (creating) return;
        final name = nameCtrl.text.trim();
        if (name.isEmpty) {
          GlitchToast.show(ctx, s.categoryCreateNameEmpty);
          return;
        }
        setModal(() => creating = true);
        try {
          await api.createCategory(serverId, name, isPrivate: isPrivate);
          onCreated();
          if (ctx.mounted) Navigator.pop(ctx);
        } catch (e) {
          if (ctx.mounted) GlitchToast.show(ctx, errorMessage(e));
          setModal(() => creating = false);
        }
      }

      return _PlaceCreateBody(
        nameLabel: s.categoryCreateNameLabel,
        controller: nameCtrl,
        hint: s.categoryCreateNameHint,
        privateTitle: canMakePrivate ? s.placePrivateCategory : null,
        privateDesc: s.categoryCreatePrivateDesc,
        isPrivate: isPrivate,
        onPrivate: creating ? null : (v) => setModal(() => isPrivate = v),
        submitLabel: s.categoryCreateSubmit,
        creating: creating,
        onSubmit: create,
        onCancel: () => Navigator.pop(ctx),
      );
    },
  );
  nameCtrl.dispose();
}

class _PlaceCreateBody extends StatelessWidget {
  final Widget? kindPicker;
  final String nameLabel;
  final TextEditingController controller;
  final String hint;
  final String? prefix;

  final String? privateTitle;
  final String privateDesc;
  final bool isPrivate;
  final ValueChanged<bool>? onPrivate;

  final String submitLabel;
  final bool creating;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  const _PlaceCreateBody({
    this.kindPicker,
    required this.nameLabel,
    required this.controller,
    required this.hint,
    this.prefix,
    required this.privateTitle,
    required this.privateDesc,
    required this.isPrivate,
    required this.onPrivate,
    required this.submitLabel,
    required this.creating,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final title = privateTitle;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kindPicker != null) ...[kindPicker!, const SizedBox(height: 20)],
          GlitchFormField(
            label: nameLabel,
            controller: controller,
            placeholder: hint,
            prefixText: prefix,
            maxLength: kMaxRoomName,
            enabled: !creating,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
          ),
          if (title != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 17, color: GlitchColors.textPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                  ),
                ),
                GlitchSwitch(value: isPrivate, onChanged: onPrivate),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              privateDesc,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: GlitchColors.textSecond),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GlitchActionButton(label: s.cancel, soft: true, onTap: creating ? null : onCancel),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlitchActionButton(label: submitLabel, loading: creating, onTap: onSubmit),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  final Widget? avatar;
  final Widget field;
  final Widget submit;

  const _SheetBody({this.avatar, required this.field, required this.submit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (avatar != null) ...[avatar!, const SizedBox(height: 20)],
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: field),
          const SizedBox(height: 18),
          Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 20), child: submit),
        ],
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  final XFile? file;
  final VoidCallback onTap;

  const _AvatarPicker({required this.file, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EditableAvatar(
        size: 84,
        shape: AvatarShape.community,
        onTap: onTap,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            borderRadius: AvatarShape.community.borderRadius(84),
            color: GlitchColors.bgInput,
            border: Border.all(color: GlitchColors.borderCard, width: 1.5),
          ),
          child: file != null
              ? AvatarShape.community.clip(
                  size: 81,
                  child: localImage(file!.path, fit: BoxFit.cover),
                )
              : Icon(Icons.add_photo_alternate_outlined, color: GlitchColors.textSecond, size: 28),
        ),
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;

  const _NameField({required this.controller, required this.hint, this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        border: Border.all(color: GlitchColors.borderCard),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: onSubmitted,
        style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: GlitchColors.textHint),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          // Тема (theme/app_theme.dart) даёт КАЖДОМУ TextField свою заливку
          // filled:true/fillColor:bgInput по умолчанию — без явного
          // fillColor:transparent здесь она рисуется ВТОРЫМ полем внутри уже
          // закрашенной карточки. См. память glitch-textfield-filled-trap.
          filled: true,
          fillColor: Colors.transparent,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const _SubmitButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlitchPressable(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(gradient: GlitchColors.gradientAccent, borderRadius: BorderRadius.circular(14)),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  context.s.commonCreate,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }
}
