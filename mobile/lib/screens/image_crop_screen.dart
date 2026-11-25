import 'package:cross_file/cross_file.dart';
import '../services/media_platform_web.dart' if (dart.library.io) '../services/media_platform_native.dart';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../core/l10n.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart' show errorMessage;
import '../theme/app_theme.dart';
import '../widgets/adaptive_sheet.dart' show openAdaptiveWindow;
import '../widgets/avatar_shape.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_slider.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/glitch_icon_button.dart';



enum _CropKind { avatar, banner }

class CropTarget {
  final _CropKind _kind;

  /// Размер результата в пикселях. Пропорция рамки берётся отсюда же, чтобы
  /// рамка и итоговый файл не могли разойтись.
  final int outWidth;
  final int outHeight;

  final AvatarShape? shape;

  final Size wideSize;

  const CropTarget._(this._kind, this.outWidth, this.outHeight, this.shape, this.wideSize);

  static const Size _squareWindow = Size(560, 760);

  const CropTarget.avatar(AvatarShape shape)
      : this._(_CropKind.avatar, 512, 512, shape, _squareWindow);

  const CropTarget.banner({required int width, required int height})
      : this._(_CropKind.banner, width, height, null, const Size(900, 640));

  double get aspect => outWidth / outHeight;

  bool get _webp => _kind != _CropKind.avatar;

  int get _quality => _kind == _CropKind.banner ? 88 : 90;

  String get _filePrefix => switch (_kind) {
        _CropKind.avatar => 'glitch_avatar',
        _CropKind.banner => 'banner',
      };

  String _title(BuildContext context) => switch (_kind) {
        _CropKind.avatar => context.s.galleryCropTitle,
        _CropKind.banner => context.s.bannerCropTitle,
      };
}


Future<XFile?> openImageCrop(BuildContext context, XFile file, CropTarget target) {
  Widget build(BuildContext _) => ImageCropScreen(imageFile: file, target: target);
  return openAdaptiveWindow<XFile>(
    context,
    narrowBuilder: build,
    wideBuilder: build,
    wideSize: target.wideSize,
  );
}


class ImageCropScreen extends StatefulWidget {
  final XFile imageFile;
  final CropTarget target;

