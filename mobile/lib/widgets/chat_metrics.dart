import 'dart:math' as math;
import 'package:flutter/material.dart';



const double kMaxChatContentWidth = 740;

class ChatContentWidth extends StatelessWidget {
  final Widget? child;
  final Widget Function(BuildContext context, double sideInset)? builder;
  final double maxWidth;

  const ChatContentWidth({
    super.key,
    required Widget this.child,
    this.maxWidth = kMaxChatContentWidth,
  }) : builder = null;

  const ChatContentWidth.scrollable({
    super.key,
    required Widget Function(BuildContext context, double sideInset) this.builder,
    this.maxWidth = kMaxChatContentWidth,
  }) : child = null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final canvas = math.min(available, maxWidth);

        final build = builder;
        if (build != null) {
          return _ChatMetricsScope(
            canvas: canvas,
            child: SizedBox(
              width: available,
              child: Builder(builder: (ctx) => build(ctx, (available - canvas) / 2)),
            ),
          );
        }
        return _ChatMetricsScope(
          canvas: canvas,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: canvas),
              child: child!,
            ),
          ),
        );
      },
    );
  }
}


const double kFeedSidePadding = 8;

const double kMessageRowPadLeft = 8;
const double kMessageRowPadRight = 12;

const double kMessageAvatarSize = 40;
const double kMessageAvatarGap = 12;
const double kMessageGutter = kMessageAvatarSize + kMessageAvatarGap;


const double _mediaMaxWidth = 440;
const double _mediaMaxHeight = 350;
const double _cardMaxWidth = 400;
const double _embedMaxWidth = 520;
const double _embedImageMaxWidth = 400;

const double _stickerMax = 160;
const double _stickerMin = 96;
const double _videoNoteMax = 220;
const double _videoNoteMin = 120;

/// Во сколько раз кружок увеличивается при просмотре (тап запускает
/// воспроизведение — см. widgets/video_note_player.dart). Число живёт здесь, а
/// не в плеере: диаметр в покое ([ChatMetrics.videoNote]) обязан заранее
/// оставлять место под увеличенное состояние, иначе на телефоне кружок при
/// просмотре вылез бы за колонку содержимого (реальный случай 2026-08-27, тогда
/// ещё в пузыре: 220×1.4=308 не помещалось в потолок сообщения).
const double videoNotePlayingScale = 1.4;

@immutable
class ChatMetrics {
  final double canvas;

  const ChatMetrics._(this.canvas);

  double get content => math.max(
        0,
        canvas - 2 * kFeedSidePadding - kMessageRowPadLeft - kMessageRowPadRight - kMessageGutter,
      );

  double get media => math.min(content, _mediaMaxWidth);

  double singleMedia(double? aspectRatio) => aspectRatio == null || aspectRatio <= 0
      ? media
      : math.min(media, _mediaMaxHeight * aspectRatio);

  double get card => math.min(content, _cardMaxWidth);

  double get embed => math.min(content, _embedMaxWidth);

  double embedImage(double? aspectRatio) {
    final cap = math.min(embed, _embedImageMaxWidth);
    return aspectRatio == null || aspectRatio <= 0 ? cap : math.min(cap, _mediaMaxHeight * aspectRatio);
  }

  double get sticker => content.clamp(_stickerMin, _stickerMax).toDouble();

  double get videoNote => math
      .min(content.clamp(_videoNoteMin, _videoNoteMax).toDouble(), content / videoNotePlayingScale);

  static ChatMetrics of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ChatMetricsScope>();
    if (scope != null) return ChatMetrics._(scope.canvas);

    assert(
      false,
      'ChatMetrics.of: над этим местом нет ChatContentWidth — ширина будет '
      'посчитана от окна, а не от колонки ленты, и на сайте разъедется. '
      'Оберните ленту в ChatContentWidth (см. widgets/chat_metrics.dart).',
    );
    final windowWidth = MediaQuery.sizeOf(context).width;
    return ChatMetrics._(math.min(windowWidth, kMaxChatContentWidth));
  }
}

class _ChatMetricsScope extends InheritedWidget {
  final double canvas;

  const _ChatMetricsScope({required this.canvas, required super.child});

  @override
  bool updateShouldNotify(_ChatMetricsScope old) => old.canvas != canvas;
}
