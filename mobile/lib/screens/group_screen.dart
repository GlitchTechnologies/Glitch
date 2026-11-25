import 'user_profile_screen.dart';
import 'dart:async';
import '../services/file_open_result.dart';
import '../services/file_open_web.dart' if (dart.library.io) '../services/file_open_native.dart';
import '../services/media_platform_web.dart' if (dart.library.io) '../services/media_platform_native.dart';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/media_platform_web.dart' if (dart.library.io) '../services/media_platform_native.dart';
import 'package:flutter/material.dart';
import '../services/user_presences.dart';
import '../models/presence.dart';
import 'package:http/http.dart' as http;
import '../core/l10n.dart';
import '../core/file_size.dart';
import '../core/media_content.dart';
import '../core/presence.dart' as presence;
import '../theme/app_theme.dart';
import '../theme/glitch_icons.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/current_screen.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../providers/group_provider.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/presence_indicator.dart' show presenceColor;
import '../core/copy_actions.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/glitch_pressable.dart' show ClickableCursor;
import '../widgets/marquee_text.dart';
import '../widgets/glitch_toast.dart';
import 'chat_screen.dart';
import 'group_settings_screen.dart';
import 'media_viewer_screen.dart';
import '../widgets/glitch_search_field.dart';
import '../widgets/glitch_segmented_control.dart';
import '../widgets/media_tab_placeholder.dart';
import '../widgets/profile_action_button.dart';
import '../providers/theme_provider.dart';
import '../core/adaptive_open.dart';
import '../core/group_exit.dart';
import '../widgets/glitch_icon_button.dart';
import '../core/shell_controller.dart' show ShellSlot;

class GroupScreen extends StatefulWidget {
  final int chatId;

  const GroupScreen({super.key, required this.chatId});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> with ThemeAwareState<GroupScreen> {
  late final GroupProvider _provider;
  String _mediaTab = 'media'; // 'media' | 'files'
  bool _notificationsOn = true;

  @override
  void initState() {
    super.initState();
    CurrentScreen.name = 'GroupScreen';
    _provider = GroupProvider(chatId: widget.chatId)..init();
    _provider.addListener(_onProviderChange);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChange);
    _provider.dispose();
    super.dispose();
  }

  void _onProviderChange() {
    if (mounted) setState(() {
      if (_provider.chat != null) _notificationsOn = !_provider.chat!.isMuted;
    });
  }

  Future<void> _toggleNotifications() async {
    final newVal = !_notificationsOn;
    setState(() => _notificationsOn = newVal);
    try {
      await api.patch('/chats/${widget.chatId}/notifications');
    } catch (e) {
      if (!mounted) return;
      setState(() => _notificationsOn = !newVal);
      GlitchToast.show(context, errorMessage(e));
    }
  }

  void _switchTab(String tab) {
    setState(() => _mediaTab = tab);
    if (tab == 'media') _provider.loadMedia();
    if (tab == 'files') _provider.loadFiles();
  }

