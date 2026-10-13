import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/pos_network_monitor.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Báo cáo «Mạng cửa hàng»: mạng có đủ ổn định để order / in qua mạng không, giờ nào tệ, máy nào tệ,
/// nên làm gì. Số liệu do các máy POS tự đo (ping 30s, lỗi gọi server, rớt realtime, máy in LAN).
class PosNetworkReportScreen extends StatefulWidget {
  const PosNetworkReportScreen({super.key});

  @override
  State<PosNetworkReportScreen> createState() => _PosNetworkReportScreenState();
}

class _PosNetworkReportScreenState extends State<PosNetworkReportScreen> {
  final _api = ApiService();
  int _range = 0; // 0 hôm nay, 1 hôm qua, 7 = 7 ngày
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _r;

  static final _df = DateFormat('yyyy-MM-dd');
  static final _hm = DateFormat('HH:mm');
  static final _dhm = DateFormat('dd/MM HH:mm');

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
      if (res['isSuccess'] == true && res['data'] is Map) {
        _r = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = res['message']?.toString() ?? 'Không tải được báo cáo';
      }
    });
  }

  static Color _healthColor(String? h) => switch (h) {
        'green' => SboxColors.successText,
        'yellow' => const Color(0xFFE6A100),
        'red' => const Color(0xFFD32F2F),
        _ => SboxColors.slate500,
      };

  static DateTime? _dt(dynamic v) {
    final s = v?.toString();
    if (s == null || s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    // Server trả giờ VN (đã cộng 7h) dưới dạng UTC — hiển thị đúng con số.
    return d?.toUtc();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Mạng cửa hàng')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
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
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(tr(_error!))))
            else if (_r != null)
              ..._content(_r!),
            const SizedBox(height: 16),
            Text(
              tr('Cách đo: mỗi máy đang mở màn bán hàng tự ping máy chủ 30 giây / lần, đếm lệnh gọi lỗi, số lần '
                  'rớt kết nối tức thời, thử cổng máy in LAN 2 phút / lần và sóng Wi‑Fi. Gom 5 phút gửi lên; '
                  'mất mạng thì lưu lại gửi sau. Giữ 35 ngày.'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate500, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> r) {
    final verdict = r['verdict']?.toString();
    final color = verdict == 'insufficient' ? SboxColors.slate500 : _healthColor(verdict);
    final p95 = r['latencyP95Ms'];
    final print = Map<String, dynamic>.from(r['print'] as Map? ?? {});
    final hours = (r['hours'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    final devices = (r['devices'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    final outages = (r['outages'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    final recs = (r['recommendations'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    return [
      Card(
        color: color.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withOpacity(0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text(
                  verdict == 'insufficient' ? '—' : '${r['score'] ?? 0}',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(r['verdictText']?.toString() ?? ''),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
                    ),
                    if ((r['peakNote']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(tr(r['peakNote'].toString()), style: const TextStyle(fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _kpi('Thiết bị', '${r['deviceCount'] ?? 0}'),
          _kpi('Lỗi gọi máy chủ', '${r['failPct'] ?? 0}%'),
          _kpi('Độ trễ (95%)', p95 == null ? '—' : '$p95 ms'),
          _kpi('Mất kết nối', '${r['outageCount'] ?? 0} lần · ${((r['outageSeconds'] ?? 0) as num) ~/ 60} phút'),
          _kpi('Rớt realtime', '${r['disconnects'] ?? 0} lần'),
          _kpi('Phiếu in xong (95%)', print['p95Sec'] == null ? '—' : '${print['p95Sec']} giây'),
        ],
      ),
      const SizedBox(height: 12),
      _section('Nên làm gì', [
        for (final x in recs)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              x['level'] == 'high'
                  ? Icons.error_outline
                  : x['level'] == 'info'
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
              color: x['level'] == 'high'
                  ? const Color(0xFFD32F2F)
                  : x['level'] == 'info'
                      ? SboxColors.successText
                      : const Color(0xFFE6A100),
            ),
            title: Text(tr(x['title']?.toString() ?? ''), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr(x['detail']?.toString() ?? '')),
          ),
      ]),
      if (hours.isNotEmpty) _section('Theo giờ (cột = số đơn · màu = mạng)', [_hourChart(hours)]),
      _section('Mất kết nối (${outages.length})', [
        if (outages.isEmpty)
          Text(tr('Không có lần mất kết nối nào đáng kể.'), style: const TextStyle(color: SboxColors.slate500)),
        for (final o in outages.take(30))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(o['isAgent'] == true ? Icons.print : Icons.wifi_off, color: const Color(0xFFD32F2F)),
            title: Text(tr('${o['deviceName'] ?? o['deviceId']} · ${o['kind']}')),
            subtitle: Text(tr(
                '${_dt(o['startVn']) == null ? '' : _dhm.format(_dt(o['startVn'])!)} · ${_dur(o['seconds'])}'
                '${o['isAgent'] == true ? ' · máy giữ máy in (Agent)' : ''}')),
          ),
      ]),
      _section('Thiết bị (${devices.length})', [
        for (final d in devices) _deviceTile(d),
      ]),
      _section('Lệnh in qua mạng', [
        Text(tr(
          'Tổng ${print['total'] ?? 0} · in xong ${print['completed'] ?? 0} · lỗi ${print['failed'] ?? 0} · '
          'hủy ${print['cancelled'] ?? 0} (Agent tắt ${print['staleQueued'] ?? 0}, có thể đã in '
          '${print['stuckNoRequeue'] ?? 0}) · thời gian in 50% ${print['p50Sec'] ?? '—'}s / 95% ${print['p95Sec'] ?? '—'}s',
        )),
      ]),
    ];
  }

  static String _dur(dynamic sec) {
    final s = (sec as num?)?.toInt() ?? 0;
    if (s < 60) return '$s giây';
    final m = s ~/ 60;
    return m < 60 ? '$m phút' : '${m ~/ 60} giờ ${m % 60} phút';
  }

  Widget _kpi(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: PosTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(label), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(title), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...children,
            ],
          ),
        ),
      );

  Widget _hourChart(List<Map<String, dynamic>> hours) {
    final maxOrders = hours.map((h) => (h['orders'] as num?)?.toInt() ?? 0).fold<int>(1, (a, b) => b > a ? b : a);
    final multiDay = hours.isNotEmpty &&
        _dt(hours.first['hourVn'])?.day != _dt(hours.last['hourVn'])?.day;
    return SizedBox(
      height: 150,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final h in hours)
            Tooltip(
              message: tr(
                '${_dt(h['hourVn']) == null ? '' : (multiDay ? _dhm : _hm).format(_dt(h['hourVn'])!)}\n'
                'Đơn: ${h['orders']} · thiết bị: ${h['devices']}\n'
                'Lỗi: ${h['failPct']}% · trễ 95%: ${h['latencyP95Ms'] ?? '—'} ms\n'
                'Mất mạng lâu nhất: ${_dur(h['maxDeviceOfflineSec'])} · rớt realtime: ${h['disconnects']}\n'
                'Lệnh in: ${h['printJobs']} · in xong 95%: ${h['printP95Sec'] ?? '—'}s',
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${h['orders'] ?? 0}', style: const TextStyle(fontSize: 9, color: SboxColors.slate500)),
                    Container(
                      width: 18,
                      height: 8 + 100.0 * (((h['orders'] as num?)?.toInt() ?? 0) / maxOrders),
                      decoration: BoxDecoration(
                        color: _healthColor(h['health']?.toString()),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _dt(h['hourVn']) == null ? '' : DateFormat(multiDay ? 'd/M\nH' : 'H').format(_dt(h['hourVn'])!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _deviceTile(Map<String, dynamic> d) {
    final rssi = d['wifiRssi'];
    final conn = switch (d['connType']?.toString()) {
      'wifi' => 'Wi‑Fi${rssi == null ? '' : ' $rssi dBm'}',
      'ethernet' => 'Dây LAN',
      'mobile' => '4G',
      'web' => 'Trình duyệt',
      _ => 'Không rõ',
    };
    final last = _dt(d['lastSeenVn']);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        d['isAgent'] == true ? Icons.print : Icons.devices_other,
        color: _healthColor(d['health']?.toString()),
      ),
      title: Text(tr('${d['deviceName'] ?? d['deviceId']}${d['isAgent'] == true ? ' · Agent' : ''}'),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(tr(
        '$conn · lỗi ${d['failPct']}% · trễ 95% ${d['latencyP95Ms'] ?? '—'} ms · mất mạng ${_dur(d['offlineSec'])} '
        '(${d['outages']} lần) · rớt realtime ${d['disconnects']}'
        '${((d['printerChecks'] as num?) ?? 0) > 0 ? ' · máy in LAN lỗi ${d['printerFailed']}/${d['printerChecks']}' : ''}'
        '${last == null ? '' : ' · gửi lúc ${_dhm.format(last)}'}',
      )),
    );
  }

  Future<void> _quickTest() async {
    final progress = ValueNotifier<(double, String)>((0, 'Bắt đầu'));
    NetworkQuickTestResult? result;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Kiểm tra mạng')),
        content: ValueListenableBuilder<(double, String)>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v.$1),
              const SizedBox(height: 10),
              Text(tr(v.$2)),
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
    final color = _healthColor(r.verdict);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              r.verdict == 'green' ? Icons.check_circle : Icons.warning_amber_rounded,
              color: color,
            ),
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
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr(
                  'Ping: ${r.pingSent - r.pingFailed}/${r.pingSent} OK · trễ 50% ${r.p50 ?? '—'} ms · 95% ${r.p95 ?? '—'} ms\n'
                  'Tải về: ${r.downKbps == null ? 'lỗi' : '${(r.downKbps! / 1000).toStringAsFixed(1)} Mbit/s'} · '
                  'tải lên: ${r.upKbps == null ? 'lỗi' : '${(r.upKbps! / 1000).toStringAsFixed(1)} Mbit/s'}\n'
                  'Giờ đông giả lập: ${r.burstOk}/${r.burstSent} OK · trễ 95% ${r.burstP95 ?? '—'} ms\n'
                  'Kết nối tức thời: ${r.realtimeConnected ? 'đang nối' : 'mất'}'
                  '${r.connType == null ? '' : ' · ${r.connType}${r.wifiRssi == null ? '' : ' ${r.wifiRssi} dBm'}'}'
                  '${r.printers.isEmpty ? '' : '\nMáy in LAN: ${r.printers.map((p) => '${p.name} ${p.ms == null ? 'LỖI' : '${p.ms} ms'}').join(' · ')}'}',
                )),
                const SizedBox(height: 10),
                for (final a in r.advice)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${tr(a)}'),
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
