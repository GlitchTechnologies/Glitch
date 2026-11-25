import 'package:flutter/material.dart';


const double kMediaGridTileHeight = 260;

const double kMediaGridGap = 2;

typedef MediaTileBuilder = Widget Function(int index, double width, double? height);

class MediaGridLayout extends StatelessWidget {
  final int count;
  final MediaTileBuilder tile;

  const MediaGridLayout({
    super.key,
    required this.count,
    required this.tile,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final half = (w - kMediaGridGap) / 2;
      const h = kMediaGridTileHeight;
      const halfH = (h - kMediaGridGap) / 2;

      if (count <= 0) return const SizedBox.shrink();

      if (count == 1) return tile(0, w, null);

      if (count == 2) {
        return Row(mainAxisSize: MainAxisSize.min, children: [
          tile(0, half, h),
          const SizedBox(width: kMediaGridGap),
          tile(1, half, h),
        ]);
      }

      if (count == 3) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tile(0, half, h),
            const SizedBox(width: kMediaGridGap),
            Column(mainAxisSize: MainAxisSize.min, children: [
              tile(1, half, halfH),
              const SizedBox(height: kMediaGridGap),
              tile(2, half, halfH),
            ]),
          ],
        );
      }

      final extra = count - 4;
      Widget lastTile = tile(3, half, halfH);
      if (extra > 0) {
        lastTile = Stack(children: [
          lastTile,
          Container(
            width: half, height: halfH,
            color: Colors.black54,
            child: Center(
              child: Text('+$extra',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
            ),
          ),
        ]);
      }
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          tile(0, half, halfH),
          const SizedBox(width: kMediaGridGap),
          tile(1, half, halfH),
        ]),
        const SizedBox(height: kMediaGridGap),
        Row(mainAxisSize: MainAxisSize.min, children: [
          tile(2, half, halfH),
          const SizedBox(width: kMediaGridGap),
          lastTile,
        ]),
      ]);
    });
  }
}
