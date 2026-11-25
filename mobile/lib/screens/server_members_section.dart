import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/copy_actions.dart';
import '../core/date_text.dart';
import '../core/glitch_link.dart' show linkDomain;
import '../core/l10n.dart';
import '../core/permissions.dart';
import '../core/profile_limits.dart';
import '../models/invite.dart';
import '../models/server.dart';
import '../providers/cursor_pager.dart';
import '../providers/assignable_roles.dart';
import '../providers/numbered_pager.dart';
import '../providers/server_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_bar_buttons.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_form_field.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/glitch_pressable.dart';
import '../widgets/glitch_search_field.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/page_nav_bar.dart';
import '../widgets/role_picker.dart';
import '../widgets/load_more_trigger.dart';
import '../widgets/server_user_avatar.dart';
import '../widgets/settings_parts.dart' show SettingsRetry;
import '../widgets/settings_two_pane.dart';


const int _kMaxBanReason = 255;

const double _kTableMinWidth = 640;

const List<int> _kPageSizes = [12, 25, 50, 100];


class ServerMembersSection extends StatefulWidget {
  final ServerDetail server;

  final Widget? header;

  const ServerMembersSection({super.key, required this.server, this.header});

  @override
  State<ServerMembersSection> createState() => _ServerMembersSectionState();
}

enum _MemberAction { copyId, editNick, kick, ban }

class _ServerMembersSectionState extends State<ServerMembersSection> {
  final _searchCtrl = TextEditingController();

  final _scroll = ScrollController();
  late final NumberedPager<ServerMember> _pager;
  StreamSubscription<MemberDisplayChange>? _displaySub;
  Timer? _searchDebounce;
  String _query = '';

  final Set<int> _busy = {};

  AssignableRoles? _roles;

  bool get _canAssignRoles => widget.server.myPermissions.can(Perm.manageRoles);

