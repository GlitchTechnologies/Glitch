import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../core/l10n.dart';
import '../models/attach_result.dart';
import '../services/file_pick.dart';
import '../theme/app_theme.dart';
import 'glitch_toast.dart';
import 'poll_composer.dart' show openPollComposer;

Future<AttachResult?> showAttachPicker(BuildContext context, {required bool allowFiles, required bool allowPoll}) async {
  final s = context.s;
  final choice = await showModalBottomSheet<_WebAttachChoice>(
    context: context,
    backgroundColor: GlitchColors.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allowFiles) ...[
            _row(sheetContext, Icons.photo_library_outlined, s.attachGallery,
                _WebAttachChoice.media),
            _row(sheetContext, Icons.attach_file, s.attachFile,
                _WebAttachChoice.file),
            _row(sheetContext, Icons.location_on_outlined, s.attachGeo,
                _WebAttachChoice.geo),
          ],
          if (allowPoll)
            _row(sheetContext, Icons.poll_outlined, s.attachPoll, _WebAttachChoice.poll),
        ],
      ),
    ),
  );
  if (choice == null) return null;

  switch (choice) {
    case _WebAttachChoice.media:
      final picked = await ImagePicker().pickMultipleMedia();
      if (picked.isEmpty) return null;
      return PhotosResult(picked, durations: const {});

    case _WebAttachChoice.file:
      final picked = await pickSystemFiles();
      return picked.isEmpty ? null : FileResult(picked.first);

    case _WebAttachChoice.geo:
      return _pickGeo(context);

    case _WebAttachChoice.poll:
      if (!context.mounted) return null;
      final draft = await openPollComposer(context);
      return draft == null ? null : PollResult(draft);
  }
}

Future<AttachResult?> _pickGeo(BuildContext context) async {
  final failedText = context.s.attachGeoFailed;
  final deniedText = context.s.attachGeoDenied;
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (context.mounted) GlitchToast.show(context, deniedText);
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    );
    return GeoResult(pos.latitude, pos.longitude);
  } catch (_) {
    if (context.mounted) GlitchToast.show(context, failedText);
    return null;
  }
}

Widget _row(BuildContext context, IconData icon, String label, _WebAttachChoice value) {
  return ListTile(
    leading: Icon(icon, color: GlitchColors.textPrimary),
    title: Text(label, style: TextStyle(color: GlitchColors.textPrimary)),
    onTap: () => Navigator.pop(context, value),
  );
}

enum _WebAttachChoice { media, file, geo, poll }
