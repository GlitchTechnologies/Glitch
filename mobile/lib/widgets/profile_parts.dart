import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/copy_actions.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../models/server.dart';
import '../providers/assignable_roles.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'glitch_pressable.dart' show ClickableCursor;
import 'glitch_toast.dart';
import 'role_picker.dart';
import 'selection_contrast_text.dart';


class ProfileSectionLabel extends StatelessWidget {
  final String text;

  const ProfileSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
      );
}

class ProfileFact extends StatelessWidget {
  final String label;
  final String value;

  const ProfileFact({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileSectionLabel(label),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary)),
        ],
      );
}

class ProfileNickname extends StatefulWidget {
  final String nickname;
  final double fontSize;

  const ProfileNickname(this.nickname, {super.key, this.fontSize = 13.5});

  @override
  State<ProfileNickname> createState() => _ProfileNicknameState();
}

class _ProfileNicknameState extends State<ProfileNickname> {
  int? _pointer;
  Offset? _start;

  void _copy() => copyNickname(context, widget.nickname);

  @override
  Widget build(BuildContext context) {
    final gestureSettings = MediaQuery.maybeOf(context)?.gestureSettings;
    final label = SelectionContrastText(
      Text(
        '@${widget.nickname}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: widget.fontSize, color: GlitchColors.textSecond),
      ),
    );
    return ClickableCursor(
      child: hasPointerInput
          ? Semantics(
              onTap: _copy,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  if (_pointer == null && event.buttons == kPrimaryButton) {
                    _pointer = event.pointer;
                    _start = event.position;
                  }
                },
                onPointerMove: (event) {
                  final start = _start;
                  if (event.pointer == _pointer &&
                      start != null &&
                      (event.position - start).distance > computeHitSlop(event.kind, gestureSettings)) {
                    _start = null;
                  }
                },
                onPointerCancel: (event) {
                  if (event.pointer != _pointer) return;
                  _pointer = null;
                  _start = null;
                },
                onPointerUp: (event) {
                  if (event.pointer != _pointer) return;
                  final start = _start;
                  _pointer = null;
                  _start = null;
                  if (start != null &&
                      (event.position - start).distance <= computeHitSlop(event.kind, gestureSettings)) {
                    _copy();
                  }
                },
                child: label,
              ),
            )
          : GestureDetector(behavior: HitTestBehavior.opaque, onTap: _copy, child: label),
    );
  }
}

class ProfileBio extends StatelessWidget {
  final String? bio;

  const ProfileBio({super.key, required this.bio});

  @override
  Widget build(BuildContext context) {
    final text = bio?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionLabel(context.s.accountBio),
        const SizedBox(height: 4),
        Text(text, style: TextStyle(fontSize: 13.5, height: 1.35, color: GlitchColors.textPrimary)),
      ],
    );
  }
}

class ProfileRoles extends StatelessWidget {
  final List<MemberRole> roles;

  final VoidCallback? Function(MemberRole role)? onRemove;

  final Widget? trailing;

  const ProfileRoles({super.key, required this.roles, this.onRemove, this.trailing});

  static const double _scale = 1.2;

  @override
  Widget build(BuildContext context) {
    if (roles.isEmpty && trailing == null) return const SizedBox.shrink();
    return SelectionContainer.disabled(
      child: Wrap(
        spacing: 6 * _scale,
        runSpacing: 6 * _scale,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final role in roles) MemberRoleChip(role: role, scale: _scale, onRemove: onRemove?.call(role)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EditableProfileRoles extends StatefulWidget {
  final int serverId;
  final int userId;
  final List<MemberRole> roles;
  final bool canManage;

  const EditableProfileRoles({
    super.key,
    required this.serverId,
    required this.userId,
    required this.roles,
    required this.canManage,
  });

  static bool shown({required List<MemberRole> roles, required bool canManage}) =>
      roles.isNotEmpty || canManage;

  @override
  State<EditableProfileRoles> createState() => _EditableProfileRolesState();
}

class _EditableProfileRolesState extends State<EditableProfileRoles> {
  late List<MemberRole> _roles = widget.roles;
  AssignableRoles? _assignable;

  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    if (widget.canManage) _assignable = AssignableRoles(widget.serverId)..addListener(_onChange);
  }

  @override
  void didUpdateWidget(EditableProfileRoles old) {
    super.didUpdateWidget(old);
    if (!identical(old.roles, widget.roles)) _roles = widget.roles;
  }

  @override
  void dispose() {
    _assignable?.removeListener(_onChange);
    _assignable?.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<ServerMember> _set(int roleId, bool grant) async {
    try {
      final fresh = await api.setServerMemberRole(widget.serverId, widget.userId, roleId, grant: grant);
      if (mounted) setState(() => _roles = fresh.roles);
      return fresh;
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
      rethrow;
    }
  }

  Future<void> _remove(MemberRole role) async {
    if (!_busy.add(role.id)) return;
    try {
      await _set(role.id, false);
    } catch (_) {
    } finally {
      _busy.remove(role.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignable = _assignable;
    if (assignable == null) return ProfileRoles(roles: _roles);
    return ProfileRoles(
      roles: _roles,
      onRemove: (role) => assignable.canEdit(role.id) ? () => _remove(role) : null,
      trailing: MemberRolePicker(
        roles: assignable.roles,
        memberRoles: _roles,
        error: assignable.error,
        onRetry: assignable.load,
        onToggle: (role, grant) => _set(role.id, grant),
      ),
    );
  }
}

class ProfileBlockedNotice extends StatelessWidget {
  const ProfileBlockedNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: GlitchColors.error.withOpacity(0.1),
          border: Border.all(color: GlitchColors.error.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.block_rounded, color: GlitchColors.error, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.s.contactBlockedBanner,
                style: TextStyle(fontSize: 13, color: GlitchColors.error.withOpacity(0.85)),
              ),
            ),
          ],
        ),
      );
}