  @override
  void initState() {
    super.initState();
    _pager = NumberedPager(
      (offset, limit) => api.getServerMembers(
        widget.server.id,
        query: _query,
        offset: offset,
        limit: limit,
      ),
      pageSize: _kPageSizes.first,
    )..addListener(_onChange);
    _displaySub = serverRail.memberDisplay.listen((c) {
      if (mounted && c.affects(widget.server.id)) _pager.load();
    });
    if (_canAssignRoles) {
      _roles = AssignableRoles(widget.server.id)..addListener(_onChange);
    }
    _pager.load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _displaySub?.cancel();
    _roles?.removeListener(_onChange);
    _roles?.dispose();
    _pager.removeListener(_onChange);
    _pager.dispose();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<ServerMember> _setRole(ServerMember m, ServerRole role, bool grant) async {
    try {
      final fresh = await api.setServerMemberRole(
        widget.server.id, m.user.id, role.id, grant: grant,
      );
      if (!mounted) return fresh;
      _pager.replace((x) => x.user.id == m.user.id, fresh);
      return fresh;
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
      rethrow;
    }
  }

  void _onSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final q = value.trim();
      if (q == _query) return;
      _query = q;
      _pager.restart();
    });
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _onAction(ServerMember m, _MemberAction action) async {
    switch (action) {
      case _MemberAction.copyId:
        await copyId(context, m.user.id);
      case _MemberAction.editNick:
        await _editNick(m);
      case _MemberAction.kick:
        await _kick(m);
      case _MemberAction.ban:
        await _ban(m);
    }
  }

  Future<void> _kick(ServerMember m) async {
    final s = context.s;
    final ok = await glitchConfirm(
      context,
      title: s.serverKickTitle(m.shownName),
      body: s.serverKickBody,
      confirmLabel: s.serverMemberKick,
    );
    if (!ok || !mounted) return;
    await _act(m, () => api.kickServerMember(widget.server.id, m.user.id), s.serverKickDone);
  }

  Future<void> _ban(ServerMember m) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ModalStatusBarDim(child: _BanDialog(name: m.shownName)),
    );
    if (reason == null || !mounted) return;
    await _act(
      m,
      () => api.banServerMember(widget.server.id, m.user.id, reason: reason.isEmpty ? null : reason),
      context.s.serverBanDone,
    );
  }

  Future<void> _editNick(ServerMember m) async {
    final nick = await showDialog<String>(
      context: context,
      builder: (_) => ModalStatusBarDim(child: _NickDialog(initial: m.nick ?? '')),
    );
    if (nick == null || !mounted || !_busy.add(m.user.id)) return;
    try {
      final fresh = await api.setMemberNick(widget.server.id, m.user.id, nick.isEmpty ? null : nick);
      if (!mounted) return;
      _pager.replace((x) => x.user.id == m.user.id, fresh);
      GlitchToast.show(context, context.s.serverNickDone, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      _busy.remove(m.user.id);
    }
  }

  Future<void> _act(ServerMember m, Future<void> Function() request, String done) async {
    if (!_busy.add(m.user.id)) return;
    try {
      await request();
      if (!mounted) return;
      _pager.load();
      GlitchToast.show(context, done, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      _busy.remove(m.user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return LayoutBuilder(builder: (context, constraints) {
      final table = constraints.maxWidth >= _kTableMinWidth;
      return _PagedList<ServerMember>(
        items: _pager.items,
        loading: _pager.loading,
        error: _pager.error,
        onRetry: _pager.load,
        controller: _scroll,
        header: widget.header,
        top: [
          GlitchSearchField(
            key: const ValueKey('members-search'),
            controller: _searchCtrl,
            hint: s.serverMembersSearch,
            onChanged: _onSearch,
            loading: _pager.loading && _pager.items.isNotEmpty,
          ),
          const SizedBox(height: 12),
        ],
        tableHead: table ? const _MembersTableHead() : null,
        emptyText: s.serverMembersEmpty,
        row: (m) => table
            ? _MemberTableRow(member: m, menu: _menu(m), rolePicker: _rolePicker(m))
            : _MemberListRow(member: m, menu: _menu(m), rolePicker: _rolePicker(m)),
        footer: _pager.items.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 14),
                child: PageNavBar(
                  page: _pager.page,
                  pageCount: _pager.pageCount,
                  pageSize: _pager.pageSize,
                  pageSizes: _kPageSizes,
                  totalLabel: s.serverMembersOfTotal(_pager.total),
                  onPage: (p) {
                    _pager.goTo(p);
                    _toTop();
                  },
                  onPageSize: (n) {
                    _pager.setPageSize(n);
                    _toTop();
                  },
                ),
              ),
      );
    });
  }

  Widget? _rolePicker(ServerMember m) {
    final roles = _roles;
    if (roles == null) return null;
    return MemberRolePicker(
      roles: roles.roles,
      memberRoles: m.roles,
      error: roles.error,
      onRetry: roles.load,
      onToggle: (role, grant) => _setRole(m, role, grant),
    );
  }

  Widget _menu(ServerMember m) {
    final s = context.s;
    return GlitchMenuButton<_MemberAction>(
      icon: Icon(Icons.more_vert_rounded, color: GlitchColors.textPrimary, size: 20),
      size: 32,
      onSelected: (a) => _onAction(m, a),
      itemBuilder: (_) => [
        if (m.canEditNick)
          GlitchMenuItem(
            value: _MemberAction.editNick,
            child: glitchMenuRow(Icons.edit_outlined, s.serverMemberEditNick),
          ),
        if (m.canKick)
          GlitchMenuItem(
            value: _MemberAction.kick,
            child: glitchMenuRow(Icons.person_remove_outlined, s.serverMemberKick, danger: true),
          ),
        if (m.canBan)
          GlitchMenuItem(
            value: _MemberAction.ban,
            child: glitchMenuRow(Icons.block_rounded, s.serverMemberBan, danger: true),
          ),
        GlitchMenuItem(
          value: _MemberAction.copyId,
          child: copyIdMenuRow(context, IdKind.user),
        ),
      ],
    );
  }
}

class _BanDialog extends StatefulWidget {
  final String name;

  const _BanDialog({required this.name});

  @override
  State<_BanDialog> createState() => _BanDialogState();
}

class _BanDialogState extends State<_BanDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return GlitchDialog(
      title: s.serverBanTitle(widget.name),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.serverBanBody, style: GlitchDialog.bodyStyle),
              const SizedBox(height: 18),
              GlitchFormField(
                label: s.serverBanReason,
                hint: s.serverBanReasonHint,
                controller: _reason,
                maxLength: _kMaxBanReason,
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        GlitchPlainButton(label: s.cancel, onTap: () => Navigator.pop(context)),
        GlitchFilledButton(
          label: s.serverMemberBan,
          destructive: true,
          onTap: () => Navigator.pop(context, _reason.text.trim()),
        ),
      ],
    );
  }
}

