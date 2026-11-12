import 'package:flutter/material.dart';
import '../../utils/api_datetime.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../widgets/pos/pos_quote_care_sheet.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/reports/report_drill_sheet.dart';
import 'pos_quote_care_report_screen.dart';

import '../../theme/sbox_tokens.dart';
/// Theo dõi chăm sóc khách tiềm năng theo báo giá: điểm thang 10 (nóng 8–10, ấm 5–7, lạnh 0–4),
/// xu hướng so với lần chấm trước, lịch hẹn quá hạn / hôm nay, khách lâu chưa liên hệ.
class PosQuoteCareBoardScreen extends StatefulWidget {
  const PosQuoteCareBoardScreen({super.key});

  @override
  State<PosQuoteCareBoardScreen> createState() =>
      _PosQuoteCareBoardScreenState();
}

class _CareItem {
  _CareItem(Map<String, dynamic> j)
      : quoteId = '${j['quoteId']}',
        quoteNo = '${j['quoteNo'] ?? ''}',
        customerName = j['customerName'] as String?,
        customerPhone = j['customerPhone'] as String?,
        total = (j['total'] as num?)?.toDouble() ?? 0,
        status = '${j['status'] ?? ''}',
        score = (j['score'] as num?)?.toInt(),
        previousScore = (j['previousScore'] as num?)?.toInt(),
        trend = (j['trend'] as num?)?.toInt() ?? 0,
        band = '${j['band'] ?? 'none'}',
        lastContactAt = parseApiUtcDateTime('${j['lastContactAt'] ?? ''}'),
        lastContactKind = j['lastContactKind'] as String?,
        lastContent = j['lastContent'] as String?,
        daysSinceContact = (j['daysSinceContact'] as num?)?.toInt(),
        stale = j['stale'] == true,
        nextFollowUpAt = parseApiUtcDateTime('${j['nextFollowUpAt'] ?? ''}'),
        followUp = '${j['followUp'] ?? 'none'}',
        contactCount = (j['contactCount'] as num?)?.toInt() ?? 0,
        otherQuotes = (j['otherQuotes'] as num?)?.toInt() ?? 0,
        ownerName = j['ownerName'] as String?,
        history = ((j['scoreHistory'] as List?) ?? const [])
            .map((e) => ((e as Map)['score'] as num).toInt())
            .toList();

  final String quoteId;
  final String quoteNo;
  final String? customerName;
  final String? customerPhone;
  final double total;
  final String status;
  final int? score;
  final int? previousScore;
  final int trend;
  final String band;
  final DateTime? lastContactAt;
  final String? lastContactKind;
  final String? lastContent;
  final int? daysSinceContact;
  final bool stale;
  final DateTime? nextFollowUpAt;
  final String followUp;
  final int contactCount;

  /// Số báo giá khác (đang theo dõi) của cùng khách — liên hệ ở báo giá nào cũng tính cho khách.
  final int otherQuotes;
  final String? ownerName;
  final List<int> history;
}

Color careBandColor(String band) => switch (band) {
      'hot' => SboxColors.danger,
      'warm' => const Color(0xFFEF6C00),
      'cold' => SboxColors.brand600,
      _ => SboxColors.slate500,
    };

String careBandLabel(String band) => switch (band) {
      'hot' => 'Nóng',
      'warm' => 'Ấm',
      'cold' => 'Lạnh',
      _ => 'Chưa chấm',
    };

