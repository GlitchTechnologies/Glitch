import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../screens/image_crop_screen.dart';
import '../widgets/avatar_shape.dart';


Future<XFile?> pickAvatarSource(BuildContext context, {required AvatarShape shape}) async {
  final picked = await _pickFile();
  if (picked == null || !context.mounted) return null;

  return openImageCrop(context, picked, CropTarget.avatar(shape));
}

Future<XFile?> pickRawImage(BuildContext context) => _pickFile();

Future<XFile?> _pickFile() => ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
