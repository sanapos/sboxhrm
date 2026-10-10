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
import 'pos_quote_document_wording_screen.dart';
import '../../widgets/pos/pos_quote_document_tools.dart';
import '../../widgets/pos/pos_quote_care_sheet.dart';
import '../../widgets/pos/pos_contract_payment_panel.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_quote_detail_screen.dart' show PosQuoteFlow, PosQuoteProgress;

import '../../theme/sbox_tokens.dart';
/// Chi tiết hợp đồng: tạm ứng + biên bản nghiệm thu.
class PosContractDetailScreen extends StatefulWidget {
  const PosContractDetailScreen({super.key, required this.quoteId});

  final String quoteId;

  @override
  State<PosContractDetailScreen> createState() =>
      _PosContractDetailScreenState();
}

class _PosContractDetailScreenState extends State<PosContractDetailScreen> {
  final _api = ApiService();
  final _money = NumberFormat('#,##0', 'vi_VN');
  PosQuote? _quote;
  bool _loading = true;
  bool _busy = false;

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
  }

  /// Tải lại báo giá sau khi thu tiền / sửa đợt — không thay màn bằng vòng chờ.
  Future<void> _reloadQuiet() async {
    final res = await _api.getPosQuote(widget.quoteId);
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    setState(() => _quote = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map)));
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
    await showPosHtmlPrintDialog(context, title: d.title, htmlDocument: html);
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
        title: Text(contract?.docNo ?? tr('Hợp đồng')),
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
                                child: FilledButton.tonalIcon(
                                  onPressed: contract == null
                                      ? null
                                      : () => _openDoc(contract),
                                  icon: const Icon(Icons.description_outlined),
                                  label: Text(tr('Xem / in hợp đồng')),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _busy ? null : _createPackage,
                                  icon: const Icon(Icons.folder_copy_outlined),
                                  label: Text(tr('Tạo trọn bộ hồ sơ')),
                                ),
                              ),
                            ],
                          ),
                        ),
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
                      _sectionHead(
                        'Hồ sơ liên quan',
                        Icons.folder_open_outlined,
                        'Báo giá',
                        () => printPosQuoteSlip(
                          context,
                          quoteId: q.id,
                          quote: q,
                        ),
                      ),
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(tr('Đề nghị TT')),
                            onPressed: _busy ? null : () => _create('PaymentRequest'),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(tr('Bàn giao')),
                            onPressed: _busy ? null : () => _create('Handover'),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(tr('Nghiệm thu')),
                            onPressed: _busy ? null : () => _create('Acceptance'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionHead(
    String title,
    IconData icon,
    String action,
    VoidCallback onAdd,
  ) {
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
          TextButton.icon(
            onPressed: _busy ? null : onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text(tr(action)),
          ),
        ],
      ),
    );
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

  Widget _docTile(PosQuoteDocument d) {
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
              if (d.isCustomWording || d.printTemplateId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      if (d.isCustomWording) _docBadge(tr('Đã sửa lời riêng'), Colors.orange.shade800),
                      if (d.printTemplateId != null) _docBadge(tr('Mẫu riêng'), Colors.indigo),
                    ],
                  ),
                ),
            ],
          ),
          onTap: () => _openDoc(d),
          trailing: PopupMenuButton<String>(
            tooltip: tr('Thao tác'),
            onSelected: (v) async {
              final q = _quote;
              if (q == null) return;
              if (v == 'wording') {
                await _editWording(d);
                return;
              }
              if (v == 'template') {
                if (await pickPosQuoteDocumentTemplate(context, quoteId: q.id, doc: d, api: _api)) await _load();
                return;
              }
              if (v == 'history') {
                if (await showPosQuoteDocumentHistory(context, quoteId: q.id, doc: d, api: _api)) await _load();
                return;
              }
              if (v == 'restore') {
                if (await restorePosQuoteDocumentToTemplate(context, quoteId: q.id, doc: d, api: _api)) await _load();
                return;
              }
              if (v == 'open') {
                await _openDoc(d);
                return;
              }
              await PosQuoteExport.run(
                context,
                quote: q,
                action: v,
                documentType: d.kind,
                docId: d.id,
              );
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'wording', child: Text(tr('Sửa lời riêng'))),
              PopupMenuItem(value: 'template', child: Text(tr('Chọn mẫu cho chứng từ này'))),
              if (d.isCustomWording)
                PopupMenuItem(value: 'restore', child: Text(tr('Khôi phục theo mẫu'))),
              PopupMenuItem(value: 'history', child: Text(tr('Lịch sử nội dung'))),
              PopupMenuItem(value: 'open', child: Text(tr('Xem / in'))),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'print', child: Text(tr('In'))),
              PopupMenuItem(value: 'excel', child: Text(tr('Xuất Excel'))),
              PopupMenuItem(value: 'word', child: Text(tr('Xuất Word'))),
              PopupMenuItem(value: 'pdf', child: Text(tr('Xuất PDF'))),
              PopupMenuItem(value: 'png', child: Text(tr('Xuất ảnh PNG'))),
              PopupMenuItem(value: 'email', child: Text(tr('Gửi Email'))),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'call', child: Text(tr('Gọi khách'))),
              PopupMenuItem(value: 'zaloCall', child: Text(tr('Gọi Zalo'))),
              PopupMenuItem(value: 'facebookLink', child: Text(tr('Link Facebook'))),
              PopupMenuItem(value: 'zalo', child: Text(tr('Chia sẻ Zalo'))),
              PopupMenuItem(value: 'facebook', child: Text(tr('Chia sẻ Facebook'))),
              PopupMenuItem(value: 'care', child: Text(tr('Lịch CSKH'))),
            ],
          ),
        ),
      ),
    );
  }
}
