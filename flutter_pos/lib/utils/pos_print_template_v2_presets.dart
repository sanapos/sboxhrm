import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../l10n/app_tr.dart';

/// Preset mẫu in V2 theo loại phiếu + khổ + máy in.
abstract final class PosPrintTemplateV2Presets {
  static PosPrintTemplateV2 build({
    required String documentType,
    required String paperSize,
    required String printerProfile,
    String? name,
  }) {
    final isLabel = PosPrintPaperSizes.isLabelSize(paperSize) ||
        PosPrintPaperSizes.isLabelDoc(documentType);
    final k58 = paperSize == PosPrintPaperSizes.k58 ||
        paperSize == PosPrintPaperSizes.label40x30 ||
        paperSize == 'roll_1_40x30';
    // Hóa đơn: chữ to, đậm chỗ quan trọng. Tem: cỡ vừa để không tràn 40×30.
    final titleSize = isLabel ? (k58 ? 24.0 : 26.0) : (k58 ? 40.0 : 44.0);
    final bodySize = isLabel ? (k58 ? 18.0 : 20.0) : (k58 ? 26.0 : 30.0);
    final smallSize = isLabel ? (k58 ? 14.0 : 16.0) : (k58 ? 22.0 : 24.0);
    final totalSize = k58 ? 32.0 : 38.0;

    if (documentType == PosPrintDocumentTypes.kitchenSlip ||
        documentType == PosPrintDocumentTypes.kitchenVoid) {
      return _kitchenPreset(
        documentType: documentType,
        paperSize: paperSize,
        printerProfile: printerProfile,
        titleSize: titleSize,
        bodySize: bodySize,
        name: name,
        isCancel: documentType == PosPrintDocumentTypes.kitchenVoid,
      );
    }

    if (documentType == PosPrintDocumentTypes.barcodeLabel) {
      return _productLabelPreset(
        paperSize: paperSize,
        printerProfile: printerProfile,
        titleSize: titleSize,
        bodySize: bodySize,
        smallSize: smallSize,
        name: name,
      );
    }

    if (documentType == PosPrintDocumentTypes.kitchenLabel) {
      return _kitchenLabelPreset(
        paperSize: paperSize,
        printerProfile: printerProfile,
        titleSize: titleSize,
        bodySize: bodySize,
        smallSize: smallSize,
        name: name,
      );
    }

    if (documentType == PosPrintDocumentTypes.stockIssue) {
      return PosPrintTemplateV2(
        paperSize: paperSize,
        printerProfile: printerProfile,
        documentType: documentType,
        name: name ?? 'Phiếu xuất kho ${PosPrintPaperSizes.labels[paperSize]}',
        blocks: [
          PosPrintBlock(
            type: PosPrintBlockType.field,
            field: 'Ten_Cua_Hang',
            style: PosPrintTextStyle(fontSize: titleSize, bold: true, align: PosPrintTextAlign.center),
          ),
          const PosPrintBlock(type: PosPrintBlockType.divider),
          PosPrintBlock(
            type: PosPrintBlockType.field,
            field: 'Tieu_De_In',
            style: PosPrintTextStyle(fontSize: bodySize + 2, bold: true, align: PosPrintTextAlign.center),
          ),
          PosPrintBlock(
            type: PosPrintBlockType.pair,
            leftField: 'Ma_Don_Hang',
            rightField: 'Ngay',
            fieldLabels: const {
              'Ma_Don_Hang': 'Số phiếu:',
              'Ngay': 'Ngày:',
            },
            style: PosPrintTextStyle(fontSize: bodySize, bold: true),
          ),
          PosPrintBlock(
            type: PosPrintBlockType.field,
            field: 'Nguoi_Ban',
            label: 'NV:',
            style: PosPrintTextStyle(fontSize: bodySize),
          ),
          const PosPrintBlock(type: PosPrintBlockType.divider),
          PosPrintBlock(
            type: PosPrintBlockType.lineItemsKitchen,
            style: PosPrintTextStyle(fontSize: bodySize, bold: true),
          ),
          const PosPrintBlock(type: PosPrintBlockType.divider),
          PosPrintBlock(
            type: PosPrintBlockType.field,
            field: 'Ghi_Chu',
            style: PosPrintTextStyle(fontSize: smallSize, align: PosPrintTextAlign.center),
          ),
        ],
      );
    }

    // Hóa đơn / đặt hàng / giao hàng / trả hàng — layout giống Sunmi V2S K58 hiện tại.
    return PosPrintTemplateV2(
      paperSize: paperSize,
      printerProfile: printerProfile,
      documentType: documentType,
      name: name ??
          '${PosPrintDocumentTypes.all[documentType] ?? 'Mẫu in'} — ${PosPrintPrinterProfiles.labels[printerProfile] ?? printerProfile}',
      blocks: [
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Ten_Cua_Hang',
          style: PosPrintTextStyle(fontSize: titleSize, bold: true, align: PosPrintTextAlign.center),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Dia_Chi_Chi_Nhanh',
          style: PosPrintTextStyle(fontSize: smallSize, align: PosPrintTextAlign.center),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Dien_Thoai_Chi_Nhanh',
          style: PosPrintTextStyle(fontSize: smallSize, align: PosPrintTextAlign.center),
        ),
        const PosPrintBlock(type: PosPrintBlockType.divider),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Tieu_De_In',
          style: PosPrintTextStyle(fontSize: bodySize + 2, bold: true, align: PosPrintTextAlign.center),
        ),
        // F&B: hiện bàn/khu; bán lẻ để trống → compiler bỏ qua.
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Ten_Ban',
          label: 'Bàn:',
          style: PosPrintTextStyle(fontSize: bodySize, bold: true),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Khu_Vuc',
          label: 'Khu:',
          style: PosPrintTextStyle(fontSize: smallSize),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.pair,
          leftField: 'Ma_Don_Hang',
          rightField: 'Ngay',
          fieldLabels: const {
            'Ma_Don_Hang': 'Số HĐ:',
            'Ngay': 'Ngày:',
          },
          style: PosPrintTextStyle(fontSize: bodySize, bold: true),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.text,
          text: tr('{Gio}'),
          style: PosPrintTextStyle(fontSize: smallSize),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Khach_Hang',
          label: 'KH:',
          style: PosPrintTextStyle(fontSize: bodySize),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'SDT',
          label: 'ĐT:',
          style: PosPrintTextStyle(fontSize: smallSize),
        ),
        const PosPrintBlock(type: PosPrintBlockType.divider),
        PosPrintBlock(
          type: PosPrintBlockType.lineItems,
          showColumnHeader: true,
          style: PosPrintTextStyle(fontSize: bodySize, bold: true),
        ),
        const PosPrintBlock(type: PosPrintBlockType.divider),
        PosPrintBlock(
          type: PosPrintBlockType.totals,
          fields: const [
            'Tong_Tien_Hang',
            'Chiet_Khau_Hoa_Don',
            'Tong_Cong',
            'Khach_Thanh_Toan',
            'Tien_Thua',
          ],
          fieldLabels: const {
            'Tong_Tien_Hang': 'Tổng tiền hàng',
            'Chiet_Khau_Hoa_Don': 'Chiết khấu',
            'Tong_Cong': 'TỔNG CỘNG',
            'Khach_Thanh_Toan': 'Đã thanh toán',
            'Tien_Thua': 'Tiền thừa',
          },
          style: PosPrintTextStyle(fontSize: bodySize, bold: true),
          rightStyle: PosPrintTextStyle(fontSize: totalSize, bold: true, align: PosPrintTextAlign.right),
        ),
        const PosPrintBlock(type: PosPrintBlockType.vietQr),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Tong_Cong_Bang_Chu',
          style: PosPrintTextStyle(fontSize: smallSize, align: PosPrintTextAlign.center),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.text,
          text: tr('Cảm ơn quý khách!'),
          style: PosPrintTextStyle(fontSize: smallSize, bold: true, align: PosPrintTextAlign.center),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Ghi_Chu',
          style: PosPrintTextStyle(fontSize: smallSize - 2, align: PosPrintTextAlign.center),
        ),
      ],
    );
  }

  /// Tem dán sản phẩm — tên to, giá đậm, mã vạch vừa khổ (không tràn 40×30).
  static PosPrintTemplateV2 _productLabelPreset({
    required String paperSize,
    required String printerProfile,
    required double titleSize,
    required double bodySize,
    required double smallSize,
    String? name,
  }) {
    final compact = paperSize.contains('40x30') ||
        paperSize.contains('35x22') ||
        paperSize.contains('22');
    return PosPrintTemplateV2(
      paperSize: paperSize,
      printerProfile: printerProfile,
      documentType: PosPrintDocumentTypes.barcodeLabel,
      name: name ?? 'Tem sản phẩm ${PosPrintPaperSizes.labels[paperSize]}',
      blocks: [
        if (!compact)
          PosPrintBlock(
            type: PosPrintBlockType.field,
            field: 'Ten_Cua_Hang',
            style: PosPrintTextStyle(
              fontSize: smallSize,
              bold: true,
              align: PosPrintTextAlign.center,
            ),
          ),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Ten_Hang_Hoa',
          style: PosPrintTextStyle(
            fontSize: compact ? 24 : titleSize + 2,
            bold: true,
            align: PosPrintTextAlign.center,
          ),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.barcode,
          field: 'Ma_Vach',
          barcodeHeight: compact ? 36 : 48,
          barcodeShowText: !compact,
        ),
        PosPrintBlock(
          type: PosPrintBlockType.text,
          text: tr('{Don_Gia} đ'),
          style: PosPrintTextStyle(
            fontSize: compact ? 20 : bodySize + 2,
            bold: true,
            align: PosPrintTextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Tem báo bếp / tem ly — ít dòng, tên món to, không tràn viền.
  static PosPrintTemplateV2 _kitchenLabelPreset({
    required String paperSize,
    required String printerProfile,
    required double titleSize,
    required double bodySize,
    required double smallSize,
    String? name,
  }) {
    final compact = paperSize.contains('40x30') ||
        paperSize.contains('35x22') ||
        paperSize.contains('22');
    return PosPrintTemplateV2(
      paperSize: paperSize,
      printerProfile: printerProfile,
      documentType: PosPrintDocumentTypes.kitchenLabel,
      name: name ?? 'Tem báo bếp ${PosPrintPaperSizes.labels[paperSize]}',
      blocks: [
        PosPrintBlock(
          type: PosPrintBlockType.pair,
          leftField: 'Ten_Ban',
          rightField: 'Gio',
          style: PosPrintTextStyle(fontSize: smallSize + 2, bold: true),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Ten_Hang_Hoa',
          style: PosPrintTextStyle(
            fontSize: compact ? bodySize + 6 : titleSize + 4,
            bold: true,
            align: PosPrintTextAlign.center,
          ),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Ghi_Chu',
          style: PosPrintTextStyle(
            fontSize: smallSize + 2,
            align: PosPrintTextAlign.center,
          ),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.text,
          text: tr('{So_Luong} {Don_Vi_Tinh}'),
          style: PosPrintTextStyle(
            fontSize: compact ? 20 : 22,
            bold: true,
            align: PosPrintTextAlign.center,
          ),
        ),
      ],
    );
  }

  static PosPrintTemplateV2 _kitchenPreset({
    required String documentType,
    required String paperSize,
    required String printerProfile,
    required double titleSize,
    required double bodySize,
    String? name,
    required bool isCancel,
  }) {
    final k80 = paperSize == PosPrintPaperSizes.k80;
    final itemSize = k80 ? bodySize + 2 : bodySize;
    return PosPrintTemplateV2(
      paperSize: paperSize,
      printerProfile: printerProfile,
      documentType: documentType,
      name: name ??
          (isCancel
              ? 'Hủy bếp (${PosPrintPaperSizes.displayLabel(paperSize)})'
              : 'Báo chế biến (${PosPrintPaperSizes.displayLabel(paperSize)})'),
      blocks: [
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Ten_Ban',
          style: PosPrintTextStyle(
            fontSize: titleSize,
            bold: true,
            align: PosPrintTextAlign.center,
          ),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.text,
          text: tr(isCancel ? '*** PHIẾU HỦY ***' : '*** BÁO CHẾ BIẾN ***'),
          style: PosPrintTextStyle(
            fontSize: titleSize - 2,
            bold: true,
            align: PosPrintTextAlign.center,
          ),
        ),
        const PosPrintBlock(type: PosPrintBlockType.divider),
        PosPrintBlock(
          type: PosPrintBlockType.text,
          text: tr('Mã HĐ: {Ma_Don_Hang}'),
          style: PosPrintTextStyle(fontSize: bodySize, bold: true),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.text,
          text: tr('NV: {Nguoi_Ban}'),
          style: PosPrintTextStyle(fontSize: bodySize, bold: true),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.text,
          text: tr('Ngày: {Ngay} {Gio}'),
          style: PosPrintTextStyle(fontSize: bodySize, bold: true),
        ),
        const PosPrintBlock(type: PosPrintBlockType.divider),
        PosPrintBlock(
          type: PosPrintBlockType.lineItemsKitchen,
          style: PosPrintTextStyle(fontSize: itemSize, bold: true),
        ),
        const PosPrintBlock(type: PosPrintBlockType.divider),
        PosPrintBlock(
          type: PosPrintBlockType.text,
          text: tr('— Hết —'),
          style: PosPrintTextStyle(
            fontSize: bodySize - 2,
            bold: true,
            align: PosPrintTextAlign.center,
          ),
        ),
      ],
    );
  }

  static List<PosPrintTemplateV2> seedSetForDocument(String documentType) {
    if (documentType == PosPrintDocumentTypes.kitchenLabel) {
      return [
        for (final size in PosPrintPaperSizes.kitchenLabelSizes)
          build(
            documentType: documentType,
            paperSize: size,
            printerProfile: PosPrintPrinterProfiles.genericK58,
            name: 'Tem báo bếp ${PosPrintPaperSizes.displayLabel(size)}',
          ),
      ];
    }
    if (documentType == PosPrintDocumentTypes.barcodeLabel) {
      return [
        for (final size in PosPrintPaperSizes.productLabelSizes.take(6))
          build(
            documentType: documentType,
            paperSize: size,
            printerProfile: PosPrintPrinterProfiles.genericK58,
            name: 'Tem sản phẩm ${PosPrintPaperSizes.displayLabel(size)}',
          ),
      ];
    }
    return [
      build(
        documentType: documentType,
        paperSize: PosPrintPaperSizes.k58,
        printerProfile: PosPrintPrinterProfiles.sunmiK58,
        name: 'Sunmi K57/K58 — ${PosPrintDocumentTypes.all[documentType] ?? documentType}',
      ),
      build(
        documentType: documentType,
        paperSize: PosPrintPaperSizes.k80,
        printerProfile: PosPrintPrinterProfiles.sunmiK80,
        name: 'Sunmi K80 — ${PosPrintDocumentTypes.all[documentType] ?? documentType}',
      ),
      build(
        documentType: documentType,
        paperSize: PosPrintPaperSizes.k80,
        printerProfile: PosPrintPrinterProfiles.zywellK80,
        name: 'Zywell K80 — ${PosPrintDocumentTypes.all[documentType] ?? documentType}',
      ),
    ];
  }
}
