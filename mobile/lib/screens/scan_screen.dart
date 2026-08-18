import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../l10n/l10n_extensions.dart';
import '../theme.dart';

// Tela de câmera genérica — decodifica o QR cru e delega a validação/parsing
// pro chamador via `parse`. `null` de volta = QR inválido, mostra o aviso e
// continua escaneando (sem fechar a tela); um valor não-nulo fecha a tela e
// devolve esse valor pro caller. Generalizada na Sessão 132 a partir da
// versão original (só pareamento, JSON hardcoded) pra também dar suporte ao
// scan de QR de TOTP (retorna o secret já limpo via parseTotpSecret).
//
// `title`/`instructions`/`invalidMessage` são opcionais e nulos por padrão —
// não dá pra usar `context.l10n` como valor default de parâmetro (não é
// constante em tempo de compilação), então o fallback pros textos padrão
// (em `AppLocalizations`) é resolvido em `build()`/`_onDetect`, não aqui.
class ScanScreen<T> extends StatefulWidget {
  final String? title;
  final String? instructions;
  final String? invalidMessage;
  final T? Function(String raw) parse;

  const ScanScreen({
    super.key,
    this.title,
    this.instructions,
    this.invalidMessage,
    required this.parse,
  });

  @override
  State<ScanScreen<T>> createState() => _ScanScreenState<T>();
}

class _ScanScreenState<T> extends State<ScanScreen<T>> {
  bool _scanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;

    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;

    setState(() => _scanned = true);

    final parsed = widget.parse(rawValue);
    if (parsed == null) {
      setState(() => _scanned = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.invalidMessage ?? context.l10n.scanScreenInvalidMessage),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? context.l10n.scanScreenTitle)),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error) => ColoredBox(
              color: Colors.black,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.l10n.scanScreenCameraError(
                      error.errorCode.name,
                      error.errorDetails?.message ?? '',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _ScanOverlayPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 32,
            right: 32,
            child: Text(
              widget.instructions ?? context.l10n.scanScreenInstructions,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
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
