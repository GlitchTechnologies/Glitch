import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import 'error_reporter.dart';

enum GalleryStatus {
  ok,

  denied,

  failed,
}

@immutable
class GalleryRead<T> {
  final GalleryStatus status;

  final T? data;

  final bool limited;

  const GalleryRead._({required this.status, this.data, this.limited = false});

  bool get isOk => status == GalleryStatus.ok;
}

const _retryPause = Duration(milliseconds: 350);

/// Единственный способ обратиться к галерее в этом приложении: и список
/// альбомов, и страница снимков, и файл одного снимка идут через него —
/// тогда защита от гонки и учёт частичного доступа достаются каждому месту
/// даром, а не переписываются заново.
Future<GalleryRead<T>> readGallery<T>(Future<T> Function() query) async {
  final permission = await _requestAccess();

  if (permission == null) return GalleryRead._(status: GalleryStatus.failed);

  if (!permission.hasAccess) {
    return GalleryRead._(status: GalleryStatus.denied);
  }

  final limited = permission.isLimited;

  try {
    return GalleryRead._(status: GalleryStatus.ok, data: await query(), limited: limited);
  } catch (_) {
  }

  await Future.delayed(_retryPause);

  try {
    return GalleryRead._(status: GalleryStatus.ok, data: await query(), limited: limited);
  } catch (e, s) {
    errorReporter.report(e, stack: s, context: 'gallery: чтение (вторая попытка)');
    return GalleryRead._(status: GalleryStatus.failed);
  }
}

Future<PermissionState?> _requestAccess() async {
  try {
    return await PhotoManager.requestPermissionExtend();
  } catch (e, s) {
    errorReporter.report(e, stack: s, context: 'gallery: запрос прав');
    return null;
  }
}

/// Зовётся только когда доступ действительно частичный, то есть на Android 14
/// и новее — на более старых версиях такого режима нет вовсе, а сам вызов там
/// ничего не делает.
Future<void> pickMoreGalleryFiles(RequestType type) async {
  try {
    await PhotoManager.presentLimited(type: type);
    return;
  } catch (e, s) {
    errorReporter.report(e, stack: s, context: 'gallery: presentLimited');
  }
  await openGallerySettings();
}

Future<void> openGallerySettings() async {
  try {
    await PhotoManager.openSetting();
  } catch (e, s) {
    errorReporter.report(e, stack: s, context: 'gallery: openSetting');
  }
}
