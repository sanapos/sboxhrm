import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'pos_pdf_iframe_stub.dart'
    if (dart.library.js_interop) 'pos_pdf_iframe_web.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Dialog xem trước PDF — web dùng iframe (giống KiotViet), desktop dùng PdfPreview.
Future<void> showPosPdfPreviewDialog(
  BuildContext context, {
  required Uint8List bytes,
  required String title,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: size.width * 0.92,
            maxHeight: size.height * 0.88,
            minWidth: 640,
            minHeight: 480,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(title),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                      tooltip: tr('Đóng'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: buildPosPdfPreview(bytes),
              ),
            ],
          ),
        ),
      );
    },
  );
}
