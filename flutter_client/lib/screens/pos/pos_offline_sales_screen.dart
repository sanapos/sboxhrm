import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../utils/api_datetime.dart';
import '../../providers/permission_provider.dart';
import '../../utils/pos_report_export.dart';
import '../../widgets/pos/reports/pos_health_widgets.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import '../../services/api_service.dart';
import '../../services/pos_network_monitor.dart';
import '../../services/pos_offline_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Bán offline: đơn offline trên máy này (chờ / đã gửi / lỗi) + kiểm soát cửa hàng (lịch sử cài app,
/// số hóa đơn offline đã cấp mà không về máy chủ, số nhảy cóc).
/// Trình bày cho người không chuyên: kết luận đèn xanh / vàng / đỏ, việc cần xử lý kèm cách làm, đồ thị.
class PosOfflineSalesScreen extends StatefulWidget {
  const PosOfflineSalesScreen({super.key});

  @override
  State<PosOfflineSalesScreen> createState() => _PosOfflineSalesScreenState();
}

class _PosOfflineSalesScreenState extends State<PosOfflineSalesScreen> {
  final _api = ApiService();
  final _pngKey = GlobalKey();
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _dt = DateFormat('dd/MM HH:mm');
  Map<String, dynamic>? _audit;
  String? _auditError;
  bool _loadingAudit = true;
  bool _syncing = false;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAudit());
  }

  Future<void> _loadAudit() async {
    setState(() => _loadingAudit = true);
    final res = await _api.getOfflineAudit(days: _days);
    if (!mounted) return;
    setState(() {
      _loadingAudit = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _audit = Map<String, dynamic>.from(res['data'] as Map);
        _auditError = null;
      } else {
        _auditError = res['message']?.toString() ?? 'Không tải được';
      }
    });
  }

  Future<void> _syncNow({bool retryErrors = false}) async {
    setState(() => _syncing = true);
    if (retryErrors) {
      await PosOfflineService.instance.retryErrors();
    } else {
      await PosOfflineService.instance.syncAll();
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    unawaited(_loadAudit());
  }

  String get _periodLabel => '$_days ngày gần nhất';

  static num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  static List<Map<String, dynamic>> _maps(dynamic v) =>
      (v as List? ?? const []).whereType<Map>().map(Map<String, dynamic>.from).toList();

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<PermissionProvider>().canEdit('PosPrinters');
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Bán offline & kiểm soát')),
        actions: [
          IconButton(
            tooltip: tr('Xuất PNG'),
            onPressed: () =>
                unawaited(PosReportExport.png(context: context, key: _pngKey, filePrefix: 'POS_BanOffline')),
            icon: const Icon(Icons.image_outlined),
          ),
          IconButton(
            tooltip: tr('Xuất Excel'),
            onPressed: _audit == null ? null : () => unawaited(_exportExcel()),
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: () {
              setState(() {});
              unawaited(_loadAudit());
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: PosReportPngCapture(
        pngKey: _pngKey,
        title: 'Bán offline & kiểm soát',
        periodLabel: _periodLabel,
        child: _body(canManage),
      ),
    );
  }

  Future<void> _exportExcel() async {
    final a = _audit ?? const {};
    final sales = _maps(a['sales']);
    final alerts = _maps(a['alerts']);
    await PosReportExport.excel(
      context: context,
      title: 'Bán offline & kiểm soát',
      sheetName: 'Ban offline',
      filePrefix: 'POS_BanOffline',
      periodLabel: _periodLabel,
      headers: const ['Số HĐ offline', 'Mã HĐ', 'Bán lúc', 'Gửi lên lúc', 'Trễ (phút)', 'Tổng', 'Máy', 'Người tạo', 'Trạng thái'],
      rows: [
        for (final s in sales)
          [
            '${s['offlineNo'] ?? ''}', '${s['orderNo'] ?? ''}', _fmt(s['offlineAt']), _fmt(s['syncedAt']),
            _n(s['delayMinutes']), _n(s['total']), '${s['device'] ?? ''}', '${s['createdBy'] ?? ''}',
            switch ('${s['status']}') { 'Completed' => 'Hoàn thành', 'Cancelled' => 'Đã hủy', 'Draft' => 'Phiếu tạm', final x => x },
          ],
      ],
      summaryLines: [
        if (a['verdictText'] != null) 'Kết luận: ${a['verdictText']}',
        for (final al in alerts)
          'Cảnh báo: ${al['device'] ?? ''} — ${al['text'] ?? ''}${al['range'] == null ? '' : ' (${al['range']})'}'
              '${al['action'] == null ? '' : ' → Cách xử lý: ${al['action']}'}',
      ],
    );
  }

  Widget _body(bool canManage) {
    final off = PosOfflineService.instance;
    final mon = PosNetworkMonitor.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([mon.reachable, off.pendingSales, off.errorSales, off.pendingCarts]),
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: _loadAudit,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              ..._storeSection(),
              _thisDevice(canManage),
              _deviceSales(),
              const PosHealthGlossary(entries: [
                ('Bán offline', 'Khi mất mạng, máy POS Android vẫn thu tiền mặt và in hóa đơn tạm; có mạng lại thì tự gửi đơn lên máy chủ.'),
                ('Số HĐ offline (OFF-000123)', 'Máy chủ cấp trước cho từng máy một dải số. Mỗi đơn offline dùng một số — '
                    'nhờ vậy chủ quán biết có đơn nào «biến mất» không.'),
                ('Nhảy cóc', 'Có số đã dùng (đã in cho khách) mà đơn không về máy chủ. Ví dụ có OFF-1 và OFF-3 nhưng thiếu OFF-2.'),
                ('Chờ gửi', 'Đơn bán lúc mất mạng còn nằm trên máy, chưa lên máy chủ. Có mạng lại sẽ tự gửi trong 1 phút.'),
                ('Cài lại app / xóa dữ liệu', 'Làm mất đơn chưa gửi trên máy. Hệ thống nhận ra vì mã máy giữ nguyên qua lần cài lại.'),
                ('Giả lập mất mạng', 'Cho chủ quán / quản lý tập quy trình bán offline mà không cần rút dây mạng.'),
              ]),
            ],
          ),
        );
      },
    );
  }

  // ── Kiểm soát cửa hàng ─────────────────────────────────────────────────────

  List<Widget> _storeSection() {
    final chips = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        children: [
          for (final d in const [7, 30, 90])
            ChoiceChip(
              label: Text(tr('$d ngày')),
              selected: _days == d,
              onSelected: (_) {
                setState(() => _days = d);
                unawaited(_loadAudit());
              },
            ),
        ],
      ),
    );
    if (_loadingAudit) {
      return [chips, const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))];
    }
    if (_auditError != null || _audit == null) {
      return [
        chips,
        PosHealthHero(
          status: 'none',
          title: 'Không xem được báo cáo kiểm soát',
          detail: '${_auditError ?? 'Không tải được'}. Phần kiểm soát cửa hàng chỉ chủ / quản lý xem được; '
              'phần «Máy này» bên dưới vẫn dùng bình thường.',
        ),
      ];
    }
    final a = _audit!;
    final s = Map<String, dynamic>.from(a['summary'] as Map? ?? {});
    final alerts = _maps(a['alerts']);
    final blocks = _maps(a['blocks']);
    final devices = _maps(a['devices']);
    final sales = _maps(a['sales']);
    final daily = _maps(a['daily']);
    final delayBuckets = _maps(a['delayBuckets']);
    // Máy chủ cũ chưa có «verdict» → tự suy từ số cảnh báo.
    final high = _n(s['alerts']).toInt();
    final verdict = a['verdict']?.toString() ?? (high > 0 ? 'red' : 'green');
    final verdictText = a['verdictText']?.toString() ??
        (high > 0 ? 'Có $high dấu hiệu bất thường — cần kiểm tra ngay' : 'Không có bất thường');
    final gaps = _n(s['gaps']).toInt();
    final pendingOnDevices = _n(s['pendingOnDevices']).toInt();
    final avgDelay = s['avgDelayMinutes'] as num?;

    return [
      chips,
      PosHealthHero(
        status: verdict == 'off' ? 'none' : verdict,
        title: verdictText,
        detail: a['verdictDetail']?.toString(),
        note: (a['settings'] as Map?)?['enabled'] == true
            ? 'Cửa hàng đang BẬT bán offline (tối đa ${(a['settings'] as Map)['maxHours']} giờ mất mạng).'
            : 'Cửa hàng đang TẮT bán offline.',
      ),
      PosHealthKpiGrid(items: [
        PosHealthKpi('Đơn bán offline', '${_n(s['offlineSales'])} đơn',
            hint: 'Trong $_days ngày · đã về máy chủ', icon: Icons.receipt_long),
        PosHealthKpi('Tiền bán offline', '${_money.format(_n(s['offlineTotal']))} đ',
            hint: 'Đối chiếu với tiền mặt két ca', icon: Icons.payments_outlined),
        PosHealthKpi('Số HĐ nhảy cóc', '$gaps số',
            status: gaps == 0 ? 'green' : 'red', hint: 'Đã in cho khách mà đơn không về', icon: Icons.report_gmailerrorred),
        PosHealthKpi('Đơn còn nằm trên máy', '$pendingOnDevices đơn',
            status: pendingOnDevices == 0 ? 'green' : 'yellow', hint: 'Chưa gửi về máy chủ', icon: Icons.cloud_off),
        PosHealthKpi('Thời gian chờ gửi (trung bình)', avgDelay == null ? '—' : _minutes(avgDelay),
            status: avgDelay == null ? null : PosHealth.level(avgDelay, 60, 24 * 60),
            hint: 'Từ lúc bán tới lúc về máy chủ', icon: Icons.schedule),
        PosHealthKpi('Số HĐ đã cấp / đã dùng', '${_n(s['serialsIssued'])} / ${_n(s['serialsUsed'])}',
            hint: '${_n(s['devices'])} máy · cài lại app ${_n(s['reinstalls'])} lần', icon: Icons.confirmation_number_outlined),
      ]),
      PosHealthSection(
        title: 'Việc cần xử lý',
        subtitle: 'Việc «Làm ngay» có thể là mất doanh thu — xử lý trong ngày.',
        children: [
          PosHealthActionList(
            emptyText: 'Không có việc gì cần xử lý.',
            items: [
              for (final x in alerts)
                PosHealthAction(
                  level: x['level']?.toString() ?? 'info',
                  title: '${x['device'] ?? ''}: ${x['text'] ?? ''}',
                  detail: x['range']?.toString(),
                  howTo: x['action']?.toString(),
                ),
            ],
          ),
        ],
      ),
      if (daily.any((d) => _n(d['count']) > 0)) _dailySection(daily),
      if (delayBuckets.any((b) => _n(b['count']) > 0))
        PosHealthSection(
          title: 'Bao lâu đơn offline mới về máy chủ',
          subtitle: 'Càng nhiều đơn «dưới 5 phút» càng tốt. Đơn chờ lâu = máy để lâu không có mạng hoặc tắt app.',
          children: [
            PosHealthSegmentBar(unit: 'đơn', segments: [
              for (final (i, b) in delayBuckets.indexed)
                (
                  label: b['label']?.toString() ?? '',
                  value: _n(b['count']).toInt(),
                  color: const [PosHealth.green, Color(0xFF65A30D), PosHealth.yellow, PosHealth.red][math.min(i, 3)],
                ),
            ]),
          ],
        ),
      PosHealthSection(
        title: 'Dải số hóa đơn offline đã cấp (${blocks.length})',
        subtitle: 'Mỗi thanh là một dải số cấp cho một máy. Xanh = đã dùng và đã về; đỏ = nhảy cóc; xám = chưa dùng.',
        children: [
          if (blocks.isEmpty) Text(tr('Chưa cấp dải số nào.'), style: const TextStyle(color: SboxColors.slate500)),
          for (final b in blocks) _blockRow(b),
        ],
      ),
      PosHealthExpandable(
        title: 'Lịch sử cài app theo máy (${devices.length})',
        subtitle: 'Cài lại app / xóa dữ liệu có thể làm mất đơn chưa gửi',
        icon: Icons.install_mobile,
        children: [
          if (devices.isEmpty) Text(tr('Chưa có dữ liệu.'), style: const TextStyle(color: SboxColors.slate500)),
          for (final d in devices) ...[
            Row(children: [
              Expanded(
                child: Text(tr('${d['deviceName'] ?? d['deviceKey']}'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              PosHealthChip(
                status: _n(d['reinstalls']) == 0 ? 'green' : 'yellow',
                text: _n(d['reinstalls']) == 0 ? 'Chưa cài lại' : 'Cài lại ${d['reinstalls']} lần',
              ),
            ]),
            for (final i in _maps(d['installs']))
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
                child: Text(tr(
                  '• ${i['platform'] ?? ''} ${i['appVersion'] ?? ''} · dùng từ ${_fmt(i['firstSeenAt'])} tới ${_fmt(i['lastSeenAt'])}'
                  '${(i['pendingOfflineSales'] as num? ?? 0) > 0 ? ' · còn ${i['pendingOfflineSales']} đơn chưa gửi' : ''}'
                  '${i['lastUserName'] == null ? '' : ' · ${i['lastUserName']}'}'
                  ' · mã ${_short(i['installId']?.toString())}',
                ), style: const TextStyle(fontSize: 12.5, height: 1.35)),
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
      PosHealthExpandable(
        title: 'Đơn offline đã về máy chủ (${sales.length})',
        subtitle: 'Bấm để xem từng đơn: giờ bán, giờ gửi, máy, người bán',
        icon: Icons.cloud_done_outlined,
        children: [
          if (sales.isEmpty) Text(tr('Chưa có đơn.'), style: const TextStyle(color: SboxColors.slate500)),
          for (final s in sales.take(100))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                s['status'] == 'Cancelled' ? Icons.block : Icons.receipt_long,
                color: _n(s['delayMinutes']) >= 24 * 60 ? PosHealth.yellow : SboxColors.slate500,
              ),
              title: Text(tr('${s['offlineNo']} > ${s['orderNo']} · ${_money.format(_n(s['total']))} đ')),
              subtitle: Text(tr(
                'Bán ${_fmt(s['offlineAt'])} · về máy chủ ${_fmt(s['syncedAt'])} (sau ${_minutes(_n(s['delayMinutes']))}) · '
                '${s['device'] ?? ''} · ${s['createdBy'] ?? ''}',
              )),
            ),
        ],
      ),
    ];
  }

  Widget _dailySection(List<Map<String, dynamic>> daily) {
    final points = [
      for (final d in daily)
        if (parseApiUtcDateTime(d['dateVn']) case final date?) (date: date.toUtc(), value: _n(d['total']).toDouble()),
    ];
    final days = daily.where((d) => _n(d['count']) > 0).length;
    final count = daily.fold<num>(0, (a, d) => a + _n(d['count']));
    return PosHealthSection(
      title: 'Tiền bán offline theo ngày',
      subtitle: 'Có bán offline $days ngày ($count đơn). Ngày có cột cao = ngày mất mạng lâu — nên xem lại mạng ngày đó.',
      children: [PosReportBarChart(points: points, height: 170, maxLabels: 7)],
    );
  }

  Widget _blockRow(Map<String, dynamic> b) {
    final size = _n(b['size']).toInt();
    final used = _n(b['used']).toInt();
    final gapCount = _n(b['gapCount'] ?? (b['gaps'] as List? ?? const []).length).toInt();
    final suspicious = (b['suspicious'] as List? ?? const []).map((e) => '$e').toList();
    final gaps = (b['gaps'] as List? ?? const []).map((e) => '$e').toList();
    final missing = (b['missingReported'] as List? ?? const []).map((e) => '$e').toList();
    final status = suspicious.isNotEmpty ? 'red' : 'green';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PosHealth.color(status).withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(tr('${b['deviceName'] ?? b['deviceKey']}'), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${b['from']} – ${b['to']}', style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              PosHealthChip(status: status, text: suspicious.isEmpty ? 'Khớp' : 'Bất thường'),
              if (b['installReplaced'] == true)
                Text(tr('· máy đã cài lại'), style: const TextStyle(fontSize: 12, color: PosHealth.yellow)),
            ],
          ),
          const SizedBox(height: 8),
          if (size > 0)
            PosHealthSegmentBar(height: 12, unit: 'số', segments: [
              (label: 'Đã dùng', value: used, color: PosHealth.green),
              (label: 'Nhảy cóc', value: gapCount, color: PosHealth.red),
              (label: 'Chưa dùng', value: math.max(0, size - used - gapCount), color: SboxColors.slate200),
            ])
          else
            Text(tr('Đã dùng $used${b['lastUsed'] == null ? '' : ' (tới ${b['lastUsed']})'}'),
                style: const TextStyle(fontSize: 12.5)),
          if (gaps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('Số nhảy cóc: ${gaps.join(', ')}'),
                  style: const TextStyle(fontSize: 12.5, color: PosHealth.red, fontWeight: FontWeight.w600)),
            ),
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('Máy báo đã bán nhưng chưa về: ${missing.join(', ')}'),
                  style: const TextStyle(fontSize: 12.5, color: PosHealth.red)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('Cấp lúc ${_fmt(b['reservedAt'])}${b['reservedBy'] == null ? '' : ' · ${b['reservedBy']}'}'),
                style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
          ),
        ],
      ),
    );
  }

  // ── Máy này ────────────────────────────────────────────────────────────────

  Widget _thisDevice(bool canManage) {
    final off = PosOfflineService.instance;
    final mon = PosNetworkMonitor.instance;
    final online = mon.reachable.value;
    final blocked = off.offlineSaleBlockedReason();
    final remaining = off.remainingSerials;
    final pending = off.pendingSales.value;
    final errors = off.errorSales.value;
    final ready = off.enabled && blocked == null;
    return PosHealthSection(
      title: 'Máy này',
      subtitle: 'Tình trạng bán offline trên chính máy đang cầm.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            PosHealthChip(
              status: online ? 'green' : 'red',
              text: online
                  ? 'Đang có mạng'
                  : 'Mất mạng${mon.offlineSince == null ? '' : ' từ ${DateFormat('HH:mm').format(mon.offlineSince!)}'}'
                      '${mon.simulateOffline ? ' (giả lập)' : ''}',
            ),
            PosHealthChip(
              status: !off.enabled ? 'none' : ready ? 'green' : 'yellow',
              text: !off.enabled ? 'Bán offline: TẮT' : ready ? 'Sẵn sàng bán offline' : 'Chưa bán offline được',
            ),
            PosHealthChip(
              status: errors > 0 ? 'red' : pending > 0 ? 'yellow' : 'green',
              text: errors > 0
                  ? '$errors đơn lỗi gửi'
                  : pending > 0
                      ? '$pending đơn chờ gửi'
                      : 'Không còn đơn chờ gửi',
            ),
          ],
        ),
        if (off.enabled && blocked != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PosHealth.yellow.withOpacity(0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: PosHealth.yellow, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(tr(blocked), style: const TextStyle(fontSize: 12.5, height: 1.35))),
              ],
            ),
          ),
        if (off.enabled) ...[
          const SizedBox(height: 10),
          Text(tr('Số hóa đơn offline còn lại trên máy: $remaining'),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (remaining / 50).clamp(0.0, 1.0),
              backgroundColor: SboxColors.slate200,
              valueColor: AlwaysStoppedAnimation(
                  remaining == 0 ? PosHealth.red : remaining < 15 ? PosHealth.yellow : PosHealth.green),
            ),
          ),
          Text(
            tr(remaining < 15
                ? 'Sắp hết — máy tự xin thêm số khi có mạng.'
                : 'Đủ cho khoảng $remaining đơn khi mất mạng.'),
            style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500),
          ),
        ],
        if (off.pendingCarts.value > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('${off.pendingCarts.value} giỏ hàng chưa lưu lên máy chủ (tự lưu khi có mạng).'),
                style: const TextStyle(fontSize: 12.5)),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _syncing || !online ? null : () => _syncNow(),
              icon: _syncing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(tr('Gửi ngay')),
            ),
            if (errors > 0)
              OutlinedButton.icon(
                onPressed: _syncing || !online ? null : () => _syncNow(retryErrors: true),
                icon: const Icon(Icons.replay),
                label: Text(tr('Gửi lại đơn lỗi')),
              ),
          ],
        ),
        if (canManage) ...[
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: mon.simulateOffline,
            onChanged: (v) => setState(() => mon.setSimulateOffline(v)),
            title: Text(tr('Giả lập mất mạng (tập bán offline)')),
            subtitle: Text(tr('Chỉ trên máy này, tự tắt sau 30 phút. Tắt là đơn offline tự gửi lên máy chủ.')),
          ),
        ],
        Text(
          tr('Mã máy ${_short(off.deviceKey)} · mã cài đặt ${_short(off.installId)}'
              '${off.restoredFromMirror ? ' · đã khôi phục đơn từ bản sao' : ''}'),
          style: const TextStyle(fontSize: 11, color: SboxColors.slate400),
        ),
      ],
    );
  }

  Widget _deviceSales() {
    final sales = PosOfflineService.instance.sales..sort((a, b) => b.seq.compareTo(a.seq));
    return PosHealthExpandable(
      title: 'Đơn offline trên máy này (${sales.length})',
      subtitle: 'Xanh = đã gửi · vàng = chờ gửi · đỏ = lỗi',
      icon: Icons.phone_android,
      children: [
        if (sales.isEmpty) Text(tr('Chưa có đơn bán offline.'), style: const TextStyle(color: SboxColors.slate500)),
        for (final r in sales.take(100))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              r.status == 'synced'
                  ? Icons.cloud_done
                  : r.status == 'error'
                      ? Icons.error_outline
                      : Icons.schedule,
              color: r.status == 'synced'
                  ? PosHealth.green
                  : r.status == 'error'
                      ? PosHealth.red
                      : PosHealth.yellow,
            ),
            title: Text(tr('${r.offlineNo} · ${_money.format(r.total)} đ${r.tableLabel == null ? '' : ' · ${r.tableLabel}'}')),
            subtitle: Text(tr(
              '${_dt.format(r.createdAt.toLocal())}${r.cashier == null ? '' : ' · ${r.cashier}'} · '
              '${r.status == 'synced' ? 'đã gửi > ${r.serverOrderNo ?? ''}' : r.status == 'error' ? 'LỖI: ${r.error}' : 'chờ gửi'}',
            )),
          ),
      ],
    );
  }

  static String _minutes(num m) {
    final v = m.round();
    if (v < 60) return '$v phút';
    if (v < 24 * 60) return '${v ~/ 60} giờ ${v % 60 == 0 ? '' : '${v % 60} phút'}'.trim();
    return '${v ~/ (24 * 60)} ngày ${(v % (24 * 60)) ~/ 60} giờ';
  }

  String _fmt(dynamic v) {
    // Giờ từ API là UTC (có / không có Z) → giờ máy.
    final d = parseApiUtcDateTime(v);
    return d == null ? '—' : _dt.format(d.toLocal());
  }

  static String _short(String? s) {
    final v = (s ?? '').trim();
    if (v.isEmpty) return '—';
    return v.length <= 10 ? v : '…${v.substring(v.length - 8)}';
  }
}
