import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/pos_label_design.dart';
import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../services/api_service.dart';
import 'pos_label_design_presets.dart';
import 'pos_print_template_loader.dart';
import 'pos_print_template_v2_codec.dart';

/// Loại tem soạn bằng trình soạn tem (đặt tự do theo mm).
const kPosDesignerLabelTypes = [
  PosPrintDocumentTypes.barcodeLabel,
  PosPrintDocumentTypes.scaleLabel,
  PosPrintDocumentTypes.specLabel,
  PosPrintDocumentTypes.kitchenLabel,
];

bool isPosDesignerLabelType(String documentType) => kPosDesignerLabelTypes.contains(documentType);

/// Mẫu mặc định khi cửa hàng chưa có mẫu (in không bao giờ rơi về bố cục cố định cũ).
PosLabelDesign posLabelDefaultDesign(String documentType) {
  return PosLabelDesignPresets.forType(documentType).first.build(50, 30);
}

/// Mẫu cũ (khối V2 / HTML) → mẫu trình soạn cùng khổ.
PosLabelDesign posLabelDesignFromLegacy(PosPrintTemplate t) {
  final v2 = PosPrintTemplateV2Codec.tryParse(t.htmlContent);
  final size = PosPrintPaperSizes.toLabelTemplateId(v2?.paperSize ?? t.paperSize);
  final dims = PosPrintPaperSizes.customLabelDims(size) ??
      (PosPrintPaperSizes.widthMm(size), PosPrintPaperSizes.heightMm(size));
  final w = dims.$1 >= 10 && dims.$1 <= 200 ? dims.$1 : 50.0;
  final h = dims.$2 >= 8 && dims.$2 <= 300 ? dims.$2 : 30.0;
  final d = v2 != null && v2.blocks.isNotEmpty
      ? posLabelDesignFromBlocks(v2, t.documentType, w, h)
      : PosLabelDesignPresets.forType(t.documentType).first.build(w, h);
  return d.copyWith(name: t.name);
}

final _ensureRunning = <String, Future<List<PosPrintTemplate>>>{};

/// Mẫu tem của cửa hàng cho [documentType] — đảm bảo toàn bộ là mẫu trình soạn:
/// mẫu cũ (khối / HTML) được chuyển tại chỗ (giữ id, tên, «đang dùng»); chưa có mẫu nào → tạo mẫu dựng sẵn
/// làm mẫu đang dùng. Không có quyền sửa mẫu → trả danh sách đã chuyển trong bộ nhớ (in vẫn đúng).
Future<List<PosPrintTemplate>> ensurePosLabelDesignTemplates(ApiService api, String documentType) =>
    _ensureRunning[documentType] ??= _ensure(api, documentType).whenComplete(() {
      // Không trả về Future vừa gỡ — whenComplete sẽ chờ chính nó (treo mãi).
      _ensureRunning.remove(documentType);
    });

Future<List<PosPrintTemplate>> _ensure(ApiService api, String documentType) async {
  final res = await api.getPosPrintTemplates(documentType: documentType);
  if (res['isSuccess'] != true) {
    // Mất mạng: dùng mẫu đã lưu trên máy (nếu có).
    final disk = await loadPosPrintTemplates(api, documentType);
    return [
      for (final t in disk)
        PosLabelDesign.isDesign(t.htmlContent) ? t : t.copyWith(htmlContent: posLabelDesignFromLegacy(t).encode()),
    ];
  }
  final list = parsePosPrintTemplatesResponse(res).where((t) => t.isActive).toList();
  final out = <PosPrintTemplate>[];
  for (final t in list) {
    if (PosLabelDesign.isDesign(t.htmlContent)) {
      out.add(t);
      continue;
    }
    final converted = t.copyWith(htmlContent: posLabelDesignFromLegacy(t).encode());
    try {
      final r = await api.updatePosPrintTemplate(t.id, converted.toSaveJson());
      out.add(r['isSuccess'] == true && r['data'] is Map
          ? PosPrintTemplate.fromJson(Map<String, dynamic>.from(r['data'] as Map))
          : converted);
    } catch (e) {
      debugPrint('Chuyển mẫu tem ${t.name}: $e');
      out.add(converted);
    }
  }
  if (out.isEmpty) {
    final d = posLabelDefaultDesign(documentType);
    final body = {
      'name': d.name ?? 'Mẫu tem',
      'documentType': documentType,
      'paperSize': PosPrintPaperSizes.toApiPaperSize(
          documentType, PosPrintPaperSizes.customLabelId(d.widthMm, d.heightMm)),
      'htmlContent': d.encode(),
      'isDefault': true,
      'isActive': true,
      'sortOrder': 0,
    };
    try {
      final r = await api.createPosPrintTemplate(body);
      if (r['isSuccess'] == true && r['data'] is Map) {
        out.add(PosPrintTemplate.fromJson(Map<String, dynamic>.from(r['data'] as Map)));
      }
    } catch (e) {
      debugPrint('Tạo mẫu tem mặc định: $e');
    }
  }
  return out;
}

