import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/copy_actions.dart';
import '../core/date_text.dart';
import '../core/l10n.dart';
import '../core/webhook_limits.dart';
import '../models/server.dart';
import '../models/webhook.dart';
import '../services/api_service.dart';
import '../services/avatar_service.dart';
import '../services/media_service.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_form_field.dart';
import '../widgets/image_edit_overlay.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/settings_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsDivider, pushSettingsPage;
import '../widgets/unsaved_changes_bar.dart';
import 'webhook_composer.dart';

class RoomWebhooksSection extends StatefulWidget {
  final Room room;
  final Widget? header;

  const RoomWebhooksSection({super.key, required this.room, this.header});

  @override
  State<RoomWebhooksSection> createState() => _RoomWebhooksSectionState();
}

class _RoomWebhooksSectionState extends State<RoomWebhooksSection> {
  int? _count;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final hooks = await api.getRoomWebhooks(widget.room.id);
      if (mounted) setState(() => _count = hooks.length);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _openWebhooks() async {
    await pushSettingsPage<void>(
      context,
      title: context.s.webhooksTitle,
      builder: (_) => _WebhooksPage(room: widget.room),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final header = widget.header;
    final count = _count;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, header != null ? SettingsTwoPane.topPad : 18, 16, 40),
      children: [
        if (header != null) ...[header, const SizedBox(height: 22)],
        Text(s.integrationsHint, style: TextStyle(fontSize: 14.5, height: 1.4, color: GlitchColors.textPrimary)),
        const SizedBox(height: 20),
        const SettingsDivider(),
        const SizedBox(height: 20),
        if (count == null && _error != null)
          SettingsRetry(text: _error!, onRetry: _load)
        else
          SettingsCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SettingsNavTile(
                icon: Icons.webhook_rounded,
                title: s.webhooksTitle,
                subtitle: count == null ? '' : s.webhooksCount(count),
                onTap: _openWebhooks,
              ),
            ),
          ),
      ],
    );
  }
}

class _WebhooksPage extends StatefulWidget {
  final Room room;

  const _WebhooksPage({required this.room});

  @override
  State<_WebhooksPage> createState() => _WebhooksPageState();
}

class _Draft {
  final TextEditingController name;

  Uint8List? avatarBytes;
  String? avatarDataUri;

  _Draft(String savedName) : name = TextEditingController(text: savedName);

  bool changedFrom(Webhook saved) => name.text.trim() != saved.name || avatarDataUri != null;

  void resetTo(Webhook saved) {
    if (name.text != saved.name) name.text = saved.name;
    avatarBytes = null;
    avatarDataUri = null;
  }
}

class _WebhooksPageState extends State<_WebhooksPage> with UnsavedGuard<_WebhooksPage> {
  final _barKey = GlobalKey<UnsavedChangesBarState>();
  List<Webhook>? _hooks;
  final Map<int, _Draft> _drafts = {};
  String? _error;
  bool _creating = false;
  bool _saving = false;

