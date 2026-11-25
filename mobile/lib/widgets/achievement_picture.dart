import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/avatar_sizes.dart';
import '../models/achievement.dart';
import '../services/api_service.dart';

class AchievementPicture extends StatelessWidget {
  final Achievement achievement;
  final double size;

  const AchievementPicture({super.key, required this.achievement, required this.size});

  @override
  Widget build(BuildContext context) => Semantics(
        label: achievement.name,
        image: true,
        child: CachedNetworkImage(
          imageUrl: api.mediaUrl(pickAvatarUrl(
            original: achievement.logo,
            sizes: achievement.logoSizes,
            logicalSize: size,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          )!),
          cacheManager: mediaCacheManager,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => SizedBox(width: size, height: size),
        ),
      );
}
