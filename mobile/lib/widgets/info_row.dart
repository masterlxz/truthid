import 'package:flutter/material.dart';

import '../theme.dart';

// Linha "label: valor" em destaque, usada nas telas de confirmação (scan de
// QR, detalhe de entrada do vault) pra mostrar dados relevantes antes de uma
// ação. Extraído de approval_screen.dart (era _InfoRow privado) pra reuso.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
