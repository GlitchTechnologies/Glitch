import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import '../widgets/profile_achievements.dart';
import '../widgets/achievement_viewer.dart';
import '../models/achievement.dart';
import 'package:flutter/services.dart';

import '../core/collectibles.dart';
import '../core/date_text.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../core/profile_limits.dart';
import '../core/shop_open.dart';
import '../models/collectible.dart';
import '../models/server.dart';
import '../models/user.dart';
import '../providers/server_provider.dart';
import '../providers/achievement_collection.dart';
import '../providers/achievement_arrangement.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/achievement_library.dart';
import '../widgets/banner_header_art.dart';
import '../widgets/collectible_picker.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/glitch_plus_badge.dart';
import '../widgets/glitch_pressable.dart';
import '../widgets/glitch_segmented_control.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/image_edit_overlay.dart';
import '../widgets/member_card.dart' show kMemberCardAvatar, kMemberCardNameSize, kMemberCardPadding, kMemberCardWidth;
import '../widgets/profile_effect_overlay.dart';
import '../widgets/profile_parts.dart';
import '../widgets/selectable_content.dart';
import '../widgets/settings_window.dart' show SettingsDivider, SettingsPageHeader;
import '../widgets/unsaved_changes_bar.dart';
import '../widgets/user_banner.dart';

Future<void> showProfileEditor(BuildContext context, {int? serverId, bool achievements = false}) => openAdaptiveWindow<void>(
      context,
      narrowBuilder: (_) => ProfileEditor(wide: false, serverId: serverId, achievements: achievements),
      wideBuilder: (_) => ProfileEditor(wide: true, serverId: serverId, achievements: achievements),
      wideSize: const Size(1240, 860),
    );

final double _kSideWidth = CollectiblePicker.contentWidth + 40;
const double _kCardWidth = kMemberCardWidth;
const double _kAvatar = kMemberCardAvatar;

const double _kFieldVPad = 6;

const int _kMainProfile = 0;

class ProfileEditor extends StatefulWidget {
  final bool wide;

  final int? serverId;
  final bool achievements;

  const ProfileEditor({super.key, required this.wide, this.serverId, this.achievements = false});

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> with ThemeAwareState<ProfileEditor> {
  final _barKey = GlobalKey<UnsavedChangesBarState>();
  final _libraryKey = GlobalKey();
  bool _showLibraryAfterLoad = false;
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  int? _serverId;

  User? _main;

  MyServerProfile? _community;

  bool _loadFailed = false;

  List<CollectionItem>? _collection;
  bool _collectionFailed = false;

  final _picked = <CollectibleKind, CollectionItem?>{};

  int _loadSeq = 0;

  XFile? _newAvatar;
  Uint8List? _newAvatarBytes;
  XFile? _newBanner;
  Uint8List? _newBannerBytes;

  bool _removeAvatar = false;
  bool _removeBanner = false;

  AchievementCollection? _achievements;
  AchievementArrangement? _achievementDraft;

  int _tab = 0;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _serverId = widget.serverId;
    _showLibraryAfterLoad = widget.achievements;
    _nameCtrl.addListener(_changed);
    _bioCtrl.addListener(_changed);
    _load();
    _loadCollection();
  }

  @override
  void dispose() {
    _achievementDraft?.removeListener(_changed);
    _achievementDraft?.dispose();
    _achievements?.dispose();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final serverId = _serverId;
    setState(() => _loadFailed = false);
    try {
      final main = _main ?? await api.getMe();
      final community = serverId == null ? null : await api.getMyServerProfile(serverId);
      if (!mounted || seq != _loadSeq) return;
      _main = main;
      _achievements ??= AchievementCollection(main.id);
      if (_achievementDraft == null) {
        _achievementDraft = AchievementArrangement(_achievements!)..addListener(_changed);
      }
      _community = community;
      _resetDraft();
      if (_showLibraryAfterLoad) {
        _showLibraryAfterLoad = false;
        _showAchievements();
      }
    } catch (_) {
      if (mounted && seq == _loadSeq) setState(() => _loadFailed = true);
    }
  }

