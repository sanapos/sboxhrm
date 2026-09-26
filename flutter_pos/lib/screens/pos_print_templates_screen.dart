import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../widgets/pos/pos_pdf_preview_dialog.dart';
import '../providers/permission_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import '../models/pos_print_template.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../widgets/pos/pos_docx_template_review.dart';
import '../widgets/pos/pos_print_template_gallery.dart';
import '../widgets/notification_overlay.dart';
import '../utils/pos_barcode_print.dart';
import '../utils/pos_label_printer_service.dart';
import '../utils/pos_print_template_loader.dart';
import '../utils/pos_print_template_defaults.dart';
import '../utils/pos_print_template_renderer.dart';
import '../utils/pos_print_template_v2_codec.dart';
import '../utils/pos_print_template_v2_presets.dart';
import '../utils/pos_print_template_compiler.dart';
import '../utils/pos_print_template_runtime.dart';
import '../utils/pos_print_orchestrator.dart';
import '../utils/pos_print_config_session.dart';
import '../utils/pos_sell_print_settings.dart';
import '../utils/pos_sell_store_settings.dart';
import '../utils/pos_store_printer_mapper.dart';
import '../models/pos_print_template_v2.dart';
import '../widgets/pos/pos_print_template_v2_editor.dart';
import '../widgets/pos/pos_commercial_a4_editor.dart';
import '../utils/pos_html_print.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _blue = Color(0xFF2563EB);

class PosPrintTemplatesScreen extends StatefulWidget {
  const PosPrintTemplatesScreen({
    super.key,
    this.embeddedInSettings = false,
    this.initialDocumentType,
  });

  /// Hiển thị trong Thiết lập HRM (ẩn toolbar POS).
  final bool embeddedInSettings;

  /// Loại chứng từ mở sẵn (vd. StockIssue cho phiếu xuất kho).
  final String? initialDocumentType;

  @override
  State<PosPrintTemplatesScreen> createState() => _PosPrintTemplatesScreenState();
}

