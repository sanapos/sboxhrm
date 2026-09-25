import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../widgets/pos/pos_quote_care_sheet.dart';
import '../../widgets/pos/pos_theme.dart';

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
        lastContactAt = DateTime.tryParse('${j['lastContactAt'] ?? ''}'),
        lastContactKind = j['lastContactKind'] as String?,
        lastContent = j['lastContent'] as String?,
        daysSinceContact = (j['daysSinceContact'] as num?)?.toInt(),
        stale = j['stale'] == true,
        nextFollowUpAt = DateTime.tryParse('${j['nextFollowUpAt'] ?? ''}'),
        followUp = '${j['followUp'] ?? 'none'}',
        contactCount = (j['contactCount'] as num?)?.toInt() ?? 0,
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
  final String? ownerName;
  final List<int> history;
}

Color careBandColor(String band) => switch (band) {
      'hot' => const Color(0xFFD32F2F),
      'warm' => const Color(0xFFEF6C00),
      'cold' => const Color(0xFF1976D2),
      _ => Colors.grey.shade500,
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
  bool _all = false;
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
    final res = await ApiService().getPosQuoteCareOverview(all: _all);
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
        actions: [
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Gồm cả báo giá đã chốt / từ chối / hết hạn')),
              value: _all,
              onChanged: (v) {
                setState(() => _all = v);
                _load();
              },
            ),
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
                      Icons.speed),
                ),
                Expanded(
                  child: _metric(tr('Khách đang theo'), '$total',
                      Icons.people_alt_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metric(tr('Giá trị báo giá'),
                      '${_money.format(pipeline)} đ', Icons.request_quote),
                ),
                Expanded(
                  child: _metric(tr('Kỳ vọng (× điểm/10)'),
                      '${_money.format(weighted)} đ', Icons.trending_up),
                ),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
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

  Widget _metric(String label, String value, IconData icon) => Row(
        children: [
          Icon(icon, size: 20, color: PosTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      );

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
        chip('all', 'Tất cả', _n('total'), Colors.grey),
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
      'upcoming' => ('Hẹn', Colors.blue.shade700),
      _ => ('', Colors.grey),
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
                          fontWeight: FontWeight.w700, fontSize: 15),
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
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
                            : Colors.grey.shade900,
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
                      fontSize: 18, fontWeight: FontWeight.w800, color: color),
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
                    color: i.trend > 0 ? Colors.green.shade700 : Colors.red),
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
