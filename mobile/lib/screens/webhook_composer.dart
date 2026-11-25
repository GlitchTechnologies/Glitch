import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../core/avatar_color.dart';
import '../core/file_size.dart';
import '../core/l10n.dart';
import '../core/webhook_limits.dart';
import '../models/attach_result.dart';
import '../models/bubble_data.dart';
import '../models/embed.dart';
import '../models/message.dart' show kSenderWebhook;
import '../models/webhook.dart';
import '../models/webhook_message_draft.dart';
import '../providers/composer_drafts.dart';
import '../services/api_service.dart';
import '../services/file_pick.dart';
import '../services/media_service.dart';
import '../services/upload_limits.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_sheet.dart' show AdaptiveWindowCloseButton, openAdaptiveWindow;
import '../widgets/chat_background.dart';
import '../widgets/chat_metrics.dart';
import '../widgets/color_palette.dart';
import '../widgets/file_badge.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_divider.dart';
import '../widgets/glitch_form_field.dart';
import '../widgets/glitch_icon_button.dart';
import '../widgets/glitch_pressable.dart' show GlitchHoverArea;
import '../widgets/glitch_segmented_control.dart';
import '../widgets/glitch_switch.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/message_bubble.dart';
import '../widgets/mention_input.dart';
import '../widgets/message_row.dart';
import '../widgets/settings_parts.dart';
import '../widgets/settings_window.dart' show SettingsDivider, SettingsPageHeader;

Future<void> openWebhookComposer(BuildContext context, Webhook hook) => openAdaptiveWindow<void>(
      context,
      narrowBuilder: (_) => WebhookComposer(hook: hook, wide: false),
      wideBuilder: (_) => WebhookComposer(hook: hook, wide: true),
      wideSize: const Size(1160, 800),
    );

class WebhookComposer extends StatefulWidget {
  final Webhook hook;

  final bool wide;

  const WebhookComposer({super.key, required this.hook, required this.wide});

  @override
  State<WebhookComposer> createState() => _WebhookComposerState();
}

const double _kFormWidth = 520;

class _WebhookComposerState extends State<WebhookComposer> {
  final _content = MentionTextController();
  final _contentFocus = FocusNode();
  late final _mentions = MentionAutocomplete(
    controller: _content,
    chatId: () => widget.hook.channelId,
    focusNode: _contentFocus,
  );
  final _username = TextEditingController();
  final _avatarUrl = TextEditingController();
  final List<_EmbedForm> _embeds = [];
  List<XFile> _photos = const [];
  PendingFile? _file;

  bool _sending = false;
  int _tab = 0;

  Timer? _saveTimer;

  bool _forgotten = false;

  String get _key => ComposerDrafts.webhookKey(widget.hook.id);

