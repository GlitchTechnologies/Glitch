import 'package:flutter/material.dart';
import '../core/adaptive_open.dart';
import '../theme/app_theme.dart';
import 'glitch_dialog.dart' show glitchWindowShape;
import 'glitch_menu.dart';
import 'glitch_icon_button.dart';
import 'platform_view_button_interceptor.dart';

const double kAdaptiveSheetWidth = 420;

const double _kSheetClose = 32;

Future<T?> showAdaptiveSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext ctx, StateSetter setModal) bodyBuilder,
  double wideWidth = kAdaptiveSheetWidth,
}) {
  if (isWideLayout(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: GlitchColors.bgCard,
        shape: glitchWindowShape(),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wideWidth),
          child: StatefulBuilder(builder: (ctx, setModal) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24 + _kSheetClose, 12),
                        child: Text(title,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                      ),
                      Positioned(
                        top: 16,
                        right: 12,
                        child: GlitchIconButton(
                          icon: Icon(Icons.close_rounded, size: 22),
                          size: _kSheetClose,
                          extent: _kSheetClose,
                          onTap: () => Navigator.pop(ctx),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(child: SingleChildScrollView(child: bodyBuilder(ctx, setModal))),
                const SizedBox(height: 4),
              ],
            );
          }),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: GlitchColors.bgCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 38, height: 4,
              decoration: BoxDecoration(color: GlitchColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 18),
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
            const SizedBox(height: 16),
            Flexible(child: SingleChildScrollView(child: bodyBuilder(ctx, setModal))),
          ],
        ),
      );
    }),
  );
}

Future<T?> openAdaptivePicker<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) narrowBuilder,
  required Widget Function(BuildContext ctx, StateSetter setModal) wideBodyBuilder,
  double wideWidth = kAdaptiveSheetWidth,
}) {
  if (isWideLayout(context)) {
    return showAdaptiveSheet<T>(context, title: title, bodyBuilder: wideBodyBuilder, wideWidth: wideWidth);
  }
  return Navigator.push<T>(context, MaterialPageRoute(builder: narrowBuilder));
}

Future<T?> openAdaptiveForm<T>(
  BuildContext context, {
  required Widget Function(BuildContext) narrowBuilder,
  required Widget Function(BuildContext) wideBuilder,
}) {
  if (isWideLayout(context)) {
    return showDialog<T>(context: context, barrierDismissible: false, builder: wideBuilder);
  }
  return Navigator.push<T>(context, MaterialPageRoute(builder: narrowBuilder));
}

Future<void> openAdaptivePopup(
  BuildContext anchorContext, {
  required double width,
  GlitchPopupSide? side,
  bool growRight = false,
  Rect? anchorRect,
  double? horizontalScreenMargin,
  required Widget Function(Future<void> Function() close, double maxHeight) builder,
}) async {
  if (isWideLayout(anchorContext)) {
    await openGlitchPopup(
      anchorContext,
      width: width,
      side: side,
      growRight: growRight,
      anchorRect: anchorRect,
      horizontalScreenMargin: horizontalScreenMargin,
      builder: (close, maxHeight) => GlitchPopupCard(
        maxHeight: maxHeight,
        child: builder(close, maxHeight),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: anchorContext,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: GlitchColors.bgCard,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      final keyboard = media.viewInsets.bottom;
      final maxHeight = (media.size.height - keyboard) * 0.9;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Stack(
            children: [
              builder(() async => Navigator.pop(ctx), maxHeight),
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<T?> openAdaptiveWindow<T>(
  BuildContext context, {
  required Widget Function(BuildContext) narrowBuilder,
  required Widget Function(BuildContext) wideBuilder,
  Size wideSize = const Size(920, 720),
}) {
  if (isWideLayout(context)) {
    return showDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => ModalStatusBarDim(
        child: Dialog(
          backgroundColor: GlitchColors.bg,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: glitchWindowShape(),
          insetPadding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wideSize.width, maxHeight: wideSize.height),
            child: SizedBox.expand(child: wideBuilder(ctx)),
          ),
        ),
      ),
    );
  }
  return Navigator.of(context, rootNavigator: true).push<T>(MaterialPageRoute(builder: narrowBuilder));
}


class AdaptiveWindowCloseButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool overPlatformView;

  const AdaptiveWindowCloseButton({super.key, required this.onPressed, this.overPlatformView = false});

  @override
  Widget build(BuildContext context) => Positioned(
        top: 12,
        right: 12,
        child: PlatformViewButtonInterceptor(
          enabled: overPlatformView,
          child: GlitchIconButton(
            icon: Icon(Icons.close_rounded, color: GlitchColors.textPrimary, size: 22),
            onTap: onPressed,
          ),
        ),
      );
}