  const ImageCropScreen({super.key, required this.imageFile, required this.target});

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> with ThemeAwareState<ImageCropScreen> {
  static const double _maxZoom = 8;

  ui.Image? _srcImage;

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _scaleAtStart = 1.0;
  Offset _offsetAtStart = Offset.zero;
  Offset _focalAtStart = Offset.zero;

  bool _saving = false;
  bool _layoutReady = false;

  Rect _displayRect = Rect.zero;
  Size _cropSize = Size.zero;

  double _minScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _srcImage?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _srcImage = frame.image);
    } catch (e) {
      if (!mounted) return;
      GlitchToast.show(context, errorMessage(e));
      Navigator.pop(context);
    }
  }

  void _updateLayout(Size size) {
    final img = _srcImage;
    if (img == null || size.isEmpty) return;

    final imgAspect = img.width / img.height;
    double dispW, dispH;
    if (imgAspect > size.width / size.height) {
      dispW = size.width;
      dispH = dispW / imgAspect;
    } else {
      dispH = size.height;
      dispW = dispH * imgAspect;
    }
    _displayRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: dispW,
      height: dispH,
    );

    final aspect = widget.target.aspect;
    final maxW = size.width * 0.84;
    final maxH = size.height * 0.84;
    _cropSize = maxW / maxH > aspect ? Size(maxH * aspect, maxH) : Size(maxW, maxW / aspect);

    _minScale = max(_cropSize.width / dispW, _cropSize.height / dispH);

    if (!_layoutReady) {
      _layoutReady = true;
      _scale = _minScale;
      _offset = Offset.zero;
    } else {
      _scale = _scale.clamp(_minScale, _minScale * _maxZoom);
      _offset = _clampOffset(_offset, _scale);
    }
  }

  Offset _clampOffset(Offset o, double scale) {
    if (_displayRect.isEmpty || _cropSize.isEmpty) return o;
    final maxX = max(0.0, _displayRect.width / 2 * scale - _cropSize.width / 2);
    final maxY = max(0.0, _displayRect.height / 2 * scale - _cropSize.height / 2);
    return Offset(o.dx.clamp(-maxX, maxX), o.dy.clamp(-maxY, maxY));
  }

  void _onScaleStart(ScaleStartDetails d) {
    _scaleAtStart = _scale;
    _offsetAtStart = _offset;
    _focalAtStart = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final newScale = (_scaleAtStart * d.scale).clamp(_minScale, _minScale * _maxZoom);
    setState(() {
      _scale = newScale;
      _offset = _clampOffset(_offsetAtStart + (d.localFocalPoint - _focalAtStart), newScale);
    });
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _srcImage == null) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      final newScale = (_scale * exp(-dy * 0.002)).clamp(_minScale, _minScale * _maxZoom);
      if (newScale == _scale) return;
      final fromCenter = event.localPosition - _displayRect.center;
      final offset = fromCenter - (fromCenter - _offset) * (newScale / _scale);
      setState(() {
        _scale = newScale;
        _offset = _clampOffset(offset, newScale);
      });
    });
  }

  Future<void> _apply() async {
    final img = _srcImage;
    if (img == null || _displayRect.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final target = widget.target;
      final cx = _displayRect.center.dx;
      final cy = _displayRect.center.dy;
      final halfW = _cropSize.width / 2;
      final halfH = _cropSize.height / 2;

      Offset toImage(double sx, double sy) {
        final px = cx + (sx - _offset.dx - cx) / _scale;
        final py = cy + (sy - _offset.dy - cy) / _scale;
        return Offset(
          (px - _displayRect.left) / _displayRect.width * img.width,
          (py - _displayRect.top) / _displayRect.height * img.height,
        );
      }

      final srcRect = Rect.fromPoints(
        toImage(cx - halfW, cy - halfH),
        toImage(cx + halfW, cy + halfH),
      );

      final outRect = Rect.fromLTWH(0, 0, target.outWidth.toDouble(), target.outHeight.toDouble());
      final recorder = ui.PictureRecorder();
      Canvas(recorder, outRect).drawImageRect(
        img,
        srcRect,
        outRect,
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(target.outWidth, target.outHeight);
      picture.dispose();
      final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      if (byteData == null || !mounted) return;

      var bytes = byteData.buffer.asUint8List();
      if (target._webp) {
        bytes = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: target.outWidth,
          minHeight: target.outHeight,
          quality: target._quality,
          format: CompressFormat.webp,
        );
        if (!mounted) return;
      }

      final out = await saveTempBytes(
        bytes,
        '${target._filePrefix}_${DateTime.now().millisecondsSinceEpoch}.${target._webp ? 'webp' : 'png'}',
      );
      if (out == null || !mounted) return;
      Navigator.pop(context, out);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final light = themeProvider.isLight;
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            ColoredBox(
              color: GlitchColors.bg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 18, 8),
                child: Row(
                  children: [
                    GlitchIconButton(
                      icon: Icon(Icons.close_rounded, color: GlitchColors.textPrimary, size: 24),
                      onTap: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          widget.target._title(context),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),

            Expanded(
              child: _srcImage == null
                  ? Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue))
                  : Listener(
                      onPointerSignal: _onPointerSignal,
                      child: LayoutBuilder(builder: (context, constraints) {
                      _updateLayout(Size(constraints.maxWidth, constraints.maxHeight));
                      return GestureDetector(
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        child: ClipRect(
                          child: SizedBox.expand(
                            child: Stack(children: [
                              Positioned.fill(
                                child: Transform.translate(
                                  offset: _offset,
                                  child: Transform.scale(
                                    scale: _scale,
                                    child: CustomPaint(painter: _ImagePainter(_srcImage!, _displayRect)),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _CropMaskPainter(
                                      cropSize: _cropSize,
                                      shape: widget.target.shape,
                                      maskColor: light
                                          ? Colors.white.withOpacity(0.86)
                                          : Colors.black.withOpacity(0.86),
                                      borderColor: light
                                          ? Colors.black.withOpacity(0.7)
                                          : Colors.white.withOpacity(0.88),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      );
                    }),
                    ),
            ),

            ColoredBox(
              color: GlitchColors.bg,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                  child: Row(children: [
                    Icon(Icons.circle, size: 8, color: GlitchColors.textDim),
                    const SizedBox(width: 14),
                    Expanded(
                      child: GlitchSlider(
                        value: _scale,
                        min: _minScale,
                        max: _minScale * _maxZoom,
                        onChanged: _srcImage == null
                            ? null
                            : (v) => setState(() {
                                  _scale = v;
                                  _offset = _clampOffset(_offset, v);
                                }),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Icon(Icons.circle, size: 18, color: GlitchColors.textDim),
                  ]),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
                  child: GlitchActionButton(
                    label: context.s.done,
                    onTap: _apply,
                    loading: _saving,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}


class _ImagePainter extends CustomPainter {
  final ui.Image image;
  final Rect displayRect;

  const _ImagePainter(this.image, this.displayRect);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      displayRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter old) => old.image != image || old.displayRect != displayRect;
}

class _CropMaskPainter extends CustomPainter {
  final Size cropSize;
  final AvatarShape? shape;
  final Color maskColor;
  final Color borderColor;

  const _CropMaskPainter({
    required this.cropSize,
    required this.shape,
    required this.maskColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cropSize.isEmpty) return;
    final frame = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cropSize.width,
      height: cropSize.height,
    );
    final outline = shape?.outline(frame) ?? (Path()..addRect(frame));

    canvas.drawPath(
      Path()
        ..addRect(Offset.zero & size)
        ..addPath(outline, Offset.zero)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = maskColor,
    );
    canvas.drawPath(
      outline,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropMaskPainter old) =>
      old.cropSize != cropSize || old.shape != shape || old.maskColor != maskColor || old.borderColor != borderColor;
}
