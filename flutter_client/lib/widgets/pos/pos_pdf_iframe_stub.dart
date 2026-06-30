import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

Widget buildPosPdfPreview(Uint8List bytes) {
  return PdfPreview(
    canChangeOrientation: false,
    canChangePageFormat: false,
    canDebug: false,
    allowPrinting: true,
    allowSharing: true,
    pdfFileName: 'preview.pdf',
    build: (_) async => bytes,
  );
}
