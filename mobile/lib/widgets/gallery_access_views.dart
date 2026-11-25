import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart' show RequestType;

import '../core/l10n.dart';
import '../services/gallery_access.dart';
import '../theme/app_theme.dart';


class _NoticeSpec {
  final IconData icon;
  final String text;
  final String actionLabel;
  final Future<void> Function() action;

  const _NoticeSpec({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.action,
  });
}

_NoticeSpec? _specFor(
  BuildContext context,
  GalleryStatus status,
  bool limited,
  RequestType mediaType,
  Future<void> Function() onReload,
) {
  // switch-выражением по перечислению: если у GalleryStatus когда-нибудь
  // появится четвёртый исход, сборка упадёт здесь и заставит его показать —
  // а не оставит его молча без картинки на экране.
  return switch (status) {
    GalleryStatus.denied => _NoticeSpec(
        icon: Icons.photo_library_outlined,
        text: context.s.galleryNoAccess,
        actionLabel: context.s.galleryOpenSettings,
        action: openGallerySettings,
      ),
    GalleryStatus.failed => _NoticeSpec(
        icon: Icons.error_outline_rounded,
        text: context.s.galleryLoadFailed,
        actionLabel: context.s.retry,
        action: onReload,
      ),
    GalleryStatus.ok => limited
        ? _NoticeSpec(
            icon: Icons.photo_library_outlined,
            text: context.s.galleryLimitedNotice,
            actionLabel: context.s.galleryLimitedAction,
            action: () async {
              await pickMoreGalleryFiles(mediaType);
              await onReload();
            },
          )
        : null,
  };
}


class GalleryAccessNotice extends StatelessWidget {
  final GalleryStatus status;
  final bool limited;

  final RequestType mediaType;

  final Future<void> Function() onReload;

  const GalleryAccessNotice({
    super.key,
    required this.status,
    required this.limited,
    required this.mediaType,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(context, status, limited, mediaType, onReload);
    if (spec == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(spec.icon, size: 18, color: GlitchColors.accentBlue),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              spec.text,
              style: TextStyle(fontSize: 13, color: GlitchColors.textPrimary),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: spec.action,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                spec.actionLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GlitchColors.accentBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class GalleryAccessEmpty extends StatelessWidget {
  final GalleryStatus status;
  final Future<void> Function() onReload;

  const GalleryAccessEmpty({
    super.key,
    required this.status,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(context, status, false, RequestType.common, onReload);
    if (spec == null) return const SizedBox.shrink();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(spec.icon, color: GlitchColors.textHint, size: 64),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            spec.text,
            textAlign: TextAlign.center,
            style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: spec.action,
          child: Text(
            spec.actionLabel,
            style: TextStyle(color: GlitchColors.accentBlue, fontSize: 15),
          ),
        ),
      ],
    );
  }
}