class _NickDialog extends StatefulWidget {
  final String initial;

  const _NickDialog({required this.initial});

  @override
  State<_NickDialog> createState() => _NickDialogState();
}

class _NickDialogState extends State<_NickDialog> {
  late final _nick = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _nick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return GlitchDialog(
      title: s.serverMemberEditNick,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SizedBox(
          width: double.maxFinite,
          child: GlitchFormField(
            label: s.serverNickLabel,
            hint: s.serverNickHint,
            controller: _nick,
            maxLength: kDisplayNameMax,
          ),
        ),
      ),
      actions: [
        if (widget.initial.isNotEmpty)
          GlitchPlainButton(label: s.profileFieldReset, onTap: () => Navigator.pop(context, '')),
        GlitchPlainButton(label: s.cancel, onTap: () => Navigator.pop(context)),
        GlitchFilledButton(label: s.save, onTap: () => Navigator.pop(context, _nick.text.trim())),
      ],
    );
  }
}


class ServerBansSection extends StatefulWidget {
  final ServerDetail server;
  final Widget? header;

  const ServerBansSection({super.key, required this.server, this.header});

  @override
  State<ServerBansSection> createState() => _ServerBansSectionState();
}

class _ServerBansSectionState extends State<ServerBansSection> {
  late final CursorPager<ServerBan> _pager;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _pager = CursorPager((before) => api.getServerBans(widget.server.id, before: before))
      ..addListener(_onChange);
    _pager.reload();
  }

  @override
  void dispose() {
    _pager.removeListener(_onChange);
    _pager.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _unban(ServerBan ban) async {
    final s = context.s;
    final ok = await glitchConfirm(
      context,
      title: s.serverUnbanTitle(ban.user.displayName),
      body: s.serverUnbanBody,
      confirmLabel: s.serverUnban,
      destructive: false,
    );
    if (!ok || !mounted || !_busy.add(ban.user.id)) return;
    try {
      await api.unbanServerMember(widget.server.id, ban.user.id);
      if (!mounted) return;
      _pager.removeWhere((b) => b.user.id == ban.user.id);
      GlitchToast.show(context, s.serverUnbanDone, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      _busy.remove(ban.user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PagedList<ServerBan>(
      items: _pager.items,
      loading: _pager.loading,
      error: _pager.error,
      onRetry: _pager.reload,
      header: widget.header,
      top: const [],
      emptyText: context.s.serverBansEmpty,
      row: (b) => _BanRow(ban: b, onUnban: () => _unban(b)),
      footer: _pager.moreError != null
          ? _RetryLine(message: _pager.moreError!, onRetry: _pager.loadMore)
          : (_pager.hasMore && !_pager.loading)
              ? LoadMoreTrigger(key: ValueKey(_pager.items.length), onVisible: _pager.loadMore)
              : null,
    );
  }
}


class InvitesSection extends StatefulWidget {
  final InviteTarget target;
  final Widget? header;

  final bool showVanity;

  const InvitesSection({super.key, required this.target, this.header, this.showVanity = false});

  @override
  State<InvitesSection> createState() => _InvitesSectionState();
}

enum _InviteAction { copy, revoke }

class _InvitesSectionState extends State<InvitesSection> {
  List<Invite> _items = [];
  bool _loading = true;
  String? _error;
  bool _creating = false;

  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.getInvites(widget.target);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final made = await api.createInvite(widget.target);
      if (!mounted) return;
      setState(() {
        _items = [made, ..._items];
        _creating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      GlitchToast.show(context, errorMessage(e));
    }
  }

  Future<void> _onAction(Invite inv, _InviteAction action) async {
    switch (action) {
      case _InviteAction.copy:
        await copyInviteLink(context, inv.code);
      case _InviteAction.revoke:
        await _revoke(inv);
    }
  }

  Future<void> _revoke(Invite inv) async {
    final s = context.s;
    final ok = await glitchConfirm(
      context,
      title: s.inviteRevokeTitle,
      body: s.inviteRevokeBody,
      confirmLabel: s.inviteRevoke,
    );
    if (!ok || !mounted || !_busy.add(inv.code)) return;
    try {
      await api.revokeInvite(inv.code);
      if (!mounted) return;
      setState(() => _items = _items.where((i) => i.code != inv.code).toList());
      GlitchToast.show(context, s.inviteRevokeDone, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      _busy.remove(inv.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return LayoutBuilder(builder: (context, constraints) {
      final table = constraints.maxWidth >= _kTableMinWidth;
      return _PagedList<Invite>(
        items: _items,
        loading: _loading,
        error: _error,
        onRetry: _load,
        header: widget.header,
        top: [
          if (widget.showVanity && widget.target.isServer) ...[
            _VanityBlock(serverId: widget.target.id),
            const SizedBox(height: 20),
          ],
          GlitchActionButton(label: s.inviteCreate, onTap: _create, loading: _creating),
          const SizedBox(height: 12),
        ],
        tableHead: table ? const _InvitesTableHead() : null,
        emptyText: s.inviteNoLinks,
        row: (inv) => table
            ? _InviteTableRow(invite: inv, menu: _menu(inv))
            : _InviteListRow(invite: inv, menu: _menu(inv)),
      );
    });
  }

  Widget _menu(Invite inv) {
    final s = context.s;
    return GlitchMenuButton<_InviteAction>(
      icon: Icon(Icons.more_vert_rounded, color: GlitchColors.textPrimary, size: 20),
      size: 32,
      onSelected: (a) => _onAction(inv, a),
      itemBuilder: (_) => [
        GlitchMenuItem(value: _InviteAction.copy, child: glitchMenuRow(Icons.copy_rounded, s.inviteCopyLink)),
        GlitchMenuItem(
          value: _InviteAction.revoke,
          child: glitchMenuRow(Icons.link_off_rounded, s.inviteRevoke, danger: true),
        ),
      ],
    );
  }
}

class _VanityBlock extends StatefulWidget {
  final int serverId;

  const _VanityBlock({required this.serverId});

  @override
  State<_VanityBlock> createState() => _VanityBlockState();
}

class _VanityBlockState extends State<_VanityBlock> {
  final _ctrl = TextEditingController();
  Vanity? _saved;
  bool _saving = false;
  String? _error;

  static const _maxLength = 32;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onEdit);
    _load();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onEdit);
    _ctrl.dispose();
    super.dispose();
  }

  void _onEdit() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final v = await api.getVanity(widget.serverId);
      if (!mounted) return;
      setState(() {
        _saved = v;
        _error = null;
        _ctrl.text = v.code ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  String get _typed => _ctrl.text.trim().toLowerCase();

  bool get _changed => _saved != null && _typed != (_saved!.code ?? '');

  Future<void> _save() async {
    if (_saving || !_changed) return;
    final s = context.s;
    final code = _typed;
    setState(() => _saving = true);
    try {
      final v = await api.setVanity(widget.serverId, code.isEmpty ? null : code);
      if (!mounted) return;
      setState(() {
        _saved = v;
        _ctrl.text = v.code ?? '';
      });
      GlitchToast.show(context, v.code == null ? s.vanityRemoved : s.vanitySaved, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final error = _error;
    if (error != null) return SettingsRetry(text: error, onRetry: _load);
    final saved = _saved;
    final savedCode = saved?.code;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlitchFormField(
          label: s.vanityTitle,
          hint: s.vanityHint,
          controller: _ctrl,
          enabled: saved != null && !_saving,
          prefixText: '$linkDomain/',
          placeholder: s.vanityPlaceholder,
          maxLength: _maxLength,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]'))],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (savedCode != null && !_changed)
              Expanded(
                child: Text(
                  s.inviteUses(saved!.uses),
                  style: TextStyle(color: GlitchColors.textSecond, fontSize: 13.5),
                ),
              )
            else
              const Spacer(),
            if (_changed)
              GlitchActionButton(label: s.save, onTap: _save, loading: _saving, compact: true)
            else if (savedCode != null)
              GlitchActionButton(
                label: s.inviteCopyLink,
                onTap: () => copyInviteLink(context, savedCode),
                soft: true,
                compact: true,
              ),
          ],
        ),
      ],
    );
  }
}

Widget _inviteCodeText(Invite inv, {double fontSize = 13.5}) => Text(
      inv.code,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: fontSize, color: GlitchColors.textPrimary),
    );

const int _kColCreator = 30;
const int _kColCode = 15;
const int _kColUses = 24;
const int _kColExpires = 23;

class _ExpiresCountdown extends StatefulWidget {
  final DateTime? expiresAt;
  final double fontSize;
  final Color? color;

  const _ExpiresCountdown({required this.expiresAt, this.fontSize = 13.5, this.color});

  @override
  State<_ExpiresCountdown> createState() => _ExpiresCountdownState();
}

class _ExpiresCountdownState extends State<_ExpiresCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.expiresAt != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final until = widget.expiresAt;
    final style = TextStyle(
      fontSize: widget.fontSize,
      color: widget.color ?? GlitchColors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (until == null) {
      return Text(context.s.inviteForever, style: style);
    }
    var left = until.difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final text = '${left.inDays}:${two(left.inHours % 24)}:'
        '${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}';
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
  }
}

class _InvitesTableHead extends StatelessWidget {
  const _InvitesTableHead();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    Widget cell(String t) => Text(
          t.toUpperCase(),
          maxLines: 2,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: GlitchColors.textPrimary),
        );
    return Padding(
      padding: _kTableRowPadding,
      child: Row(
        children: [
          Expanded(flex: _kColCreator, child: cell(s.invitesColCreator)),
          Expanded(flex: _kColCode, child: cell(s.invitesColCode)),
          Expanded(flex: _kColUses, child: cell(s.invitesColUses)),
          Expanded(flex: _kColExpires, child: cell(s.invitesColExpires)),
          const SizedBox(width: _kColMenu),
        ],
      ),
    );
  }
}

