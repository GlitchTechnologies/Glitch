import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import '../core/glitch_plus_gate.dart';
import '../core/l10n.dart';
import '../screens/image_crop_screen.dart';
import '../widgets/avatar_shape.dart';
import 'media_service.dart';
import 'image_pick_web.dart' if (dart.library.io) 'image_pick_native.dart';

Future<XFile?> pickAndCropAvatar(BuildContext context, {required AvatarShape shape}) async {
  if (!context.mounted) return null;
  final result = await pickAvatarSource(context, shape: shape);
  if (result == null) return null;
  return mediaService.compressAvatar(result);
}

Future<XFile?> pickBannerImage(
  BuildContext context, {
  required int outWidth,
  required int outHeight,
}) async {
  final raw = await pickRawImage(context);
  if (raw == null || !context.mounted) return null;
  final s = context.s;
  if (mediaService.isGif(raw)) {
    final allowed = await ensureGlitchPlus(
      context,
      title: s.glitchPlusGifBannerTitle,
      body: s.glitchPlusGifBannerBody,
    );
    return allowed ? raw : null;
  }
  return openImageCrop(context, raw, CropTarget.banner(width: outWidth, height: outHeight));
}

Future<XFile?> pickStickerImage(BuildContext context) => pickRawImage(context);

String mimeFromFileName(String path) {
  final ext = path.split('.').last.toLowerCase();
  const map = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
    'png': 'image/png', 'webp': 'image/webp',
    'gif': 'image/gif',
  };
  return map[ext] ?? 'image/jpeg';
}