  Future<void> _loadCollection() async {
    setState(() => _collectionFailed = false);
    try {
      final items = await api.getMyCollectibles();
      if (mounted) setState(() => _collection = items);
    } catch (_) {
      if (mounted) setState(() => _collectionFailed = true);
    }
  }


  bool get _isCommunity => _serverId != null;

  bool get _ready => _main != null && (!_isCommunity || _community != null);

  String get _savedName => _isCommunity ? (_community!.nick ?? '') : _main!.displayName;
  String get _savedBio => _isCommunity ? (_community!.bio ?? '') : (_main!.bio ?? '');
  String? get _savedAvatar => _isCommunity ? _community!.avatar : _main!.avatar;
  Map<String, String>? get _savedAvatarSizes => _isCommunity ? _community!.avatarSizes : _main!.avatarSizes;
  String? get _savedBanner => _isCommunity ? _community!.banner : _main!.banner;
  Map<String, String>? get _savedBannerSizes => _isCommunity ? _community!.bannerSizes : _main!.bannerSizes;

  bool get _canEditName => !_isCommunity || _community!.canChangeNick;

  ServerListItem? _communityOf(int serverId) {
    for (final srv in serverRail.servers) {
      if (srv.id == serverId) return srv;
    }
    return null;
  }

  void _selectProfile(int? serverId) {
    if (serverId == _serverId || _saving) return;
    if (_blockedByUnsaved()) return;
    setState(() {
      _serverId = serverId;
      _community = null;
    });
    _load();
  }


  bool get hasUnsaved {
    if (!_ready) return false;
    return _nameCtrl.text.trim() != _savedName ||
        _bioCtrl.text.trim() != _savedBio ||
        _newAvatar != null ||
        _newBanner != null ||
        _removeAvatar ||
        _removeBanner ||
        _picked.isNotEmpty || (_achievementDraft?.dirty ?? false);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool _blockedByUnsaved() {
    if (!hasUnsaved) return false;
    _barKey.currentState?.warn();
    return true;
  }

  void _close() {
    if (_blockedByUnsaved()) return;
    Navigator.pop(context);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent != true) return KeyEventResult.ignored;
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }


