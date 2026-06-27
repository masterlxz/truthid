import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
        const SnackBar(content: Text('QR inválido — tente de novo')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
