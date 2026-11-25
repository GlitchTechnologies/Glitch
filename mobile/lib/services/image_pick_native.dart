import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import '../screens/avatar_gallery_screen.dart';
import '../widgets/avatar_shape.dart';


Future<XFile?> pickAvatarSource(BuildContext context, {required AvatarShape shape}) {
  return Navigator.of(context, rootNavigator: true).push<XFile?>(
    MaterialPageRoute(builder: (_) => AvatarGalleryScreen(cropShape: shape)),
  );
}

Future<XFile?> pickRawImage(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<XFile?>(
    MaterialPageRoute(
      builder: (_) => const AvatarGalleryScreen(cropShape: null, gifAsIs: false),
    ),
  );
}
