import 'package:flutter/material.dart';
import '../models/attach_result.dart';
import '../theme/app_theme.dart';
import 'attach_sheet.dart';

Future<AttachResult?> showAttachPicker(BuildContext context, {required bool allowFiles, required bool allowPoll}) {
  return showModalBottomSheet<AttachResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ModalStatusBarDim(child: AttachSheet(allowFiles: allowFiles, allowPoll: allowPoll)),
  );
}
