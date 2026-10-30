import '../../widgets/export_file_icon.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/pos_report_export.dart';
import '../../widgets/pos/reports/pos_health_widgets.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import '../../services/api_service.dart';
import '../../services/pos_network_monitor.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Báo cáo «Mạng cửa hàng»: mạng có đủ ổn định để order / in qua mạng không, giờ nào tệ, máy nào tệ,
/// nên làm gì. Số liệu do các máy POS tự đo (ping 30s, lỗi gọi server, rớt realtime, máy in LAN).
/// Trình bày cho người không chuyên: đèn xanh / vàng / đỏ, chỉ số kèm ngưỡng, đồ thị theo giờ, việc nên làm.
class PosNetworkReportScreen extends StatefulWidget {
  const PosNetworkReportScreen({super.key});

  @override
  State<PosNetworkReportScreen> createState() => _PosNetworkReportScreenState();
}

class _PosNetworkReportScreenState extends State<PosNetworkReportScreen> {
  final _api = ApiService();
  final _pngKey = GlobalKey();
  int _range = 0; // 0 hôm nay, 1 hôm qua, 7 = 7 ngày
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _r;
  /// Giờ đang chọn trên đồ thị (chỉ số trong danh sách giờ).
  int? _selHour;

  static final _df = DateFormat('yyyy-MM-dd');
  static final _hm = DateFormat('HH:mm');
  static final _dhm = DateFormat('dd/MM HH:mm');

  // Ngưỡng hiển thị — khớp PosNetworkReportBuilder (máy chủ).
  static const _goodP95Ms = 800;
  static const _badP95Ms = 1500;
  static const _slowPrintSec = 8;

