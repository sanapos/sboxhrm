import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/pos_product.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class PosSerialLineInput {
  PosSerialLineInput({
    required this.rowId,
    required this.productName,
    required this.qty,
    required this.controllers,
    this.imeiControllers = const [],
  });

  final int rowId;
  final String productName;
  final int qty;
  final List<TextEditingController> controllers;
  final List<TextEditingController> imeiControllers;

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    for (final c in imeiControllers) {
      c.dispose();
    }
  }
}

/// Dialog nhập seri/IMEI trước khi thanh toán.
Future<Map<int, ({List<String> serials, List<String> imeis})>?> showPosSerialCaptureDialog(
  BuildContext context, {
  required List<({int rowId, PosProduct product, String displayName, double qty})> lines,
}) async {
  final inputs = <PosSerialLineInput>[];
  for (final line in lines) {
    final count = line.qty.round();
    if (count <= 0) continue;
    inputs.add(
      PosSerialLineInput(
        rowId: line.rowId,
        productName: line.displayName,
        qty: count,
        controllers: List.generate(count, (_) => TextEditingController()),
        imeiControllers: List.generate(count, (_) => TextEditingController()),
      ),
    );
  }

  try {
    return await showDialog<Map<int, ({List<String> serials, List<String> imeis})>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PosSerialCaptureDialog(inputs: inputs),
    );
  } finally {
    for (final i in inputs) {
      i.dispose();
    }
  }
}

class _PosSerialCaptureDialog extends StatefulWidget {
  const _PosSerialCaptureDialog({required this.inputs});

  final List<PosSerialLineInput> inputs;

  @override
  State<_PosSerialCaptureDialog> createState() => _PosSerialCaptureDialogState();
}

class _PosSerialCaptureDialogState extends State<_PosSerialCaptureDialog> {
  String? _error;

  void _submit() {
    final result = <int, ({List<String> serials, List<String> imeis})>{};
    final seen = <String>{};

    for (final line in widget.inputs) {
      final serials = <String>[];
      final imeis = <String>[];
      for (var i = 0; i < line.qty; i++) {
        final sn = line.controllers[i].text.trim();
        if (sn.isEmpty) {
          setState(() => _error = 'Nhập đủ seri cho ${line.productName}');
          return;
        }
        final key = sn.toLowerCase();
        if (seen.contains(key)) {
          setState(() => _error = 'Seri trùng: $sn');
          return;
        }
        seen.add(key);
        serials.add(sn);
        final imei = line.imeiControllers[i].text.trim();
        imeis.add(imei);
      }
      result[line.rowId] = (serials: serials, imeis: imeis);
    }

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Nhập seri máy')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Các mặt hàng bắt buộc seri — nhập đủ theo số lượng bán.'),
                style: TextStyle(fontSize: 12, color: PosTheme.textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(tr(_error!), style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              ...widget.inputs.map(_lineBlock),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Huỷ')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(tr('Xác nhận')),
        ),
      ],
    );
  }

  Widget _lineBlock(PosSerialLineInput line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('${line.productName} × ${line.qty}'),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...List.generate(line.qty, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(tr('${i + 1}.'), style: const TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: line.controllers[i],
                      decoration: PosTheme.inputDecoration(
                        label: 'Seri ${i + 1}',
                        hint: 'Quét hoặc nhập seri',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: line.imeiControllers[i],
                      decoration: PosTheme.inputDecoration(
                        label: 'IMEI (tuỳ chọn)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