class _PosPrintTemplatesScreenState extends State<PosPrintTemplatesScreen> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _docTypeScrollCtrl = ScrollController();

  String _docType = PosPrintDocumentTypes.saleInvoice;
  List<PosPrintTemplate> _templates = [];
  List<PosPrintTemplateCatalog> _catalog = [];
  PosPrintTemplate? _selected;
  PosPrintTemplateV2? _v2Template;
  /// Khi khác null: lưu HTML thuần (legacy), không encode V2.
  String? _legacyHtml;
  String _commercialPaper = PosPrintPaperSizes.a4;
  bool _loading = true;
  bool _saving = false;
  bool _testingPrint = false;
  bool _dirty = false;
  /// false = thư viện mẫu (lưới thẻ), true = đang soạn một mẫu.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDocumentType != null &&
        widget.initialDocumentType!.isNotEmpty) {
      _docType = widget.initialDocumentType!;
    }
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _docTypeScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({String? keepId}) async {
    setState(() => _loading = true);

    _templates = await loadPosPrintTemplates(_api, _docType);
    await _upgradeLegacyHtmlTemplates();

    final catRes = await _api.getPosPrintTemplateCatalog(documentType: _docType);
    _catalog = [];
    if (catRes['isSuccess'] == true && catRes['data'] is List) {
      _catalog = (catRes['data'] as List)
          .whereType<Map>()
          .map((e) => PosPrintTemplateCatalog.fromJson(
              Map<String, dynamic>.from(e)))
          .toList();
    }

    _selected = (keepId == null ? null : _templates.where((t) => t.id == keepId).firstOrNull) ??
        _templates.where((t) => t.isDefault).firstOrNull ??
        _templates.firstOrNull;

    if (_selected != null) {
      _bindTemplateContent(_selected);
      _nameCtrl.text = _selected!.name;
    } else {
      _applyLocalDefault();
    }
    _dirty = false;

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _adoptCatalog(PosPrintTemplateCatalog cat) async {
    final res = await _api.adoptPosPrintTemplateCatalog(cat.id, setAsDefault: true);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã chọn mẫu',
        message: tr(
            'Toàn cửa hàng sẽ in theo «${cat.name}». Bạn có thể sửa bản cửa hàng mà không ảnh hưởng mẫu chung.'),
      );
      await _load();
      if (res['data'] is Map) {
        final adopted = PosPrintTemplate.fromJson(
            Map<String, dynamic>.from(res['data'] as Map));
        _applyTemplate(adopted);
        await _syncDevicePrintTemplateId(adopted.id);
        PosPrintConfigSession.instance.invalidate();
      }
    } else {
      NotificationOverlayManager().showError(
        title: 'Không chọn được mẫu',
        message: res['message']?.toString() ?? 'Thử lại',
      );
    }
  }

  Future<void> _setStoreDefault() async {
    final t = _selected;
    if (t == null) return;
    final res = await _api.setDefaultPosPrintTemplate(t.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Mẫu mặc định cửa hàng',
        message: tr('Toàn bộ máy thu ngân sẽ in theo «${t.name}»'),
      );
      await _syncDevicePrintTemplateId(t.id);
      PosPrintConfigSession.instance.invalidate();
      await _load(keepId: t.id);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không đặt được mặc định',
      );
    }
  }

  Future<void> _syncDevicePrintTemplateId(String templateId) async {
    try {
      final s = await PosSellPrintSettings.load();
      if (_docType == PosPrintDocumentTypes.saleInvoice) {
        await s.copyWith(templateId: templateId).save();
      } else if (_docType == PosPrintDocumentTypes.stockIssue) {
        await s.copyWith(warehouseTemplateId: templateId).save();
      }
    } catch (_) {}
  }

  void _applyLocalDefault({String? paperSize}) {
    _selected = null;
    if (_isCommercialDoc) {
      _commercialPaper = PosPrintPaperSizes.a4;
      _legacyHtml = posPrintDefaultHtml(
        documentType: _docType,
        paperSize: PosPrintPaperSizes.a4,
      );
      _v2Template = PosPrintTemplateV2Presets.build(
        documentType: _docType,
        paperSize: PosPrintPaperSizes.a4,
        printerProfile: PosPrintPrinterProfiles.sunmiK80,
        name: posPrintDefaultTemplateName(PosPrintPaperSizes.a4,
            documentType: _docType),
      );
      _nameCtrl.text = _v2Template!.name ??
          posPrintDefaultTemplateName(PosPrintPaperSizes.a4,
              documentType: _docType);
      _dirty = false;
      return;
    }
    _legacyHtml = null;
    final paper = paperSize ??
        (_docType == PosPrintDocumentTypes.kitchenLabel
            ? PosPrintPaperSizes.label50x30
            : _docType == PosPrintDocumentTypes.barcodeLabel
                ? 'roll_1_50x30'
                : PosPrintPaperSizes.k80);
    _v2Template = PosPrintTemplateV2Presets.build(
      documentType: _docType,
      paperSize: paper,
      printerProfile: PosPrintPaperSizes.isLabelSize(paper)
          ? PosPrintPrinterProfiles.genericK58
          : PosPrintPrinterProfiles.sunmiK80,
      name: posPrintDefaultTemplateName(paper, documentType: _docType),
    );
    _nameCtrl.text = _v2Template!.name ??
        posPrintDefaultTemplateName(paper, documentType: _docType);
    _dirty = false;
  }

  void _bindTemplateContent(PosPrintTemplate? t) {
    if (_isCommercialDoc) {
      final raw = (t?.htmlContent ?? '').trim();
      // JSON V2 (`<!--POS_TEMPLATE_V2-->…`) cũng khởi đầu bằng `<`; phải loại
      // trước khi dán vào editor Word, nếu không editor sẽ hiển thị raw JSON.
      final looksLikeHtml =
          raw.startsWith('<') && !PosPrintTemplateV2Codec.isV2Content(raw);
      _commercialPaper = PosPrintPaperSizes.normalizeCommercialPaper(t?.paperSize);
      _legacyHtml = looksLikeHtml
          ? t!.htmlContent
          : posPrintDefaultHtml(
              documentType: _docType,
              paperSize: _commercialPaper,
            );
      _v2Template = PosPrintTemplateV2Presets.build(
        documentType: _docType,
        paperSize: _commercialPaper,
        printerProfile: PosPrintPrinterProfiles.sunmiK80,
        name: t?.name,
      );
      return;
    }
    final parsed = PosPrintTemplateV2Codec.tryParse(t?.htmlContent);
    if (parsed != null) {
      _v2Template = parsed;
      _legacyHtml = null;
      return;
    }
    final raw = (t?.htmlContent ?? '').trim();
    if (raw.isNotEmpty && !PosPrintTemplateV2Codec.isV2Content(raw)) {
      // Giữ HTML thuần; vẫn tạo V2 preset để có thể quay lại chỉnh khối.
      _legacyHtml = t!.htmlContent;
      final paper = t.paperSize;
      final profile = paper == PosPrintPaperSizes.k58
          ? PosPrintPrinterProfiles.sunmiK58
          : PosPrintPrinterProfiles.sunmiK80;
      _v2Template = PosPrintTemplateV2Presets.build(
        documentType: _docType,
        paperSize: paper,
        printerProfile: profile,
        name: t.name,
      );
      return;
    }
    final paper = t?.paperSize ?? PosPrintPaperSizes.k80;
    final profile = paper == PosPrintPaperSizes.k58
        ? PosPrintPrinterProfiles.sunmiK58
        : PosPrintPrinterProfiles.sunmiK80;
    _legacyHtml = null;
    _v2Template = PosPrintTemplateV2Presets.build(
      documentType: _docType,
      paperSize: paper,
      printerProfile: profile,
      name: t?.name,
    );
  }

  /// HTML seed cũ (`1 x {Don_Gia}`) không điều khiển máy nhiệt — đổi sang V2 4 cột.
  Future<void> _upgradeLegacyHtmlTemplates() async {
    if (_isCommercialDoc) {
      await _upgradeCommercialToA4Html();
      return;
    }
    var changed = false;
    final next = <PosPrintTemplate>[];
    for (final t in _templates) {
      if (PosPrintTemplateV2Codec.tryParse(t.htmlContent) != null ||
          !PosPrintPaperSizes.isThermal(t.paperSize)) {
        next.add(t);
        continue;
      }
      final v2 = PosPrintTemplateV2Presets.build(
        documentType: t.documentType,
        paperSize: t.paperSize,
        printerProfile: t.paperSize == PosPrintPaperSizes.k58
            ? PosPrintPrinterProfiles.sunmiK58
            : PosPrintPrinterProfiles.sunmiK80,
        name: t.name,
      );
      final res = await _api.updatePosPrintTemplate(
        t.id,
        t.copyWith(htmlContent: PosPrintTemplateV2Codec.encode(v2)).toSaveJson(),
      );
      if (res['isSuccess'] == true && res['data'] is Map) {
        next.add(PosPrintTemplate.fromJson(
          Map<String, dynamic>.from(res['data'] as Map),
        ));
        changed = true;
      } else {
        next.add(t);
      }
    }
    if (changed) _templates = next;
  }

  /// Mẫu báo giá/HĐ: K80/K58 cũ → A4; HTML V2/stale → mẫu chuẩn.
  Future<void> _upgradeCommercialToA4Html() async {
    final next = <PosPrintTemplate>[];
    for (final t in _templates) {
      final raw = t.htmlContent.trim();
      final isV2 = PosPrintTemplateV2Codec.isV2Content(raw);
      final looksLikeHtml = raw.startsWith('<') && !isV2;
      final paperOk = t.paperSize == PosPrintPaperSizes.a4 ||
          t.paperSize == PosPrintPaperSizes.a5;
      final staleHtml = looksLikeHtml && posCommercialHtmlLooksStale(raw);
      final needPaper = !paperOk;
      final needHtml = isV2 || !looksLikeHtml || staleHtml;
      if (!needPaper && !needHtml) {
        next.add(t);
        continue;
      }
      final paper = paperOk
          ? t.paperSize
          : PosPrintPaperSizes.a4;
      final baseHtml = needHtml
          ? posPrintDefaultHtml(documentType: _docType, paperSize: paper)
          : raw;
      final setup = PosCommercialPageSetup.parse(baseHtml, fallbackPaper: paper)
          .copyWith(paperSize: paper);
      final html = setup.applyToHtml(baseHtml);
      final res = await _api.updatePosPrintTemplate(
        t.id,
        t.copyWith(
          htmlContent: html,
          paperSize: paper,
        ).toSaveJson(),
      );
      if (res['isSuccess'] == true && res['data'] is Map) {
        next.add(PosPrintTemplate.fromJson(
          Map<String, dynamic>.from(res['data'] as Map),
        ));
      } else {
        next.add(t.copyWith(
          htmlContent: html,
          paperSize: paper,
        ));
      }
    }
    _templates = next;
  }

  void _selectTemplate(PosPrintTemplate? t) {
    if (_dirty) {
      _confirmDiscard(() => _applyTemplate(t));
      return;
    }
    _applyTemplate(t);
  }

  void _applyTemplate(PosPrintTemplate? t) {
    setState(() {
      _selected = t;
      if (t != null) {
        _bindTemplateContent(t);
        _nameCtrl.text = t.name;
      } else {
        _applyLocalDefault();
      }
      _dirty = false;
    });
  }

  void _onLegacyHtml(String html) {
    setState(() {
      _legacyHtml = html;
      _dirty = true;
    });
    NotificationOverlayManager().showSuccess(
      title: 'HTML thuần',
      message: tr('Đã gắn HTML. Bấm Lưu để ghi. In nhiệt nên dùng JSON V2.'),
    );
  }

  Future<void> _confirmDiscard(VoidCallback onOk) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bỏ thay đổi?')),
        content: Text(tr('Mẫu in đang chỉnh sửa chưa lưu. Bỏ thay đổi?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bỏ'))),
        ],
      ),
    );
    if (ok == true && mounted) onOk();
  }

  String? get _dropdownValue {
    final id = _selected?.id;
    if (id == null || id.isEmpty) return null;
    return _templates.any((t) => t.id == id) ? id : null;
  }

  Future<void> _save() async {
    if (_selected == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: tr('Nhập tên mẫu in'));
      return;
    }
    setState(() => _saving = true);
    if (_isCommercialDoc) {
      final paper = PosPrintPaperSizes.normalizeCommercialPaper(_commercialPaper);
      final rawHtml = (_legacyHtml ?? '').trim().isEmpty
          ? posPrintDefaultHtml(
              documentType: _docType,
              paperSize: paper,
            )
          : _legacyHtml!;
      final setup = PosCommercialPageSetup.parse(rawHtml, fallbackPaper: paper)
          .copyWith(paperSize: paper);
      final html = ensurePosPrintItemLoop(setup.applyToHtml(rawHtml));
      final body = _selected!
          .copyWith(
            name: name,
            htmlContent: html,
            documentType: _docType,
            paperSize: paper,
            isDefault: _selected!.isDefault,
          )
          .toSaveJson();
      final res = await _api.updatePosPrintTemplate(_selected!.id, body);
      if (!mounted) return;
      setState(() => _saving = false);
      if (res['isSuccess'] == true) {
        _dirty = false;
        NotificationOverlayManager().showSuccess(
          title: 'Đã lưu',
          message: tr(_selected!.isDefault
              ? 'Mẫu A4 đang dùng đã cập nhật'
              : 'Đã lưu. Bấm «Dùng mẫu này» để dùng khi in'),
        );
        PosPrintConfigSession.instance.invalidate();
        await _load(keepId: _selected!.id);
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không lưu được',
        );
      }
      return;
    }
    final v2 = _v2Template!.copyWith(
      name: name,
      documentType: _docType,
      paperSize: _v2Template!.paperSize,
    );
    // Luôn lưu V2 — HTML legacy cũ ({So_Luong} x {Don_Gia}) không điều khiển máy nhiệt.
    final htmlContent = PosPrintTemplateV2Codec.encode(v2);
    _legacyHtml = null;
    final apiPaper = PosPrintPaperSizes.toApiPaperSize(_docType, v2.paperSize);
    final body = _selected!.copyWith(
      name: name,
      htmlContent: htmlContent,
      documentType: _docType,
      paperSize: apiPaper,
      isDefault: _selected!.isDefault,
    ).toSaveJson();
    final res = await _api.updatePosPrintTemplate(_selected!.id, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      _dirty = false;
      NotificationOverlayManager().showSuccess(
        title: 'Đã lưu',
        message: tr(_selected!.isDefault
            ? 'Mẫu đang dùng đã cập nhật — máy bán hàng in theo bản mới'
            : 'Đã lưu. Bấm «Dùng mẫu này» để máy bán hàng in theo mẫu này'),
      );
      try {
        if (_selected!.isDefault) await _syncDevicePrintTemplateId(_selected!.id);
        PosPrintConfigSession.instance.invalidate();
      } catch (_) {}
      await _load(keepId: _selected!.id);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được',
      );
    }
  }

  List<(String key, String label)> _paperOptionsForDoc() {
    if (_docType == PosPrintDocumentTypes.kitchenLabel) {
      return PosPrintPaperSizes.kitchenLabelSizes
          .map((k) => (k, PosPrintPaperSizes.displayLabel(k)))
          .toList();
    }
    if (_docType == PosPrintDocumentTypes.barcodeLabel) {
      return PosPrintPaperSizes.productLabelSizes
          .map((id) => (id, PosPrintPaperSizes.displayLabel(id)))
          .toList();
    }
    if (_isCommercialDoc) {
      return [
        (PosPrintPaperSizes.a4, PosPrintPaperSizes.labels[PosPrintPaperSizes.a4]!),
        (PosPrintPaperSizes.a5, PosPrintPaperSizes.labels[PosPrintPaperSizes.a5]!),
      ];
    }
    return [
      (PosPrintPaperSizes.k58, PosPrintPaperSizes.labels[PosPrintPaperSizes.k58]!),
      (PosPrintPaperSizes.k80, PosPrintPaperSizes.labels[PosPrintPaperSizes.k80]!),
      (PosPrintPaperSizes.a5, PosPrintPaperSizes.labels[PosPrintPaperSizes.a5]!),
      (PosPrintPaperSizes.a4, PosPrintPaperSizes.labels[PosPrintPaperSizes.a4]!),
    ];
  }

  Future<void> _addTemplate() async {
    final presetsRes = await _api.getPosPrintTemplatePresets(documentType: _docType);
    final presets = presetsRes['isSuccess'] == true && presetsRes['data'] is List
        ? (presetsRes['data'] as List)
            .map((e) => PosPrintTemplatePreset.fromJson(e as Map<String, dynamic>))
            .toList()
        : <PosPrintTemplatePreset>[];

    final paperOpts = _paperOptionsForDoc();
    String paper = paperOpts.first.$1;
    if (_docType == PosPrintDocumentTypes.barcodeLabel) {
      paper = 'roll_1_50x30';
    } else if (_docType == PosPrintDocumentTypes.kitchenLabel) {
      paper = PosPrintPaperSizes.label50x30;
    } else if (PosPrintDocumentTypes.isCommercial(_docType)) {
      paper = PosPrintPaperSizes.a4;
    } else {
      paper = PosPrintPaperSizes.k80;
    }
    if (!paperOpts.any((e) => e.$1 == paper)) {
      paper = paperOpts.first.$1;
    }
    final nameCtrl = TextEditingController(text: tr('Mẫu in mới'));
    final isLabel = PosPrintPaperSizes.isLabelDoc(_docType);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr('Thêm mẫu in')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: tr('Tên mẫu'), hintText: tr('vd. HĐ K80')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paper,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr(isLabel ? 'Khổ tem' : 'Khổ giấy'),
                  ),
                  items: paperOpts
                      .map((e) => DropdownMenuItem(
                            value: e.$1,
                            child: Text(tr(e.$2), overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setDlg(() => paper = v);
                  },
                ),
                if (presets.isNotEmpty && !isLabel && !_isCommercialDoc) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: presets.any((p) => p.paperSize == paper)
                        ? paper
                        : presets.first.paperSize,
                    decoration: InputDecoration(labelText: tr('Mẫu gợi ý')),
                    items: presets
                        .map((p) => DropdownMenuItem(
                              value: p.paperSize,
                              child: Text(tr(p.name)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final preset =
                          presets.where((p) => p.paperSize == v).firstOrNull;
                      setDlg(() {
                        paper = v;
                        if (preset != null && nameCtrl.text == 'Mẫu in mới') {
                          nameCtrl.text = preset.name;
                        }
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Bỏ qua'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Tạo'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final stock = posBarcodeLabelTemplateById(paper);
    final displayName = nameCtrl.text.trim().isEmpty
        ? (stock != null
            ? '${stock.name} (${stock.sizeLabel})'
            : (PosPrintPaperSizes.labels[paper] ?? paper))
        : nameCtrl.text.trim();

    final v2Paper = paper;
    final v2Preset = PosPrintTemplateV2Presets.build(
      documentType: _docType,
      paperSize: v2Paper,
      printerProfile: PosPrintPaperSizes.isLabelSize(v2Paper)
          ? PosPrintPrinterProfiles.genericK58
          : (v2Paper == PosPrintPaperSizes.k58
              ? PosPrintPrinterProfiles.sunmiK58
              : PosPrintPrinterProfiles.zywellK80),
      name: displayName,
    );

    final commercial = PosPrintDocumentTypes.isCommercial(_docType);
    final res = await _api.createPosPrintTemplate({
      'name': displayName,
      'documentType': _docType,
      'paperSize': PosPrintPaperSizes.toApiPaperSize(_docType, v2Paper),
      'htmlContent': commercial
          ? posPrintDefaultHtml(documentType: _docType, paperSize: v2Paper)
          : PosPrintTemplateV2Codec.encode(v2Preset),
      'isDefault': _templates.isEmpty,
      'isActive': true,
      'sortOrder': _templates.length,
    });
    if (res['isSuccess'] == true && res['data'] is Map) {
      NotificationOverlayManager().showSuccess(title: 'Đã tạo', message: tr('Mẫu in mới'));
      await _load();
      final created = PosPrintTemplate.fromJson(res['data'] as Map<String, dynamic>);
      _applyTemplate(created);
      setState(() => _editing = true);
    }
  }

  bool get _isCommercialDoc =>
      PosPrintDocumentTypes.isCommercial(_docType);

  /// Loại phiếu dùng được mẫu Word A4 giữ bố cục (báo giá / HĐ / biên bản + hóa đơn bán, trả, giao hàng).
  bool get _supportsWordTpl =>
      _isCommercialDoc ||
      const [
        PosPrintDocumentTypes.saleInvoice,
        PosPrintDocumentTypes.saleOrder,
        PosPrintDocumentTypes.saleReturn,
        PosPrintDocumentTypes.delivery,
      ].contains(_docType);

  /// Mẫu Word của khách giữ nguyên bố cục: AI chỉ chỗ dữ liệu động → xem lại → lưu.
  // Quyền module «Mẫu in» (server chặn cùng mức) — ẩn / khóa thao tác không được phép.
  PermissionProvider get _perm => context.read<PermissionProvider>();
  bool get _canCreateTpl => _perm.canCreate('PosPrintTemplates');
  bool get _canEditTpl => _perm.canEdit('PosPrintTemplates');
  bool get _canDeleteTpl => _perm.canDelete('PosPrintTemplates');

  Future<void> _reviewDocx() async {
    final id = _selected?.id;
    if (id == null) return;
    final saved = await showPosDocxTemplateReview(context, _api, id);
    if (saved && mounted) await _load();
  }

  Future<void> _importCustomerTemplate() async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['docx', 'doc', 'pdf'],
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) return;
      final f = pick.files.first;
      final lower = f.name.toLowerCase();
      // Word .docx: luôn giữ nguyên bố cục file (không chuyển sang HTML) → AI gắn trường → trình soạn mẫu.
      if (lower.endsWith('.docx')) {
        if (!mounted) return;
        final created = await importPosDocxTemplateWithAi(context, _api, documentType: _docType, file: f);
        if (created && mounted) await _load();
        return;
      }
      if (lower.endsWith('.doc')) {
        NotificationOverlayManager().showError(
          title: 'File Word cũ (.doc)',
          message: tr('Mở file bằng Word → Lưu thành (.docx) rồi tải lên để giữ nguyên bố cục.'),
        );
        return;
      }
      if (!_isCommercialDoc) {
        NotificationOverlayManager().showError(
          title: 'Chỉ nhận file Word',
          message: tr('Hóa đơn A4: tải file Word (.docx). PDF không giữ được chữ để gắn dữ liệu.'),
        );
        return;
      }
      final bytes = f.bytes;
      if (bytes == null) {
        NotificationOverlayManager().showError(
          title: 'Không đọc được file',
          message: tr('Chọn lại file Word hoặc PDF'),
        );
        return;
      }
      final res = await _api.importPosPrintTemplateFile(
        bytes: bytes,
        fileName: f.name,
        documentType: _docType,
        name: f.name.replaceAll(RegExp(r'\.(docx|doc|pdf)$', caseSensitive: false), ''),
      );
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map) {
        NotificationOverlayManager().showSuccess(
          title: 'Đã tạo mẫu từ file',
          message: tr('Khổ A4 — chèn {Khach_Hang}, {Tong_Cong}… rồi Lưu'),
        );
        await _load();
        final created = PosPrintTemplate.fromJson(
            Map<String, dynamic>.from(res['data'] as Map));
        _applyTemplate(created);
      } else {
        NotificationOverlayManager().showError(
          title: 'Không nhập được file',
          message: res['message']?.toString() ?? 'Thử file Word .docx',
        );
      }
    } catch (e) {
      if (!mounted) return;
      NotificationOverlayManager().showError(
        title: 'Không nhập được file',
        message: '$e',
      );
    }
  }

  Future<void> _testPrintTemplate() async {
    // Mẫu Word: in thử = PDF điền dữ liệu mẫu (đúng như bản in thật).
    if (_selected?.isDocx == true) {
      final res = await _api.getPosDocxTemplatePreview(_selected!.id, 'sample');
      if (!mounted) return;
      if (res['isSuccess'] != true || res['data'] is! List) {
        NotificationOverlayManager().showError(
            title: 'Không dựng được bản in thử', message: res['message']?.toString() ?? '');
        return;
      }
      await showPosPdfPreviewDialog(
        context,
        bytes: Uint8List.fromList(List<int>.from(res['data'] as List)),
        title: tr('In thử · ${_selected!.name}'),
      );
      return;
    }
    if (_isCommercialDoc) {
      final paper = PosPrintPaperSizes.normalizeCommercialPaper(_commercialPaper);
      final raw = (_legacyHtml ?? '').trim().isEmpty
          ? posPrintDefaultHtml(
              documentType: _docType,
              paperSize: paper,
            )
          : _legacyHtml!;
      final setup = PosCommercialPageSetup.parse(raw, fallbackPaper: paper)
          .copyWith(paperSize: paper);
      final body = renderPosPrintTemplateHtml(
        raw,
        data: posPrintSampleData(documentType: _docType),
        lineItems: posPrintSampleLines(count: 8),
        wrapDocument: false,
        paperSize: paper,
      );
      if (!mounted) return;
      await showPosHtmlPrintDialog(
        context,
        title: _nameCtrl.text.trim().isEmpty
            ? tr('Xem trước ${setup.paperSize}')
            : _nameCtrl.text.trim(),
        htmlDocument: wrapPosCommercialPrintHtml(body, setup),
        a4Paper: true,
      );
      return;
    }
    final v2 = _v2Template;
    if (v2 == null) return;
    setState(() => _testingPrint = true);
    try {
      final orch = PosPrintOrchestrator.instance;
      await orch.ensureListening();
      // Xóa máy cloud không còn trong chip Agent trước khi mở picker.
      try {
        await _api.cleanupPosAgentOrphanPrinters();
      } catch (_) {}
      await orch.refreshConfig(force: true);
      final deviceId = await PosPrintOrchestrator.stableDeviceId();
      // 1 máy / cổng — ẩn nội bộ máy khác và clone Cloud+Nội bộ.
      final active = PosPrintOrchestrator.uniquePrintersForPicker(
        orch.printers,
        deviceId: deviceId,
      );
      active.sort((a, b) {
        final ao = a.isOnline ? 0 : 1;
        final bo = b.isOnline ? 0 : 1;
        if (ao != bo) return ao.compareTo(bo);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (active.isEmpty) {
        if (!mounted) return;
        NotificationOverlayManager().showWarning(
          title: 'Chưa có máy in',
          message: tr('Thêm máy in cửa hàng / máy in nội bộ trước khi in thử'),
        );
        return;
      }

      final isBarcodeLabel = v2.documentType == PosPrintDocumentTypes.barcodeLabel;
      final isKitchenLabel =
          v2.documentType == PosPrintDocumentTypes.kitchenLabel;
      final isKitchenSlipDoc =
          v2.documentType == PosPrintDocumentTypes.kitchenSlip ||
              v2.documentType == PosPrintDocumentTypes.kitchenVoid;

      List<PosStorePrinter> candidates;
      if (isBarcodeLabel || isKitchenLabel) {
        candidates = active.where((p) => p.isLabelPrinter).toList();
        if (candidates.isEmpty) {
          candidates = active
              .where((p) =>
                  p.isSunmi ||
                  p.documentTypes.isEmpty ||
                  p.documentTypes.contains(v2.documentType))
              .toList();
        }
        if (candidates.isEmpty) candidates = List.of(active);
      } else if (isKitchenSlipDoc) {
        candidates = active
            .where((p) =>
                !p.isLabelPrinter &&
                (p.canPrintKitchenSlip ||
                    p.documentTypes.isEmpty ||
                    p.documentTypes.any((d) =>
                        d == PosPrintDocumentTypes.kitchenSlip ||
                        d == PosPrintDocumentTypes.kitchenVoid ||
                        d == v2.documentType)))
            .toList();
        if (candidates.isEmpty) {
          candidates = active.where((p) => !p.isLabelPrinter).toList();
        }
        if (candidates.isEmpty) candidates = List.of(active);
      } else {
        candidates = active.where((p) => !p.isLabelPrinter).toList();
        if (candidates.isEmpty) candidates = List.of(active);
      }

      if (!mounted) return;
      final picked = await _pickTestPrinter(candidates);
      if (picked == null || !mounted) return;

      final isKitchenSlip =
          v2.documentType == PosPrintDocumentTypes.kitchenSlip ||
              v2.documentType == PosPrintDocumentTypes.kitchenVoid;
      final isLabel = v2.documentType == PosPrintDocumentTypes.kitchenLabel;
      final store = await PosSellStoreSettings.load();
      final sample = posPrintSampleData(
        documentType: v2.documentType,
        storeName: store.storeName,
        storeAddress: store.address,
        storePhone: store.phone,
      );

      // Tem: local USB hoặc TSPL qua Agent (A7 không cắm tem).
      if (isBarcodeLabel || isLabel || picked.isLabelPrinter) {
        final output = PosPrintTemplateCompiler.compile(
          template: v2,
          data: sample,
          lineItems: [
            {
              'Ten_Hang_Hoa': sample['Ten_Hang_Hoa'] ?? 'Trà đào',
              'So_Luong': sample['So_Luong'] ?? '1',
              'Don_Vi_Tinh': sample['Don_Vi_Tinh'] ?? '',
              'Ghi_Chu': sample['Ghi_Chu'] ?? '',
              'Don_Gia': sample['Don_Gia'] ?? '',
              'Ma_Hang': sample['Ma_Hang'] ?? '',
              'Ma_Vach': sample['Ma_Vach'] ?? '',
            },
          ],
        );
        final labelSettings = toLabelSettings(picked).copyWith(enabled: true);
        final designTplId = PosPrintPaperSizes.toLabelTemplateId(v2.paperSize);
        final designSize = posBarcodeLabelTemplateById(designTplId);
        final machineTpl = labelSettings.template ??
            posBarcodeLabelTemplateById('roll_1_50x30')!;
        final tpl = designSize ?? machineTpl;
        bool ok;
        if (await PosPrintOrchestrator.instance
            .canProbeLocalPortForTest(picked)) {
          ok = await PosLabelPrinterService.printCompiledTemplate(
            output: output,
            settings: labelSettings,
            widthMm: tpl.labelWidthMm,
            heightMm: tpl.labelHeightMm,
          );
        } else {
          final jobs = await PosLabelPrinterService.buildCompiledTemplateJobs(
            output: output,
            settings: labelSettings,
            widthMm: tpl.labelWidthMm,
            heightMm: tpl.labelHeightMm,
          );
          ok = jobs.isNotEmpty;
          for (var i = 0; i < jobs.length; i++) {
            final sent = await orch.dispatchEscPos(
              documentType: isBarcodeLabel
                  ? PosPrintDocumentTypes.barcodeLabel
                  : PosPrintDocumentTypes.kitchenLabel,
              bytes: jobs[i],
              printerId: picked.id,
              showFeedback: false,
              skipDedup: true,
              waitForCompletion: false,
              acceptClaimedAsSuccess: true,
              hangAfter: const Duration(seconds: 90),
            );
            if (!sent) {
              ok = false;
              break;
            }
          }
        }
        if (!mounted) return;
        if (ok) {
          NotificationOverlayManager().showSuccess(
            title: 'In thử tem',
            message: tr('Đã gửi tem theo mẫu → ${picked.name}'),
          );
        } else {
          NotificationOverlayManager().showError(
            title: 'In thử tem thất bại',
            message: tr('Kiểm tra kết nối máy in tem (${picked.name})'),
          );
        }
        return;
      }

      // Sunmi chip (A7 → A6 Agent): TemplatePreviewJson — đúng draft editor.
      if (picked.isSunmi) {
        final ok = await orch.dispatchTemplatePreview(
          template: v2,
          printer: picked,
          data: sample,
          lineItems: isKitchenSlip ? const [] : posPrintSampleLines(),
          mode: isKitchenSlip ? 'kitchenSlip' : 'sale',
          kitchen: isKitchenSlip
              ? {
                  'tableName': 'Bàn 05',
                  'isCancel':
                      v2.documentType == PosPrintDocumentTypes.kitchenVoid,
                  'lines': [
                    {
                      'name': 'Phở bò tái',
                      'qty': '2',
                      'unit': 'tô',
                      'note': 'Ít hành',
                    },
                    {'name': 'Trà đá', 'qty': '2', 'unit': 'ly'},
                  ],
                  'senderName': 'NV Demo',
                  'orderNo': 'DH0001',
                }
              : null,
          kitchenFeed: isKitchenSlip,
          showFeedback: false,
          successTitle: 'In thử',
        );
        if (!mounted) return;
        if (ok) {
          NotificationOverlayManager().showSuccess(
            title: 'In thử',
            message: tr('Đã gửi mẫu → ${picked.name}'),
          );
        } else {
          NotificationOverlayManager().showError(
            title: 'In thử thất bại',
            message: tr('Sunmi/Agent không nhận mẫu (${picked.name})'),
          );
        }
        return;
      }

      final output = isKitchenSlip
          ? PosPrintTemplateRuntime.compileKitchenSlip(
              template: v2,
              tableName: 'Bàn 05',
              isCancel: v2.documentType == PosPrintDocumentTypes.kitchenVoid,
              lines: const [
                (name: 'Phở bò tái', qty: '2', unit: 'tô', note: 'Ít hành'),
                (name: 'Trà đá', qty: '2', unit: 'ly', note: null),
              ],
              senderName: 'NV Demo',
              orderNo: 'DH0001',
              sentAt: DateTime.now(),
            )
          : PosPrintTemplateCompiler.compile(
              template: v2,
              data: sample,
              lineItems: posPrintSampleLines(),
            );

      final settings = toThermalSettings(picked).copyWith(
        enabled: true,
        paperSize: v2.paperSize,
      );

      final bytes = await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
        output: output,
        settings: settings,
      );
      final ok = picked.isDeviceLocal
          ? await orch.dispatchLocalEscPos(
              bytes: bytes,
              settingsOverride: settings,
              documentType: v2.documentType,
              showFeedback: false,
              skipDedup: true,
            )
          : await orch.dispatchEscPos(
              documentType: v2.documentType,
              bytes: bytes,
              printerId: picked.id,
              showFeedback: false,
              skipDedup: true,
            );
      if (!mounted) return;
      if (ok) {
        NotificationOverlayManager().showSuccess(
          title: 'In thử',
          message: tr('Đã gửi mẫu in thử → ${picked.name}'),
        );
      } else {
        NotificationOverlayManager().showError(
          title: 'In thử thất bại',
          message: tr('Kiểm tra kết nối máy in (${picked.name})'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      NotificationOverlayManager().showError(
        title: 'In thử thất bại',
        message: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _testingPrint = false);
    }
  }

  Future<PosStorePrinter?> _pickTestPrinter(List<PosStorePrinter> printers) {
    if (printers.length == 1) return Future.value(printers.first);
    return showModalBottomSheet<PosStorePrinter>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                tr('Chọn máy in thử'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: printers.length,
                itemBuilder: (_, i) {
                  final p = printers[i];
                  final source = p.isDeviceLocal ? 'Nội bộ' : 'Agent';
                  final kind = p.isLabelPrinter
                      ? 'Tem'
                      : (p.isSunmi ? 'Sunmi' : p.connectionType);
                  final online = p.isOnline
                      ? 'Online'
                      : (p.healthStatus.trim().isEmpty
                          ? 'Offline'
                          : p.healthStatus);
                  final sameName = printers
                      .where((x) =>
                          x.name.trim().toLowerCase() ==
                          p.name.trim().toLowerCase())
                      .length;
                  final title = sameName > 1
                      ? '${p.name} ($source)'
                      : p.name;
                  return ListTile(
                    leading: Icon(
                      p.isLabelPrinter
                          ? Icons.label_outline
                          : Icons.print_outlined,
                      color: p.isOnline ? _blue : Colors.grey,
                    ),
                    title: Text(tr(title)),
                    subtitle: Text(tr('$source · $kind · $online')),
                    onTap: () => Navigator.of(ctx).pop(p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTemplate() async {
    if (_selected == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa mẫu in?')),
        content: Text(tr('Xóa mẫu «${_selected!.name}»?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosPrintTemplate(_selected!.id);
    if (res['isSuccess'] == true) {
      await _load();
    }
  }

  // ─── Thao tác từ thư viện mẫu ─────────────────────────────────────

  Future<void> _changeDocType(String type) async {
    if (type == _docType && !_editing) return;
    void go() {
      setState(() {
        _docType = type;
        _editing = false;
      });
      _load();
    }

    if (_editing && _dirty) {
      await _confirmDiscard(go);
    } else {
      go();
    }
  }

  Future<void> _editTemplate(PosPrintTemplate t) async {
    if (t.isDocx) {
      // Mẫu Word: trình soạn riêng (mẫu gốc / soạn trên trang in / bản in thử).
      final saved = await showPosDocxTemplateReview(context, _api, t.id);
      if (saved && mounted) await _load(keepId: t.id);
      return;
    }
    _applyTemplate(t);
    setState(() => _editing = true);
  }

  Future<void> _exitEditor() async {
    if (_dirty) {
      await _confirmDiscard(() {
        setState(() => _editing = false);
        _load(keepId: _selected?.id);
      });
      return;
    }
    setState(() => _editing = false);
  }

  Future<void> _useTemplate(PosPrintTemplate t) async {
    _selected = t;
    await _setStoreDefault();
  }

  Future<void> _testTemplate(PosPrintTemplate t) async {
    if (!_editing) _applyTemplate(t);
    await _testPrintTemplate();
  }

  Future<void> _deleteTemplateOf(PosPrintTemplate t) async {
    _selected = t;
    await _deleteTemplate();
  }

  Future<void> _duplicateTemplate(PosPrintTemplate t) async {
    final res = await _api.createPosPrintTemplate({
      'name': '${t.name} (bản sao)',
      'documentType': t.documentType,
      'paperSize': t.paperSize,
      'htmlContent': t.htmlContent,
      'isDefault': false,
      'isActive': true,
      'sortOrder': _templates.length,
    });
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      NotificationOverlayManager().showSuccess(title: 'Đã nhân bản', message: tr('Sửa bản sao không ảnh hưởng mẫu đang dùng'));
      final created = PosPrintTemplate.fromJson(Map<String, dynamic>.from(res['data'] as Map));
      await _load(keepId: created.id);
    } else {
      NotificationOverlayManager().showError(title: 'Không nhân bản được', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _onAddTemplate() async {
    final choice = await showPosPrintAddTemplateSheet(
      context,
      documentType: _docType,
      catalog: _catalog,
      allowWord: _supportsWordTpl,
    );
    if (choice == null || !mounted) return;
    if (choice == 'word') {
      await _importCustomerTemplate();
    } else if (choice == 'blank') {
      await _addTemplate();
    } else if (choice.startsWith('catalog:')) {
      final id = choice.substring('catalog:'.length);
      final cat = _catalog.where((c) => c.id == id).firstOrNull;
      if (cat != null) await _adoptCatalog(cat);
    }
  }

  // ─── Giao diện ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);
    final hubBody = widget.embeddedInSettings && !HrmPageChrome.showInPageAppBar(context);
    final hideInnerBar = hubBody || (mobile && (ModalRoute.of(context)?.isFirst ?? true) && !_editing);
    return PopScope(
      canPop: !_editing,
      onPopInvoked: (didPop) {
        if (!didPop && _editing) _exitEditor();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: hubBody ? HrmPageChrome.scaffoldBackground(context) : const Color(0xFFF3F4F6),
        appBar: hideInnerBar || (!mobile && _editing)
            ? null
            : AppBar(
                title: Text(_editing ? tr('Sửa mẫu in') : tr('Mẫu in')),
                backgroundColor: PosTheme.kiotBlue,
                foregroundColor: Colors.white,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: tr('Quay lại'),
                  onPressed: () => _editing ? _exitEditor() : Navigator.maybePop(context),
                ),
                actions: _editing
                    ? [
                        TextButton(
                          onPressed: _saving || _selected == null || !_canEditTpl ? null : _save,
                          child: Text(_dirty ? tr('Lưu*') : tr('Lưu'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ]
                    : null,
              ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hubBody && !mobile && !_editing) const PosModuleToolbar(activeModule: 'PosSell'),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _editing
                      ? _buildEditorView(mobile)
                      : _buildGalleryView(mobile),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryView(bool mobile) {
    final hint = PosPrintDocumentTypes.usageHint(_docType);
    final header = Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mobile)
                  InkWell(
                    onTap: () async {
                      final t = await showPosPrintDocTypePicker(context, _docType);
                      if (t != null) _changeDocType(t);
                    },
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(tr(posPrintDocLabel(_docType)),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const Icon(Icons.arrow_drop_down, size: 28),
                    ]),
                  )
                else
                  Text(tr(posPrintDocLabel(_docType)),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(tr(hint), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
              ],
            ),
          ),
          if (_canCreateTpl && !mobile)
            FilledButton.icon(
              onPressed: _onAddTemplate,
              icon: const Icon(Icons.add),
              label: Text(tr('Thêm mẫu')),
            ),
        ],
      ),
    );

    final cards = <Widget>[
      for (final t in _templates)
        PosPrintTemplateCard(
          template: t,
          canEdit: _canEditTpl,
          onEdit: () => _editTemplate(t),
          onUse: () => _useTemplate(t),
          onTestPrint: () => _testTemplate(t),
          onDuplicate: _canCreateTpl && !t.isDocx ? () => _duplicateTemplate(t) : null,
          onDelete: _canDeleteTpl ? () => _deleteTemplateOf(t) : null,
        ),
      if (_canCreateTpl) PosPrintAddTemplateCard(onTap: _onAddTemplate),
    ];

    final grid = cards.isEmpty
        ? Center(child: Text(tr('Chưa có mẫu in cho loại phiếu này')))
        : GridView.extent(
            padding: const EdgeInsets.all(16),
            maxCrossAxisExtent: mobile ? 220 : 260,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: mobile ? .58 : .62,
            children: cards,
          );

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (_templates.isNotEmpty && !_templates.any((t) => t.isDefault))
          Material(
            color: const Color(0xFFFFF7ED),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(tr('Chưa chọn mẫu đang dùng — bấm «Dùng mẫu này» trên một mẫu để máy bán hàng in theo mẫu đó.'),
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412))),
            ),
          ),
        Expanded(child: grid),
      ],
    );

    if (mobile) return main;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 240,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: PosPrintDocTypeNav(current: _docType, onSelect: _changeDocType),
        ),
        Expanded(child: main),
      ],
    );
  }

  Widget _buildEditorView(bool mobile) {
    final isDefault = _selected?.isDefault == true;
    final topBar = mobile
        ? null
        : Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _exitEditor,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(tr('Tất cả mẫu')),
                  ),
                  const SizedBox(width: 8),
                  Text(tr(posPrintDocLabel(_docType)),
                      style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: tr('Tên mẫu'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _dirty = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isDefault)
                    Chip(
                      avatar: const Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
                      label: Text(tr('Đang dùng')),
                      visualDensity: VisualDensity.compact,
                    ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _testingPrint ? null : _testPrintTemplate,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: Text(tr('In thử')),
                  ),
                  if (!isDefault && _canEditTpl) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _dirty ? null : _setStoreDefault,
                      child: Text(tr('Dùng mẫu này')),
                    ),
                  ],
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving || _selected == null || !_canEditTpl ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(_dirty ? tr('Lưu*') : tr('Lưu')),
                  ),
                ],
              ),
            ),
          );

    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: tr('Tên mẫu'), isDense: true, border: const OutlineInputBorder()),
              onChanged: (_) => setState(() => _dirty = true),
            ),
          ),
          Expanded(child: _buildMobileEditorBody()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        topBar!,
        if (_legacyHtml != null && !_isCommercialDoc)
          Material(
            color: const Color(0xFFFFF7ED),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.html, color: Color(0xFFB45309)),
              title: Text(tr('Mẫu này đang ở dạng HTML thuần')),
              subtitle: Text(tr('Bấm «Chuyển sang soạn theo khối» để chỉnh dễ hơn (ghi đè HTML khi lưu).')),
              trailing: TextButton(
                onPressed: () => setState(() {
                  _legacyHtml = null;
                  _dirty = true;
                }),
                child: Text(tr('Chuyển sang soạn theo khối')),
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _isCommercialDoc
                ? PosCommercialA4Editor(
                    html: _legacyHtml ?? posPrintDefaultHtml(documentType: _docType, paperSize: _commercialPaper),
                    documentType: _docType,
                    paperSize: _commercialPaper,
                    onPageSetupChanged: (s) => setState(() {
                      _commercialPaper = s.paperSize;
                      _dirty = true;
                    }),
                    onChanged: (html) => setState(() {
                      _legacyHtml = html;
                      _dirty = true;
                    }),
                  )
                : _v2Template == null
                    ? Center(child: Text(tr('Đang tải…')))
                    : PosPrintTemplateV2Editor(
                        template: _v2Template!,
                        onChanged: (v) => setState(() {
                          _v2Template = v;
                          _legacyHtml = null;
                          _dirty = true;
                        }),
                        onLegacyHtml: _onLegacyHtml,
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileEditorBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_legacyHtml != null && !_isCommercialDoc)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.html, color: Color(0xFFB45309), size: 22),
                  title: Text(tr('HTML thuần'), style: TextStyle(fontSize: 13)),
                  trailing: TextButton(
                    onPressed: () => setState(() {
                      _legacyHtml = null;
                      _dirty = true;
                    }),
                    child: Text(tr('Về V2')),
                  ),
                ),
              ),
            ),
          Expanded(
            child: _isCommercialDoc
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: PosCommercialA4Editor(
                      compact: true,
                      initialTab: 1,
                      initialZoom: 1,
                      html: _legacyHtml ??
                          posPrintDefaultHtml(
                            documentType: _docType,
                            paperSize: _commercialPaper,
                          ),
                      documentType: _docType,
                      paperSize: _commercialPaper,
                      onPageSetupChanged: (s) => setState(() {
                        _commercialPaper = s.paperSize;
                        _dirty = true;
                      }),
                      onChanged: (html) => setState(() {
                        _legacyHtml = html;
                        _dirty = true;
                      }),
                    ),
                  )
                : _v2Template == null
                ? const Center(child: CircularProgressIndicator())
                : PosPrintTemplateV2Editor(
                    compact: true,
                    template: _v2Template!,
                    onChanged: (v) => setState(() {
                      _v2Template = v;
                      _legacyHtml = null;
                      _dirty = true;
                    }),
                    onLegacyHtml: _onLegacyHtml,
                  ),
          ),
        ],
      ),
    );
  }
}
