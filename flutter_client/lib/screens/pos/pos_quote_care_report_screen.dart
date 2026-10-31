import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/pos/pos_quote_care_card.dart';
import '../../widgets/pos/pos_quote_care_sheet.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_quote_care_board_screen.dart' show PosQuoteCareStaffScreen;

/// Báo cáo chăm sóc khách theo khoảng ngày: tổng số lần, theo loại, theo ngày, theo người ghi,
/// lịch hẹn đã giữ / quá hạn, và nhật ký mọi lần chăm sóc (bấm để mở dòng thời gian của báo giá).
class PosQuoteCareReportScreen extends StatefulWidget {
  const PosQuoteCareReportScreen({super.key});

  @override
  State<PosQuoteCareReportScreen> createState() => _PosQuoteCareReportScreenState();
}

class _LogItem {
  _LogItem(Map<String, dynamic> j)
      : activity = PosQuoteActivity.fromJson(Map<String, dynamic>.from(j['activity'] as Map)),
        quoteId = '${j['quoteId'] ?? ''}',
        quoteNo = '${j['quoteNo'] ?? ''}',
        customerName = j['customerName'] as String?,
        customerPhone = j['customerPhone'] as String?;

  final PosQuoteActivity activity;
  final String quoteId;
  final String quoteNo;
  final String? customerName;
  final String? customerPhone;
}

class _PosQuoteCareReportScreenState extends State<PosQuoteCareReportScreen> {
  /// 7 / 30 / 90 ngày gần nhất; 0 = tháng này.
  int _days = 30;
  String? _kind;
  String? _employeeId;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _byDay = const [];
  List<Map<String, dynamic>> _byStaff = const [];
  List<_LogItem> _items = const [];
  bool _truncated = false;

