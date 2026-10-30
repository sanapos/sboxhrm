import '../../widgets/export_file_icon.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/api_datetime.dart';
import '../../utils/pos_report_export.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_health_widgets.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// «Nguy cơ gian lận»: đơn giảm / hủy sau tạm tính, đá bill, đá món, hủy hóa đơn đã thu, không in hóa đơn,
/// in lại nhiều lần, giảm giá tay lớn, trả hàng ngay sau bán — theo đơn và theo nhân viên, kèm cách kiểm tra.
/// Chỉ là DẤU HIỆU cần soát, không phải kết luận gian lận.
class PosRiskReportScreen extends StatefulWidget {
  const PosRiskReportScreen({super.key});

  @override
  State<PosRiskReportScreen> createState() => _PosRiskReportScreenState();
}

class _PosRiskReportScreenState extends State<PosRiskReportScreen> {
  final _api = ApiService();
  final _pngKey = GlobalKey();
  final _money = NumberFormat('#,##0', 'vi_VN');
  static final _df = DateFormat('yyyy-MM-dd');
  static final _dhm = DateFormat('dd/MM HH:mm');
  int _days = 7; // 1 = hôm nay
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _r;
  String _levelFilter = 'all'; // all / high / medium

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final today = DateTime.now();
    final res = await _api.getPosRiskReport(
      from: _df.format(today.subtract(Duration(days: _days - 1))),
      to: _df.format(today),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _r = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = res['message']?.toString() ?? 'Không tải được báo cáo';
      }
    });
  }

  String get _periodLabel {
    final f = DateFormat('dd/MM/yyyy');
    final today = DateTime.now();
    return _days == 1
        ? 'Hôm nay (${f.format(today)})'
        : '$_days ngày (${f.format(today.subtract(Duration(days: _days - 1)))} – ${f.format(today)})';
  }

  static num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  static List<Map<String, dynamic>> _maps(dynamic v) =>
      (v as List? ?? const []).whereType<Map>().map(Map<String, dynamic>.from).toList();

  String _m(dynamic v) => '${_money.format(_n(v))} đ';

  String _fmt(dynamic v) {
    final d = parseApiUtcDateTime(v);
    return d == null ? '—' : _dhm.format(d.toLocal());
  }

  static String _levelStatus(String? l) => switch (l) {
        'high' || 'red' => 'red',
        'medium' || 'yellow' => 'yellow',
        'low' => 'none',
        _ => 'green',
      };

  static String _levelText(String? l) => switch (l) {
        'high' => 'Nghiêm trọng',
        'medium' => 'Cần xem',
        'low' => 'Để ý',
        _ => 'Tốt',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Nguy cơ gian lận')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: tr('Xuất PNG'),
            onPressed: _r == null
                ? null
                : () => unawaited(PosReportExport.png(context: context, key: _pngKey, filePrefix: 'POS_NguyCoGianLan')),
            icon: const ExportFileIcon(ExportFileKind.png),
          ),
          IconButton(
            tooltip: tr('Xuất Excel'),
            onPressed: _r == null ? null : () => unawaited(_exportExcel()),
            icon: const ExportFileIcon(ExportFileKind.excel),
          ),
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: PosReportPngCapture(
        pngKey: _pngKey,
        title: 'Nguy cơ gian lận',
        periodLabel: _periodLabel,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (d, label) in const [(1, 'Hôm nay'), (7, '7 ngày'), (30, '30 ngày')])
                    ChoiceChip(
                      label: Text(tr(label)),
                      selected: _days == d,
                      onSelected: (_) {
                        setState(() => _days = d);
                        unawaited(_load());
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                PosHealthHero(
                  status: 'none',
                  title: 'Không xem được báo cáo',
                  detail: '$_error. Báo cáo này chỉ chủ / quản lý xem được.',
                )
              else if (_r != null)
                ..._content(_r!),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportExcel() async {
    final orders = _maps(_r?['orders']);
    await PosReportExport.excel(
      context: context,
      title: 'Nguy cơ gian lận',
      sheetName: 'Nguy co',
      filePrefix: 'POS_NguyCoGianLan',
      periodLabel: _periodLabel,
      headers: const ['Mức', 'Lúc', 'Mã HĐ', 'Bàn', 'Nhân viên', 'Tiền cần soát', 'Tạm tính', 'Tổng đơn', 'Dấu hiệu', 'Cách kiểm tra'],
      rows: [
        for (final o in orders)
          [
            _levelText(o['level']?.toString()), _fmt(o['atUtc']), '${o['orderNo'] ?? ''}', '${o['resourceName'] ?? ''}',
            '${o['staff'] ?? ''}', _n(o['amountAtRisk']), o['provisionalTotal'] == null ? '' : _n(o['provisionalTotal']),
            _n(o['total']),
            _maps(o['flags']).map((f) => '${f['title']}: ${f['detail']}').join(' | '),
            '${o['howToCheck'] ?? ''}',
          ],
      ],
      summaryLines: [
        '${_r?['verdictText'] ?? ''}',
        for (final s in _maps(_r?['staff']).where((s) => s['level'] != 'green'))
          'Nhân viên cần chú ý: ${s['name']} — ${(s['notes'] as List? ?? const []).join('; ')}',
      ],
    );
  }

  List<Widget> _content(Map<String, dynamic> r) {
    final s = Map<String, dynamic>.from(r['summary'] as Map? ?? {});
    final byCode = _maps(r['byCode']);
    final orders = _maps(r['orders']);
    final staff = _maps(r['staff']);
    final daily = _maps(r['daily']);
    final recs = _maps(r['recommendations']);
    final verdict = r['verdict']?.toString();
    final noReceiptPct = _n(s['noReceiptPct']);
    final shown = orders.where((o) => _levelFilter == 'all' || o['level'] == _levelFilter).toList();
    return [
      PosHealthHero(
        status: verdict,
        title: r['verdictText']?.toString() ?? '',
        detail: r['verdictDetail']?.toString(),
        note: 'Đây là DẤU HIỆU cần kiểm tra, không phải kết luận nhân viên gian lận — nhiều trường hợp có lý do chính đáng.',
      ),
      PosHealthKpiGrid(items: [
        PosHealthKpi('Đơn cần soát', '${_n(s['riskOrders'])} đơn',
            status: _n(s['highOrders']) > 0 ? 'red' : _n(s['riskOrders']) > 0 ? 'yellow' : 'green',
            hint: '${_n(s['highOrders'])} nghiêm trọng · đã soát ${_n(s['ordersChecked'])} đơn', icon: Icons.policy_outlined),
        PosHealthKpi('Tiền cần soát', _m(s['amountAtRisk']),
            status: _n(s['amountAtRisk']) > 0 ? 'yellow' : 'green', hint: 'Tổng tiền các đơn có dấu hiệu',
            icon: Icons.payments_outlined),
        PosHealthKpi('Thu ít hơn tạm tính', _m(s['reducedAfterBillAmount']),
            status: _n(s['reducedAfterBillAmount']) > 0 ? 'red' : 'green',
            hint: 'Khách đã cầm phiếu tạm tính, tiền thu thấp hơn', icon: Icons.trending_down),
        PosHealthKpi('Hủy món / đơn sau tạm tính', '${_n(s['voidsAfterBill'])} lần',
            status: _n(s['voidsAfterBill']) > 0 ? 'red' : 'green', hint: 'Dấu hiệu «đá món / đá bill»',
            icon: Icons.remove_shopping_cart_outlined),
        PosHealthKpi('Hủy hóa đơn đã thu tiền', '${_n(s['paidCancels'])} lần',
            status: _n(s['paidCancels']) > 0 ? 'yellow' : 'green', hint: 'Xóa / hủy đơn có món: ${_n(s['droppedBills'])} lần',
            icon: Icons.block),
        PosHealthKpi('Tiền mặt không in hóa đơn', '${noReceiptPct.toString().replaceAll('.', ',')}%',
            status: PosHealth.level(noReceiptPct, 10, 30),
            hint: '${_n(s['noReceipt'])} đơn · tạm tính đã in: ${_n(s['provisionalBills'])} bàn', icon: Icons.receipt_long),
      ]),
      PosHealthSection(
        title: 'Việc nên làm',
        subtitle: 'Cách chặn các kẽ hở — làm một lần, dùng lâu dài.',
        children: [
          PosHealthActionList(items: [
            for (final x in recs)
              PosHealthAction(
                level: x['level']?.toString() ?? 'info',
                title: x['title']?.toString() ?? '',
                howTo: x['detail']?.toString(),
              ),
          ]),
        ],
      ),
      if (byCode.isNotEmpty) _byCodeSection(byCode),
      if (daily.any((d) => _n(d['amount']) > 0)) _dailySection(daily),
      _staffSection(staff),
      PosHealthSection(
        title: 'Đơn cần kiểm tra (${orders.length})',
        subtitle: 'Nghiêm trọng xếp đầu, tiền lớn trước. Mỗi đơn có «Cách kiểm tra».',
        trailing: null,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final (v, label) in const [('all', 'Tất cả'), ('high', 'Nghiêm trọng'), ('medium', 'Cần xem')])
                ChoiceChip(
                  label: Text(tr(label)),
                  selected: _levelFilter == v,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _levelFilter = v),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Row(children: [
              const Icon(Icons.check_circle_rounded, color: PosHealth.green, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('Không có đơn nào cần kiểm tra.'))),
            ]),
          for (final o in shown.take(150)) _orderCard(o),
        ],
      ),
      const PosHealthGlossary(entries: [
        ('Tạm tính', 'Phiếu báo tiền in cho khách xem trước khi thanh toán. Sau tạm tính mà số tiền giảm là điểm cần soát nhất.'),
        ('Đá bill', 'Thu tiền của khách nhưng xóa / hủy hóa đơn (hoặc không lập hóa đơn) để giữ tiền lại.'),
        ('Đá món', 'Món đã làm và khách đã dùng nhưng bị hủy khỏi đơn — tiền món đó không vào doanh thu.'),
        ('Không in hóa đơn', 'Khách trả tiền mặt mà không nhận hóa đơn — dễ bị hủy đơn sau đó mà khách không biết.'),
        ('In lại nhiều lần', 'Một hóa đơn in ra nhiều bản — có thể dùng bản cũ đưa cho khách khác.'),
        ('Tiền cần soát', 'Số tiền có thể bị thất thoát nếu dấu hiệu là thật — cần kiểm tra để biết chắc.'),
      ]),
    ];
  }

  Widget _byCodeSection(List<Map<String, dynamic>> byCode) {
    final maxCount = byCode.map((c) => _n(c['count']).toInt()).fold<int>(1, math.max);
    return PosHealthSection(
      title: 'Các loại dấu hiệu',
      subtitle: 'Thanh càng dài càng nhiều lần. Màu đỏ = nghiêm trọng, cam = cần xem.',
      children: [
        for (final c in byCode)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(tr(c['label']?.toString() ?? ''),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    '${_n(c['count'])} lần${_n(c['amount']) > 0 ? ' · ${_m(c['amount'])}' : ''}',
                    style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600),
                  ),
                ]),
                const SizedBox(height: 3),
                LayoutBuilder(
                  builder: (_, box) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 10,
                      width: math.max(6, box.maxWidth * _n(c['count']) / maxCount),
                      decoration: BoxDecoration(
                        color: PosHealth.color(_levelStatus(c['level']?.toString())),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dailySection(List<Map<String, dynamic>> daily) {
    final points = [
      for (final d in daily)
        if (parseApiUtcDateTime(d['dateVn']) case final date?) (date: date.toUtc(), value: _n(d['amount']).toDouble()),
    ];
    return PosHealthSection(
      title: 'Tiền cần soát theo ngày',
      subtitle: 'Ngày có cột cao = nhiều đơn bất thường — đối chiếu lịch ca xem ai làm hôm đó.',
      children: [PosReportBarChart(points: points, height: 170, maxLabels: 7)],
    );
  }

  Widget _staffSection(List<Map<String, dynamic>> staff) {
    return PosHealthSection(
      title: 'Theo nhân viên (${staff.length})',
      subtitle: 'So với cả quán. Đỏ = nhiều dấu hiệu nghiêm trọng / tiền lớn; vàng = cần để ý.',
      children: [
        if (staff.isEmpty) Text(tr('Chưa có số liệu.'), style: const TextStyle(color: SboxColors.slate500)),
        for (final s in staff)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: PosHealth.color(s['level']?.toString()).withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(tr('${s['name']}'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    PosHealthChip(
                      status: s['level']?.toString(),
                      text: switch (s['level']) { 'red' => 'Cần kiểm tra', 'yellow' => 'Để ý', _ => 'Bình thường' },
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  tr('${_n(s['orders'])} đơn thu · ${_n(s['highSignals'])} dấu hiệu nghiêm trọng · ${_n(s['mediumSignals'])} cần xem'
                      '${_n(s['amountAtRisk']) > 0 ? ' · ${_m(s['amountAtRisk'])} cần soát' : ''}'
                      '${_n(s['kitchenVoids']) > 0 ? ' · hủy ${_n(s['kitchenVoids'])} món' : ''}'
                      '${_n(s['cashOrders']) > 0 ? ' · không in HĐ ${_n(s['noReceiptPct']).toString().replaceAll('.', ',')}%' : ''}'),
                  style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600, height: 1.35),
                ),
                for (final note in (s['notes'] as List? ?? const []))
                  Text('• ${tr('$note')}', style: const TextStyle(fontSize: 12.5, color: SboxColors.slate800, height: 1.35)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final level = o['level']?.toString();
    final st = _levelStatus(level);
    final c = PosHealth.color(st);
    final flags = _maps(o['flags']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withOpacity(0.04), Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PosHealthChip(status: st, text: _levelText(level)),
              Text(
                tr('${o['orderNo'] ?? 'Đơn đã xóa'}${o['resourceName'] == null ? '' : ' · ${o['resourceName']}'}'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              Text(_fmt(o['atUtc']), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr('${_n(o['amountAtRisk']) > 0 ? 'Cần soát ${_m(o['amountAtRisk'])}' : 'Cần xem'}'
                '${o['provisionalTotal'] == null ? '' : ' · tạm tính ${_m(o['provisionalTotal'])}'}'
                '${_n(o['total']) > 0 ? ' · đơn ${_m(o['total'])}' : ''}'
                '${o['paymentMethod'] == null ? '' : ' · ${o['paymentMethod']}'}'
                '${o['staff'] == null ? '' : ' · ${o['staff']}'}'),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c),
          ),
          const SizedBox(height: 4),
          for (final f in flags)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(PosHealth.icon(_levelStatus(f['level']?.toString())),
                        size: 14, color: PosHealth.color(_levelStatus(f['level']?.toString()))),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${tr(f['title']?.toString() ?? '')}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: tr(f['detail']?.toString() ?? '')),
                      ]),
                      style: const TextStyle(fontSize: 12.5, color: SboxColors.slate800, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          if ((o['howToCheck']?.toString() ?? '').isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: BoxDecoration(
                color: SboxColors.slate50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SboxColors.slate200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.fact_check_outlined, size: 16, color: SboxColors.slate600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${tr('Cách kiểm tra')}: ${tr(o['howToCheck'].toString())}',
                        style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