  Future<void> _showAddMember() async {
    final searchCtrl = TextEditingController();
    User? foundUser;
    bool searching = false;
    String? searchError;
    Timer? debounce;
    bool sheetDismissed = false;

    await showAdaptiveSheet(
      context,
      title: context.s.membersAddTitle,
      bodyBuilder: (ctx, setModal) {
        Future<void> search(String q) async {
          final nick = q.trim().replaceFirst('@', '');
          if (nick.isEmpty) { if (!sheetDismissed) setModal(() { foundUser = null; searchError = null; }); return; }
          if (!sheetDismissed) setModal(() { searching = true; foundUser = null; searchError = null; });
          try {
            final user = await api.getUser(nick);
            if (!sheetDismissed) setModal(() { foundUser = user; searching = false; });
          } on ApiException {
            if (!sheetDismissed) setModal(() { searchError = context.s.membersNotFound; searching = false; });
          }
        }

        void onSearchChanged(String q) {
          debounce?.cancel();
          debounce = Timer(const Duration(milliseconds: 400), () => search(q));
        }

        Future<void> add() async {
          if (foundUser == null) return;
          try {
            await _provider.addMember(foundUser!.nickname);
            if (mounted) {
              Navigator.pop(ctx);
              GlitchToast.show(context, context.s.membersAdded(foundUser!.displayName), type: ToastType.success);
            }
          } on ApiException catch (e) {
            if (mounted) GlitchToast.show(context, e.message);
          }
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: GlitchSearchField(
                  controller: searchCtrl,
                  hint: context.s.adminsSearchHint,
                  onChanged: onSearchChanged,
                  autofocus: true,
                  loading: searching,
                ),
              ),
              const SizedBox(height: 12),
              if (foundUser != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  child: Row(
                    children: [
                      GlitchAvatar(
                        initials: GlitchAvatar.initialsFromName(foundUser!.displayName),
                        size: 46,
                        colorIndex: GlitchAvatar.colorFromNickname(foundUser!.nickname),
                        imageUrl: foundUser!.avatar != null ? api.mediaUrl(foundUser!.avatar!) : null,
                        avatarSizes: foundUser!.avatarSizes,
                      ),
                      const SizedBox(width: 13),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(foundUser!.displayName, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
                          Text('@${foundUser!.nickname}', style: TextStyle(fontSize: 13, color: GlitchColors.textSecond)),
                        ],
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                  child: ClickableCursor(
                    child: GestureDetector(
                      onTap: add,
                      child: Container(
                        width: double.infinity, height: 50,
                        decoration: BoxDecoration(gradient: GlitchColors.gradientAccent, borderRadius: BorderRadius.circular(14)),
                        child: Center(child: Text(context.s.membersAddButton, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                      ),
                    ),
                  ),
                ),
              ] else if (searchError != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(searchError!, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14)),
                ),
              const SizedBox(height: 18),
            ],
          ),
        );
      },
    );
    sheetDismissed = true;
    debounce?.cancel();
    searchCtrl.dispose();
  }

  Widget _buildMenuButton() {
    return GlitchMenuButton<String>(
      icon: Icon(Icons.more_horiz_rounded, color: GlitchColors.textPrimary, size: 26),
      onSelected: (val) {
        if (val == 'settings' && _provider.chat != null) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => GroupSettingsScreen(
              chat: _provider.chat!,
              onUpdated: (_) => _provider.load(),
            ),
          ));
        } else if (val == 'leave') {
          confirmLeaveGroup(context, widget.chatId);
        } else if (val == 'copyId' && _provider.chat != null) {
          copyId(context, _provider.chat!.id);
        }
      },
      itemBuilder: (_) => [
        if (_provider.iAmAdmin)
          GlitchMenuItem(
            value: 'settings',
            child: Row(children: [
              Icon(GlitchIcons.settings, color: GlitchColors.textPrimary, size: 18),
              const SizedBox(width: 10),
              Text(context.s.settings, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
            ]),
          ),
        if (!_provider.iAmOwner)
          GlitchMenuItem(
            value: 'leave',
            child: Row(children: [
              const Icon(Icons.logout_rounded, color: GlitchColors.error, size: 18),
              const SizedBox(width: 10),
              Text(context.s.groupLeaveBtn, style: const TextStyle(color: GlitchColors.error, fontSize: 15)),
            ]),
          ),
        if (_provider.chat != null)
          GlitchMenuItem(value: 'copyId', child: copyIdMenuRow(context, IdKind.group)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = _provider.chat;
    final chatName = chat?.name ?? '';
    final initials = GlitchAvatar.initialsFromName(chatName.isNotEmpty ? chatName : 'G');
    final colorIdx = GlitchAvatar.colorFromNickname(chatName);
    final avatarUrl = chat?.avatar != null ? api.mediaUrl(chat!.avatar!) : null;
    final avatarSizes = chat?.avatarSizes;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 6, 0),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
                    onTap: () => closeAdaptive(context, slot: ShellSlot.details),
                  ),
                  const Spacer(),
                  if (chat != null) _buildMenuButton(),
                ],
              ),
            ),
            Divider(height: 1, color: GlitchColors.borderSoft),
            Expanded(
              child: SingleChildScrollView(
                child: _buildScrollContent(context, chat, initials, colorIdx, avatarUrl, avatarSizes),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollContent(BuildContext context, chat, String initials, int colorIdx, String? avatarUrl,
      Map<String, String>? avatarSizes) {
    if (_provider.loading) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue)),
      );
    }
    if (chat == null) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Center(child: Text(context.s.errorLoad, style: TextStyle(color: GlitchColors.textSecond))),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
      child: Column(
        children: [
                      GlitchAvatar(initials: initials, size: 108, colorIndex: colorIdx, imageUrl: avatarUrl, avatarSizes: avatarSizes),
                      const SizedBox(height: 16),
                      Center(
                        child: MarqueeText(
                          chat.name ?? context.s.group,
                          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary, letterSpacing: -0.3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(context.s.membersCount(chat.members.length), style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond)),

                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: ProfileActionButton(
                              icon: Icons.chat_bubble_outline_rounded,
                              label: context.s.groupOpenChat,
                              gradient: GlitchColors.gradientAccent,
                              textColor: Colors.white,
                              onTap: () {
                                final c = _provider.chat;
                                final myId = authService.currentUser?.id ?? 0;
                                final chatName = c?.displayName(myId) ?? context.s.group;
                                final avatarUrl = c?.avatar != null ? api.mediaUrl(c!.avatar!) : null;
                                final chatAvatarSizes = c?.avatarSizes;
                                openAdaptive(
                                  context,
                                  slot: ShellSlot.main,
                                  slotKey: chatSlotKey(widget.chatId),
                                  builder: (_) => ChatScreen(
                                    chatId: widget.chatId,
                                    chatName: chatName,
                                    colorIndex: GlitchAvatar.colorFromNickname(chatName),
                                    isGroup: true,
                                    avatarUrl: avatarUrl,
                                    avatarSizes: chatAvatarSizes,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ProfileActionButton(
                              icon: _notificationsOn ? Icons.notifications_outlined : Icons.notifications_off_outlined,
                              label: context.s.notifications,
                              gradient: null,
                              textColor: GlitchColors.textPrimary,
                              onTap: _toggleNotifications,
                            ),
                          ),
                        ],
                      ),

                      if (chat.description != null && chat.description!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
                          decoration: BoxDecoration(color: GlitchColors.bgCard, border: Border.all(color: GlitchColors.borderCard), borderRadius: BorderRadius.circular(18)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(chat.description!, style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary, height: 1.45)),
                              const SizedBox(height: 4),
                              Text(context.s.description, style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(context.s.groupMembersHeader, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: GlitchColors.textHint)),
                          const Spacer(),
                          if (_provider.iAmAdmin)
                            ClickableCursor(
                              child: GestureDetector(
                                onTap: _showAddMember,
                                child: Text(context.s.add, style: TextStyle(fontSize: 13.5, color: GlitchColors.accentBlue)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(color: GlitchColors.bgCard, border: Border.all(color: GlitchColors.borderCard), borderRadius: BorderRadius.circular(18)),
                        child: Column(
                          children: [
                            for (int i = 0; i < chat.members.length; i++)
                              _memberRow(chat.members[i], i < chat.members.length - 1),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                      GlitchSegmentedControl(
                        labels: [context.s.media, context.s.files],
                        selected: _mediaTab == 'media' ? 0 : 1,
                        onChanged: (i) => _switchTab(i == 0 ? 'media' : 'files'),
                      ),
                      const SizedBox(height: 12),

                      if (_mediaTab == 'media') ...[
                        if (!_provider.mediaLoaded)
                          const MediaTabPlaceholder(loading: true)
                        else if (_provider.mediaItems.isEmpty)
                          MediaTabPlaceholder(loading: false, emptyText: context.s.noMedia)
                        else
                          Builder(builder: (context) {
                            final tiles = flattenMediaMessages(_provider.mediaItems);
                            return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3, mainAxisSpacing: 3, crossAxisSpacing: 3,
                            ),
                            itemCount: tiles.length,
                            itemBuilder: (_, i) {
                              final tile = tiles[i];
                              final mediaUrl = api.mediaUrl(tile.url);
                              final isVideo = tile.isVideo;
                              return GestureDetector(
                                onTap: () {
                                    final allItems = tiles
                                        .map((t) => MediaItem(
                                              url: api.mediaUrl(t.url),
                                              isVideo: t.isVideo,
                                              aspectRatio: t.aspectRatio,
                                            )).toList();
                                    openMediaViewer(
                                      context,
                                      items: allItems,
                                      initialIndex: i,
                                      senderName: tile.message.senderDisplayName,
                                      senderNickname: tile.message.senderNickname,
                                      senderAvatarUrl: tile.message.senderAvatar != null ? api.mediaUrl(tile.message.senderAvatar!) : null,
                                      senderAvatarSizes: tile.message.senderAvatarSizes,
                                      colorIndex: GlitchAvatar.colorFromNickname(tile.message.senderNickname),
                                    );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (isVideo)
                                        _MediaGridVideoThumb(url: mediaUrl)
                                      else
                                        CachedNetworkImage(
                                          imageUrl: mediaUrl,
                                          cacheManager: mediaCacheManager,
                                          fit: BoxFit.cover,
                                          httpHeaders: api.headersFor(mediaUrl),
                                          placeholder: (_, __) => Container(color: GlitchColors.bgInput),
                                          errorWidget: (_, __, ___) => Container(color: GlitchColors.bgInput),
                                        ),
                                      if (isVideo)
                                        Container(
                                          color: Colors.black26,
                                          alignment: Alignment.center,
                                          child: Container(
                                            width: 32, height: 32,
                                            decoration: const BoxDecoration(color: Color(0x88000000), shape: BoxShape.circle),
                                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            );
                          }),
                      ] else ...[
                        if (!_provider.filesLoaded)
                          const MediaTabPlaceholder(loading: true)
                        else if (_provider.fileItems.isEmpty)
                          MediaTabPlaceholder(loading: false, emptyText: context.s.noFiles)
                        else
                          Container(
                            decoration: BoxDecoration(color: GlitchColors.bgCard, border: Border.all(color: GlitchColors.borderCard), borderRadius: BorderRadius.circular(18)),
                            child: Column(
                              children: [
                                for (int i = 0; i < _provider.fileItems.length; i++)
                                  _FileRow(msg: _provider.fileItems[i], border: i < _provider.fileItems.length - 1),
                              ],
                            ),
                          ),
        ],
      ],
    ),
  );
}

  Widget _memberRow(ChatMember member, bool border) => ListenableBuilder(
        listenable: userPresences,
        builder: (_, __) => _memberPresenceRow(member, border),
      );

  Widget _memberPresenceRow(ChatMember member, bool border) {
    final isMe = member.id == authService.currentUser?.id;
    final isAdmin = member.role == 'admin';
    final status = userPresences.statusOf(member.id, member.presenceStatus);
    final presenceLine = presence.presenceText(context,
        isOnline: status.isOnline,
        lastSeen: userPresences.lastSeenOf(member.id, presence.unhideLastSeen(member.lastSeen)), status: status);
    return GestureDetector(
      onTap: isMe ? null : () => showUserProfile(context, nickname: member.nickname),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: border ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.borderSoft))) : null,
      child: Row(
        children: [
          GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(member.displayName),
            size: 44,
            colorIndex: GlitchAvatar.colorFromNickname(member.nickname),
            imageUrl: member.avatar != null ? api.mediaUrl(member.avatar!) : null,
            avatarSizes: member.avatarSizes,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isMe ? '${member.displayName} (${context.s.you})' : member.displayName,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: GlitchColors.accentBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text(context.s.adminBadge, style: TextStyle(fontSize: 11, color: GlitchColors.accentBlue)),
                      ),
                    ],
                  ],
                ),
                if (presenceLine.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    presenceLine,
                    style: TextStyle(fontSize: 12.5, color: presenceColor(context, status)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),   // Container
    );   // GestureDetector
  }
}




class _FileRow extends StatefulWidget {
  final Message msg;
  final bool border;
  const _FileRow({required this.msg, required this.border});

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _loading = false;
  String? _tmpPath;

  @override
  void dispose() {
    final p = _tmpPath;
    if (p != null) deleteTempPath(p);
    super.dispose();
  }

  Future<void> _download() async {
    if (_loading || widget.msg.content == null) return;
    setState(() => _loading = true);
    final serverErrorMsg = context.s.fileServerError;
    try {
      final url = api.mediaUrl(widget.msg.content!);
      final name = widget.msg.fileName ?? widget.msg.content!.split('/').last;
      final result = await downloadAndOpenFile(
        url: url,
        fileName: '${widget.msg.id}_$name',
        headers: api.headersFor(url),
      );
      if (result == FileOpenResult.failed) throw Exception(serverErrorMsg(0));
    } catch (e) {
      if (mounted) GlitchToast.show(context, e is Exception ? e.toString().replaceFirst('Exception: ', '') : context.s.fileDownloadError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.msg.fileName ?? context.s.file;
    final size = widget.msg.fileSize != null ? formatBytes(context.s, widget.msg.fileSize!) : '';
    return GestureDetector(
      onTap: _download,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: widget.border ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.borderSoft))) : null,
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: GlitchColors.accentBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.insert_drive_file_outlined, color: GlitchColors.accentBlue, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(fontSize: 14.5, color: GlitchColors.textPrimary, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                  if (size.isNotEmpty)
                    Text(size, style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaGridVideoThumb extends StatefulWidget {
  final String url;
  const _MediaGridVideoThumb({required this.url});
  @override
  State<_MediaGridVideoThumb> createState() => _MediaGridVideoThumbState();
}

class _MediaGridVideoThumbState extends State<_MediaGridVideoThumb> {
  Uint8List? _thumb;
  bool _done = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await videoFrameFromUrl(
        widget.url, headers: api.headersFor(widget.url), maxWidth: 300, quality: 70,
      );
      if (mounted) setState(() { _thumb = data; _done = true; });
    } catch (_) {
      if (mounted) setState(() => _done = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumb != null) return Image.memory(_thumb!, fit: BoxFit.cover);
    return Container(
      color: GlitchColors.bgInput,
      child: _done
          ? Icon(Icons.videocam_rounded, color: GlitchColors.textHint, size: 28)
          : Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.textHint))),
    );
  }
}
