import 'package:flutter/widgets.dart';

import 'l10n.dart';
import 'permissions.dart';
import '../models/server.dart' show RoomKind;


typedef PermGroup = (String Function(BuildContext) title, List<Perm> perms);

final List<PermGroup> kPermGroups = [
  (_titleGeneral, [
    Perm.viewRoom,
    Perm.sendMessages,
    Perm.attachFiles,
    Perm.addReactions,
    Perm.sendPolls,
    Perm.mentionEveryone,
  ]),
  (_titleModeration, [
    Perm.manageMessages,
    Perm.manageRooms,
    Perm.manageRoles,
    Perm.createInvite,
    Perm.kickMembers,
    Perm.banMembers,
    Perm.viewAuditLog,
  ]),
  (_titleMembers, [
    Perm.changeNickname,
    Perm.manageNicknames,
  ]),
  (_titleVoice, [
    Perm.connect,
    Perm.speak,
    Perm.stream,
    Perm.muteMembers,
    Perm.deafenMembers,
    Perm.moveMembers,
  ]),
  (_titleServer, [
    Perm.manageServer,
    Perm.manageStickers,
    Perm.manageWebhooks,
    Perm.administrator,
  ]),
];

const Set<Perm> _kTextOnlyPerms = {
  Perm.sendMessages,
  Perm.attachFiles,
  Perm.addReactions,
  Perm.sendPolls,
  Perm.mentionEveryone,
  Perm.manageMessages,
  Perm.manageWebhooks, // вебхук бывает только у текстового канала
};

const Set<Perm> _kVoiceOnlyPerms = {
  Perm.connect,
  Perm.speak,
  Perm.stream,
  Perm.muteMembers,
  Perm.deafenMembers,
  Perm.moveMembers,
};

bool placeShowsPerm(RoomKind? kind, Perm p) =>
    kRoomOverwritePerms.contains(p) &&
    switch (kind) {
      null => true,
      RoomKind.text => !_kVoiceOnlyPerms.contains(p),
      RoomKind.voice => !_kTextOnlyPerms.contains(p),
    };

String _titleGeneral(BuildContext c) => c.s.permGroupGeneral;
String _titleModeration(BuildContext c) => c.s.permGroupModeration;
String _titleMembers(BuildContext c) => c.s.permGroupMembers;
String _titleVoice(BuildContext c) => c.s.permGroupVoice;
String _titleServer(BuildContext c) => c.s.permGroupServer;

String permLabel(BuildContext c, Perm p, {bool inRoom = false}) {
  final s = c.s;
  if (inRoom && p == Perm.manageRoles) return s.permManageRoomPerms;
  return switch (p) {
    Perm.viewRoom => s.permViewRoom,
    Perm.sendMessages => s.permSendMessages,
    Perm.attachFiles => s.permAttachFiles,
    Perm.addReactions => s.permAddReactions,
    Perm.mentionEveryone => s.permMentionEveryone,
    Perm.manageMessages => s.permManageMessages,
    Perm.manageRooms => s.permManageRooms,
    Perm.manageRoles => s.permManageRoles,
    Perm.createInvite => s.permCreateInvite,
    Perm.kickMembers => s.permKickMembers,
    Perm.banMembers => s.permBanMembers,
    Perm.viewAuditLog => s.permViewAuditLog,
    Perm.changeNickname => s.permChangeNickname,
    Perm.manageNicknames => s.permManageNicknames,
    Perm.connect => s.permConnect,
    Perm.speak => s.permSpeak,
    Perm.stream => s.permStream,
    Perm.sendPolls => s.permSendPolls,
    Perm.muteMembers => s.permMuteMembers,
    Perm.deafenMembers => s.permDeafenMembers,
    Perm.moveMembers => s.permMoveMembers,
    Perm.manageServer => s.permManageServer,
    Perm.manageStickers => s.permManageStickers,
    Perm.manageWebhooks => s.permManageWebhooks,
    Perm.administrator => s.permAdministrator,
  };
}

String permDesc(BuildContext c, Perm p, {bool inRoom = false}) {
  final s = c.s;
  if (inRoom && p == Perm.manageRoles) return s.permManageRoomPermsDesc;
  return switch (p) {
    Perm.viewRoom => s.permViewRoomDesc,
    Perm.sendMessages => s.permSendMessagesDesc,
    Perm.attachFiles => s.permAttachFilesDesc,
    Perm.addReactions => s.permAddReactionsDesc,
    Perm.mentionEveryone => s.permMentionEveryoneDesc,
    Perm.manageMessages => s.permManageMessagesDesc,
    Perm.manageRooms => s.permManageRoomsDesc,
    Perm.manageRoles => s.permManageRolesDesc,
    Perm.createInvite => s.permCreateInviteDesc,
    Perm.kickMembers => s.permKickMembersDesc,
    Perm.banMembers => s.permBanMembersDesc,
    Perm.viewAuditLog => s.permViewAuditLogDesc,
    Perm.changeNickname => s.permChangeNicknameDesc,
    Perm.manageNicknames => s.permManageNicknamesDesc,
    Perm.connect => s.permConnectDesc,
    Perm.speak => s.permSpeakDesc,
    Perm.stream => s.permStreamDesc,
    Perm.sendPolls => s.permSendPollsDesc,
    Perm.muteMembers => s.permMuteMembersDesc,
    Perm.deafenMembers => s.permDeafenMembersDesc,
    Perm.moveMembers => s.permMoveMembersDesc,
    Perm.manageServer => s.permManageServerDesc,
    Perm.manageStickers => s.permManageStickersDesc,
    Perm.manageWebhooks => s.permManageWebhooksDesc,
    Perm.administrator => s.permAdministratorDesc,
  };
}

