import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/relationship.dart';
import '../providers/friends.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'glitch_dialog.dart';
import 'glitch_hover_row.dart';
import 'glitch_icon_button.dart';
import 'glitch_toast.dart';
import 'glitch_tooltip.dart';

class FriendBannerButton extends StatelessWidget {
  final int userId;

  final bool hidden;

  const FriendBannerButton({super.key, required this.userId, this.hidden = false});

  static const double _size = 32;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: friends,
      builder: (context, _) {
        final kind = friends.of(userId)?.kind;
        if (hidden ||
            userId == authService.currentUser?.id ||
            !friends.loaded) {
          return const SizedBox.shrink();
        }
        final isFriend = kind == RelationshipKind.friend;
        final inactive = isFriend || kind == RelationshipKind.outgoing;
        final Widget icon = friends.isBusy(userId)
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(
                isFriend ? Icons.how_to_reg_rounded : Icons.person_add_alt_1_rounded,
                size: 17,
                color: Colors.white,
              );
        return Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
              ),
              child: GlitchTooltip(
                message: isFriend
                    ? context.s.tipFriend
                    : kind == RelationshipKind.outgoing
                        ? context.s.tipFriendRequestSent
                        : context.s.tipAddFriend,
                child: GlitchIconButton(
                  size: _size,
                  extent: _size,
                  onTap: inactive || friends.isBusy(userId)
                      ? null
                      : () => runFriendAction(context, () => friends.request(userId)),
                  icon: icon,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum FriendMenuAction { ignore, cancel, remove }

FriendMenuAction? friendMenuActionFor(int userId) => switch (friends.of(userId)?.kind) {
      RelationshipKind.incoming => FriendMenuAction.ignore,
      RelationshipKind.outgoing => FriendMenuAction.cancel,
      RelationshipKind.friend => FriendMenuAction.remove,
      null => null,
    };

String friendMenuLabel(BuildContext context, FriendMenuAction action) => switch (action) {
      FriendMenuAction.ignore => context.s.friendsIgnoreRequest,
      FriendMenuAction.cancel => context.s.friendsCancelRequest,
      FriendMenuAction.remove => context.s.friendsRemove,
    };

Future<void> runFriendMenuAction(
  BuildContext context,
  FriendMenuAction action, {
  required int userId,
  required String displayName,
}) async {
  if (action == FriendMenuAction.remove) {
    await confirmRemoveFriend(context, userId: userId, displayName: displayName);
    return;
  }
  await runFriendAction(context, () => friends.remove(userId));
}

Future<void> confirmRemoveFriend(
  BuildContext context, {
  required int userId,
  required String displayName,
}) async {
  final s = context.s;
  final ok = await glitchConfirm(
    context,
    title: s.friendsRemoveTitle(displayName),
    body: s.friendsRemoveBody(displayName),
    confirmLabel: s.friendsRemove,
  );
  if (!ok || !context.mounted) return;
  await runFriendAction(context, () => friends.remove(userId));
}

Future<void> runFriendAction(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) GlitchToast.show(context, errorMessage(e));
  }
}