/// Mẫu dùng khi in [documentType]: [preferId] (đã chọn trong hộp in) → mẫu «đang dùng» → mẫu đầu tiên →
/// mẫu dựng sẵn (không bao giờ null).
Future<PosLabelDesign> loadPosLabelDesignForPrint(String documentType, {String? preferId}) async {
  try {
    final list = await ensurePosLabelDesignTemplates(ApiService(), documentType)
        .timeout(const Duration(seconds: 8), onTimeout: () => const []);
    final pick = list.where((t) => t.id == preferId).firstOrNull ??
        list.where((t) => t.isDefault).firstOrNull ??
        list.firstOrNull;
    final d = PosLabelDesign.tryParse(pick?.htmlContent);
    if (d != null) return d;
  } catch (e) {
    debugPrint('Mẫu tem $documentType: $e');
  }
  return posLabelDefaultDesign(documentType);
}

/// Mẫu khối V2 cũ → phần tử đặt tự do (xếp từ trên xuống, co lại nếu dài hơn tem).
PosLabelDesign posLabelDesignFromBlocks(PosPrintTemplateV2 v2, String documentType, double w, double h) {
  const m = 1.5;
  const dotsPerMm = 8.0;
  final els = <PosLabelElement>[];
  var y = 1.0;
  PosLabelAlign al(PosPrintTextAlign a) => switch (a) {
        PosPrintTextAlign.center => PosLabelAlign.center,
        PosPrintTextAlign.right => PosLabelAlign.right,
        PosPrintTextAlign.left => PosLabelAlign.left,
      };
  // Cỡ chữ V2 tính theo điểm in (203 dpi) → pt.
  double pt(double dots) => (dots / (203 / 72) * 10).roundToDouble() / 10;
  PosLabelElement text(String s, PosPrintTextStyle st, double x, double ww) {
    final hh = math.max(2.5, st.fontSize / dotsPerMm * 1.2);
    return PosLabelElement(
      id: PosLabelDesignPresets.newId(),
      type: PosLabelElementType.text,
      x: x,
      y: y,
      w: ww,
      h: hh,
      text: st.uppercase ? s.toUpperCase() : s,
      fontSize: pt(st.fontSize),
      bold: st.bold,
      align: al(st.align),
      maxLines: 1,
    );
  }

  for (final b in v2.blocks) {
    switch (b.type) {
      case PosPrintBlockType.text:
      case PosPrintBlockType.field:
        final s = b.type == PosPrintBlockType.field
            ? '${(b.label ?? '').isNotEmpty ? '${b.label}: ' : ''}{${b.field}}'
            : (b.text ?? '');
        final e = text(s, b.style, m, w - 2 * m);
        els.add(e);
        y += e.h;
      case PosPrintBlockType.pair:
        final l = text('{${b.leftField}}', b.style, m, (w - 2 * m) / 2);
        final r = text('{${b.rightField}}', b.rightStyle ?? b.style, m + (w - 2 * m) / 2, (w - 2 * m) / 2)
            .copyWith(align: PosLabelAlign.right);
        els.addAll([l, r]);
        y += math.max(l.h, r.h);
      case PosPrintBlockType.barcode:
        final hh = b.barcodeQr ? math.min(b.barcodeHeight / dotsPerMm, w * 0.5) : b.barcodeHeight / dotsPerMm + (b.barcodeShowText ? 3 : 0);
        els.add(PosLabelElement(
          id: PosLabelDesignPresets.newId(),
          type: b.barcodeQr ? PosLabelElementType.qr : PosLabelElementType.barcode,
          x: b.barcodeQr ? (w - hh) / 2 : m,
          y: y,
          w: b.barcodeQr ? hh : w - 2 * m,
          h: hh,
          text: (b.codeContent ?? '').isNotEmpty ? b.codeContent! : '{${b.field ?? 'Ma_Vach'}}',
          showText: b.barcodeShowText,
        ));
        y += hh + 0.5;
      case PosPrintBlockType.divider:
        els.add(PosLabelElement(
            id: PosLabelDesignPresets.newId(), type: PosLabelElementType.line, x: m, y: y, w: w - 2 * m, h: 1));
        y += 1;
      case PosPrintBlockType.spacer:
        y += b.height / dotsPerMm;
      case PosPrintBlockType.image:
        final iw = (w - 2 * m) * b.imageWidthPct / 100;
        els.add(PosLabelElement(
          id: PosLabelDesignPresets.newId(),
          type: PosLabelElementType.image,
          x: (w - iw) / 2,
          y: y,
          w: iw,
          h: iw * 0.5,
          imageData: b.imageData,
        ));
        y += iw * 0.5;
      default:
        break;
    }
  }
  // Dài hơn tem → co toạ độ dọc + cỡ chữ cho vừa.
  final total = y + 1;
  if (total > h) {
    final k = h / total;
    for (var i = 0; i < els.length; i++) {
      final e = els[i];
      els[i] = e.copyWith(y: e.y * k, h: e.h * k, fontSize: (e.fontSize * k * 10).roundToDouble() / 10);
    }
  }
  return PosLabelDesign(documentType: documentType, widthMm: w, heightMm: h, elements: els, name: v2.name);
}
