class ChatFolder {
  final int id;
  final String name;
  final int position;
  final List<int> chatIds;

  const ChatFolder({
    required this.id,
    required this.name,
    required this.position,
    this.chatIds = const [],
  });

  factory ChatFolder.fromJson(Map<String, dynamic> j) => ChatFolder(
    id: j['id'],
    name: j['name'],
    position: j['position'] ?? 0,
    chatIds: (j['chat_ids'] as List?)?.map((e) => e as int).toList() ?? const [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'position': position,
    'chat_ids': chatIds,
  };
}

class ChatPin {
  final int folderId;
  final int chatId;

  const ChatPin({required this.folderId, required this.chatId});

  factory ChatPin.fromJson(Map<String, dynamic> j) =>
      ChatPin(folderId: j['folder_id'], chatId: j['chat_id']);

  Map<String, dynamic> toJson() => {'folder_id': folderId, 'chat_id': chatId};
}
