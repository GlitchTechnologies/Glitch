import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../core/avatar_sizes.dart';
import '../widgets/avatar_shape.dart';


const double _iconLogicalSize = 48;
const double _iconPixelRatio = 2;

const Duration _fetchTimeout = Duration(seconds: 3);

Future<Uint8List?> notificationIcon({
  required String? avatar,
  Map<String, String>? avatarSizes,
}) async {
  final url = pickAvatarUrl(
    original: avatar,
    sizes: avatarSizes,
    logicalSize: _iconLogicalSize,
    devicePixelRatio: _iconPixelRatio,
  );
  if (url == null || url.isEmpty) return null;
  ui.Codec? codec;
  ui.Image? source;
  ui.Image? icon;
  try {
    final response = await http.get(Uri.parse(url)).timeout(_fetchTimeout);
    if (response.statusCode != 200) return null;
    const side = (_iconLogicalSize * _iconPixelRatio);
    codec = await ui.instantiateImageCodec(
      response.bodyBytes,
      targetWidth: side.toInt(),
      targetHeight: side.toInt(),
    );
    source = (await codec.getNextFrame()).image;

    final rect = const ui.Rect.fromLTWH(0, 0, side, side);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, rect)..clipPath(AvatarShape.person.outline(rect));
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      rect,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    icon = await recorder.endRecording().toImage(side.toInt(), side.toInt());
    final png = await icon.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    icon?.dispose();
    source?.dispose();
    codec?.dispose();
  }
}