  @override
  void initState() {
    super.initState();
    for (final c in [_content, _username, _avatarUrl]) {
      c.addListener(_changed);
    }
    final files = composerDrafts.of(_key);
    _photos = files.photos;
    _file = files.file;
    _restore();
    uploadLimits.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _restore() async {
    final draft = WebhookMessageDraft.decode(await composerDrafts.load(_key));
    if (!mounted) return;
    _content.text = draft.content;
    _username.text = draft.username;
    _avatarUrl.text = draft.avatarUrl;
    setState(() {
      _embeds.addAll([for (final e in draft.embeds) _EmbedForm.from(e, _changed)]);
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (!_forgotten) _save();
    _mentions.dispose();
    for (final c in [_content, _username, _avatarUrl]) {
      c.dispose();
    }
    _contentFocus.dispose();
    for (final e in _embeds) {
      e.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  void _save() {
    composerDrafts.save(_key, _draft().encode());
    composerDrafts.put(_key, AttachmentDraft(photos: _photos, file: _file));
  }

  WebhookMessageDraft _draft() {
    final now = DateTime.now();
    return WebhookMessageDraft(
      content: _content.wireText,
      username: _username.text,
      avatarUrl: _avatarUrl.text,
      embeds: [for (final e in _embeds) e.toEmbed(now)],
    );
  }

  bool get _isEmpty =>
      _content.text.trim().isEmpty && _embeds.isEmpty && _photos.isEmpty && _file == null;


  Future<void> _attach() async {
    final picked = await pickSystemFiles(multiple: true);
    if (picked.isEmpty || !mounted) return;
    final max = uploadLimits.maxAttachments;
    final images = [..._photos, for (final p in picked) if (mediaService.isImage(p.file)) p.file];
    final others = [if (_file != null) _file!, for (final p in picked) if (!mediaService.isImage(p.file)) p];
    if (others.isNotEmpty && (others.length > 1 || images.isNotEmpty)) {
      GlitchToast.show(context, context.s.webhookComposerFilesMixed);
      return;
    }
    if (max != null && images.length > max) {
      GlitchToast.show(context, context.s.webhookComposerFilesRule(max));
      return;
    }
    setState(() {
      _photos = images;
      _file = others.isEmpty ? null : others.single;
    });
    _changed();
  }

  void _removePhoto(XFile photo) {
    setState(() => _photos = [..._photos.where((p) => p != photo)]);
    _changed();
  }

  void _removeFile() {
    setState(() => _file = null);
    _changed();
  }


  void _addEmbed() {
    setState(() => _embeds.add(_EmbedForm(_changed)));
    _changed();
  }

  void _removeEmbed(_EmbedForm embed) {
    setState(() => _embeds.remove(embed));
    _disposeAfterFrame(embed.dispose);
    _changed();
  }

  void _moveEmbed(int index, int delta) {
    final to = index + delta;
    if (to < 0 || to >= _embeds.length) return;
    setState(() => _embeds.insert(to, _embeds.removeAt(index)));
    _changed();
  }

  void _duplicateEmbed(int index) {
    if (_embeds.length >= kEmbedsMax) return;
    setState(() => _embeds.insert(index + 1, _EmbedForm.from(_embeds[index].toEmbed(DateTime.now()), _changed)));
    _changed();
  }

  int get _embedText => _embeds.fold(0, (sum, e) => sum + e.textLength);


  Future<void> _send() async {
    if (_sending) return;
    final s = context.s;
    final url = widget.hook.url;
    if (url == null) {
      GlitchToast.show(context, s.webhookUrlLost);
      return;
    }
    if (_isEmpty) {
      GlitchToast.show(context, s.webhookComposerEmpty);
      return;
    }
    setState(() => _sending = true);
    try {
      await api.executeWebhook(url, _draft().toPayload(), photos: _photos, file: _file?.file);
      if (!mounted) return;
      _forget();
      GlitchToast.show(context, s.webhookComposerSent, type: ToastType.success);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) GlitchToast.show(context, _errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _errorText(Object e) {
    if (e is! ApiException || e.fieldErrors.isEmpty) return errorMessage(e);
    final first = e.fieldErrors.entries.first;
    final place = _placeOf(first.key.split('.'));
    return place == null ? first.value : '$place: ${first.value}';
  }

  String? _placeOf(List<String> path) {
    final s = context.s;
    switch (path) {
      case ['content', ...]:
        return s.webhookComposerContent;
      case ['username', ...]:
        return s.webhookName;
      case ['avatar_url', ...]:
        return s.webhookComposerAvatarUrl;
      case ['embeds', final i, ...final rest] when int.tryParse(i) != null:
        final card = s.webhookComposerEmbed(int.parse(i) + 1);
        final part = switch (rest) {
          ['title', ...] => s.webhookComposerTitle,
          ['description', ...] => s.webhookComposerDescription,
          ['url', ...] => s.webhookComposerTitleUrl,
          ['color', ...] => s.webhookComposerColor,
          ['author', ...] => s.webhookComposerAuthor,
          ['footer', ...] => s.webhookComposerFooter,
          ['image', ...] => s.webhookComposerImage,
          ['thumbnail', ...] => s.webhookComposerThumbnail,
          ['fields', final j, ...] when int.tryParse(j) != null => s.webhookComposerField(int.parse(j) + 1),
          _ => null,
        };
        return part == null ? card : '$card · $part';
      default:
        return null;
    }
  }

  void _forget() {
    _saveTimer?.cancel();
    _forgotten = true;
    composerDrafts.save(_key, '');
    composerDrafts.put(_key, const AttachmentDraft());
  }

  Future<void> _clear() async {
    final s = context.s;
    final ok = await glitchConfirm(
      context,
      title: s.webhookComposerClearTitle,
      body: s.webhookComposerClearBody,
      confirmLabel: s.webhookComposerClear,
    );
    if (!ok || !mounted) return;
    final removed = [..._embeds];
    _disposeAfterFrame(() {
      for (final e in removed) {
        e.dispose();
      }
    });
    setState(() {
      _embeds.clear();
      _photos = const [];
      _file = null;
    });
    _content.clear();
    _username.clear();
    _avatarUrl.clear();
  }

  static void _disposeAfterFrame(VoidCallback dispose) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => dispose());


  BubbleData _previewData() {
    final hook = widget.hook;
    final text = _content.wireText;
    final type = _photos.length > 1
        ? 'album'
        : _photos.isNotEmpty
            ? 'photo'
            : _file != null
                ? 'file'
                : 'text';
    final username = _username.text.trim();
    final avatar = _avatarUrl.text.trim();
    return BubbleData(
      id: 0,
      senderId: hook.id,
      senderKind: kSenderWebhook,
      type: type,
      content: type == 'text' ? text : null,
      caption: type == 'text' || text.trim().isEmpty ? null : text,
      localPath: switch (type) {
        'album' => jsonEncode([for (final p in _photos) p.path]),
        'photo' => _photos.first.path,
        'file' => _file!.file.path,
        _ => null,
      },
      fileName: _file?.name,
      fileSize: _file?.size,
      createdAt: DateTime.now(),
      senderNickname: '',
      senderDisplayName: username.isNotEmpty ? username : hook.name,
      senderAvatar: avatar.isNotEmpty ? avatar : hook.avatarUrl,
      status: 'sent',
      mentions: text.trim().isEmpty ? const [] : _content.wireMentions,
      embeds: [for (final e in _embeds) e.toEmbed(DateTime.now())],
    );
  }

  Widget _preview() {
    final data = _previewData();
    return ChatBackground(
      child: ChatContentWidth.scrollable(
        builder: (context, side) => ListView(
          padding: EdgeInsets.fromLTRB(side, 16, side, 24),
          children: [
            MessageRow(
              data: data,
              startsGroup: true,
              child: MessageBubble(data: data, isMine: false),
            ),
          ],
        ),
      ),
    );
  }


  List<Widget> _form() {
    final s = context.s;
    final hook = widget.hook;
    return [
      _Section(title: s.webhookComposerProfile, children: [
        GlitchFormField(
          label: s.webhookName,
          controller: _username,
          placeholder: hook.name,
          maxLength: kWebhookNameMax,
          enabled: !_sending,
        ),
        GlitchFormField(
          label: s.webhookComposerAvatarUrl,
          controller: _avatarUrl,
          placeholder: 'https://',
          enabled: !_sending,
        ),
      ]),
      _Section(title: s.webhookComposerContent, children: [
        MentionSuggestions(
          autocomplete: _mentions,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, event) => _mentions.handleKey(event),
            child: GlitchFormField(
              controller: _content,
              focusNode: _contentFocus,
              placeholder: s.webhookComposerContentHint,
              minLines: 4,
              maxLines: 12,
              enabled: !_sending,
            ),
          ),
        ),
      ]),
      _Section(title: s.webhookComposerFiles, hint: _filesHint(), children: [
        for (final p in _photos) _fileRow(ObjectKey(p), p.name, null, () => _removePhoto(p)),
        if (_file != null) _fileRow(ObjectKey(_file), _file!.name, _file!.size, _removeFile),
        Align(
          alignment: Alignment.centerLeft,
          child: GlitchActionButton(
            label: s.webhookComposerAttach,
            icon: Icons.attach_file_rounded,
            compact: true,
            soft: true,
            onTap: _sending ? null : _attach,
          ),
        ),
      ]),
      _Section(
        title: s.webhookComposerEmbeds,
        hint: _embeds.isEmpty ? null : s.webhookComposerEmbedText(_embedText, kEmbedTotalMax),
        children: [
          for (var i = 0; i < _embeds.length; i++)
            _EmbedEditor(
              key: ObjectKey(_embeds[i]),
              form: _embeds[i],
              index: i,
              enabled: !_sending,
              onChanged: _changed,
              onMoveUp: i > 0 ? () => _moveEmbed(i, -1) : null,
              onMoveDown: i < _embeds.length - 1 ? () => _moveEmbed(i, 1) : null,
              onDuplicate: _embeds.length < kEmbedsMax ? () => _duplicateEmbed(i) : null,
              onRemove: () => _removeEmbed(_embeds[i]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: GlitchActionButton(
              label: s.webhookComposerAddEmbed,
              icon: Icons.add_rounded,
              compact: true,
              soft: true,
              onTap: _sending || _embeds.length >= kEmbedsMax ? null : _addEmbed,
            ),
          ),
        ],
      ),
    ];
  }

  String? _filesHint() {
    final max = uploadLimits.maxAttachments;
    return max == null ? null : context.s.webhookComposerFilesRule(max);
  }

  Widget _fileRow(Key key, String name, int? size, VoidCallback onRemove) {
    final s = context.s;
    return SettingsCard(
      key: key,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            FileBadge(name, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary)),
                  if (size != null)
                    Text(formatBytes(s, size), style: TextStyle(fontSize: 13, color: GlitchColors.textSecond)),
                ],
              ),
            ),
            _RemoveButton(onTap: _sending ? null : onRemove),
          ],
        ),
      ),
    );
  }

  Widget _actions() {
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          GlitchActionButton(
            label: s.webhookComposerClear,
            compact: true,
            soft: true,
            onTap: _sending || _isEmpty ? null : _clear,
          ),
          const Spacer(),
          GlitchActionButton(
            label: s.webhookComposerSend,
            compact: true,
            loading: _sending,
            onTap: _isEmpty ? null : _send,
          ),
        ],
      ),
    );
  }

  Widget _formList({required EdgeInsets padding}) => ListView(
        padding: padding,
        children: [
          for (final w in _form()) ...[w, const SizedBox(height: 22)],
        ],
      );

  Widget _wideLayout() {
    final s = context.s;
    return Stack(
      fit: StackFit.expand,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _kFormWidth,
              child: ColoredBox(
                color: GlitchColors.bgCard,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                      child: _Heading(title: s.webhookSendMessage, subtitle: widget.hook.name),
                    ),
                    const Padding(padding: EdgeInsets.only(top: 18), child: SettingsDivider()),
                    Expanded(child: _formList(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12))),
                    const SettingsDivider(),
                    _actions(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 26, 64, 12),
                    child: GlitchFormLabel(label: s.webhookComposerPreview),
                  ),
                  Expanded(child: _preview()),
                ],
              ),
            ),
          ],
        ),
        AdaptiveWindowCloseButton(onPressed: () => Navigator.of(context).maybePop()),
      ],
    );
  }

  Widget _narrowLayout() {
    final s = context.s;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsPageHeader(title: s.webhookSendMessage),
          const SettingsDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: GlitchSegmentedControl(
              labels: [s.webhookComposerEditor, s.webhookComposerPreview],
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(
            child: _tab == 0 ? _formList(padding: const EdgeInsets.fromLTRB(16, 16, 16, 12)) : _preview(),
          ),
          const SettingsDivider(),
          _actions(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: GlitchColors.bg,
        body: widget.wide ? _wideLayout() : _narrowLayout(),
      );
}

class _RemoveButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _RemoveButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GlitchIconButton(
        onTap: onTap,
        size: 32,
        extent: 32,
        icon: const Icon(Icons.close_rounded, size: 20),
      );
}