  Future<void> _pickAvatar() async {
    try {
      final file = await pickAndCropAvatar(context, shape: AvatarShape.person);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      _newAvatar = file;
      _newAvatarBytes = bytes;
      _removeAvatar = false;
      _changed();
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  Future<void> _pickBanner() async {
    try {
      final file = await pickBannerImage(context, outWidth: kUserBannerWidth, outHeight: kUserBannerHeight);
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
    _removeBanner = _savedBanner != null;
    _changed();
  }

  void _removeAvatarPressed() {
    _newAvatar = null;
    _newAvatarBytes = null;
    _removeAvatar = _savedAvatar != null;
    _changed();
  }

  bool get _ownBannerNow => _newBanner != null || (_savedBanner != null && !_removeBanner);
  bool get _ownAvatarNow => _newAvatarBytes != null || (_savedAvatar != null && !_removeAvatar);


  CollectibleLook? _savedLook(CollectibleKind kind) {
    final me = _main!;
    if (kind == CollectibleKind.avatarDecoration) return me.avatarDecoration;
    if (kind == CollectibleKind.nameplate) return me.nameplate;
    return me.profileEffect;
  }

  CollectibleLook? _lookNow(CollectibleKind kind) =>
      _picked.containsKey(kind) ? _picked[kind]?.look : _savedLook(kind);

  void _pick(CollectibleKind kind, CollectionItem? item) {
    if (item?.id == _savedLook(kind)?.id) {
      _picked.remove(kind);
    } else {
      _picked[kind] = item;
    }
    _changed();
  }


  void _resetDraft() {
    _newAvatar = null;
    _newAvatarBytes = null;
    _newBanner = null;
    _newBannerBytes = null;
    _removeAvatar = false;
    _removeBanner = false;
    _picked.clear();
    _achievementDraft?.reset();
    final name = _savedName;
    if (_nameCtrl.text != name) _nameCtrl.text = name;
    final bio = _savedBio;
    if (_bioCtrl.text != bio) _bioCtrl.text = bio;
    _changed();
  }

  Future<void> _save() async {
    if (_saving || !_ready) return;
    final name = _nameCtrl.text.trim();
    if (!_isCommunity && name.isEmpty) {
      GlitchToast.show(context, context.s.profileEditNameEmpty);
      return;
    }
    final serverId = _serverId;
    final avatar = _newAvatar;
    final banner = _newBanner;
    setState(() => _saving = true);
    try {
      if (serverId != null) {
        final updated = await api.updateMyServerProfile(
          serverId,
          nick: name,
          bio: _bioCtrl.text.trim(),
          avatar: avatar,
          avatarMime: avatar != null ? mimeFromFileName(avatar.name) : null,
          banner: banner,
          bannerMime: banner != null ? mimeFromFileName(banner.name) : null,
          removeAvatar: _removeAvatar,
          removeBanner: _removeBanner,
        );
        if (!mounted) return;
        _community = updated;
      } else {
        final updated = await api.updateMyProfile(
          displayName: name,
          bio: _bioCtrl.text.trim(),
          avatar: avatar,
          avatarMime: avatar != null ? mimeFromFileName(avatar.name) : null,
          banner: banner,
          bannerMime: banner != null ? mimeFromFileName(banner.name) : null,
          removeBanner: _removeBanner,
          equip: {for (final e in _picked.entries) e.key: e.value?.id},
          achievementOrder: _achievementDraft?.order,
        );
        authService.currentUser = updated;
        if (!mounted) return;
        _main = updated;
        _achievements?.acceptOrder(_achievementDraft?.order);
        await _achievements?.load();
        if (!mounted) return;
      }
      _resetDraft();
      GlitchToast.show(context, context.s.profileEditSaved, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  /// Аватарка, которую сейчас увидят: новая → своя этого профиля → основная
  /// (в профиле сообщества пустое — «как в основном»). [decoration] — поверх
  /// неё; на карточке — выбранное украшение, в плитках выбора — своё у каждой.
  Widget _avatar(User me, double size, {CollectibleLook? decoration, bool animate = true}) {
    final bytes = _newAvatarBytes;
    if (bytes != null) {
      final picture = AvatarShape.person.clip(
        size: size,
        child: SizedBox(
          width: size,
          height: size,
          child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        ),
      );
      if (decoration == null) return picture;
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            KeyedSubtree(key: const ValueKey('avatar'), child: picture),
            AvatarDecorationLayer(
              key: const ValueKey('decoration'),
              size: size,
              decoration: decoration,
              playing: animate,
            ),
          ],
        ),
      );
    }
    final own = !_removeAvatar ? _savedAvatar : null;
    final url = own ?? me.avatar;
    final sizes = own != null ? _savedAvatarSizes : me.avatarSizes;
    final typed = _nameCtrl.text.trim();
    return GlitchAvatar(
      initials: GlitchAvatar.initialsFromName(typed.isEmpty ? me.displayName : typed),
      size: size,
      colorIndex: GlitchAvatar.colorFromNickname(me.nickname),
      imageUrl: url != null ? api.mediaUrl(url) : null,
      avatarSizes: sizes,
      decoration: decoration,
      animateDecoration: animate,
    );
  }

  Widget _banner(User me) {
    final ownBanner = _removeBanner ? null : _savedBanner;
    final fallback = _isCommunity && ownBanner == null;
    return UserBanner(
      url: ownBanner ?? (fallback ? me.banner : null),
      sizes: ownBanner != null ? _savedBannerSizes : (fallback ? me.bannerSizes : null),
      localBytes: _newBannerBytes,
      color: me.avatarColor,
      nickname: me.nickname,
    );
  }

  Widget _header(User me, double avatarSize, {bool preview = false}) {
    final s = context.s;
    final busy = _saving || preview;
    final ownBanner = _removeBanner ? null : _savedBanner;
    final fallback = _isCommunity && ownBanner == null;
    final shownBanner = ownBanner ?? (fallback ? me.banner : null);
    bool showRemove(bool active) => active || !hasPointerInput;
    return BannerHeaderArt(
      besideAvatar: preview ? null : ProfileAchievements(userId: me.id, collection: _achievements,
          arrangement: _isCommunity ? null : _achievementDraft, editingEnabled: !_saving,
          onShowAll: _showAchievements, onOpenAchievement: _viewAchievement),
      bannerAspect: kUserBannerAspect,
      banner: _banner(me),
      // Украшение — слоем шапки над затемнением с карандашом (как эффект
      // над затемнением баннера), а не частью аватарки. В открытом профиле
      // оно играет всегда — и на карточке редактора; в плитке эффекта
      // оживает только сам эффект.
      avatar: _avatar(me, avatarSize),
      avatarDecoration: _lookNow(CollectibleKind.avatarDecoration),
      animateDecoration: !preview,
      avatarSize: avatarSize,
      avatarShape: AvatarShape.person,
      ringColor: GlitchColors.bgCard,
      onBannerTap: busy ? null : _pickBanner,
      onAvatarEdit: busy ? null : _pickAvatar,
      bannerOverlay: preview
          ? (_) => const SizedBox.shrink()
          : (active) => Stack(
              fit: StackFit.expand,
              children: [
                if (active) const ImageEditHint(iconSize: 30),
                if (_newBannerBytes == null && shownBanner == null && !active)
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
                if (_ownBannerNow && showRemove(active))
                  Positioned(
                    top: 8,
                    right: 8,
                    child: ImageRemoveBadge(onTap: busy ? null : _removeBannerPressed),
                  ),
              ],
            ),
      avatarOverlay: preview
          ? (_) => const SizedBox.shrink()
          : (active) => Stack(
              fit: StackFit.expand,
              children: [
                if (_isCommunity && _ownAvatarNow && showRemove(active))
                  Align(
                    alignment: const Alignment(0, -0.62),
                    child: ImageRemoveBadge(onTap: busy ? null : _removeAvatarPressed),
                  ),
              ],
            ),
    );
  }

  Widget _resetText(TextEditingController ctrl, {bool enabled = true}) {
    if (!_isCommunity || ctrl.text.isEmpty) return const SizedBox.shrink();
    return TextButton(
      onPressed: _saving || !enabled ? null : () => ctrl.clear(),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(context.s.profileFieldReset, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _card(
    User me, {
    required CollectibleLook? effect,
    bool preview = false,
    bool animateEffect = true,
  }) {
    final s = context.s;
    const nameStyle = TextStyle(fontSize: kMemberCardNameSize, fontWeight: FontWeight.w700);
    final canName = _canEditName;
    final name = _nameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    Widget asField(String text, TextStyle style) => Padding(
          padding: const EdgeInsets.symmetric(vertical: _kFieldVPad),
          child: Text(text, style: style),
        );
    final details = Padding(
      padding: kMemberCardPadding.copyWith(top: kMemberCardPadding.top - _kFieldVPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: preview
                    ? asField(
                        name.isEmpty ? me.displayName : name,
                        nameStyle.copyWith(color: GlitchColors.textPrimary),
                      )
                    : _InlineField(
                        controller: _nameCtrl,
                        placeholder: _isCommunity ? me.displayName : s.accountName,
                        hintIsValue: _isCommunity,
                        style: nameStyle.copyWith(color: GlitchColors.textPrimary),
                        maxLength: kDisplayNameMax,
                        enabled: !_saving && canName,
                      ),
              ),
              _resetText(_nameCtrl, enabled: canName),
              if (me.isGlitchPlus) ...[
                const SizedBox(width: 6),
                const GlitchPlusBolt(size: 20),
              ],
            ],
          ),
          if (!canName) ...[
            const SizedBox(height: 2),
            Text(
              s.profileCommunityNameLocked,
              style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond),
            ),
          ],
          const SizedBox(height: 2),
          DefaultSelectionStyle.merge(
            mouseCursor: SystemMouseCursors.basic,
            child: Text(
              '@${me.nickname}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: ProfileSectionLabel(s.accountBio)),
              _resetText(_bioCtrl),
            ],
          ),
          const SizedBox(height: 4),
          if (preview)
            asField(
              bio.isEmpty ? s.accountBioPlaceholder : bio,
              TextStyle(
                fontSize: 14.5,
                height: 1.35,
                color: bio.isEmpty ? GlitchColors.textHint : GlitchColors.textPrimary,
              ),
            )
          else
            _InlineField(
              controller: _bioCtrl,
              placeholder: _isCommunity ? (me.bio ?? s.accountBioPlaceholder) : s.accountBioPlaceholder,
              hintIsValue: _isCommunity && me.bio != null,
              style: TextStyle(fontSize: 14.5, height: 1.35, color: GlitchColors.textPrimary),
              maxLength: kBioMax,
              minLines: 1,
              maxLines: 6,
              showCounter: true,
              enabled: !_saving,
            ),
          const SizedBox(height: 16),
          ProfileFact(label: s.serverMembersColAccount, value: formatDay(me.createdAt)),
        ],
      ),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ProfileEffectOverlay(
        effect: effect,
        playing: animateEffect,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(me, _kAvatar, preview: preview),
            preview ? details : SelectableContent(child: details),
          ],
        ),
      ),
    );
  }


  Widget _profilePicker() {
    final s = context.s;
    final serverId = _serverId;
    final community = serverId == null ? null : _communityOf(serverId);
    final label = serverId == null ? s.profileEditorTitle : (community?.name ?? '');
    return Builder(
      builder: (btnCtx) => GlitchPressable(
        onTap: _saving
            ? null
            : () => openGlitchMenu<int>(
                  btnCtx,
                  growRight: true,
                  items: [
                    GlitchMenuItem(
                      value: _kMainProfile,
                      child: glitchMenuRow(Icons.person_outline_rounded, s.profileEditorTitle),
                    ),
                    for (final srv in serverRail.servers)
                      GlitchMenuItem(value: srv.id, child: _communityRow(srv)),
                  ],
                  onSelected: (v) => _selectProfile(v == _kMainProfile ? null : v),
                ),
        child: Row(
          children: [
            if (community != null) ...[
              _communityIcon(community, 22),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: GlitchColors.textPrimary),
          ],
        ),
      ),
    );
  }

  Widget _communityIcon(ServerListItem srv, double size) => GlitchAvatar(
        initials: GlitchAvatar.initialsFromName(srv.name),
        size: size,
        colorIndex: GlitchAvatar.colorFromNickname(srv.name),
        imageUrl: srv.avatar != null ? api.mediaUrl(srv.avatar!) : null,
        avatarSizes: srv.avatarSizes,
        shape: AvatarShape.community,
      );

  Widget _communityRow(ServerListItem srv) => Row(
        children: [
          _communityIcon(srv, 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              srv.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15),
            ),
          ),
        ],
      );


  Widget _decor(User me, {required double cardWidth}) {
    if (_isCommunity) {
      return Text(
        context.s.profileDecorCommunityNote,
        style: TextStyle(fontSize: 13.5, height: 1.35, color: GlitchColors.textSecond),
      );
    }
    final typed = _nameCtrl.text.trim();
    return CollectiblePicker(
      collection: _collection,
      loadFailed: _collectionFailed,
      onRetry: _loadCollection,
      selectedOf: _lookNow,
      onSelect: _saving ? null : _pick,
      onShop: _saving ? null : _openShop,
      avatar: (size, decoration, animate) => _avatar(me, size, decoration: decoration, animate: animate),
      card: (effect, animate) => IgnorePointer(
        child: SizedBox(
          width: cardWidth,
          child: _card(me, effect: effect, preview: true, animateEffect: animate),
        ),
      ),
      name: typed.isEmpty ? me.displayName : typed,
    );
  }

  void _openShop(CollectibleKind kind) {
    if (_blockedByUnsaved()) return;
    openShop(context, kind: kind);
  }


  Widget _tabs() {
    final soon = context.s.soon;
    return GlitchSegmentedControl(
      labels: [_isCommunity ? soon : context.s.achievements, soon, soon],
      selected: _tab,
      onChanged: (i) => setState(() => _tab = i),
    );
  }

  Widget _tabContent() {
    final collection = _achievements;
    if (_isCommunity || _tab != 0 || collection == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: AchievementLibrary(key: _libraryKey, collection: collection,
          arrangement: _achievementDraft, editingEnabled: !_saving, onOpenAchievement: _viewAchievement),
    );
  }

  void _showAchievements() {
    if (_isCommunity) {
      if (_blockedByUnsaved()) return;
      _showLibraryAfterLoad = true;
      _selectProfile(null);
      return;
    }
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _libraryKey.currentContext;
      if (target != null) Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 220));
    });
  }

  void _viewAchievement(Achievement item) {
    if (_blockedByUnsaved()) return;
    final nav = Navigator.of(context, rootNavigator: true);
    nav.pop();
    openAchievement(nav.context, item);
  }


  Widget _dock() => UnsavedChangesDock(
        visible: hasUnsaved,
        wide: false,
        maxWidth: 720,
        barKey: _barKey,
        saving: _saving,
        onReset: () {
          if (_ready) _resetDraft();
        },
        onSave: _save,
      );

  Widget? _placeholder() {
    if (_ready) return null;
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.s.errorLoad, style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)),
            TextButton(onPressed: _load, child: Text(context.s.retry)),
          ],
        ),
      );
    }
    return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
  }

  Widget _wideLayout() {
    final me = _main;
    return Stack(
      fit: StackFit.expand,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _kSideWidth,
              child: ColoredBox(
                color: GlitchColors.bgCard,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                      child: Align(alignment: Alignment.centerLeft, child: _profilePicker()),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: SettingsDivider(),
                    ),
                    if (_ready)
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 110),
                          child: _decor(me!, cardWidth: _kCardWidth),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _placeholder() ??
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 40, 40, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: _kCardWidth,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 110),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _card(me!, effect: _lookNow(CollectibleKind.profileEffect)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 36),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _tabs(),
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.only(bottom: 110),
                                    child: _tabContent(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ),
          ],
        ),
        AdaptiveWindowCloseButton(onPressed: _close),
        _dock(),
      ],
    );
  }

  Widget _narrowLayout() {
    final me = _main;
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsPageHeader(title: context.s.profileEdit),
              Divider(height: 1, color: GlitchColors.borderSoft),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Align(alignment: Alignment.centerLeft, child: _profilePicker()),
              ),
              Expanded(
                child: _placeholder() ??
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                      child: LayoutBuilder(
                        builder: (context, box) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _card(me!, effect: _lookNow(CollectibleKind.profileEffect)),
                            const SizedBox(height: 24),
                            _decor(me, cardWidth: box.maxWidth),
                            const SizedBox(height: 24),
                            _tabs(),
                            _tabContent(),
                          ],
                        ),
                      ),
                    ),
              ),
            ],
          ),
          _dock(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // WillPopScope, а не PopScope, — та же причина, что в settings_window.dart:
    // на части версий Flutter его нет.
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async => !_blockedByUnsaved(),
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: GlitchColors.bg,
          body: widget.wide ? _wideLayout() : _narrowLayout(),
        ),
      ),
    );
  }
}