  int? _fresh;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final d in _drafts.values) {
      d.name.dispose();
    }
    super.dispose();
  }

  _Draft _draftOf(Webhook hook) =>
      _drafts.putIfAbsent(hook.id, () => _Draft(hook.name)..name.addListener(_changed));

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  bool get hasUnsaved => [...?_hooks].any((h) => _drafts[h.id]?.changedFrom(h) ?? false);

  @override
  void warnUnsaved() => _barKey.currentState?.warn();

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final hooks = await api.getRoomWebhooks(widget.room.id);
      hooks.sort((a, b) => b.id.compareTo(a.id));
      if (mounted) setState(() => _hooks = hooks);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final hook = await api.createWebhook(widget.room.id, name: context.s.webhookDefaultName);
      if (!mounted) return;
      setState(() {
        _hooks = [hook, ...?_hooks];
        _fresh = hook.id;
      });
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _pickAvatar(Webhook hook) async {
    final picked = await _pickAvatarImage(context);
    if (picked == null || !mounted) return;
    setState(() {
      _draftOf(hook)
        ..avatarBytes = picked.bytes
        ..avatarDataUri = picked.dataUri;
    });
  }

  void _reset() {
    for (final h in [...?_hooks]) {
      _drafts[h.id]?.resetTo(h);
    }
    _changed();
  }

  Future<void> _save() async {
    if (_saving) return;
    final hooks = [...?_hooks];
    final changed = [for (final h in hooks) if (_drafts[h.id]?.changedFrom(h) ?? false) h];
    for (final h in changed) {
      if (_drafts[h.id]!.name.text.trim().isEmpty) {
        GlitchToast.show(context, context.s.webhookNameEmpty);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      for (final h in changed) {
        final d = _drafts[h.id]!;
        final name = d.name.text.trim();
        final saved = await api.updateWebhook(
          h.id,
          name: name != h.name ? name : null,
          avatar: d.avatarDataUri != null ? (dataUri: d.avatarDataUri) : null,
        );
        if (!mounted) return;
        setState(() {
          _hooks = [for (final x in _hooks!) x.id == saved.id ? saved : x];
          d.resetTo(saved);
        });
      }
      if (mounted) GlitchToast.show(context, context.s.roomSaved, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _deleted(Webhook hook) {
    setState(() {
      _hooks = [...?_hooks?.where((h) => h.id != hook.id)];
      _drafts.remove(hook.id)?.name.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final hooks = _hooks;
    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
            children: [
              Text(s.webhooksHint, style: TextStyle(fontSize: 14.5, height: 1.4, color: GlitchColors.textPrimary)),
              const SizedBox(height: 20),
              const SettingsDivider(),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: GlitchActionButton(
                  label: s.webhooksNew,
                  compact: true,
                  loading: _creating,
                  onTap: hooks == null || hooks.length >= kMaxWebhooksPerChannel ? null : _create,
                ),
              ),
              const SizedBox(height: 18),
              if (hooks == null)
                _error != null
                    ? SettingsRetry(text: _error!, onRetry: _load)
                    : const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
              else if (hooks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(s.webhooksEmpty, style: TextStyle(fontSize: 14, color: GlitchColors.textHint))),
                )
              else
                for (final hook in hooks) ...[
                  _WebhookCard(
                    key: ValueKey(hook.id),
                    hook: hook,
                    draft: _draftOf(hook),
                    saving: _saving,
                    initiallyOpen: hook.id == _fresh,
                    onPickAvatar: () => _pickAvatar(hook),
                    onDeleted: () => _deleted(hook),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
        UnsavedChangesDock(
          visible: hasUnsaved,
          wide: true,
          maxWidth: SettingsTwoPane.contentMaxWidth,
          barKey: _barKey,
          saving: _saving,
          onReset: _reset,
          onSave: _save,
        ),
      ],
    );
  }
}

Future<({Uint8List bytes, String dataUri})?> _pickAvatarImage(BuildContext context) async {
  final file = await pickAndCropAvatar(context, shape: AvatarShape.circle);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final mime = switch (mediaService.ext(file)) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
  return (bytes: bytes, dataUri: 'data:$mime;base64,${base64Encode(bytes)}');
}

class _WebhookCard extends StatefulWidget {
  final Webhook hook;
  final _Draft draft;
  final bool saving;
  final bool initiallyOpen;
  final VoidCallback onPickAvatar;
  final VoidCallback onDeleted;

  const _WebhookCard({
    super.key,
    required this.hook,
    required this.draft,
    required this.saving,
    required this.initiallyOpen,
    required this.onPickAvatar,
    required this.onDeleted,
  });

  @override
  State<_WebhookCard> createState() => _WebhookCardState();
}

class _WebhookCardState extends State<_WebhookCard> {
  late bool _open = widget.initiallyOpen;
  bool _deleting = false;

  static const double _avatarSize = 80;

  void _copyUrl() {
    final s = context.s;
    final url = widget.hook.url;
    if (url == null) {
      GlitchToast.show(context, s.webhookUrlLost);
      return;
    }
    copyToClipboard(context, url, s.webhookUrlCopied);
  }

  void _openComposer() {
    if (widget.hook.url == null) {
      GlitchToast.show(context, context.s.webhookUrlLost);
      return;
    }
    openWebhookComposer(context, widget.hook);
  }

  Future<void> _delete() async {
    if (_deleting) return;
    final s = context.s;
    final ok = await glitchConfirm(
      context,
      title: s.webhookDeleteConfirmTitle(widget.hook.name),
      body: s.webhookDeleteConfirmBody,
      confirmLabel: s.delete,
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      await api.deleteWebhook(widget.hook.id);
      if (mounted) widget.onDeleted();
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _avatar(double size) {
    final hook = widget.hook;
    return GlitchAvatar(
      initials: GlitchAvatar.initialsFromName(hook.name),
      size: size,
      colorIndex: GlitchAvatar.colorFromNickname(hook.name),
      imageUrl: hook.avatarUrl != null ? api.mediaUrl(hook.avatarUrl!) : null,
    );
  }

  Widget _avatarEditor() {
    final bytes = widget.draft.avatarBytes;
    return Semantics(
      button: true,
      label: context.s.webhookAvatarChange,
      child: EditableAvatar(
        size: _avatarSize,
        shape: AvatarShape.person,
        onTap: widget.saving ? null : widget.onPickAvatar,
        child: bytes != null
            ? AvatarShape.person.clip(
                size: _avatarSize,
                child: Image.memory(bytes, width: _avatarSize, height: _avatarSize, fit: BoxFit.cover),
              )
            : _avatar(_avatarSize),
      ),
    );
  }

  Widget _nameField() => GlitchFormField(
        label: context.s.webhookName,
        controller: widget.draft.name,
        maxLength: kWebhookNameMax,
        enabled: !widget.saving,
      );

  String _createdLine() {
    final s = context.s;
    final hook = widget.hook;
    final date = formatDay(hook.createdAt);
    final nick = hook.creatorNickname;
    return nick != null ? s.webhookCreatedBy(nick, date) : s.webhookCreatedOn(date);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return LayoutBuilder(builder: (context, c) {
      return SettingsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SettingsNavTile(
                leading: _avatar(40),
                title: widget.hook.name,
                subtitle: _createdLine(),
                subtitleStrong: true,
                onTap: () => setState(() => _open = !_open),
                trailing: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 24, color: GlitchColors.textSecond),
              ),
            ),
            if (_open) ...[
              const SettingsDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    c.maxWidth >= 360
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _avatarEditor(),
                              const SizedBox(width: 20),
                              Expanded(child: _nameField()),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _avatarEditor(),
                              const SizedBox(height: 16),
                              _nameField(),
                            ],
                          ),
                    const SizedBox(height: 16),
                    const SettingsDivider(),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        GlitchActionButton(label: s.webhookSendMessage, compact: true, soft: true, onTap: _openComposer),
                        GlitchActionButton(label: s.webhookCopyUrl, compact: true, soft: true, onTap: _copyUrl),
                        GlitchActionButton(
                          label: s.webhookDelete,
                          compact: true,
                          destructive: true,
                          loading: _deleting,
                          onTap: widget.saving ? null : _delete,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}