  @override
  void initState() {
    super.initState();
    // Đẩy số liệu đang giữ trên máy này trước khi xem.
    unawaited(PosNetworkMonitor.instance.flush().whenComplete(_load));
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final today = DateTime.now();
    final DateTime from;
    final DateTime to;
    if (_range == 1) {
      from = to = today.subtract(const Duration(days: 1));
    } else if (_range == 7) {
      from = today.subtract(const Duration(days: 6));
      to = today;
    } else {
      from = to = today;
    }
    final res = await _api.getNetworkReport(from: _df.format(from), to: _df.format(to));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _selHour = null;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _r = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = res['message']?.toString() ?? 'Không tải được báo cáo';
      }
    });
  }

  static DateTime? _dt(dynamic v) {
    final s = v?.toString();
    if (s == null || s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    // Server trả giờ VN (đã cộng 7h) dưới dạng UTC — hiển thị đúng con số.
    return d?.toUtc();
  }

  static num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  static String _sec(num ms) {
    if (ms < 1000) return '${ms.round()} ms';
    final s = ms / 1000;
    return '${s.toStringAsFixed(s < 10 ? 1 : 0).replaceAll('.', ',')} giây';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Mạng cửa hàng')),
        actions: [
          IconButton(
            tooltip: tr('Xuất PNG'),
            onPressed: _r == null
                ? null
                : () => unawaited(PosReportExport.png(context: context, key: _pngKey, filePrefix: 'POS_MangCuaHang')),
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
        title: 'Mạng cửa hàng',
        periodLabel: _periodLabel(),
        child: _body(),
      ),
    );
  }

  String _periodLabel() {
    final f = DateFormat('dd/MM/yyyy');
    final today = DateTime.now();
    return switch (_range) {
      1 => 'Hôm qua (${f.format(today.subtract(const Duration(days: 1)))})',
      7 => '7 ngày (${f.format(today.subtract(const Duration(days: 6)))} – ${f.format(today)})',
      _ => 'Hôm nay (${f.format(today)})',
    };
  }

  Future<void> _exportExcel() async {
    final hours = ((_r?['hours'] as List?) ?? const []).whereType<Map>().toList();
    // Cột số (trễ / in xong) để trống khi không có số liệu — không ghi dạng chữ.
    Object opt(dynamic v) => v == null ? '' : _n(v);
    await PosReportExport.excel(
      context: context,
      title: 'Mạng cửa hàng',
      sheetName: 'Mang',
      filePrefix: 'POS_MangCuaHang',
      periodLabel: _periodLabel(),
      headers: const [
        'Giờ', 'Thiết bị', 'Ping gửi', 'Ping lỗi', 'Lỗi %', 'Trễ p95 (ms)', 'Mất mạng lâu nhất (giây)',
        'Rớt realtime', 'Đơn mới', 'Phiếu in', 'In xong p95 (giây)', 'Tình trạng',
      ],
      rows: [
        for (final h in hours)
          [
            _dt(h['hourVn']) == null ? '' : _dhm.format(_dt(h['hourVn'])!),
            _n(h['devices']), _n(h['pingSent']), _n(h['pingFailed']), _n(h['failPct']), opt(h['latencyP95Ms']),
            _n(h['maxDeviceOfflineSec']), _n(h['disconnects']), _n(h['orders']), _n(h['printJobs']),
            opt(h['printP95Sec']), _healthLabel(h['health']?.toString()),
          ],
      ],
      summaryLines: [
        '${_r?['verdictText'] ?? ''} · ${_n(_r?['score'])} điểm',
        'Thiết bị: ${_n(_r?['deviceCount'])} · Lỗi gọi máy chủ: ${_n(_r?['failPct'])}% · Trễ p95: ${_n(_r?['latencyP95Ms'])} ms'
            ' · Mất kết nối: ${_n(_r?['outageCount'])} lần',
        for (final x in ((_r?['recommendations'] as List?) ?? const []).whereType<Map>())
          'Nên làm: ${x['title'] ?? ''} — ${x['detail'] ?? ''}',
      ],
    );
  }

  static String _healthLabel(String? h) => switch (h) {
        'green' => 'Tốt',
        'yellow' => 'Chập chờn',
        'red' => 'Kém',
        _ => 'Không có số liệu',
      };

  Widget _body() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (v, label) in [(0, 'Hôm nay'), (1, 'Hôm qua'), (7, '7 ngày')])
                ChoiceChip(
                  label: Text(tr(label)),
                  selected: _range == v,
                  onSelected: (_) {
                    setState(() => _range = v);
                    unawaited(_load());
                  },
                ),
              FilledButton.icon(
                onPressed: _quickTest,
                style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
                icon: const Icon(Icons.network_check),
                label: Text(tr('Kiểm tra mạng ngay')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            PosHealthHero(status: 'none', title: 'Không tải được báo cáo', detail: _error)
          else if (_r != null)
            ..._content(_r!),
          const SizedBox(height: 4),
          Text(
            tr('Cách đo: mỗi máy đang mở màn bán hàng tự ping máy chủ 30 giây / lần, đếm lệnh gọi lỗi, số lần '
                'rớt kết nối tức thời, thử cổng máy in LAN 2 phút / lần và sóng Wi-Fi. Gom 5 phút gửi lên; '
                'mất mạng thì lưu lại gửi sau. Giữ 35 ngày.'),
            style: const TextStyle(fontSize: 12, color: SboxColors.slate500, height: 1.4),
          ),
        ],
      ),
    );
  }

  static String _meaning(String? verdict) => switch (verdict) {
        'green' => 'Máy bán hàng gọi máy chủ nhanh, ít lỗi. Order bằng điện thoại, báo bếp, in phiếu qua mạng chạy ổn.',
        'yellow' => 'Thỉnh thoảng chậm hoặc rớt mạng. Vẫn bán được, nhưng giờ đông có thể phải chờ phiếu in / '
            'order chậm. Xem «Việc nên làm» bên dưới.',
        'red' => 'Mạng hay rớt hoặc rất chậm — order qua mạng / in phiếu có thể treo. Nên bật «Bán offline» '
            'và làm ngay các việc bên dưới.',
        _ => 'Mở màn bán hàng trên các máy ít nhất 1 giờ để hệ thống tự đo, hoặc bấm «Kiểm tra mạng ngay».',
      };

  List<Widget> _content(Map<String, dynamic> r) {
    final verdict = r['verdict']?.toString();
    final p95 = r['latencyP95Ms'] as num?;
    final failPct = _n(r['failPct']);
    final print = Map<String, dynamic>.from(r['print'] as Map? ?? {});
    final hours = (r['hours'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    final devices = (r['devices'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    final outages = (r['outages'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    final recs = (r['recommendations'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    final netOutages = outages.where((o) => (o['kind']?.toString() ?? '').startsWith('Mất kết nối máy')).toList();
    final longestOutage = netOutages.map((o) => _n(o['seconds'])).fold<num>(0, math.max);
    final outageCount = _n(r['outageCount']).toInt();
    final disc = _n(r['disconnects']).toInt();
    final printP95 = print['p95Sec'] as num?;
    final insufficient = verdict == 'insufficient';

    return [
      PosHealthHero(
        status: insufficient ? 'none' : verdict,
        score: insufficient ? null : _n(r['score']).toInt(),
        title: r['verdictText']?.toString() ?? '',
        detail: _meaning(verdict),
        note: r['peakNote']?.toString(),
      ),
      PosHealthKpiGrid(items: [
        PosHealthKpi(
          'Lần gọi máy chủ bị lỗi',
          '${failPct.toString().replaceAll('.', ',')}%',
          status: insufficient ? 'none' : PosHealth.level(failPct, 0.99, 5),
          hint: 'Dưới 1% là tốt · trên 5% là kém',
          icon: Icons.sync_problem,
        ),
        PosHealthKpi(
          'Tốc độ phản hồi (95% lần gọi)',
          p95 == null ? '—' : _sec(p95),
          status: PosHealth.level(p95, _goodP95Ms, _badP95Ms),
          hint: 'Dưới 0,8 giây là nhanh',
          icon: Icons.speed,
        ),
        PosHealthKpi(
          'Mất mạng',
          outageCount == 0 ? 'Không lần nào' : '$outageCount lần · ${_dur(r['outageSeconds'])}',
          status: insufficient ? 'none' : (outageCount == 0 ? 'green' : longestOutage >= 120 ? 'red' : 'yellow'),
          hint: 'Tính lần mất từ 30 giây · từ 2 phút là nặng',
          icon: Icons.wifi_off,
        ),
        PosHealthKpi(
          'Rớt cập nhật tức thời',
          '$disc lần',
          status: insufficient ? 'none' : (disc == 0 ? 'green' : disc > 20 ? 'red' : 'yellow'),
          hint: 'Bàn / phiếu trên máy khác cập nhật chậm',
          icon: Icons.bolt,
        ),
        PosHealthKpi(
          'Thời gian in phiếu qua mạng',
          printP95 == null ? '—' : '${printP95.toString().replaceAll('.', ',')} giây',
          status: PosHealth.level(printP95, _slowPrintSec, 15),
          hint: '95% phiếu in xong trong · dưới 8 giây là tốt',
          icon: Icons.print_outlined,
        ),
        PosHealthKpi(
          'Máy đang gửi số liệu',
          '${_n(r['deviceCount'])} máy',
          hint: 'Máy mở màn bán hàng mới được đo',
          icon: Icons.devices_other,
        ),
      ]),
      PosHealthSection(
        title: 'Việc nên làm',
        subtitle: 'Làm theo thứ tự — việc «Làm ngay» ảnh hưởng trực tiếp tới bán hàng.',
        children: [
          PosHealthActionList(
            items: [
              for (final x in recs)
                PosHealthAction(
                  level: x['code'] == 'OK' ? 'ok' : (x['level']?.toString() ?? 'info'),
                  title: x['title']?.toString() ?? '',
                  howTo: x['detail']?.toString(),
                ),
            ],
            emptyText: insufficient ? 'Chưa đủ số liệu để gợi ý.' : 'Không có việc gì cần làm — mạng ổn.',
          ),
        ],
      ),
      if (hours.isNotEmpty) _hoursSection(hours),
      if (hours.any((h) => h['latencyP95Ms'] != null)) _latencySection(hours),
      PosHealthSection(
        title: 'Từng máy bán hàng (${devices.length})',
        subtitle: 'Máy có biểu tượng máy in là máy giữ máy in cho máy khác in qua (Agent) — cần mạng tốt nhất.',
        children: [
          if (devices.isEmpty)
            Text(tr('Chưa có máy nào gửi số liệu.'), style: const TextStyle(color: SboxColors.slate500)),
          for (final d in devices) _deviceCard(d),
        ],
      ),
      PosHealthSection(
        title: 'Những lần mất kết nối (${outages.length})',
        subtitle: 'Mới nhất ở trên. «Tức thời» = vẫn bán được nhưng bàn / phiếu cập nhật chậm.',
        children: [
          if (outages.isEmpty)
            Row(children: [
              const Icon(Icons.check_circle_rounded, color: PosHealth.green, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('Không có lần mất kết nối nào đáng kể.'))),
            ]),
          for (final o in outages.take(30))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                o['isAgent'] == true ? Icons.print : Icons.wifi_off,
                color: (o['kind']?.toString() ?? '').startsWith('Mất kết nối máy') && _n(o['seconds']) >= 120
                    ? PosHealth.red
                    : PosHealth.yellow,
              ),
              title: Text(tr('${o['deviceName'] ?? o['deviceId']} · ${o['kind']}')),
              subtitle: Text(tr(
                  '${_dt(o['startVn']) == null ? '' : _dhm.format(_dt(o['startVn'])!)} · kéo dài ${_dur(o['seconds'])}'
                  '${o['isAgent'] == true ? ' · máy giữ máy in (Agent)' : ''}')),
            ),
        ],
      ),
      _printSection(print),
      const PosHealthGlossary(entries: [
        ('Máy chủ', 'Hệ thống SBOX trên Internet — nơi lưu đơn, bàn, phiếu bếp. Máy bán hàng phải gọi được máy chủ.'),
        ('Lần gọi bị lỗi', 'Máy hỏi máy chủ mà không có trả lời. Nhiều lỗi = order / thanh toán phải bấm lại.'),
        ('Tốc độ phản hồi', 'Thời gian máy chủ trả lời. «95%» nghĩa là 95 trên 100 lần nhanh hơn con số này.'),
        ('Cập nhật tức thời (realtime)', 'Kênh báo ngay cho các máy khác khi có món mới / bàn đổi. Rớt thì máy khác thấy chậm.'),
        ('Máy giữ máy in (Agent)', 'Máy tính bảng / máy POS cắm với máy in; máy khác gửi phiếu in qua máy này.'),
        ('Máy in LAN', 'Máy in cắm dây mạng trong quán. Đo bằng cách thử kết nối mỗi 2 phút.'),
        ('dBm (sóng Wi-Fi)', 'Từ -30 đến -60 là mạnh; -70 trở xuống là yếu (dễ rớt).'),
        ('Điểm', '100 là hoàn hảo. Từ 85 xanh, 60–84 vàng, dưới 60 đỏ.'),
      ]),
    ];
  }

  // ── Theo giờ ───────────────────────────────────────────────────────────────

  static int _busy(Map<String, dynamic> h) => _n(h['orders']).toInt() + _n(h['printJobs']).toInt();

  Widget _hoursSection(List<Map<String, dynamic>> hours) {
    final counts = <String, int>{};
    for (final h in hours) {
      final k = h['health']?.toString() ?? 'none';
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final multiDay = _dt(hours.first['hourVn'])?.day != _dt(hours.last['hourVn'])?.day;
    // Mặc định chọn giờ tệ nhất (đỏ → vàng), trùng thì giờ đông nhất.
    int defaultSel() {
      int rank(String? h) => switch (h) { 'red' => 0, 'yellow' => 1, 'green' => 2, _ => 3 };
      var best = 0;
      for (var i = 1; i < hours.length; i++) {
        final a = rank(hours[i]['health']?.toString());
        final b = rank(hours[best]['health']?.toString());
        if (a < b || (a == b && _busy(hours[i]) > _busy(hours[best]))) best = i;
      }
      return best;
    }

    final sel = (_selHour != null && _selHour! < hours.length) ? _selHour! : defaultSel();
    final maxBusy = hours.map(_busy).fold<int>(1, math.max);
    final step = math.max(1, (hours.length / 12).ceil());
    String hourLabel(int i) {
      final d = _dt(hours[i]['hourVn']);
      if (d == null) return '';
      return multiDay ? DateFormat('d/M\nH').format(d) : '${d.hour}h';
    }

    return PosHealthSection(
      title: 'Mạng theo từng giờ',
      subtitle: 'Cột cao = giờ đông (đơn mới + phiếu in). Màu cột = mạng giờ đó. Bấm vào cột để xem chi tiết.',
      children: [
        PosHealthSegmentBar(unit: 'giờ', segments: [
          (label: 'Tốt', value: counts['green'] ?? 0, color: PosHealth.green),
          (label: 'Chập chờn', value: counts['yellow'] ?? 0, color: PosHealth.yellow),
          (label: 'Kém', value: counts['red'] ?? 0, color: PosHealth.red),
          (label: 'Không đo', value: counts['none'] ?? 0, color: PosHealth.grey),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 190,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              minY: 0,
              maxY: maxBusy * 1.15,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFE8ECF0), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (v, meta) => v == meta.max
                        ? const SizedBox.shrink()
                        : Text(v.toInt().toString(), style: const TextStyle(fontSize: 9, color: SboxColors.slate500)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: multiDay ? 28 : 18,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= hours.length || i % step != 0) return const SizedBox.shrink();
                      return Text(hourLabel(i),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9, color: SboxColors.slate500, height: 1.1));
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barTouchData: BarTouchData(
                handleBuiltInTouches: false,
                touchCallback: (event, resp) {
                  if (event is FlTapUpEvent && resp?.spot != null) {
                    setState(() => _selHour = resp!.spot!.touchedBarGroupIndex);
                  }
                },
              ),
              barGroups: [
                for (var i = 0; i < hours.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        // Giờ không có đơn vẫn hiện cột thấp để thấy màu mạng.
                        toY: math.max(_busy(hours[i]).toDouble(), maxBusy * 0.04),
                        color: PosHealth.color(hours[i]['health']?.toString()),
                        width: hours.length <= 14 ? 16 : hours.length <= 30 ? 9 : 5,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        borderSide: i == sel
                            ? const BorderSide(color: SboxColors.slate900, width: 2)
                            : BorderSide.none,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _hourDetail(hours[sel], multiDay),
      ],
    );
  }

  Widget _hourDetail(Map<String, dynamic> h, bool multiDay) {
    final d = _dt(h['hourVn']);
    final health = h['health']?.toString();
    final p95 = h['latencyP95Ms'] as num?;
    final when = d == null ? '' : '${(multiDay ? _dhm : _hm).format(d)} – ${_hm.format(d.add(const Duration(hours: 1)))}';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(PosHealth.color(health).withOpacity(0.07), Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PosHealth.color(health).withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(when, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(width: 8),
            PosHealthChip(status: health, text: _healthLabel(health)),
          ]),
          const SizedBox(height: 6),
          Text(
            tr('${_n(h['orders'])} đơn mới · ${_n(h['printJobs'])} phiếu in · ${_n(h['devices'])} máy đo\n'
                'Lỗi gọi máy chủ ${_n(h['failPct']).toString().replaceAll('.', ',')}% · phản hồi ${p95 == null ? '—' : _sec(p95)}\n'
                'Mất mạng lâu nhất ${_dur(h['maxDeviceOfflineSec'])} · rớt cập nhật tức thời ${_n(h['disconnects'])} lần'
                '${h['printP95Sec'] == null ? '' : '\nIn phiếu xong trong ${h['printP95Sec']} giây (95%)'}'),
            style: const TextStyle(fontSize: 12.5, height: 1.45, color: SboxColors.slate700),
          ),
        ],
      ),
    );
  }

  Widget _latencySection(List<Map<String, dynamic>> hours) {
    final spots = <FlSpot>[
      for (var i = 0; i < hours.length; i++)
        if (hours[i]['latencyP95Ms'] != null) FlSpot(i.toDouble(), _n(hours[i]['latencyP95Ms']) / 1000),
    ];
    final maxY = math.max(1.2, spots.map((s) => s.y).fold<double>(0, math.max) * 1.15);
    final multiDay = _dt(hours.first['hourVn'])?.day != _dt(hours.last['hourVn'])?.day;
    final step = math.max(1, (hours.length / 8).ceil());
    return PosHealthSection(
      title: 'Tốc độ phản hồi theo giờ',
      subtitle: 'Đường càng thấp càng nhanh. Vượt vạch đỏ (0,8 giây) là khách / nhân viên bắt đầu thấy chậm.',
      children: [
        SizedBox(
          height: 170,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: math.max(1, hours.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFE8ECF0), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: _goodP95Ms / 1000,
                  color: PosHealth.red,
                  strokeWidth: 1.5,
                  dashArray: const [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    style: const TextStyle(fontSize: 10, color: PosHealth.red, fontWeight: FontWeight.w600),
                    labelResolver: (_) => tr('ngưỡng chậm'),
                  ),
                ),
              ]),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (v, meta) => v == meta.max
                        ? const SizedBox.shrink()
                        : Text('${v.toStringAsFixed(1).replaceAll('.', ',')}s',
                            style: const TextStyle(fontSize: 9, color: SboxColors.slate500)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 18,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (v != i.toDouble() || i < 0 || i >= hours.length || i % step != 0) {
                        return const SizedBox.shrink();
                      }
                      final d = _dt(hours[i]['hourVn']);
                      return Text(d == null ? '' : (multiDay ? DateFormat('d/M H') : DateFormat("H'h'")).format(d),
                          style: const TextStyle(fontSize: 9, color: SboxColors.slate500));
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${_dt(hours[s.x.toInt()]['hourVn']) == null ? '' : _hm.format(_dt(hours[s.x.toInt()]['hourVn'])!)}\n'
                        '${s.y.toStringAsFixed(2).replaceAll('.', ',')} giây',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: PosTheme.kiotBlue,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                      radius: 3,
                      color: s.y > _goodP95Ms / 1000 ? PosHealth.red : PosTheme.kiotBlue,
                      strokeWidth: 0,
                    ),
                  ),
                  belowBarData: BarAreaData(show: true, color: PosTheme.kiotBlue.withOpacity(0.08)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Máy / lệnh in ──────────────────────────────────────────────────────────

  Widget _deviceCard(Map<String, dynamic> d) {
    final rssi = d['wifiRssi'] as num?;
    final (connIcon, conn) = switch (d['connType']?.toString()) {
      'wifi' => (Icons.wifi, 'Wi-Fi${rssi == null ? '' : ' (sóng ${rssi >= -60 ? 'mạnh' : rssi > -70 ? 'vừa' : 'yếu'} $rssi dBm)'}'),
      'ethernet' => (Icons.settings_ethernet, 'Dây LAN'),
      'mobile' => (Icons.signal_cellular_alt, '4G / di động'),
      'web' => (Icons.language, 'Trình duyệt'),
      _ => (Icons.device_unknown, 'Không rõ kết nối'),
    };
    final health = d['health']?.toString();
    final problems = <String>[
      if (_n(d['failPct']) >= 1) 'Lỗi gọi máy chủ ${_n(d['failPct']).toString().replaceAll('.', ',')}%',
      if (_n(d['latencyP95Ms']) > _goodP95Ms) 'Phản hồi chậm (${_sec(_n(d['latencyP95Ms']))})',
      if (_n(d['outages']) > 0) 'Mất mạng ${d['outages']} lần (tổng ${_dur(d['offlineSec'])})',
      if (_n(d['disconnects']) > 0) 'Rớt cập nhật tức thời ${d['disconnects']} lần',
      if (rssi != null && rssi <= -70) 'Sóng Wi-Fi yếu — đặt gần router hoặc cắm dây',
      if (d['connType'] == 'mobile') 'Đang dùng 4G — nên dùng Wi-Fi / dây của quán',
      if (_n(d['printerChecks']) > 0 && _n(d['printerFailed']) > 0)
        'Máy in LAN không kết nối được ${d['printerFailed']}/${d['printerChecks']} lần thử',
    ];
    final last = _dt(d['lastSeenVn']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PosHealth.color(health).withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(d['isAgent'] == true ? Icons.print : Icons.point_of_sale, color: PosHealth.color(health), size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(tr('${d['deviceName'] ?? d['deviceId']}'),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    PosHealthChip(status: health, text: _healthLabel(health)),
                    if (d['isAgent'] == true)
                      Text(tr('giữ máy in'), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
                  ],
                ),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(connIcon, size: 14, color: SboxColors.slate500),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      tr('$conn${last == null ? '' : ' · gửi số liệu lúc ${_dhm.format(last)}'}'),
                      style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                if (problems.isEmpty)
                  Text(tr('Mạng máy này tốt.'), style: const TextStyle(fontSize: 12.5, color: PosHealth.green))
                else
                  for (final p in problems)
                    Text('• ${tr(p)}', style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _printSection(Map<String, dynamic> print) {
    final total = _n(print['total']).toInt();
    final completed = _n(print['completed']).toInt();
    final failed = _n(print['failed']).toInt();
    final cancelled = _n(print['cancelled']).toInt();
    final other = math.max(0, total - completed - failed - cancelled);
    final p50 = print['p50Sec'];
    final p95 = print['p95Sec'];
    return PosHealthSection(
      title: 'In phiếu qua mạng',
      subtitle: 'Phiếu bếp / hóa đơn gửi qua máy chủ tới máy giữ máy in.',
      children: [
        if (total == 0)
          Text(tr('Chưa có phiếu in qua mạng trong kỳ này.'), style: const TextStyle(color: SboxColors.slate500))
        else ...[
          PosHealthSegmentBar(unit: 'phiếu', segments: [
            (label: 'In xong', value: completed, color: PosHealth.green),
            (label: 'Lỗi', value: failed, color: PosHealth.red),
            (label: 'Hủy', value: cancelled, color: PosHealth.yellow),
            (label: 'Đang chờ', value: other, color: PosHealth.grey),
          ]),
          const SizedBox(height: 8),
          Text(
            tr('Một nửa số phiếu in xong trong ${p50 ?? '—'} giây; 95% trong ${p95 ?? '—'} giây.'
                '${_n(print['staleQueued']) > 0 ? ' ${print['staleQueued']} phiếu bị hủy vì máy giữ máy in tắt / mất mạng.' : ''}'
                '${_n(print['stuckNoRequeue']) > 0 ? ' ${print['stuckNoRequeue']} phiếu có thể đã in — kiểm tra trước khi in lại.' : ''}'),
            style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700, height: 1.4),
          ),
        ],
      ],
    );
  }

  static String _dur(dynamic sec) {
    final s = (sec as num?)?.toInt() ?? 0;
    if (s < 60) return '$s giây';
    final m = s ~/ 60;
    return m < 60 ? '$m phút' : '${m ~/ 60} giờ ${m % 60} phút';
  }

  // ── Kiểm tra mạng ngay ─────────────────────────────────────────────────────

  Future<void> _quickTest() async {
    final progress = ValueNotifier<(double, String)>((0, 'Bắt đầu'));
    NetworkQuickTestResult? result;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đang kiểm tra mạng…')),
        content: ValueListenableBuilder<(double, String)>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v.$1),
              const SizedBox(height: 10),
              Text(tr(v.$2)),
              const SizedBox(height: 6),
              Text(tr('Khoảng 30–60 giây. Đừng tắt màn hình.'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ],
          ),
        ),
      ),
    ));
    try {
      result = await PosNetworkMonitor.instance.runQuickTest(
        onProgress: (p, step) => progress.value = (p, step),
      );
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;
    final r = result;
    String mbit(double? kbps) => kbps == null ? 'lỗi' : '${(kbps / 1000).toStringAsFixed(1).replaceAll('.', ',')} Mbit/s';
    final okPings = r.pingSent - r.pingFailed;
    final rows = <(String, String, String)>[
      ('Gọi máy chủ', '$okPings/${r.pingSent} lần thành công',
          r.failPct == 0 ? 'green' : r.failPct <= 5 ? 'yellow' : 'red'),
      ('Tốc độ phản hồi', r.p95 == null ? 'không đo được' : _sec(r.p95!),
          PosHealth.level(r.p95, _goodP95Ms, 2000)),
      ('Tải về / tải lên', '${mbit(r.downKbps)} / ${mbit(r.upKbps)}',
          r.downKbps == null || r.upKbps == null ? 'red' : 'green'),
      ('Giờ đông giả lập (${r.burstSent} yêu cầu cùng lúc)', '${r.burstOk}/${r.burstSent} OK',
          r.burstOk < r.burstSent ? 'red' : PosHealth.level(r.burstP95, 2000, 2000)),
      ('Cập nhật tức thời', r.realtimeConnected ? 'đang nối' : 'mất', r.realtimeConnected ? 'green' : 'red'),
      if (r.connType != null)
        (
          'Kết nối',
          '${switch (r.connType) { 'wifi' => 'Wi-Fi', 'ethernet' => 'Dây LAN', 'mobile' => '4G', _ => r.connType! }}'
              '${r.wifiRssi == null ? '' : ' · ${r.wifiRssi} dBm'}',
          r.connType == 'mobile' || (r.wifiRssi != null && r.wifiRssi! <= -70) ? 'yellow' : 'green',
        ),
      for (final p in r.printers)
        ('Máy in «${p.name}»', p.ms == null ? 'không kết nối được' : '${p.ms} ms', p.ms == null ? 'red' : 'green'),
    ];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(PosHealth.icon(r.verdict), color: PosHealth.color(r.verdict)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr(switch (r.verdict) {
                'green' => 'Mạng tốt',
                'yellow' => 'Mạng tạm được — nên khắc phục',
                _ => 'Mạng không ổn định',
              })),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (label, value, st) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(PosHealth.icon(st), size: 18, color: PosHealth.color(st)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tr(label), style: const TextStyle(fontSize: 13))),
                        Text(tr(value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                const Divider(height: 18),
                Text(tr('Nên làm'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                for (final a in r.advice)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${tr(a)}', style: const TextStyle(fontSize: 13, height: 1.35)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
        ],
      ),
    );
  }
}