class _PlaqueDivider extends StatelessWidget {
  const _PlaqueDivider();

  @override
  Widget build(BuildContext context) => const GlitchDivider();
}

class _HeadButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _HeadButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GlitchIconButton(
          onTap: onTap,
          size: 32,
          extent: 32,
          icon: Icon(icon, size: 19),
        ),
      );
}

class _Disclosure extends StatelessWidget {
  final bool open;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final Widget child;

  const _Disclosure({super.key, required this.open, required this.onTap, required this.padding, required this.child});

  @override
  Widget build(BuildContext context) => GlitchHoverArea(
        onTap: onTap,
        builder: (_, __) => Padding(
          padding: padding,
          child: Row(
            children: [
              AnimatedRotation(
                turns: open ? 0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.chevron_right_rounded, size: 22, color: GlitchColors.textPrimary),
              ),
              const SizedBox(width: 6),
              Expanded(child: child),
            ],
          ),
        ),
      );
}

class _Heading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _Heading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: GlitchColors.textSecond)),
        ],
      );
}

class _Section extends StatelessWidget {
  final String title;
  final String? hint;
  final List<Widget> children;

  const _Section({required this.title, this.hint, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlitchFormLabel(label: title, hint: hint),
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 10), children[i]],
        ],
      );
}