class _InviteTableRow extends StatelessWidget {
  final Invite invite;
  final Widget menu;

  const _InviteTableRow({required this.invite, required this.menu});

  @override
  Widget build(BuildContext context) {
    final inv = invite;
    return Padding(
      padding: _kTableRowPadding,
      child: Row(
        children: [
          Expanded(
            flex: _kColCreator,
            child: Row(
              children: [
                ServerUserAvatar(user: inv.creator, name: inv.creator.displayName, size: 34),
                const SizedBox(width: 10),
                Expanded(child: _NameBlock(name: inv.creator.displayName, nickname: inv.creator.nickname)),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Expanded(flex: _kColCode, child: _inviteCodeText(inv)),
          Expanded(
            flex: _kColUses,
            child: Text(
              '${inv.uses}',
              style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary),
            ),
          ),
          Expanded(flex: _kColExpires, child: _ExpiresCountdown(expiresAt: inv.expiresAt)),
          SizedBox(width: _kColMenu, child: menu),
        ],
      ),
    );
  }
}

class _InviteListRow extends StatelessWidget {
  final Invite invite;
  final Widget menu;

  const _InviteListRow({required this.invite, required this.menu});

  @override
  Widget build(BuildContext context) {
    final inv = invite;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServerUserAvatar(user: inv.creator, name: inv.creator.displayName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NameBlock(name: inv.creator.displayName, nickname: inv.creator.nickname),
                const SizedBox(height: 4),
                _inviteCodeText(inv, fontSize: 13),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      context.s.inviteUses(inv.uses),
                      style: TextStyle(fontSize: 12.5, color: GlitchColors.textHint),
                    ),
                    Text(' · ', style: TextStyle(fontSize: 12.5, color: GlitchColors.textHint)),
                    _ExpiresCountdown(expiresAt: inv.expiresAt, fontSize: 12.5, color: GlitchColors.textHint),
                  ],
                ),
              ],
            ),
          ),
          menu,
        ],
      ),
    );
  }
}


