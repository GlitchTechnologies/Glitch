import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import '../services/media_platform_web.dart' if (dart.library.io) '../services/media_platform_native.dart';

class VideoThumbPreview extends StatefulWidget {
  final XFile file;
  final double size;
  final int? duration;
  const VideoThumbPreview({super.key, required this.file, required this.size, this.duration});

  @override
  State<VideoThumbPreview> createState() => _VideoThumbPreviewState();
}

class _VideoThumbPreviewState extends State<VideoThumbPreview> {
  Uint8List? _thumb;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await videoFrameBytes(
      widget.file,
      maxWidth: widget.size.toInt() * 2,
      quality: 60,
    );
    if (mounted) setState(() { _thumb = data; _loading = false; });
  }

  String _formatDuration(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    if (_loading) {
      return Container(width: s, height: s, color: const Color(0xFF2c2c2c),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)));
    }
    return Stack(children: [
      _thumb != null
          ? Image.memory(_thumb!, width: s, height: s, fit: BoxFit.cover)
          : Container(width: s, height: s, color: const Color(0xFF2c2c2c)),
      Positioned.fill(child: Center(
        child: Icon(Icons.play_arrow_rounded, color: Colors.white.withOpacity(0.9), size: s * 0.45),
      )),
      if (widget.duration != null)
        Positioned(
          bottom: 3, right: 4,
          child: Text(
            _formatDuration(widget.duration!),
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white,
              shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
          ),
        ),
    ]);
  }
}