class _PosQuoteCareBoardScreenState extends State<PosQuoteCareBoardScreen> {
  final _money = NumberFormat('#,###', 'vi_VN');
  final _search = TextEditingController();
  bool _loading = true;
  /// pipeline = đang chào giá, aftersale = đã chốt (chăm sóc sau bán), all = tất cả.
  String _scope = 'pipeline';
  String? _error;
  String _filter = 'all';
  Map<String, dynamic> _summary = const {};
  List<_CareItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ApiService().getPosQuoteCareOverview(scope: _scope);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? tr('Không tải được dữ liệu');
      });
      return;
    }
    final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    setState(() {
      _loading = false;
      _summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
      _items = ((data['items'] as List?) ?? const [])
          .map((e) => _CareItem((e as Map).cast<String, dynamic>()))
          .toList();
    });
  }

  List<_CareItem> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _items.where((i) {
      final ok = switch (_filter) {
        'hot' || 'warm' || 'cold' || 'none' => i.band == _filter,
        'overdue' || 'today' => i.followUp == _filter,
        'stale' => i.stale,
        _ => true,
      };
      if (!ok) return false;
      if (q.isEmpty) return true;
      return i.quoteNo.toLowerCase().contains(q) ||
          (i.customerName ?? '').toLowerCase().contains(q) ||
          (i.customerPhone ?? '').contains(q);
    }).toList();
  }

  Future<void> _open(_CareItem i) async {
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
    final items = _visible;
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Theo dõi chăm sóc khách')),
        actions: sboxBarActions([
          // Nút có chữ (trước: biểu tượng nhóm người không nhãn — không ai biết có báo cáo).
          TextButton.icon(
            icon: const Icon(Icons.bar_chart_outlined, size: 18),
            label: Text(tr('Báo cáo')),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PosQuoteCareReportScreen())),
          ),
          TextButton.icon(
            icon: const Icon(Icons.groups_outlined, size: 18),
            label: Text(tr('Theo nhân viên')),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PosQuoteCareStaffScreen())),
          ),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _summaryCard(),
            const SizedBox(height: 10),
            _filters(),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Tìm số báo giá, tên, SĐT khách'),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'pipeline', label: Text(tr('Đang chào giá'))),
                ButtonSegment(value: 'aftersale', label: Text(tr('Sau bán'))),
                ButtonSegment(value: 'all', label: Text(tr('Tất cả'))),
              ],
              selected: {_scope},
              onSelectionChanged: (v) {
                setState(() => _scope = v.first);
                _load();
              },
            ),
            const SizedBox(height: 4),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red))),
              )
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                    child: Text(tr('Không có khách nào trong mục này'))),
              )
            else
              for (final i in items) ...[
                _itemCard(i),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  int _n(String k) => (_summary[k] as num?)?.toInt() ?? 0;

  /// Ô tổng → các báo giá đang theo (đã tải trên màn) tạo ra số đó; bấm dòng mở sổ chăm sóc.
  void _drill(String title, List<_CareItem> list,
      {String Function(_CareItem i)? trailing, String? note, String? total}) {
    showReportDrillSheet(
      context,
      title: title,
      note: note,
      total: total,
      emptyText: 'Không có báo giá',
      rows: [
        for (final i in list)
          ReportDrillRow(
            title: '${i.quoteNo} · ${i.customerName ?? 'Khách'}',
            subtitle: [
              careBandLabel(i.band),
              if (i.score != null) 'điểm ${i.score}/10',
              '${_money.format(i.total)} đ',
              if ((i.ownerName ?? '').isNotEmpty) i.ownerName!,
            ].join(' · '),
            trailing: trailing?.call(i),
            trailingColor: careBandColor(i.band),
            icon: Icons.request_quote_outlined,
            onTap: () => _open(i),
          ),
      ],
    );
  }

  void _drillAvg() {
    final scored = _items.where((i) => i.score != null).toList()
      ..sort((a, b) => b.score!.compareTo(a.score!));
    final sum = scored.fold<int>(0, (s, i) => s + i.score!);
    final avg = (_summary['averageScore'] as num?)?.toDouble();
    _drill('Điểm TB', scored,
        trailing: (i) => '${i.score}/10',
        note: 'Điểm TB = tổng điểm ÷ số báo giá đã chấm = $sum ÷ ${scored.length}'
            '${avg == null ? '' : ' = ${avg.toStringAsFixed(1)}/10'}. Báo giá chưa chấm điểm không tính.');
  }

  void _drillPipeline() {
    final list = [..._items]..sort((a, b) => b.total.compareTo(a.total));
    _drill('Giá trị báo giá', list,
        trailing: (i) => '${_money.format(i.total)} đ',
        total: 'Tổng ${_money.format((_summary['pipelineValue'] as num?) ?? 0)} đ');
  }

  void _drillWeighted() {
    final list = _items.where((i) => i.score != null).toList()
      ..sort((a, b) => (b.total * b.score!).compareTo(a.total * a.score!));
    _drill('Kỳ vọng (× điểm/10)', list,
        trailing: (i) => '${_money.format(i.total * i.score! / 10)} đ',
        total: 'Tổng ${_money.format((_summary['weightedValue'] as num?) ?? 0)} đ',
        note: 'Kỳ vọng = Σ (giá trị báo giá × điểm ÷ 10). Báo giá chưa chấm điểm không tính.');
  }

  Widget _summaryCard() {
    final avg = (_summary['averageScore'] as num?)?.toDouble();
    final weighted = (_summary['weightedValue'] as num?)?.toDouble() ?? 0;
    final pipeline = (_summary['pipelineValue'] as num?)?.toDouble() ?? 0;
    final total = _n('total');
    Widget seg(String band, int n) => Expanded(
          flex: n == 0 ? 0 : n,
          child: n == 0
              ? const SizedBox.shrink()
              : Container(height: 10, color: careBandColor(band)),
        );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _metric(
                      tr('Điểm TB'),
                      avg == null ? '—' : '${avg.toStringAsFixed(1)}/10',
                      Icons.speed,
                      onTap: _drillAvg),
                ),
                Expanded(
                  // Danh sách ngay bên dưới chính là các khách đang theo → bỏ lọc / tìm để hiện đủ.
                  child: _metric(tr('Khách đang theo'), '$total',
                      Icons.people_alt_outlined, onTap: () {
                    _search.clear();
                    setState(() => _filter = 'all');
                  }),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metric(tr('Giá trị báo giá'),
                      '${_money.format(pipeline)} đ', Icons.request_quote,
                      onTap: _drillPipeline),
                ),
                Expanded(
                  child: _metric(tr('Kỳ vọng (× điểm/10)'),
                      '${_money.format(weighted)} đ', Icons.trending_up,
                      onTap: _drillWeighted),
                ),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Row(children: [
                  seg('hot', _n('hot')),
                  seg('warm', _n('warm')),
                  seg('cold', _n('cold')),
                  seg('none', _n('unscored')),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon, {VoidCallback? onTap}) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: PosTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 12, color: SboxColors.slate700)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ));

  Widget _filters() {
    Widget chip(String key, String label, int? n, Color color) {
      final selected = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => setState(() => _filter = selected ? 'all' : key),
          avatar: key == 'all'
              ? null
              : CircleAvatar(backgroundColor: color, radius: 6),
          label: Text(n == null ? tr(label) : '${tr(label)} $n'),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return Wrap(
      children: [
        chip('all', 'Tất cả', _n('total'), SboxColors.slate500),
        chip('overdue', 'Quá hạn hẹn', _n('overdue'), Colors.red.shade900),
        chip('today', 'Hẹn hôm nay', _n('dueToday'), Colors.amber.shade800),
        chip('stale', 'Lâu chưa liên hệ', _n('stale'), Colors.brown),
        chip('hot', 'Nóng 8–10', _n('hot'), careBandColor('hot')),
        chip('warm', 'Ấm 5–7', _n('warm'), careBandColor('warm')),
        chip('cold', 'Lạnh 0–4', _n('cold'), careBandColor('cold')),
        chip('none', 'Chưa chấm', _n('unscored'), careBandColor('none')),
      ],
    );
  }

  Widget _itemCard(_CareItem i) {
    final color = careBandColor(i.band);
    final df = DateFormat('dd/MM HH:mm');
    final (fuText, fuColor) = switch (i.followUp) {
      'overdue' => ('Quá hạn hẹn', Colors.red.shade800),
      'today' => ('Hẹn hôm nay', Colors.amber.shade900),
      'upcoming' => ('Hẹn', SboxColors.brand700),
      _ => ('', SboxColors.slate500),
    };
    final lastText = i.lastContactAt == null
        ? tr('Chưa liên hệ lần nào')
        : [
            i.daysSinceContact == 0
                ? tr('Hôm nay')
                : tr('${i.daysSinceContact} ngày trước'),
            _kindLabel(i.lastContactKind),
            if ((i.lastContent ?? '').isNotEmpty) i.lastContent!,
          ].join(' · ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(i),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _scoreBadge(i, color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (i.customerName ?? '').isNotEmpty
                          ? i.customerName!
                          : tr('Chưa chọn khách'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        i.quoteNo,
                        PosQuote.statusLabel(i.status),
                        '${_money.format(i.total)} đ',
                        if ((i.ownerName ?? '').isNotEmpty) i.ownerName!,
                      ].join('  ·  '),
                      style:
                          TextStyle(fontSize: 12, color: SboxColors.slate700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: i.stale
                            ? Colors.brown.shade700
                            : SboxColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (fuText.isNotEmpty && i.nextFollowUpAt != null)
                          _tag(
                              '${tr(fuText)} ${df.format(i.nextFollowUpAt!.toLocal())}',
                              fuColor),
                        if (i.stale)
                          _tag(tr('Lâu chưa liên hệ'), Colors.brown),
                        _tag(tr('${i.contactCount} lần liên hệ'),
                            Colors.blueGrey),
                        if (i.otherQuotes > 0)
                          _tag(tr('Khách còn ${i.otherQuotes} báo giá khác'), (SboxColors.posApp ? SboxColors.brand600 : Colors.indigo)),
                        if (i.history.length > 1) _sparkline(i.history),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreBadge(_CareItem i, Color color) {
    final trendIcon = switch (i.trend) {
      > 0 => Icons.arrow_upward,
      < 0 => Icons.arrow_downward,
      _ => null,
    };
    return SizedBox(
      width: 54,
      child: Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: (i.score ?? 0) / 10,
                  strokeWidth: 5,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                Text(
                  i.score?.toString() ?? '—',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(tr(careBandLabel(i.band)),
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              if (trendIcon != null)
                Icon(trendIcon,
                    size: 12,
                    color: i.trend > 0 ? SboxColors.okSwatch.shade700 : Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  /// Các lần chấm điểm gần nhất (cột cao = điểm, màu theo nhóm).
  Widget _sparkline(List<int> scores) => Tooltip(
        message: '${tr('Điểm các lần')}: ${scores.join(' → ')}',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final s in scores)
              Container(
                width: 5,
                height: 3 + s * 1.6,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: careBandColor(s >= 8
                      ? 'hot'
                      : s >= 5
                          ? 'warm'
                          : 'cold'),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
      );

  String _kindLabel(String? kind) => switch (kind) {
        'Call' => tr('Gọi điện'),
        'Meeting' => tr('Gặp khách'),
        'FollowUp' => tr('Hẹn'),
        _ => tr('Ghi chú'),
      };
}

/// Báo cáo chăm sóc theo nhân viên: số lần liên hệ, hẹn quá hạn, khách bỏ quên, tỉ lệ chốt.
class PosQuoteCareStaffScreen extends StatefulWidget {
  const PosQuoteCareStaffScreen({super.key});

  @override
  State<PosQuoteCareStaffScreen> createState() => _PosQuoteCareStaffScreenState();
}

class _PosQuoteCareStaffScreenState extends State<PosQuoteCareStaffScreen> {
  final _money = NumberFormat('#,###', 'vi_VN');
  int _days = 30;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

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
    final res = await ApiService().getPosQuoteCareStaff(days: _days);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? tr('Không tải được dữ liệu');
      });
      return;
    }
    final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    setState(() {
      _loading = false;
      _rows = ((data['items'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    });
  }

  Widget _stat(String label, String value, {Color? color, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 14, top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
      );

  num _n(Map<String, dynamic> r, String k) => (r[k] as num?) ?? 0;

  // ───── Số của từng nhân viên → báo giá tạo ra số đó ─────
  // Đang theo / giá trị / quá hẹn / bỏ quên / điểm TB: từ bảng chăm sóc (care-overview, báo giá đang chào)
  // lọc theo người lập — cùng nguồn PosQuoteCareBoard như care-staff.
  // BG lập / đã chốt / doanh số / tỉ lệ chốt: danh sách báo giá lọc người lập + ngày tạo trong [_days] ngày.

  bool _ownedBy(Map<String, dynamic> item, Map<String, dynamic> r) {
    final emp = '${r['employeeId'] ?? ''}';
    if (emp.isNotEmpty) return '${item['ownerEmployeeId'] ?? ''}' == emp;
    return item['ownerEmployeeId'] == null && '${item['ownerName'] ?? ''}' == '${r['name'] ?? ''}';
  }

  void _drillCare(Map<String, dynamic> r, String title, bool Function(Map<String, dynamic> i) where,
      {String Function(Map<String, dynamic> i)? trailing, String? total, String? note}) {
    showReportDrillSheet(
      context,
      title: title,
      subtitle: '${r['name'] ?? 'Chưa rõ người lập'}',
      note: note,
      total: total,
      emptyText: 'Không có báo giá',
      load: () async {
        final res = await ApiService().getPosQuoteCareOverview(scope: 'pipeline');
        if (res['isSuccess'] != true) throw Exception(res['message']?.toString() ?? 'Không tải được dữ liệu');
        final items = (((res['data'] as Map?)?['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .where((i) => _ownedBy(i, r) && where(i))
            .toList();
        return [
          for (final i in items)
            ReportDrillRow(
              title: '${i['quoteNo'] ?? ''} · ${i['customerName'] ?? 'Khách'}',
              subtitle: [
                careBandLabel('${i['band'] ?? 'none'}'),
                if (i['score'] != null) 'điểm ${i['score']}/10',
                '${_money.format(_n(i, 'total'))} đ',
              ].join(' · '),
              trailing: trailing?.call(i),
              icon: Icons.request_quote_outlined,
              onTap: () => showPosQuoteCareSheet(
                context,
                quoteId: '${i['quoteId']}',
                quoteNo: '${i['quoteNo'] ?? ''}',
                customerName: i['customerName'] as String?,
                customerPhone: i['customerPhone'] as String?,
              ),
            ),
        ];
      },
    );
  }

  void _drillCreated(Map<String, dynamic> r, String title, {Set<String>? statuses, bool money = false, String? note}) {
    final emp = '${r['employeeId'] ?? ''}';
    showReportDrillSheet(
      context,
      title: title,
      subtitle: '${r['name'] ?? 'Chưa rõ người lập'} · $_days ngày',
      note: note,
      total: money ? 'Tổng ${_money.format(_n(r, 'acceptedValue'))} đ' : null,
      emptyText: 'Không có báo giá',
      footer: emp.isEmpty ? 'Người lập không gắn nhân viên — danh sách có thể gồm báo giá của người khác.' : null,
      load: () async {
        final out = <Map<String, dynamic>>[];
        for (var page = 1; page <= 5; page++) {
          final res = await ApiService().getPosQuotes(
            employeeId: emp.isEmpty ? null : emp,
            from: DateTime.now().toUtc().subtract(Duration(days: _days)),
            page: page,
            pageSize: 200,
          );
          if (res['isSuccess'] != true) throw Exception(res['message']?.toString() ?? 'Không tải được dữ liệu');
          final data = (res['data'] as Map?) ?? const {};
          final list = ((data['items'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          out.addAll(list);
          if (list.length < 200) break;
        }
        final rows = out.where((q) => statuses == null || statuses.contains('${q['status']}')).where((q) {
          // Người lập không gắn nhân viên: lọc theo tên người lập như máy chủ gom nhóm.
          if (emp.isNotEmpty) return true;
          return q['quotedByEmployeeId'] == null && '${q['quotedBy'] ?? ''}' == '${r['name'] ?? ''}';
        }).toList();
        return [
          for (final q in rows)
            ReportDrillRow(
              title: '${q['quoteNo'] ?? ''} · ${q['customerName'] ?? 'Khách'}',
              subtitle: _statusVi('${q['status']}'),
              trailing: '${_money.format(_n(q, 'total'))} đ',
              icon: Icons.request_quote_outlined,
              onTap: () => showPosQuoteCareSheet(
                context,
                quoteId: '${q['id']}',
                quoteNo: '${q['quoteNo'] ?? ''}',
                customerName: q['customerName'] as String?,
                customerPhone: q['customerPhone'] as String?,
              ),
            ),
        ];
      },
    );
  }

  static String _statusVi(String s) => switch (s) {
        'Draft' => 'Nháp',
        'Sent' => 'Đã gửi',
        'Revised' => 'Đã sửa',
        'Accepted' => 'Đã chốt',
        'Rejected' => 'Từ chối',
        'Expired' => 'Hết hạn',
        'Cancelled' => 'Đã hủy',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(title: Text(tr('Chăm sóc theo nhân viên'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 7, label: Text('7 ngày')),
              ButtonSegment(value: 30, label: Text('30 ngày')),
              ButtonSegment(value: 90, label: Text('90 ngày')),
            ],
            selected: {_days},
            onSelectionChanged: (v) {
              setState(() => _days = v.first);
              _load();
            },
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red)))
          else if (_rows.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('Chưa có dữ liệu'))))
          else
            for (final r in _rows)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['name'] ?? tr('Chưa rõ người lập')}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Wrap(children: [
                      _stat(tr('Đang theo'), '${_n(r, 'openQuotes')}',
                          onTap: () => _drillCare(r, 'Báo giá đang theo', (_) => true)),
                      _stat(tr('Giá trị đang chào'), _money.format(_n(r, 'pipelineValue')),
                          onTap: () => _drillCare(r, 'Giá trị đang chào', (_) => true,
                              trailing: (i) => '${_money.format(_n(i, 'total'))} đ',
                              total: 'Tổng ${_money.format(_n(r, 'pipelineValue'))} đ')),
                      // Lần liên hệ: đếm nhật ký trên mọi báo giá của người này — chưa có danh sách theo người lập.
                      _stat(tr('Lần liên hệ'), '${_n(r, 'contacts')}'),
                      _stat(tr('Quá hẹn'), '${_n(r, 'overdue')}', color: _n(r, 'overdue') > 0 ? Colors.red : null,
                          onTap: () => _drillCare(r, 'Quá hạn hẹn', (i) => i['followUp'] == 'overdue')),
                      _stat(tr('Bỏ quên'), '${_n(r, 'stale')}',
                          color: _n(r, 'stale') > 0 ? Colors.orange.shade800 : null,
                          onTap: () => _drillCare(r, 'Lâu chưa liên hệ', (i) => i['stale'] == true,
                              trailing: (i) => i['daysSinceContact'] == null ? 'chưa liên hệ' : '${i['daysSinceContact']} ngày')),
                      _stat(tr('BG lập'), '${_n(r, 'createdQuotes')}',
                          onTap: () => _drillCreated(r, 'Báo giá lập trong $_days ngày')),
                      _stat(tr('Đã chốt'), '${_n(r, 'accepted')}',
                          onTap: () => _drillCreated(r, 'Báo giá đã chốt', statuses: const {'Accepted'})),
                      _stat(tr('Tỉ lệ chốt'), r['conversionRate'] == null ? '—' : '${r['conversionRate']}%',
                          onTap: () => _drillCreated(r, 'Tỉ lệ chốt',
                              statuses: const {'Accepted', 'Rejected', 'Expired', 'Cancelled'},
                              note: 'Tỉ lệ chốt = đã chốt ÷ báo giá đã có kết quả (chốt, từ chối, hết hạn, hủy) '
                                  'lập trong $_days ngày = ${_n(r, 'accepted')} ÷ (số dòng dưới) = '
                                  '${r['conversionRate'] == null ? '—' : '${r['conversionRate']}%'}.')),
                      _stat(tr('Doanh số chốt'), _money.format(_n(r, 'acceptedValue')),
                          onTap: () => _drillCreated(r, 'Doanh số chốt', statuses: const {'Accepted'}, money: true)),
                      _stat(tr('Điểm TB'), r['averageScore'] == null ? '—' : '${r['averageScore']}/10',
                          onTap: () => _drillCare(r, 'Điểm TB', (i) => i['score'] != null,
                              trailing: (i) => '${i['score']}/10',
                              note: 'Điểm TB = trung bình điểm các báo giá đang chào đã chấm = '
                                  '${r['averageScore'] == null ? '—' : '${r['averageScore']}/10'}.')),
                    ]),
                  ]),
                ),
              ),
        ]),
      ),
    );
  }
}
