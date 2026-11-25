/// ## Два файла обязаны совпадать
///
/// ## Почему BigInt, а не int
///
/// В Dart на телефоне `int` 64-битный, а в браузере (Flutter Web) `int` — это
/// число JavaScript, точное лишь до 2^53. Права с 54-м битом там молча
/// испортились бы: на Android всё работает, в браузере у человека пропадает
/// одно право, и повторить это невозможно. Ровно поэтому Discord тоже отдаёт
/// маску строкой.
library;

enum Perm {
  viewRoom(0),
  sendMessages(1),
  attachFiles(2),
  addReactions(3),
  mentionEveryone(4),
  manageMessages(5),
  manageRooms(6),
  manageRoles(7),
  createInvite(8),
  kickMembers(9),
  banMembers(10),
  connect(11),
  speak(12),
  muteMembers(13),
  manageServer(14),
  administrator(15),
  viewAuditLog(16), // РЕЗЕРВ: журнала действий в проекте ещё нет
  changeNickname(17),
  manageNicknames(18),
  deafenMembers(19),
  moveMembers(20),
  stream(21),
  sendPolls(22), // 2026-10-15: создавать опросы
  manageStickers(23), // 2026-10-16: стикеры сообщества
  manageWebhooks(24); // 2026-10-23: вебхуки канала

  const Perm(this.bit);

  final int bit;

  BigInt get mask => BigInt.one << bit;
}

const Set<Perm> kRoomOverwritePerms = {
  Perm.viewRoom,
  Perm.sendMessages,
  Perm.attachFiles,
  Perm.addReactions,
  Perm.mentionEveryone,
  Perm.manageMessages,
  Perm.manageRooms,
  Perm.manageRoles,
  Perm.createInvite,
  Perm.connect,
  Perm.speak,
  Perm.muteMembers,
  Perm.deafenMembers,
  Perm.moveMembers,
  Perm.stream,
  Perm.sendPolls,
  Perm.manageWebhooks,
};

class Perms {
  final BigInt value;

  const Perms(this.value);

  static final Perms none = Perms(BigInt.zero);

  factory Perms.fromJson(dynamic raw) {
    if (raw == null) return Perms(BigInt.zero);
    final parsed = BigInt.tryParse(raw.toString());
    if (parsed == null || parsed.isNegative) return Perms(BigInt.zero);
    return Perms(parsed);
  }

  bool has(Perm p) => (value & p.mask) != BigInt.zero;

  Perms withPerm(Perm p) => Perms(value | p.mask);

  Perms withoutPerm(Perm p) => Perms(value & ~p.mask);

  bool can(Perm p) => has(Perm.administrator) || has(p);

  String toJson() => value.toString();

  @override
  bool operator ==(Object other) => other is Perms && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