class _InlineField extends StatefulWidget {
  final TextEditingController controller;
  final String placeholder;
  final TextStyle style;
  final int maxLength;
  final int minLines;
  final int maxLines;
  final bool showCounter;
  final bool enabled;

  final bool hintIsValue;

  const _InlineField({
    required this.controller,
    required this.placeholder,
    required this.style,
    required this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
    this.showCounter = false,
    this.enabled = true,
    this.hintIsValue = false,
  });

  @override
  State<_InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<_InlineField> {
  final _focus = FocusNode();

  static const double _pad = 8;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final radius = BorderRadius.circular(8);
    final none = OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none, gapPadding: 0);
    return SelectionContainer.disabled(
      child: Transform.translate(
        offset: const Offset(-_pad, 0),
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          style: widget.style,
          maxLength: widget.maxLength,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          keyboardType: widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text,
          textInputAction: widget.maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: focused || !hasPointerInput ? GlitchColors.bgInput : Colors.transparent,
            hoverColor: GlitchColors.bgInput,
            hintText: widget.placeholder,
            hintStyle: widget.hintIsValue ? widget.style : widget.style.copyWith(color: GlitchColors.textHint),
            counterText: widget.showCounter && focused ? null : '',
            contentPadding: const EdgeInsets.symmetric(horizontal: _pad, vertical: _kFieldVPad),
            border: none,
            enabledBorder: none,
            disabledBorder: none,
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: GlitchColors.accentBlue, width: 1.5),
              gapPadding: 0,
            ),
          ),
        ),
      ),
    );
  }
}