class _PagedList<T> extends StatelessWidget {
  final List<T> items;

  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ScrollController? controller;
  final Widget? header;
  final List<Widget> top;
  final Widget? tableHead;
  final Widget Function(T item) row;
  final String emptyText;
  final Widget? footer;

  const _PagedList({
    required this.items,
    required this.loading,
    required this.error,
    required this.onRetry,
    this.controller,
    required this.header,
    required this.top,
    this.tableHead,
    required this.row,
    required this.emptyText,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, header != null ? SettingsTwoPane.topPad : 18, 16, 40),
      children: [
        if (header != null) ...[header!, const SizedBox(height: 22)],
        ...top,
        _body(context),
        if (footer != null) footer!,
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final err = error;
    if (err != null) return _RetryLine(message: err, onRetry: onRetry);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          emptyText,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary),
        ),
      );
    }
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: loading ? 0.5 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          border: Border.all(color: GlitchColors.borderCard),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tableHead != null) ...[
              tableHead!,
              Divider(height: 1, color: GlitchColors.borderCard),
            ],
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: GlitchColors.borderCard),
              row(items[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _RetryLine extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _RetryLine({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(context.s.retry, style: TextStyle(color: GlitchColors.accentBlue)),
          ),
        ],
      ),
    );
  }
}


