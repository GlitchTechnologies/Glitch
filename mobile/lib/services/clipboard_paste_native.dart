import 'package:cross_file/cross_file.dart';

typedef PastedMediaHandler = void Function(List<XFile> files);

void Function() listenPastedMedia(PastedMediaHandler onMedia) => () {};
