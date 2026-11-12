import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../utils/pos_html_print.dart';
import '../../utils/pos_quote_commercial.dart';
import '../../utils/pos_quote_export.dart';
import '../../widgets/notification_overlay.dart';
import 'pos_quote_document_template_screen.dart';
import 'pos_quote_document_wording_screen.dart';
import '../../widgets/pos/pos_quote_document_tools.dart';
import '../../widgets/pos/pos_quote_care_card.dart';
import '../../widgets/pos/pos_quote_care_sheet.dart';
import '../../widgets/pos/pos_quote_quick_actions.dart';
import '../../widgets/pos/pos_contract_payment_panel.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_quote_detail_screen.dart' show PosQuoteFlow, PosQuoteProgress;

import '../../theme/sbox_tokens.dart';
import '../../utils/pos_busy.dart';
import 'dart:typed_data';
import '../../widgets/pos/pos_pdf_preview_dialog.dart';
/// Chi tiết hợp đồng: tạm ứng + biên bản nghiệm thu.
class PosContractDetailScreen extends StatefulWidget {
  const PosContractDetailScreen({super.key, required this.quoteId, this.onChanged, this.onClose});

  final String quoteId;

  /// Hồ sơ vừa đổi (tạo trọn bộ, thu tiền, sửa đợt…) → màn chia đôi tải lại danh sách bên trái.
  /// Trước đây thẻ bên trái vẫn «Đã lập HĐ · 4/7» trong khi chi tiết đã «Đã nghiệm thu».
  final VoidCallback? onChanged;

  /// Nhúng ở cột phải màn chia đôi: nút đóng thay nút quay lại.
  final VoidCallback? onClose;

  @override
  State<PosContractDetailScreen> createState() =>
      _PosContractDetailScreenState();
}

class _PosContractDetailScreenState extends State<PosContractDetailScreen> {
  final _api = ApiService();
  final _money = NumberFormat('#,##0', 'vi_VN');
  PosQuote? _quote;
  bool _loading = true;
  bool _loadedOnce = false;
  bool _busy = false;
  final _careKey = GlobalKey<PosQuoteCareCardState>();

  List<PosQuoteDocument> get _docs => _quote?.documents ?? const [];

  PosQuoteDocument? get _contract {
    for (final d in _docs) {
      if (d.kind == 'Contract') return d;
    }
    return null;
  }

  List<PosQuoteDocument> get _advances =>
      _docs.where((d) => d.kind == 'PaymentRequest').toList();

  List<PosQuoteDocument> get _handovers =>
      _docs.where((d) => d.kind == 'Handover').toList();

  List<PosQuoteDocument> get _acceptances =>
      _docs.where((d) => d.kind == 'Acceptance').toList();