  /// Danh sách người ghi lấy từ lần tải không lọc người — lọc theo một người vẫn chọn được người khác.
  List<Map<String, dynamic>> _staffOptions = const [];

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
    final now = DateTime.now();
    final res = await ApiService().getPosQuoteCareLog(
      days: _days == 0 ? 31 : _days,
      from: _days == 0 ? DateTime(now.year, now.month, 1) : null,
      to: _days == 0 ? now : null,
      employeeId: _employeeId,
      kind: _kind,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? tr('Không tải được dữ liệu');
      });
      return;
    }
    final d = Map<String, dynamic>.from(res['data'] as Map);
    List<Map<String, dynamic>> rows(String k) =>
        ((d[k] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    setState(() {
      _loading = false;
      _summary = Map<String, dynamic>.from((d['summary'] as Map?) ?? const {});
      _byDay = rows('byDay');
      _byStaff = rows('byStaff');
      _items = [
        for (final e in rows('items'))
          if (e['activity'] is Map) _LogItem(e),
      ];
      _truncated = d['truncated'] == true;
      if (_employeeId == null) _staffOptions = _byStaff.where((r) => r['employeeId'] != null).toList();
    });
  }

  int _n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;

  Future<void> _openQuote(_LogItem i) async {
    await showPosQuoteCareSheet(
      context,
      quoteId: i.quoteId,
      quoteNo: i.quoteNo,
      customerName: i.customerName,
      customerPhone: i.customerPhone,
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Báo cáo chăm sóc khách')),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const PosQuoteCareStaffScreen())),
            icon: const Icon(Icons.groups_outlined, size: 18),
            label: Text(tr('Theo nhân viên')),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
              children: [
                _filters(),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(_error!, style: const TextStyle(color: SboxColors.danger))),
                  )
                else ...[
                  _summaryTiles(),
                  const SizedBox(height: 12),
                  _dayChart(),
                  if (_byStaff.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _staffCard(),
                  ],
                  const SizedBox(height: 12),
                  _logCard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required String title, Widget? trailing, required Widget child}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(tr(title), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _filters() {
    Widget kindChip(String? k, String label) => ChoiceChip(
          label: Text(tr(label)),
          selected: _kind == k,
          visualDensity: VisualDensity.compact,
          onSelected: (_) {
            setState(() => _kind = k);
            _load();
          },
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: 7, label: Text(tr('7 ngày'))),
          ButtonSegment(value: 30, label: Text(tr('30 ngày'))),
          ButtonSegment(value: 90, label: Text(tr('90 ngày'))),
          ButtonSegment(value: 0, label: Text(tr('Tháng này'))),
        ],
        selected: {_days},
        onSelectionChanged: (v) {
          setState(() => _days = v.first);
          _load();
        },
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        kindChip(null, 'Tất cả'),
        kindChip('Call', 'Gọi điện'),
        kindChip('Meeting', 'Gặp khách'),
        kindChip('Note', 'Ghi chú'),
        kindChip('FollowUp', 'Hẹn chăm sóc'),
        if (_staffOptions.length > 1)
          DropdownButton<String?>(
            value: _employeeId,
            hint: Text(tr('Nhân viên: Tất cả')),
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(tr('Nhân viên: Tất cả'))),
              for (final r in _staffOptions)
                DropdownMenuItem<String?>(value: '${r['employeeId']}', child: Text('${r['name'] ?? ''}')),
            ],
            onChanged: (v) {
              setState(() => _employeeId = v);
              _load();
            },
          ),
      ]),
    ]);
  }

  Widget _summaryTiles() {
    final byKind = Map<String, dynamic>.from((_summary['byKind'] as Map?) ?? const {});
    final fu = Map<String, dynamic>.from((_summary['followUps'] as Map?) ?? const {});
    final avg = (_summary['averageScore'] as num?)?.toDouble();
    Widget tile(String label, String value, {String? sub, IconData? icon, Color? iconColor}) => Container(
          width: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SboxColors.slate200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 16, color: iconColor ?? PosTheme.kiotBlue), const SizedBox(width: 6)],
              Expanded(child: Text(tr(label), style: const TextStyle(fontSize: 12, color: SboxColors.slate600))),
            ]),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
            if (sub != null) Text(tr(sub), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
          ]),
        );
    return Wrap(spacing: 10, runSpacing: 10, children: [
      tile('Lần chăm sóc', '${_n(_summary, 'total')}', icon: Icons.event_note_outlined),
      tile('Khách được chăm sóc', '${_n(_summary, 'customers')}',
          sub: '${_n(_summary, 'quotes')} báo giá', icon: Icons.people_alt_outlined),
      tile('Gọi điện', '${_n(byKind, 'Call')}', icon: posCareKindIcon('Call'), iconColor: posCareKindColor('Call')),
      tile('Gặp khách', '${_n(byKind, 'Meeting')}',
          icon: posCareKindIcon('Meeting'), iconColor: posCareKindColor('Meeting')),
      tile('Ghi chú', '${_n(byKind, 'Note')}', icon: posCareKindIcon('Note'), iconColor: posCareKindColor('Note')),
      tile('Lịch hẹn', '${_n(fu, 'set')}',
          sub: 'Đã giữ ${_n(fu, 'done')} · quá hạn ${_n(fu, 'overdue')} · sắp tới ${_n(fu, 'upcoming')}',
          icon: posCareKindIcon('FollowUp'),
          iconColor: posCareKindColor('FollowUp')),
      tile('Điểm tiềm năng TB', avg == null ? '—' : '${avg.toStringAsFixed(1)}/10', icon: Icons.speed),
    ]);
  }

  /// Số lần chăm sóc mỗi ngày — một chuỗi, cột mảnh bo đầu, rê / chạm từng cột xem số.
  Widget _dayChart() {
    final maxCount = _byDay.fold<int>(0, (a, r) => _n(r, 'count') > a ? _n(r, 'count') : a);
    final df = DateFormat('dd/MM');
    DateTime? day(Map<String, dynamic> r) => DateTime.tryParse('${r['date']}');
    return _card(
      title: 'Số lần chăm sóc theo ngày',
      child: _byDay.isEmpty || maxCount == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text(tr('Chưa có lần chăm sóc nào trong khoảng này'),
                      style: const TextStyle(color: SboxColors.slate500))),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: 140,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final r in _byDay)
                    Expanded(
                      child: Tooltip(
                        message: '${day(r) == null ? r['date'] : df.format(day(r)!)} · '
                            '${tr('${_n(r, 'count')} lần chăm sóc')}\n'
                            '${tr('Gọi ${_n(r, 'call')} · gặp ${_n(r, 'meeting')} · ghi chú ${_n(r, 'note')} · hẹn ${_n(r, 'followUp')}')}',
                        child: Container(
                          color: Colors.transparent, // vùng rê chuột cao cả cột, dễ trúng hơn cột thấp
                          alignment: Alignment.bottomCenter,
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Container(
                            height: _n(r, 'count') == 0 ? 0 : 4 + 132 * _n(r, 'count') / maxCount,
                            constraints: const BoxConstraints(maxWidth: 18),
                            decoration: const BoxDecoration(
                              color: PosTheme.kiotBlue,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              Container(height: 1, color: SboxColors.slate200),
              const SizedBox(height: 4),
              Row(children: [
                Text(day(_byDay.first) == null ? '' : df.format(day(_byDay.first)!),
                    style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
                const Spacer(),
                Text(tr('Cao nhất $maxCount lần/ngày'), style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
                const Spacer(),
                Text(day(_byDay.last) == null ? '' : df.format(day(_byDay.last)!),
                    style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
              ]),
            ]),
    );
  }

  Widget _staffCard() {
    final top = _byStaff.fold<int>(0, (a, r) => _n(r, 'count') > a ? _n(r, 'count') : a);
    return _card(
      title: 'Theo người chăm sóc',
      child: Column(children: [
        for (final r in _byStaff)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(
                width: 170,
                child: Text('${r['name'] ?? tr('Chưa rõ người ghi')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 10,
                      width: top == 0 ? 0 : c.maxWidth * _n(r, 'count') / top,
                      decoration: BoxDecoration(
                        color: PosTheme.kiotBlue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 210,
                child: Text(
                  tr('${_n(r, 'count')} lần · gọi ${_n(r, 'calls')} · gặp ${_n(r, 'meetings')} · ${_n(r, 'quotes')} BG'),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate700),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _logCard() {
    return _card(
      title: _items.isEmpty ? 'Nhật ký chăm sóc' : 'Nhật ký chăm sóc (${_items.length}${_truncated ? '+' : ''})',
      child: _items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(tr('Chưa có lần chăm sóc nào'), style: const TextStyle(color: SboxColors.slate500)),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < _items.length; i++)
                InkWell(
                  onTap: () => _openQuote(_items[i]),
                  child: PosCareTimelineTile(
                    activity: _items[i].activity,
                    quoteNo: [
                      _items[i].quoteNo,
                      if ((_items[i].customerName ?? '').trim().isNotEmpty) _items[i].customerName!.trim(),
                    ].join(' · '),
                    isLast: i == _items.length - 1,
                    maxLines: 3,
                  ),
                ),
              if (_truncated)
                Text(tr('Chỉ hiện 500 lần mới nhất — thu hẹp khoảng ngày để xem hết.'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ]),
    );
  }
}