class _EmbedForm {
  final authorName = TextEditingController();
  final authorUrl = TextEditingController();
  final authorIcon = TextEditingController();
  final title = TextEditingController();
  final url = TextEditingController();
  final description = TextEditingController();
  final image = TextEditingController();
  final thumbnail = TextEditingController();
  final footerText = TextEditingController();
  final footerIcon = TextEditingController();

  String? color;

  bool timestamp = false;
  final List<_FieldForm> fields = [];

  bool open = false;
  final Set<_EmbedPart> openParts = {};

  final VoidCallback _onChanged;

  _EmbedForm(this._onChanged) {
    for (final c in _controllers) {
      c.addListener(_onChanged);
    }
  }

  factory _EmbedForm.from(Embed e, VoidCallback onChanged) {
    final form = _EmbedForm(onChanged)
      ..authorName.text = e.author?.name ?? ''
      ..authorUrl.text = e.author?.url ?? ''
      ..authorIcon.text = e.author?.iconUrl ?? ''
      ..title.text = e.title ?? ''
      ..url.text = e.url ?? ''
      ..description.text = e.description ?? ''
      ..image.text = e.image?.url ?? ''
      ..thumbnail.text = e.thumbnail?.url ?? ''
      ..footerText.text = e.footer?.text ?? ''
      ..footerIcon.text = e.footer?.iconUrl ?? ''
      ..color = e.color == null ? null : avatarColorToJson(Color(0xFF000000 | e.color!))
      ..timestamp = e.timestamp != null;
    form.fields.addAll([for (final f in e.fields) _FieldForm(onChanged, f)]);
    return form;
  }

