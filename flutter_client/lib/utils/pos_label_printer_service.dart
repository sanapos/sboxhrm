import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/pos_product.dart';
import 'pos_barcode_print.dart';
import 'pos_label_printer_settings.dart';
import 'pos_label_renderer.dart';
import 'pos_printer_transport.dart';

/// In tem nhãn ra máy in TSPL / ESC/POS (Bluetooth, LAN, USB, Sunmi).
class PosLabelPrinterService {
  static final _money = NumberFormat('#,##0', 'vi_VN');

  /// Tạo danh sách payload in tem (mỗi phần tử = 1 lệnh gửi máy in).
  static Future<List<List<int>>> buildLabelByteJobs(
    List<PosProduct> products, {
    required PosBarcodePrintOptions options,
    required PosLabelPrinterSettings settings,
  }) async {
    if (products.isEmpty || kIsWeb) return [];
    final template = options.template;
    final copies = options.copiesPerProduct.clamp(1, 5000);
    final dpi = settings.dpi;
    final jobs = <List<int>>[];

    final items = products
        .map((p) => PosLabelRenderer.fromProduct(p, options, _money))
        .toList();

    if (template.cols > 1 && !template.isSheet) {
      for (var c = 0; c < copies; c++) {
        for (var i = 0; i < items.length; i += template.cols) {
          final chunk = items.sublist(
            i,
            (i + template.cols > items.length) ? items.length : i + template.cols,
          );
          final raster = await PosLabelRenderer.renderRow(
            items: chunk,
            template: template,
            dpi: dpi,
          );
          jobs.add(_bytesForRaster(settings, template, raster, rowMode: true));
        }
      }
      return jobs;
    }

    for (final item in items) {
      for (var c = 0; c < copies; c++) {
        final raster = await PosLabelRenderer.renderSingle(
          item: item,
          template: template,
          dpi: dpi,
        );
        jobs.add(_bytesForRaster(settings, template, raster));
      }
    }
    return jobs;
  }

  static List<int> _bytesForRaster(
    PosLabelPrinterSettings settings,
    PosBarcodeLabelTemplate template,
    ({Uint8List raster, int widthPx, int heightPx}) raster, {
    bool rowMode = false,
  }) {
    if (settings.protocol == PosLabelPrinterProtocol.tspl) {
      return _buildTsplJob(
        widthMm: rowMode ? template.rollPageWidthMm : template.labelWidthMm,
        heightMm: template.labelHeightMm,
        gapMm: settings.gapMm,
        raster: raster.raster,
        widthPx: raster.widthPx,
        heightPx: raster.heightPx,
      );
    }
    return _buildEscPosLabelJob(
      raster: raster.raster,
      widthPx: raster.widthPx,
      heightPx: raster.heightPx,
      feedLines: rowMode ? 2 : 3,
    );
  }

  static Future<bool> printLabels(
    List<PosProduct> products, {
    required PosBarcodePrintOptions options,
    required PosLabelPrinterSettings settings,
  }) async {
    if (products.isEmpty || kIsWeb) return false;
    final jobs = await buildLabelByteJobs(products, options: options, settings: settings);
    for (final bytes in jobs) {
      final ok = await _send(settings, bytes);
      if (!ok) return false;
    }
    return true;
  }

  static Future<bool> testPrint(PosLabelPrinterSettings settings) async {
    if (kIsWeb) return false;
    final template = settings.template ?? posBarcodeLabelTemplates[3];
    const item = PosLabelRenderItem(
      name: 'Đậu phộng da cá',
      code: 'SP001234',
      priceText: '35.000 đ',
    );
    final raster = await PosLabelRenderer.renderSingle(
      item: item,
      template: template,
      dpi: settings.dpi,
    );
    final bytes = _bytesForRaster(settings, template, raster);
    return _send(settings, bytes);
  }

  static Future<bool> _send(PosLabelPrinterSettings s, List<int> bytes) =>
      PosPrinterTransport.send(
        connectionType: s.connectionType,
        bluetoothAddress: s.bluetoothAddress,
        lanHost: s.lanHost,
        lanPort: s.lanPort,
        bytes: bytes,
        sunmiFeedLines: 2,
      );

  static List<int> _buildTsplJob({
    required double widthMm,
    required double heightMm,
    required double gapMm,
    required Uint8List raster,
    required int widthPx,
    required int heightPx,
  }) {
    final bytesPerRow = (widthPx + 7) ~/ 8;
    final header = StringBuffer()
      ..writeln('SIZE ${widthMm.toStringAsFixed(1)} mm, ${heightMm.toStringAsFixed(1)} mm')
      ..writeln('GAP ${gapMm.toStringAsFixed(1)} mm, 0 mm')
      ..writeln('DIRECTION 1')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS')
      ..write('BITMAP 0,0,$bytesPerRow,$heightPx,0,');
    return [...utf8.encode(header.toString()), ...raster, ...utf8.encode('\r\nPRINT 1,1\r\n')];
  }

  static List<int> _buildEscPosLabelJob({
    required Uint8List raster,
    required int widthPx,
    required int heightPx,
    int feedLines = 3,
  }) {
    final bytesPerRow = (widthPx + 7) ~/ 8;
    final feed = feedLines.clamp(1, 10);
    final buf = <int>[0x1B, 0x40];
    buf.addAll([
      0x1D, 0x76, 0x30, 0x00,
      bytesPerRow & 0xFF,
      (bytesPerRow >> 8) & 0xFF,
      heightPx & 0xFF,
      (heightPx >> 8) & 0xFF,
      ...raster,
    ]);
    for (var i = 0; i < feed; i++) {
      buf.add(0x0A);
    }
    buf.addAll([0x1B, 0x64, feed, 0x1D, 0x56, 0x01]);
    return buf;
  }
}