class _NameBlock extends StatelessWidget {
  final String name;
  final String nickname;

  const _NameBlock({required this.name, required this.nickname});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
          ),
          Text(
            '@$nickname',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
          ),
        ],
      );
}

class _RoleChips extends StatelessWidget {
  final List<MemberRole> roles;

  final Widget? trailing;

  const _RoleChips({required this.roles, this.trailing});

  @override
  Widget build(BuildContext context) {
    final hidden = roles.length - 1;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (roles.isNotEmpty) MemberRoleChip(role: roles.first),
        if (hidden > 0) MemberRolesMore(roles: roles, hidden: hidden),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _InviteCode extends StatelessWidget {
  final String? code;

  const _InviteCode({required this.code});

  @override
  Widget build(BuildContext context) {
    final c = code;
    if (c == null) {
      return Text(
        context.s.serverMembersInviteUnknown,
        style: TextStyle(fontSize: 13.5, color: GlitchColors.textHint),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.link_rounded, size: 15, color: GlitchColors.textSecond),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            c,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

const int _kColName = 30;
const int _kColJoined = 20;
const int _kColAccount = 16;
const int _kColInvite = 17;
const int _kColRoles = 20;
const double _kColMenu = 40;
const EdgeInsets _kTableRowPadding = EdgeInsets.fromLTRB(16, 10, 8, 10);

class _MembersTableHead extends StatelessWidget {
  const _MembersTableHead();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    Widget cell(String t) => Text(
          t.toUpperCase(),
          maxLines: 2,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: GlitchColors.textPrimary),
        );
    return Padding(
      padding: _kTableRowPadding,
      child: Row(
        children: [
          Expanded(flex: _kColName, child: cell(s.serverMembersColName)),
          Expanded(flex: _kColJoined, child: cell(s.serverMembersColJoined)),
          Expanded(flex: _kColAccount, child: cell(s.serverMembersColAccount)),
          Expanded(flex: _kColInvite, child: cell(s.serverMembersColInvite)),
          Expanded(flex: _kColRoles, child: cell(s.serverMembersColRoles)),
          const SizedBox(width: _kColMenu),
        ],
      ),
    );
  }
}

class _MemberTableRow extends StatelessWidget {
  final ServerMember member;
  final Widget menu;
  final Widget? rolePicker;

  const _MemberTableRow({required this.member, required this.menu, this.rolePicker});

  @override
  Widget build(BuildContext context) {
    final m = member;
    final dateStyle = TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary);
    return Padding(
      padding: _kTableRowPadding,
      child: Row(
        children: [
          Expanded(
            flex: _kColName,
            child: Row(
              children: [
                ServerUserAvatar(user: m.user, name: m.shownName, size: 34),
                const SizedBox(width: 10),
                Expanded(child: _NameBlock(name: m.shownName, nickname: m.user.nickname)),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Expanded(flex: _kColJoined, child: Text(formatDay(m.joinedAt), style: dateStyle)),
          Expanded(flex: _kColAccount, child: Text(formatDay(m.accountCreatedAt), style: dateStyle)),
          Expanded(
            flex: _kColInvite,
            child: Align(alignment: Alignment.centerLeft, child: _InviteCode(code: m.inviteCode)),
          ),
          Expanded(
            flex: _kColRoles,
            child: _RoleChips(roles: m.roles, trailing: rolePicker),
          ),
          SizedBox(width: _kColMenu, child: menu),
        ],
      ),
    );
  }
}

class _MemberListRow extends StatelessWidget {
  final ServerMember member;
  final Widget menu;
  final Widget? rolePicker;

  const _MemberListRow({required this.member, required this.menu, this.rolePicker});

  @override
  Widget build(BuildContext context) {
    final m = member;
    final s = context.s;
    final hasChips = m.roles.isNotEmpty || rolePicker != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServerUserAvatar(user: m.user, name: m.shownName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NameBlock(name: m.shownName, nickname: m.user.nickname),
                const SizedBox(height: 4),
                Text(
                  '${s.serverMembersJoinedLine(formatDay(m.joinedAt))} · '
                  '${m.inviteCode ?? s.serverMembersInviteUnknown}',
                  style: TextStyle(fontSize: 12.5, color: GlitchColors.textHint),
                ),
                if (hasChips) ...[
                  const SizedBox(height: 8),
                  _RoleChips(roles: m.roles, trailing: rolePicker),
                ],
              ],
            ),
          ),
          menu,
        ],
      ),
    );
  }
}

class _BanRow extends StatelessWidget {
  final ServerBan ban;
  final VoidCallback onUnban;

  const _BanRow({required this.ban, required this.onUnban});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final b = ban;
    final by = b.bannedBy;
    final reason = b.reason;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServerUserAvatar(user: b.user, name: b.user.displayName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NameBlock(name: b.user.displayName, nickname: b.user.nickname),
                const SizedBox(height: 6),
                Text(
                  reason ?? s.serverBanNoReason,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    color: reason != null ? GlitchColors.textPrimary : GlitchColors.textHint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (by != null) s.serverBannedBy(by.displayName),
                    formatDay(b.createdAt),
                  ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: GlitchColors.textHint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GlitchPressable(
            onTap: onUnban,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: GlitchColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                s.serverUnban,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