  List<TextEditingController> get _controllers =>
      [authorName, authorUrl, authorIcon, title, url, description, image, thumbnail, footerText, footerIcon];

  static String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Embed toEmbed(DateTime now) {
    final author = _text(authorName);
    final footer = _text(footerText);
    final picture = _text(image);
    final thumb = _text(thumbnail);
    return Embed(
      title: _text(title),
      description: description.text.trim().isEmpty ? null : description.text,
      url: _text(url),
      color: color == null ? null : parseAvatarColor(color)!.toARGB32() & 0xFFFFFF,
      timestamp: timestamp ? now : null,
      author: author == null ? null : EmbedAuthor(name: author, url: _text(authorUrl), iconUrl: _text(authorIcon)),
      footer: footer == null ? null : EmbedFooter(text: footer, iconUrl: _text(footerIcon)),
      image: picture == null ? null : EmbedMedia(url: picture),
      thumbnail: thumb == null ? null : EmbedMedia(url: thumb),
      fields: [for (final f in fields) f.toField()],
    );
  }

  /// Текст карточки в счёт общего предела — как считает сервер
  /// (`Embed.text_length` в app/core/embeds.py): по тому, что уйдёт, и в
  /// знаках, а не в единицах UTF-16 (эмодзи — один знак, как у Python).
  int get textLength {
    final e = toEmbed(DateTime.now());
    int n(String? text) => text?.runes.length ?? 0;
    return n(e.title) +
        n(e.description) +
        n(e.footer?.text) +
        n(e.author?.name) +
        e.fields.fold(0, (sum, f) => sum + n(f.name) + n(f.value));
  }

