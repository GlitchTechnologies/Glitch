import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/l10n.dart';
import '../services/api_service.dart';
import '../services/error_reporter.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_icon_button.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController();
  bool _processing = false;
  bool _reportedError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['code'] == null || data['device_name'] == null) return;
    } catch (_) {
      return; // не наш QR — просто продолжаем сканировать
    }

    _processing = true;
    final code = data['code'] as String;
    final deviceName = data['device_name'] as String;

    final confirm = await glitchConfirm(context,
        title: context.s.qrScanConfirmTitle,
        body: context.s.qrScanConfirmBody(deviceName),
        confirmLabel: context.s.qrScanConfirmButton,
        destructive: false);

    if (!mounted) return;
    if (!confirm) {
      _processing = false;
      return;
    }

    try {
      await api.qrApprove(code);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      GlitchToast.show(context, e.message);
      _processing = false;
    } catch (_) {
      if (!mounted) return;
      GlitchToast.show(context, context.s.qrScanApproveError);
      _processing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => _buildScannerError(context, error),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 40,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  context.s.qrScanInstructions,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildScannerError(BuildContext context, MobileScannerException error) {
    final detail = error.errorDetails?.message ?? error.errorCode.name;
    if (!_reportedError) {
      _reportedError = true;
      errorReporter.report(error, screen: 'qr_scanner:camera');
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 40),
              const SizedBox(height: 16),
              Text(
                context.s.qrScanCameraError,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
