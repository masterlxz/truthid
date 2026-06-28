import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _scanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;

    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;

    setState(() => _scanned = true);

    try {
      final payload = jsonDecode(rawValue) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).pop(payload);
    } catch (_) {
      setState(() => _scanned = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid QR — try again')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          IgnorePointer(
            child: CustomPaint(
              painter: _ScanOverlayPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          const Positioned(
            bottom: 80,
            left: 32,
            right: 32,
            child: Text(
              'Point the camera at the QR code on your screen',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  static const double _boxSize = 260;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: _boxSize,
      height: _boxSize,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    // Dark overlay with transparent cutout
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black54,
    );
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.dstOut);
    canvas.restore();

    // Accent border around the cutout
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
