import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'banner_picture.dart';
import 'glitch_avatar.dart';

const int kUserBannerWidth = 1500;
const int kUserBannerHeight = 600;
const double kUserBannerAspect = kUserBannerWidth / kUserBannerHeight;

class UserBanner extends StatelessWidget {
  final String? url;
  final Map<String, String>? sizes;

  final Uint8List? localBytes;

  final Color? color;

  final String nickname;

  const UserBanner({
    super.key,
    this.url,
    this.sizes,
    this.localBytes,
    required this.color,
    required this.nickname,
  });

  Widget _fill() {
    final c = color;
    if (c != null) return ColoredBox(color: c);
    const gradients = GlitchColors.avatarGradients;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradients[GlitchAvatar.colorFromNickname(nickname) % gradients.length],
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BannerPicture(url: url, sizes: sizes, localBytes: localBytes, fallback: _fill());
}
