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
    final k58 = paperSize == PosPrintPaperSizes.k58;
    final titleSize = k58 ? 34.0 : 38.0;
    final bodySize = k58 ? 24.0 : 26.0;
    final smallSize = k58 ? 22.0 : 24.0;
    final totalSize = k58 ? 28.0 : 30.0;

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
          const PosPrintBlock(type: PosPrintBlockType.divider, divider: PosPrintDividerStyle.equals),
          PosPrintBlock(
            type: PosPrintBlockType.field,
            field: 'Tieu_De_In',
            style: PosPrintTextStyle(fontSize: bodySize + 2, bold: true, align: PosPrintTextAlign.center),
          ),
          PosPrintBlock(
            type: PosPrintBlockType.pair,
            leftField: 'Ma_Don_Hang',
            rightField: 'Ngay',
            style: PosPrintTextStyle(fontSize: bodySize, bold: true),
          ),
          PosPrintBlock(
            type: PosPrintBlockType.field,
            field: 'Nguoi_Ban',
            style: PosPrintTextStyle(fontSize: bodySize),
          ),
          const PosPrintBlock(type: PosPrintBlockType.divider),
          const PosPrintBlock(type: PosPrintBlockType.lineItems),
          const PosPrintBlock(type: PosPrintBlockType.divider, divider: PosPrintDividerStyle.equals),
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
        const PosPrintBlock(type: PosPrintBlockType.divider, divider: PosPrintDividerStyle.equals),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Tieu_De_In',
          style: PosPrintTextStyle(fontSize: bodySize + 2, bold: true, align: PosPrintTextAlign.center),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.pair,
          leftField: 'Ma_Don_Hang',
          rightField: 'Ngay',
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
          style: PosPrintTextStyle(fontSize: bodySize),
        ),
        PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'SDT',
          style: PosPrintTextStyle(fontSize: smallSize),
        ),
        const PosPrintBlock(type: PosPrintBlockType.divider),
        const PosPrintBlock(type: PosPrintBlockType.lineItems),
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
          style: PosPrintTextStyle(fontSize: bodySize),
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

  static PosPrintTemplateV2 _kitchenPreset({
    required String documentType,
    required String paperSize,
    required String printerProfile,
    required double titleSize,
    required double bodySize,
    String? name,
    required bool isCancel,
  }) =>
      PosPrintTemplateV2(
        paperSize: paperSize,
        printerProfile: printerProfile,
        documentType: documentType,
        name: name ?? (isCancel ? 'Phiếu hủy bếp' : 'Phiếu chế biến'),
        blocks: [
          PosPrintBlock(
            type: PosPrintBlockType.field,
            field: 'Ten_Ban',
            style: PosPrintTextStyle(fontSize: titleSize, bold: true, align: PosPrintTextAlign.center),
          ),
          PosPrintBlock(
            type: PosPrintBlockType.text,
            text: tr(isCancel ? '*** PHIẾU HỦY ***' : '*** BÁO CHẾ BIẾN ***'),
            style: PosPrintTextStyle(fontSize: titleSize - 2, bold: true, align: PosPrintTextAlign.center),
          ),
          PosPrintBlock(
            type: PosPrintBlockType.text,
            text: tr('Mã HĐ: {Ma_Don_Hang}'),
            style: PosPrintTextStyle(fontSize: bodySize, bold: true),
          ),
          PosPrintBlock(
            type: PosPrintBlockType.field,
            field: 'Nguoi_Ban',
            style: PosPrintTextStyle(fontSize: bodySize, bold: true),
          ),
          PosPrintBlock(
            type: PosPrintBlockType.text,
            text: tr('Ngày: {Ngay} {Gio}'),
            style: PosPrintTextStyle(fontSize: bodySize, bold: true),
          ),
          const PosPrintBlock(type: PosPrintBlockType.divider, divider: PosPrintDividerStyle.equals),
          const PosPrintBlock(type: PosPrintBlockType.lineItemsKitchen),
          const PosPrintBlock(type: PosPrintBlockType.divider, divider: PosPrintDividerStyle.equals),
        ],
      );

  static List<PosPrintTemplateV2> seedSetForDocument(String documentType) => [
        build(
          documentType: documentType,
          paperSize: PosPrintPaperSizes.k58,
          printerProfile: PosPrintPrinterProfiles.sunmiK58,
          name: 'Sunmi K58 — ${PosPrintDocumentTypes.all[documentType] ?? documentType}',
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