  void addField() => fields.add(_FieldForm(_onChanged));

  void removeField(_FieldForm field) {
    fields.remove(field);
    WidgetsBinding.instance.addPostFrameCallback((_) => field.dispose());
  }

  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in fields) {
      f.dispose();
    }
  }
}

class _FieldForm {
  final TextEditingController name;
  final TextEditingController value;
  bool inline;

  _FieldForm(VoidCallback onChanged, [EmbedField? field])
      : name = TextEditingController(text: field?.name ?? ''),
        value = TextEditingController(text: field?.value ?? ''),
        inline = field?.inline ?? false {
    name.addListener(onChanged);
    value.addListener(onChanged);
  }

  EmbedField toField() => EmbedField(name: name.text, value: value.text, inline: inline);

  void dispose() {
    name.dispose();
    value.dispose();
  }
}

enum _EmbedPart { author, body, fields, images, footer }

class _EmbedEditor extends StatelessWidget {
  final _EmbedForm form;
  final int index;
  final bool enabled;
  final VoidCallback onChanged;

  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDuplicate;
  final VoidCallback onRemove;

  const _EmbedEditor({
    super.key,
    required this.form,
    required this.index,
    required this.enabled,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDuplicate,
    required this.onRemove,
  });

  void _edit(VoidCallback change) {
    change();
    onChanged();
  }

  String _title(BuildContext context) {
    final card = context.s.webhookComposerEmbed(index + 1);
    final summary = Embed.summaryOf([form.toEmbed(DateTime.now())]);
    return summary == null ? card : '$card — $summary';
  }

  String _partTitle(BuildContext context, _EmbedPart part) {
    final s = context.s;
    return switch (part) {
      _EmbedPart.author => s.webhookComposerAuthor,
      _EmbedPart.body => s.webhookComposerBody,
      _EmbedPart.fields => s.webhookComposerFields,
      _EmbedPart.images => s.webhookComposerImages,
      _EmbedPart.footer => s.webhookComposerFooter,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final stripe = parseAvatarColor(form.color) ?? GlitchColors.accentBlue;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: GlitchColors.bgEmbedForm,
          border: Border(left: BorderSide(color: stripe, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Disclosure(
              open: form.open,
              onTap: () => _edit(() => form.open = !form.open),
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _title(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (onMoveUp != null)
                    _HeadButton(icon: Icons.keyboard_arrow_up_rounded, label: s.webhookComposerEmbedUp,
                        onTap: enabled ? onMoveUp : null),
                  if (onMoveDown != null)
                    _HeadButton(icon: Icons.keyboard_arrow_down_rounded, label: s.webhookComposerEmbedDown,
                        onTap: enabled ? onMoveDown : null),
                  _HeadButton(icon: Icons.copy_rounded, label: s.webhookComposerEmbedCopy,
                      onTap: enabled ? onDuplicate : null),
                  _HeadButton(icon: Icons.close_rounded, label: s.webhookComposerEmbedDelete,
                      onTap: enabled ? onRemove : null),
                ],
              ),
            ),
            if (form.open)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final part in _EmbedPart.values) ...[
                      if (part != _EmbedPart.values.first) const _PlaqueDivider(),
                      _Disclosure(
                        key: ValueKey(part),
                        open: form.openParts.contains(part),
                        onTap: () => _edit(() {
                          if (!form.openParts.remove(part)) form.openParts.add(part);
                        }),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _partTitle(context, part),
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary),
                        ),
                      ),
                      if (form.openParts.contains(part))
                        Padding(
                          key: ValueKey(('body', part)),
                          padding: const EdgeInsets.fromLTRB(4, 0, 0, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, w) in _partFields(context, part).indexed) ...[
                                if (i > 0) const SizedBox(height: 14),
                                w,
                              ],
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
          {String? placeholder, int? maxLength, bool counter = false, int minLines = 1, int maxLines = 1}) =>
      GlitchFormField(
        label: label,
        controller: c,
        placeholder: placeholder,
        maxLength: maxLength,
        showCounter: counter,
        minLines: minLines,
        maxLines: maxLines,
        enabled: enabled,
      );

