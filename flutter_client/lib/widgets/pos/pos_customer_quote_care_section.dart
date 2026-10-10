import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../utils/api_datetime.dart';
import 'pos_quote_care_sheet.dart';

/// Hồ sơ khách hàng: các báo giá của khách + lịch sử chăm sóc gần nhất (mọi báo giá).
/// Nhấn báo giá mở lịch chăm sóc của báo giá đó để ghi tiếp.
class PosCustomerQuoteCareSection extends StatefulWidget {
  const PosCustomerQuoteCareSection({super.key, this.customerId, this.phone, this.customerName});

  final String? customerId;
  final String? phone;
  final String? customerName;

  @override
  State<PosCustomerQuoteCareSection> createState() => _PosCustomerQuoteCareSectionState();
}

class _PosCustomerQuoteCareSectionState extends State<PosCustomerQuoteCareSection> {
  final _money = NumberFormat('#,###', 'vi_VN');
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _quotes = const [];
  List<Map<String, dynamic>> _acts = const [];
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ApiService().getPosCustomerQuoteCare(customerId: widget.customerId, phone: widget.phone);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? tr('Không tải được dữ liệu');
      });
      return;
    }
    final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    List<Map<String, dynamic>> list(String k) =>
        ((data[k] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    setState(() {
      _loading = false;
      _quotes = list('quotes');
      _acts = list('activities');
    });
  }

  Future<void> _openCare(Map<String, dynamic> q) async {
    await showPosQuoteCareSheet(
      context,
      quoteId: '${q['id']}',
      quoteNo: '${q['quoteNo'] ?? ''}',
      customerName: widget.customerName,
      customerPhone: widget.phone,
    );
    if (mounted) await _load();
  }

  String _date(dynamic v) {
    final d = v is DateTime ? v : parseApiUtcDateTime(v);
    return d == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    if (_quotes.isEmpty) {
      return Padding(padding: const EdgeInsets.all(12), child: Text(tr('Khách chưa có báo giá nào')));
    }
    final acts = _showAll ? _acts : _acts.take(5).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final q in _quotes)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.request_quote_outlined, size: 20),
          title: Text('${q['quoteNo'] ?? ''} · ${q['statusText'] ?? q['status'] ?? ''}'),
          subtitle: Text([
            '${_money.format((q['total'] as num?) ?? 0)} đ',
            _date(q['createdAt']),
            if (q['potentialScore'] != null) 'tiềm năng ${q['potentialScore']}/10',
          ].where((e) => e.isNotEmpty).join(' · ')),
          trailing: const Icon(Icons.support_agent, size: 18),
          onTap: () => _openCare(q),
        ),
      if (acts.isNotEmpty) ...[
        const Divider(),
        Text(tr('Lịch sử chăm sóc'), style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final e in acts)
          Builder(builder: (_) {
            final a = PosQuoteActivity.fromJson((e['activity'] as Map).cast<String, dynamic>());
            final by = (a.employeeName ?? a.createdBy ?? '').trim();
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text([
                '${e['quoteNo'] ?? ''}',
                PosQuoteActivity.kindLabel(a.kind),
                _date(a.createdAt),
              ].where((x) => x.isNotEmpty).join(' · ')),
              subtitle: Text([
                a.displayContent.trim(),
                if (a.score != null) 'Điểm ${a.score}/10',
                if (a.nextFollowUpAt != null) 'Hẹn ${DateFormat('dd/MM HH:mm').format(a.nextFollowUpAt!.toLocal())}',
                if (by.isNotEmpty) by,
              ].where((x) => x.isNotEmpty).join('\n')),
            );
          }),
        if (_acts.length > 5 && !_showAll)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => setState(() => _showAll = true), child: Text('${tr('Xem tất cả')} (${_acts.length})')),
          ),
      ],
    ]);
  }
}