  @override
  void initState() {
    super.initState();
    // Mở từ PosBusy.run(… push màn này) — lệnh chỉ xong khi màn đóng → lớp «Đang mở…» đè suốt lúc soạn.
    PosBusy.hideLayer();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosQuote(widget.quoteId);
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Không tải được',
        message: res['message']?.toString() ?? tr('Không tìm thấy hợp đồng'),
      );
      return;
    }
    setState(() {
      _loading = false;
      _quote = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
    });
    // Lần tải đầu chỉ là mở màn; các lần sau là tải lại sau một thao tác.
    if (_loadedOnce) widget.onChanged?.call();
    _loadedOnce = true;
  }

  /// Tải lại báo giá sau khi thu tiền / sửa đợt — không thay màn bằng vòng chờ.
  Future<void> _reloadQuiet() async {
    final res = await _api.getPosQuote(widget.quoteId);
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    setState(() => _quote = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map)));
    widget.onChanged?.call();
  }

  Future<void> _openDoc(PosQuoteDocument d) async {
    final q = _quote;
    final type = switch (d.kind) {
      'Contract' => PosPrintDocumentTypes.contract,
      'Handover' => PosPrintDocumentTypes.handover,
      'Acceptance' => PosPrintDocumentTypes.acceptance,
      'PaymentRequest' => PosPrintDocumentTypes.paymentRequest,
      'Quote' => PosPrintDocumentTypes.quote,
      _ => '',
    };
    if (q != null && type == PosPrintDocumentTypes.quote) {
      await printPosQuoteSlip(context, quoteId: q.id, quote: q);
      return;
    }
    // Cửa hàng dùng mẫu Word (hợp đồng upload) → xem đúng file PDF dựng từ mẫu Word, giữ nguyên bố cục
    // bản upload (trước đây «Xem / in» luôn hiện bản HTML mẫu chuẩn, khác hẳn bản Word).
    if (q != null && type.isNotEmpty && d.id.isNotEmpty &&
        await PosQuoteExport.usesWordTemplate(q, type, d.id)) {
      final res = await _api.exportPosQuoteFile(q.id, kind: type, docId: d.id, format: 'pdf');
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is List && (res['data'] as List).isNotEmpty) {
        await showPosPdfPreviewDialog(
          context,
          bytes: Uint8List.fromList(List<int>.from(res['data'] as List)),
          title: '${d.docNo} · ${d.title.isEmpty ? PosQuoteDocument.kindLabel(d.kind) : d.title}',
        );
        return;
      }
      NotificationOverlayManager().showError(
        title: 'Chưa dựng được từ mẫu Word',
        message: '${res['message'] ?? ''} — ${tr('hiện bản HTML')}',
      );
    }
    if (q != null && type.isNotEmpty) {
      // Đúng chứng từ này: lời văn sửa riêng hoặc mẫu chọn riêng + số liệu mới nhất.
      final server = await posQuoteServerDocument(
        q.id,
        type,
        docId: d.id,
        api: _api,
      );
      if (!mounted) return;
      if (server != null) {
        if (server.isStale) {
          final choice = await askPosQuoteStaleWording(context, d.docNo);
          if (!mounted || choice == null) return;
          if (choice == 'edit') {
            await _editWording(d);
            return;
          }
          if (choice == 'refresh') {
            final res = await _api.updatePosQuoteDocumentWording(q.id, d.id, restore: true);
            if (!mounted) return;
            if (res['isSuccess'] == true) {
              await _load();
              if (!mounted) return;
              final fresh = _quote?.documents.where((x) => x.id == d.id).firstOrNull;
              await _openDoc(fresh ?? d);
            } else {
              NotificationOverlayManager().showError(
                title: 'Chưa cập nhật được',
                message: res['message']?.toString() ?? d.docNo,
              );
            }
            return;
          }
        }
        await showPosHtmlPrintDialog(
          context,
          title: d.title.isEmpty ? d.docNo : d.title,
          htmlDocument: server.html,
          a4Paper: true,
        );
        return;
      }
    }
    if (!mounted) return;
    // Mất mạng: lời văn đã sửa riêng của chứng từ này (đã tải sẵn) — không dựng lại đè mất.
    if (d.isCustomWording && d.htmlContent.trim().isNotEmpty) {
      await showPosHtmlPrintDialog(
        context,
        title: d.title.isEmpty ? d.docNo : d.title,
        htmlDocument: d.htmlContent,
        a4Paper: true,
      );
      return;
    }
    if (q != null && type.isNotEmpty && q.lines.isNotEmpty) {
      Map<String, dynamic>? profile;
      try {
        final profileRes = await _api.getPosCommercialProfile();
        if (profileRes['isSuccess'] == true && profileRes['data'] is Map) {
          profile = Map<String, dynamic>.from(profileRes['data'] as Map);
        }
      } catch (_) {}
      final html = bindPosCommercialPrintHtmlLocal(
        q,
        documentType: type,
        docNo: d.docNo,
        commercialProfile: profile,
      );
      if (!mounted) return;
      if (html.trim().isNotEmpty) {
        await showPosHtmlPrintDialog(
          context,
          title: d.title.isEmpty ? d.docNo : d.title,
          htmlDocument: html,
          a4Paper: true,
        );
        return;
      }
    }
    var html = d.htmlContent;
    if (html.trim().isEmpty) {
      final preview = await _api.previewPosQuoteDocument(widget.quoteId, d.kind);
      if (preview['isSuccess'] == true && preview['data'] is Map) {
        html = (preview['data']['htmlContent'] ??
                preview['data']['HtmlContent'] ??
                '')
            .toString();
      }
    }
    if (!mounted) return;
    if (html.trim().isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Chưa có phiếu',
        message: d.docNo,
      );
      return;
    }
    await showPosHtmlPrintDialog(context, title: d.title, htmlDocument: html, a4Paper: true);
  }

  Future<void> _createPackage() async {
    final q = _quote;
    if (q == null || _busy) return;
    setState(() => _busy = true);
    final ok = await createPosQuoteCommercialPackage(context, quote: q);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) await _load();
  }

  Future<void> _create(String kind) async {
    final q = _quote;
    if (q == null || _busy) return;
    setState(() => _busy = true);
    final doc = await createPosQuoteCommercialDoc(
      context,
      quote: q,
      kind: kind,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (doc != null) {
      await _load();
      if (mounted && doc.htmlContent.isNotEmpty) {
        await showPosHtmlPrintDialog(
          context,
          title: doc.title,
          htmlDocument: doc.htmlContent,
          a4Paper: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    final contract = _contract;
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        // Số HĐ trong khung bo góc như chip (cùng kiểu chi tiết báo giá / thẻ danh sách).
        title: contract == null
            ? Text(tr('Hợp đồng'))
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SboxColors.slate50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: SboxColors.slate200),
                ),
                child: Text(contract.docNo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SboxColors.isBoss ? SboxColors.onBar : SboxColors.slate800)),
              ),
        automaticallyImplyLeading: widget.onClose == null,
        // Cột chi tiết khi chia đôi: thanh tiêu đề thấp như chi tiết báo giá.
        toolbarHeight: widget.onClose != null ? 48 : null,
        actions: [
          if (widget.onClose != null)
            IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close), onPressed: widget.onClose),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : q == null
              ? Center(child: Text(tr('Không tìm thấy')))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: SboxColors.slate200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: SboxColors.success.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(tr(PosQuote.stageLabel(q.commercialStage)),
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.success)),
                                ),
                                const Spacer(),
                                Text(tr('Từ báo giá ${q.quoteNo}'),
                                    style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                              ]),
                              const SizedBox(height: 10),
                              Text(
                                tr(contract?.title ?? 'Hợp đồng'),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SboxColors.slate600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr((q.customerName ?? '').trim().isEmpty ? 'Khách lẻ' : q.customerName!.trim()),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: SboxColors.slate900),
                              ),
                              // Có khung «Thu tiền hợp đồng» (giá trị HĐ / đã thu / còn phải thu) → không lặp ở đầu trang.
                              if (!canUsePosContracts(context)) ...[
                              const SizedBox(height: 10),
                              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(tr('Giá trị hợp đồng'),
                                        style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                                    Text(tr('${_money.format(q.total)} đ'),
                                        style: const TextStyle(
                                            fontSize: 22, fontWeight: FontWeight.w800, color: PosTheme.kiotBlue)),
                                  ]),
                                ),
                                if (q.depositAmount > 0)
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text(tr('Cọc'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                                    Text(
                                      tr('${_money.format(q.depositAmount)} đ${q.depositPercent != null ? ' (${q.depositPercent!.round()}%)' : ''}'),
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                    ),
                                  ]),
                              ]),
                              ],
                              const SizedBox(height: 14),
                              PosQuoteProgress(done: PosQuoteFlow.doneCount(q), stopped: PosQuoteFlow.isStopped(q)),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                // Viền: theme vẽ tonal y hệt nút đặc → 2 nút xanh đặc, không rõ nút chính.
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                                  onPressed: contract == null
                                      ? null
                                      : () => PosBusy.run(context, () => _openDoc(contract),
                                          label: 'Đang mở hợp đồng…'),
                                  icon: const Icon(Icons.description_outlined),
                                  label: Text(tr('Xem / in hợp đồng')),
                                ),
                              ),
                              // Trọn bộ chỉ khi còn thiếu chứng từ (trước: nút đặc to nhất kể cả khi đã đủ 4 loại).
                              if (_missingKinds.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _busy ? null : _createPackage,
                                    icon: const Icon(Icons.folder_copy_outlined),
                                    label: Text(tr('Lập nốt hồ sơ còn thiếu')),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  tr('Còn thiếu: ${_missingKinds.map((k) => PosQuoteDocument.kindLabel(k).toLowerCase()).join(', ')}'),
                                  style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      PosQuoteContactRow(
                        phone: q.customerPhone,
                        onCare: () => _careKey.currentState?.open(),
                      ),
                      const SizedBox(height: 14),
                      // Tiến độ HĐ, đợt thanh toán, thu cọc / thu các đợt → phiếu thu quỹ (gói có «Hợp đồng»).
                      if (canUsePosContracts(context)) ...[
                        PosContractPaymentPanel(
                          quoteId: q.id,
                          onChanged: _reloadQuiet,
                        ),
                        const SizedBox(height: 14),
                      ],
                      _sectionHead('Hồ sơ liên quan', Icons.folder_open_outlined, _createMenu()),
                      _docTile(
                        PosQuoteDocument(
                          id: q.id,
                          kind: 'Quote',
                          docNo: q.quoteNo,
                          title: 'Bảng báo giá',
                          htmlContent: '',
                        ),
                      ),
                      if (contract != null) _docTile(contract),
                      for (final d in _advances) _docTile(d),
                      for (final d in _handovers) _docTile(d),
                      for (final d in _acceptances) _docTile(d),
                      const SizedBox(height: 14),
                      PosQuoteCareCard(
                        key: _careKey,
                        quoteId: q.id,
                        quoteNo: q.quoteNo,
                        customerName: q.customerName,
                        customerPhone: q.customerPhone,
                      ),
                    ],
                  ),
                ),
    );
  }

  /// Loại chứng từ của trọn bộ hồ sơ chưa lập.
  List<String> get _missingKinds {
    final have = _docs.map((d) => d.kind).toSet();
    return [for (final k in posQuotePackageKinds) if (!have.contains(k)) k];
  }

  Widget _sectionHead(String title, IconData icon, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: PosTheme.kiotBlue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr(title),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  /// «+ Lập chứng từ ▾» — một nút thay 3 nút «+ Đề nghị TT / + Bàn giao / + Nghiệm thu»; loại đã có đánh dấu ✓
  /// (lập thêm vẫn được, vd đề nghị thanh toán đợt 2).
  Widget _createMenu() {
    final have = <String, int>{};
    for (final d in _docs) {
      have[d.kind] = (have[d.kind] ?? 0) + 1;
    }
    return MenuAnchor(
      menuChildren: [
        for (final (kind, icon) in const [
          ('PaymentRequest', Icons.payments_outlined),
          ('Handover', Icons.local_shipping_outlined),
          ('Acceptance', Icons.fact_check_outlined),
        ])
          MenuItemButton(
            leadingIcon: Icon(icon, size: 18),
            trailingIcon: (have[kind] ?? 0) > 0
                ? const Icon(Icons.check_circle, size: 16, color: SboxColors.success)
                : null,
            onPressed: _busy ? null : () => _create(kind),
            child: Text(tr(PosQuoteDocument.kindLabel(kind))),
          ),
      ],
      builder: (context, controller, _) => TextButton.icon(
        onPressed: _busy ? null : () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.add, size: 18),
        label: Text(tr('Lập chứng từ')),
      ),
    );
  }

  /// Sửa riêng toàn bộ nội dung chứng từ (số liệu tự cập nhật theo báo giá).
  Future<void> _editContent(PosQuoteDocument d) async {
    final q = _quote;
    if (q == null || d.id.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PosQuoteDocumentTemplateScreen(quoteId: q.id, document: d)),
    );
    if (changed == true) await _load();
  }

  Future<void> _editWording(PosQuoteDocument d) async {
    final q = _quote;
    if (q == null) return;
    var doc = d;
    PosQuoteDocument? match;
    for (final x in q.documents) {
      if (x.id == d.id) {
        match = x;
        break;
      }
    }
    if (match == null && d.kind == 'Quote') {
      for (final x in q.documents) {
        if (x.kind == 'Quote') {
          match = x;
          break;
        }
      }
    }
    if (match != null) {
      doc = match;
    } else if (d.kind == 'Quote') {
      final res = await _api.createPosQuoteDocument(
        q.id,
        'Quote',
        includeImages: q.includeImages,
      );
      if (!mounted) return;
      if (res['isSuccess'] != true || res['data'] is! Map) {
        NotificationOverlayManager().showError(
          title: 'Chưa mở được',
          message: res['message']?.toString() ?? tr('Chưa có phiếu để sửa'),
        );
        return;
      }
      doc = PosQuoteDocument.fromJson(
          Map<String, dynamic>.from(res['data'] as Map));
    }
    if (doc.htmlContent.trim().isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PosQuoteDocumentWordingScreen(
          quoteId: q.id,
          document: doc,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Widget _docBadge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  /// «⋮» của một chứng từ: 3 mục có chữ (trước ~20 mục không tên nhóm, lặp cả gọi khách / CSKH ở mọi chứng từ —
  /// liên hệ khách giờ ở hàng Gọi / Zalo / Chăm sóc đầu trang).
  Future<void> _docAction(PosQuoteDocument d, String v) async {
    final q = _quote;
    if (q == null) return;
    final label = d.title.isEmpty ? PosQuoteDocument.kindLabel(d.kind) : d.title;
    if (v == 'send') {
      final action = await showPosDocSendSheet(context, title: 'Gửi / in chứng từ', subtitle: '${d.docNo} · $label');
      if (action == null || !mounted) return;
      await PosBusy.run(
        context,
        () => PosQuoteExport.run(context, quote: q, action: action, documentType: d.kind, docId: d.id),
        label: 'Đang xử lý chứng từ…',
      );
      return;
    }
    if (v == 'note') {
      if (await editPosQuoteDocumentNote(context, quoteId: q.id, doc: d)) await _load();
      return;
    }
    final pick = await showPosQuoteActionSheet(
      context,
      title: 'Sửa nội dung chứng từ',
      subtitle: '${d.docNo} · $label',
      sections: [
        (
          'Nội dung',
          [
            const PosSheetAction('content', Icons.edit_note_outlined, 'Sửa riêng nội dung (số liệu tự cập nhật)',
                hint: 'Đổi lời văn / bố cục riêng chứng từ này; số tiền, hàng hóa vẫn theo báo giá.'),
            const PosSheetAction('wording', Icons.lock_outline, 'Chốt bản in & sửa chữ',
                hint: 'Giữ cố định bản in hiện tại rồi sửa từng chữ; số liệu không tự cập nhật nữa.'),
            const PosSheetAction('template', Icons.view_quilt_outlined, 'Chọn mẫu cho chứng từ này',
                hint: 'Dùng mẫu in khác cho riêng chứng từ này.'),
          ]
        ),
        (
          'Phiên bản',
          [
            const PosSheetAction('history', Icons.history, 'Lịch sử nội dung', hint: 'Xem / khôi phục các lần sửa trước.'),
            if (d.isCustomWording)
              const PosSheetAction('restore', Icons.restart_alt, 'Khôi phục theo mẫu',
                  hint: 'Bỏ bản đã chốt, dựng lại theo mẫu và số liệu mới nhất.'),
          ]
        ),
      ],
    );
    if (pick == null || !mounted) return;
    await PosBusy.run(context, () async {
      switch (pick) {
        case 'content':
          await _editContent(d);
        case 'wording':
          await _editWording(d);
        case 'template':
          if (await pickPosQuoteDocumentTemplate(context, quoteId: q.id, doc: d, api: _api)) await _load();
        case 'history':
          if (await showPosQuoteDocumentHistory(context, quoteId: q.id, doc: d, api: _api)) await _load();
        case 'restore':
          if (await restorePosQuoteDocumentToTemplate(context, quoteId: q.id, doc: d, api: _api)) await _load();
      }
    }, label: 'Đang xử lý chứng từ…');
  }

  Widget _docTile(PosQuoteDocument d) {
    final note = (d.note ?? '').trim();
    final isQuote = d.kind == 'Quote';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          title: Text(
            '${d.docNo} · ${d.title}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text([
                PosQuoteDocument.kindLabel(d.kind),
                if (d.issuedAt != null)
                  DateFormat('dd/MM/yyyy HH:mm').format(d.issuedAt!.toLocal()),
              ].join(' · ')),
              // Ghi chú in trên chứng từ — trước đây chỉ thấy khi in ra.
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(tr('Ghi chú in: $note'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: SboxColors.slate600, fontStyle: FontStyle.italic)),
                ),
              if (d.isCustomWording || d.printTemplateId != null || d.hasCustomTemplate)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      if (d.isCustomWording) _docBadge(tr('Bản chốt đã sửa chữ'), Colors.orange.shade800),
                      if (d.hasCustomTemplate && !d.isCustomWording) _docBadge(tr('Nội dung riêng'), (SboxColors.isBoss ? SboxColors.brandSwatch : SboxColors.okSwatch).shade700),
                      if (d.printTemplateId != null && !d.hasCustomTemplate) _docBadge(tr('Mẫu chọn riêng'), (SboxColors.posApp ? SboxColors.brand600 : SboxColors.isBoss ? SboxColors.brandSwatch : Colors.indigo)),
                    ],
                  ),
                ),
            ],
          ),
          onTap: () => PosBusy.run(context, () => _openDoc(d),
              label: 'Đang mở ${PosQuoteDocument.kindLabel(d.kind).toLowerCase()}…'),
          trailing: PopupMenuButton<String>(
            tooltip: tr('Thao tác'),
            onSelected: (v) => _docAction(d, v),
            itemBuilder: (_) => [
              _docMenu('send', Icons.send_outlined, 'Gửi khách / In…'),
              _docMenu('edit', Icons.edit_note_outlined, 'Sửa nội dung…'),
              if (!isQuote) _docMenu('note', Icons.sticky_note_2_outlined, 'Ghi chú in trên chứng từ'),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _docMenu(String v, IconData icon, String label) => PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(icon, size: 18, color: SboxColors.slate600),
          const SizedBox(width: 10),
          Text(tr(label)),
        ]),
      );
}