  List<Widget> _partFields(BuildContext context, _EmbedPart part) {
    final s = context.s;
    const link = 'https://';
    return switch (part) {
      _EmbedPart.author => [
          _field(form.authorName, s.webhookName, maxLength: kEmbedAuthorMax),
          _field(form.authorUrl, s.webhookComposerAuthorUrl, placeholder: link, maxLength: kEmbedUrlMax),
          _field(form.authorIcon, s.webhookComposerAuthorIcon, placeholder: link, maxLength: kEmbedUrlMax),
        ],
      _EmbedPart.body => [
          _field(form.title, s.webhookComposerTitle, maxLength: kEmbedTitleMax),
          _field(form.url, s.webhookComposerTitleUrl, placeholder: link, maxLength: kEmbedUrlMax),
          _field(form.description, s.webhookComposerDescription,
              maxLength: kEmbedDescriptionMax, counter: true, minLines: 3, maxLines: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlitchFormLabel(label: s.webhookComposerColor),
              GlitchColorChoice(
                value: form.color,
                enabled: enabled,
                onPick: (c) => _edit(() => form.color = c),
              ),
            ],
          ),
        ],
      _EmbedPart.fields => [
          for (var i = 0; i < form.fields.length; i++) _fieldEditor(context, form.fields[i], i),
          Align(
            alignment: Alignment.centerLeft,
            child: GlitchActionButton(
              label: s.webhookComposerAddField,
              icon: Icons.add_rounded,
              compact: true,
              soft: true,
              onTap: enabled && form.fields.length < kEmbedFieldsMax ? () => _edit(form.addField) : null,
            ),
          ),
        ],
      _EmbedPart.images => [
          _field(form.image, s.webhookComposerImage, placeholder: link, maxLength: kEmbedUrlMax),
          _field(form.thumbnail, s.webhookComposerThumbnail, placeholder: link, maxLength: kEmbedUrlMax),
        ],
      _EmbedPart.footer => [
          _field(form.footerText, s.webhookComposerContent, maxLength: kEmbedFooterMax),
          _field(form.footerIcon, s.webhookComposerFooterIcon, placeholder: link, maxLength: kEmbedUrlMax),
          GlitchSwitchRow(
            label: s.webhookComposerTimestamp,
            value: form.timestamp,
            border: false,
            padding: EdgeInsets.zero,
            onChanged: enabled ? (v) => _edit(() => form.timestamp = v) : null,
          ),
        ],
    };
  }

  Widget _fieldEditor(BuildContext context, _FieldForm field, int i) {
    final s = context.s;
    return Container(
      key: ObjectKey(field),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GlitchColors.borderMenu),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.webhookComposerField(i + 1),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
              ),
              _RemoveButton(onTap: enabled ? () => _edit(() => form.removeField(field)) : null),
            ],
          ),
          _field(field.name, s.webhookComposerFieldName, maxLength: kEmbedFieldNameMax),
          const SizedBox(height: 10),
          _field(field.value, s.webhookComposerFieldValue,
              maxLength: kEmbedFieldValueMax, counter: true, minLines: 2, maxLines: 6),
          const SizedBox(height: 6),
          GlitchSwitchRow(
            label: s.webhookComposerFieldInline,
            value: field.inline,
            border: false,
            padding: EdgeInsets.zero,
            onChanged: enabled ? (v) => _edit(() => field.inline = v) : null,
          ),
        ],
      ),
    );
  }
}
