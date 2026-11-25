import 'dart:io';
import 'package:flutter/material.dart';

Widget localImage(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  return Image.file(File(path), width: width, height: height, fit: fit);
}
