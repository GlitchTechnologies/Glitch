import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../core/avatar_color.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../models/server.dart';
import '../providers/server_provider.dart';
import '../services/api_service.dart';
import '../services/avatar_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/banner_header_art.dart';
import '../widgets/game_picker.dart';
import '../widgets/glitch_form_field.dart';
import '../widgets/image_edit_overlay.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/server_profile_card.dart';
import '../widgets/unsaved_changes_bar.dart';
import '../widgets/settings_two_pane.dart';

const int _kMaxName = 128;
const int _kMaxDescription = 500;

class ServerProfileSection extends StatefulWidget {
  final ServerDetail server;

  final Widget? header;

  final ValueChanged<bool>? onUnsavedChanged;

  const ServerProfileSection({
    super.key,
    required this.server,
    this.header,
    this.onUnsavedChanged,
  });

  @override
  State<ServerProfileSection> createState() => ServerProfileSectionState();
}

class ServerProfileSectionState extends State<ServerProfileSection>
    with UnsavedGuard<ServerProfileSection> {
  final _barKey = GlobalKey<UnsavedChangesBarState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  late ServerDetail _saved;

  XFile? _newAvatar;
  Uint8List? _newAvatarBytes;
  XFile? _newBanner;
  Uint8List? _newBannerBytes;
  bool _removeBanner = false;

  late List<Game> _games;

  late bool _isPublic;

  bool _saving = false;
  bool _lastReported = false;

  @override
  void initState() {
    super.initState();
    _saved = widget.server;
    _games = _saved.games;
    _isPublic = _saved.isPublic;
    _nameCtrl = TextEditingController(text: _saved.name)..addListener(_changed);
    _descCtrl = TextEditingController(text: _saved.description ?? '')..addListener(_changed);
  }

  @override
  void didUpdateWidget(ServerProfileSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.server, widget.server) && !hasUnsaved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !hasUnsaved) _resetTo(widget.server);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  bool get hasUnsaved =>
      _nameCtrl.text.trim() != _saved.name ||
      _descCtrl.text.trim() != (_saved.description ?? '') ||
      _newAvatar != null ||
      _newBanner != null ||
      _removeBanner ||
      _isPublic != _saved.isPublic ||
      !_sameGames(_games, _saved.games);

  static bool _sameGames(List<Game> a, List<Game> b) =>
      a.length == b.length && [for (var i = 0; i < a.length; i++) a[i].id == b[i].id].every((x) => x);

  @override
  void warnUnsaved() => _barKey.currentState?.warn();

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final now = hasUnsaved;
    if (now != _lastReported) {
      _lastReported = now;
      widget.onUnsavedChanged?.call(now);
    }
  }


  Future<void> _pickAvatar() async {
    try {
      final file = await pickAndCropAvatar(context, shape: AvatarShape.community);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      _newAvatar = file;
      _newAvatarBytes = bytes;
      _changed();
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  Future<void> _pickBanner() async {
    try {
      final file = await pickBannerImage(
          context, outWidth: kServerBannerWidth, outHeight: kServerBannerHeight);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      _newBanner = file;
      _newBannerBytes = bytes;
      _removeBanner = false;
      _changed();
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  void _removeBannerPressed() {
    _newBanner = null;
    _newBannerBytes = null;
    _removeBanner = _saved.banner != null;
    _changed();
  }

  bool get _hasBannerNow => _newBanner != null || (_saved.banner != null && !_removeBanner);

  void _setPublic(bool value) {
    if (_isPublic == value) return;
    _isPublic = value;
    _changed();
  }


  void _resetTo(ServerDetail saved) {
    _saved = saved;
    _newAvatar = null;
    _newAvatarBytes = null;
    _newBanner = null;
    _newBannerBytes = null;
    _removeBanner = false;
    _games = saved.games;
    _isPublic = saved.isPublic;
    if (_nameCtrl.text != saved.name) _nameCtrl.text = saved.name;
    final desc = saved.description ?? '';
    if (_descCtrl.text != desc) _descCtrl.text = desc;
    _changed();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      GlitchToast.show(context, context.s.serverCreateNameEmpty);
      return;
    }
    final avatar = _newAvatar;
    final banner = _newBanner;
    setState(() => _saving = true);
    try {
      final updated = await api.updateServerProfile(
        _saved.id,
        name: name,
        description: _descCtrl.text.trim(),
        avatar: avatar,
        avatarMime: avatar != null ? mimeFromFileName(avatar.name) : null,
        banner: banner,
        bannerMime: banner != null ? mimeFromFileName(banner.name) : null,
        removeBanner: _removeBanner,
        gameIds: [for (final g in _games) g.id],
        isPublic: _isPublic,
      );
      serverRail.applyProfile(updated.profile);
      if (!mounted) return;
      _resetTo(updated);
      GlitchToast.show(context, context.s.serverProfileSaved, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  static const double _logoSize = 88;

  static const double _maxFormWidth = 560;

  String get _currentName {
    final typed = _nameCtrl.text.trim();
    return typed.isEmpty ? _saved.name : typed;
  }

  Widget _logo() {
    final bytes = _newAvatarBytes;
    if (bytes != null) {
      return AvatarShape.community.clip(
        size: _logoSize,
        child: SizedBox(
          width: _logoSize,
          height: _logoSize,
          child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        ),
      );
    }
    final url = _saved.avatar;
    return GlitchAvatar(
      initials: GlitchAvatar.initialsFromName(_currentName),
      size: _logoSize,
      colorIndex: GlitchAvatar.colorFromNickname(_currentName),
      imageUrl: url != null ? api.mediaUrl(url) : null,
      avatarSizes: url != null ? _saved.avatarSizes : null,
      shape: AvatarShape.community,
    );
  }

  Widget _header() {
    final s = context.s;
    final busy = _saving;
    return BannerHeaderArt(
      bannerAspect: kServerBannerAspect,
      ringColor: GlitchColors.bg,
      bannerRadius: 16,
      avatarSize: _logoSize,
      avatarShape: AvatarShape.community,
      avatar: _logo(),
      banner: ServerBanner(
        localBytes: _newBannerBytes,
        url: _removeBanner ? null : _saved.banner,
        sizes: _removeBanner ? null : _saved.bannerSizes,
        fallbackColor: parseAvatarColor(_saved.avatarColor),
      ),
      onBannerTap: busy ? null : _pickBanner,
      onAvatarEdit: busy ? null : _pickAvatar,
      bannerOverlay: (active) => Stack(
        fit: StackFit.expand,
        children: [
          if (active) const ImageEditHint(iconSize: 30),
          if (!_hasBannerNow && !active)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined, color: Colors.white, size: 28),
                  const SizedBox(height: 6),
                  Text(
                    s.serverProfileAddBanner,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
            ),
          if (_hasBannerNow && (active || !hasPointerInput))
            Positioned(
              top: 8,
              right: 8,
              child: ImageRemoveBadge(onTap: busy ? null : _removeBannerPressed),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final unsaved = hasUnsaved;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, widget.header != null ? SettingsTwoPane.topPad : 18, 16, 110),
          child: Align(
            alignment: widget.header != null ? Alignment.topLeft : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxFormWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.header != null) ...[
                    widget.header!,
                    const SizedBox(height: 22),
                  ],
                  _header(),
                  const SizedBox(height: 12),
                  Text(
                    s.serverProfileImagesHint,
                    style: TextStyle(fontSize: 13, height: 1.3, color: GlitchColors.textSecond),
                  ),
                  const SizedBox(height: 24),
                  GlitchFormField(
                    label: s.serverProfileName,
                    controller: _nameCtrl,
                    placeholder: s.serverProfileName,
                    maxLength: _kMaxName,
                    enabled: !_saving,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 22),
                  GlitchFormField(
                    label: s.serverProfileDescription,
                    hint: s.serverProfileDescriptionHint,
                    controller: _descCtrl,
                    placeholder: s.serverProfileDescriptionPlaceholder,
                    maxLength: _kMaxDescription,
                    showCounter: true,
                    minLines: 3,
                    maxLines: 6,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 22),
                  GamePicker(
                    selected: _games,
                    enabled: !_saving,
                    onChanged: (games) {
                      _games = games;
                      _changed();
                    },
                  ),
                  const SizedBox(height: 22),
                  GlitchFormLabel(
                    label: s.serverProfilePrivacy,
                    hint: s.serverProfilePrivacyHint,
                  ),
                  GlitchChoiceTile(
                    icon: Icons.public_rounded,
                    title: s.serverProfilePublic,
                    subtitle: s.serverProfilePublicHint,
                    selected: _isPublic,
                    onTap: _saving ? null : () => _setPublic(true),
                  ),
                  const SizedBox(height: 10),
                  GlitchChoiceTile(
                    icon: Icons.lock_outline_rounded,
                    title: s.serverProfilePrivate,
                    subtitle: s.serverProfilePrivateHint,
                    selected: !_isPublic,
                    onTap: _saving ? null : () => _setPublic(false),
                  ),
                ],
              ),
            ),
          ),
        ),
        UnsavedChangesDock(
          visible: unsaved,
          wide: widget.header != null,
          maxWidth: _maxFormWidth,
          barKey: _barKey,
          saving: _saving,
          onReset: () => _resetTo(_saved),
          onSave: _save,
        ),
      ],
    );
  }
}
