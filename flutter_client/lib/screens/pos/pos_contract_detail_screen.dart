import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../utils/pos_html_print.dart';
import '../../utils/pos_quote_commercial.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';

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

  Future<void> _openDoc(PosQuoteDocument d) async {
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
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                contract?.title ?? tr('Hợp đồng'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  q.quoteNo,
                                  q.customerName ?? '',
                                  '${_money.format(q.total)} đ',
                                  PosQuote.stageLabel(q.commercialStage),
                                ].where((e) => e.isNotEmpty).join(' · '),
                                style: TextStyle(
                                    color: Colors.grey.shade700, fontSize: 13),
                              ),
                              if (q.depositAmount > 0) ...[
                                const SizedBox(height: 8),
                                Text(
                                  tr(
                                      'Cọc: ${_money.format(q.depositAmount)} đ${q.depositPercent != null ? ' (${q.depositPercent!.round()}%)' : ''}'),
                                  style: const TextStyle(
                                      color: PosTheme.kiotBlue,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
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
                      const SizedBox(height: 16),
                      _sectionHead(
                        'Tạm ứng',
                        Icons.payments_outlined,
                        'Tạo tạm ứng',
                        () => _create('PaymentRequest'),
                      ),
                      if (_advances.isEmpty)
                        _emptyHint('Chưa có phiếu tạm ứng / đề nghị thanh toán')
                      else
                        for (final d in _advances) _docTile(d),
                      const SizedBox(height: 16),
                      _sectionHead(
                        'Biên bản bàn giao',
                        Icons.handshake_outlined,
                        'Tạo bàn giao',
                        () => _create('Handover'),
                      ),
                      if (_handovers.isEmpty)
                        _emptyHint('Chưa có biên bản bàn giao')
                      else
                        for (final d in _handovers) _docTile(d),
                      const SizedBox(height: 16),
                      _sectionHead(
                        'Biên bản nghiệm thu',
                        Icons.fact_check_outlined,
                        'Tạo nghiệm thu',
                        () => _create('Acceptance'),
                      ),
                      if (_acceptances.isEmpty)
                        _emptyHint('Chưa có biên bản nghiệm thu')
                      else
                        for (final d in _acceptances) _docTile(d),
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
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        tr(text),
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
      ),
    );
  }

  Widget _docTile(PosQuoteDocument d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          title: Text(
            '${d.docNo} · ${d.title}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          subtitle: Text([
            PosQuoteDocument.kindLabel(d.kind),
            if (d.issuedAt != null)
              DateFormat('dd/MM/yyyy HH:mm').format(d.issuedAt!.toLocal()),
          ].join(' · ')),
          trailing: const Icon(Icons.print_outlined),
          onTap: () => _openDoc(d),
        ),
      ),
    );
  }
}
