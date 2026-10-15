import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../utils/api_datetime.dart';
import '../../providers/permission_provider.dart';
import '../../utils/pos_report_export.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import '../../services/api_service.dart';
import '../../services/pos_network_monitor.dart';
import '../../services/pos_offline_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Bán offline: đơn offline trên máy này (chờ / đã gửi / lỗi) + kiểm soát cửa hàng (lịch sử cài app,
/// số hóa đơn offline đã cấp mà không về máy chủ, số nhảy cóc).
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

  @override
  void initState() {
    super.initState();
    unawaited(_loadAudit());
  }

  Future<void> _loadAudit() async {
    setState(() => _loadingAudit = true);
    final res = await _api.getOfflineAudit(days: 30);
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

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<PermissionProvider>().canEdit('PosPrinters');
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Bán offline & kiểm soát')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
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
        periodLabel: '30 ngày gần nhất',
        child: _body(canManage),
      ),
    );
  }

  Future<void> _exportExcel() async {
    final a = _audit ?? const {};
    final sales = ((a['sales'] as List?) ?? const []).whereType<Map>().toList();
    final alerts = ((a['alerts'] as List?) ?? const []).whereType<Map>().toList();
    num n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
    await PosReportExport.excel(
      context: context,
      title: 'Bán offline & kiểm soát',
      sheetName: 'Ban offline',
      filePrefix: 'POS_BanOffline',
      periodLabel: '30 ngày gần nhất',
      headers: const ['Số HĐ offline', 'Mã HĐ', 'Bán lúc', 'Gửi lên lúc', 'Trễ (phút)', 'Tổng', 'Máy', 'Người tạo', 'Trạng thái'],
      rows: [
        for (final s in sales)
          [
            '${s['offlineNo'] ?? ''}', '${s['orderNo'] ?? ''}', _fmt(s['offlineAt']), _fmt(s['syncedAt']),
            n(s['delayMinutes']), n(s['total']), '${s['device'] ?? ''}', '${s['createdBy'] ?? ''}',
            switch ('${s['status']}') { 'Completed' => 'Hoàn thành', 'Cancelled' => 'Đã hủy', 'Draft' => 'Phiếu tạm', final x => x },
          ],
      ],
      summaryLines: [
        for (final al in alerts) 'Cảnh báo: ${al['device'] ?? ''} — ${al['text'] ?? ''}${al['range'] == null ? '' : ' (${al['range']})'}',
      ],
    );
  }

  Widget _body(bool canManage) {
    final off = PosOfflineService.instance;
    final mon = PosNetworkMonitor.instance;
    return AnimatedBuilder(
        animation: Listenable.merge([mon.reachable, off.pendingSales, off.errorSales, off.pendingCarts]),
        builder: (context, _) {
          final sales = off.sales..sort((a, b) => b.seq.compareTo(a.seq));
          final blocked = off.offlineSaleBlockedReason();
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              _card('Trên máy này', [
                _row('Kết nối máy chủ', mon.reachable.value
                    ? 'Đang có mạng'
                    : 'MẤT KẾT NỐI${mon.offlineSince == null ? '' : ' từ ${_dt.format(mon.offlineSince!)}'}'),
                _row('Cho bán offline', off.enabled ? 'BẬT (tối đa ${off.maxHours} giờ mất mạng)' : 'TẮT'),
                _row('Số HĐ offline còn lại', '${off.remainingSerials}'),
                if (off.enabled && blocked != null) _row('Hiện không bán offline được', blocked),
                _row('Đơn offline chờ gửi / lỗi', '${off.pendingSales.value} / ${off.errorSales.value}'),
                _row('Giỏ hàng chưa lưu lên máy chủ', '${off.pendingCarts.value}'),
                _row('Mã cài đặt / thiết bị',
                    '${_short(off.installId)} · ${_short(off.deviceKey)}${off.restoredFromMirror ? ' · đã khôi phục từ bản sao' : ''}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _syncing || !mon.reachable.value ? null : () => _syncNow(),
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(tr('Gửi ngay')),
                    ),
                    if (off.errorSales.value > 0)
                      OutlinedButton.icon(
                        onPressed: _syncing || !mon.reachable.value ? null : () => _syncNow(retryErrors: true),
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
                    title: Text(tr('Giả lập mất mạng (thử quy trình bán offline)')),
                    subtitle: Text(tr('Chỉ trên máy này, tự tắt sau 30 phút. Tắt là đơn offline tự gửi lên máy chủ.')),
                  ),
                ],
              ]),
              _card('Đơn offline trên máy này (${sales.length})', [
                if (sales.isEmpty)
                  Text(tr('Chưa có đơn bán offline.'), style: const TextStyle(color: SboxColors.slate500)),
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
                          ? SboxColors.successText
                          : r.status == 'error'
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFFE6A100),
                    ),
                    title: Text(tr('${r.offlineNo} · ${_money.format(r.total)}đ${r.tableLabel == null ? '' : ' · ${r.tableLabel}'}')),
                    subtitle: Text(tr(
                      '${_dt.format(r.createdAt.toLocal())}${r.cashier == null ? '' : ' · ${r.cashier}'} · '
                      '${r.status == 'synced' ? 'đã gửi → ${r.serverOrderNo ?? ''}' : r.status == 'error' ? 'LỖI: ${r.error}' : 'chờ gửi'}',
                    )),
                  ),
              ]),
              _auditSection(),
            ],
          );
        },
      );
  }

  Widget _auditSection() {
    if (_loadingAudit) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (_auditError != null || _audit == null) {
      return _card('Kiểm soát cửa hàng', [
        Text(tr(_auditError ?? 'Không tải được'), style: const TextStyle(color: SboxColors.slate500)),
      ]);
    }
    final a = _audit!;
    final summary = Map<String, dynamic>.from(a['summary'] as Map? ?? {});
    final alerts = (a['alerts'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    final devices = (a['devices'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    final blocks = (a['blocks'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    final sales = (a['sales'] as List? ?? []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card('Kiểm soát cửa hàng (30 ngày)', [
          _row('Đơn bán offline đã đồng bộ',
              '${summary['offlineSales'] ?? 0} đơn · ${_money.format((summary['offlineTotal'] as num?) ?? 0)}đ'),
          _row('Thiết bị / lần cài lại app', '${summary['devices'] ?? 0} / ${summary['reinstalls'] ?? 0}'),
          _row('Cảnh báo nghiêm trọng', '${summary['alerts'] ?? 0}'),
          const SizedBox(height: 6),
          for (final x in alerts)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                x['level'] == 'high' ? Icons.gpp_maybe : Icons.info_outline,
                color: x['level'] == 'high' ? const Color(0xFFD32F2F) : SboxColors.slate500,
              ),
              title: Text(tr('${x['device'] ?? ''}: ${x['text'] ?? ''}')),
              subtitle: x['range'] == null ? null : Text(tr(x['range'].toString())),
            ),
        ]),
        _card('Lịch sử cài app theo thiết bị', [
          if (devices.isEmpty) Text(tr('Chưa có dữ liệu.'), style: const TextStyle(color: SboxColors.slate500)),
          for (final d in devices) ...[
            Text(tr('${d['deviceName'] ?? d['deviceKey']} · cài lại ${d['reinstalls']} lần'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final i in (d['installs'] as List? ?? []).whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
                child: Text(tr(
                  '• ${_short(i['installId']?.toString())} · ${i['platform'] ?? ''} ${i['appVersion'] ?? ''} · '
                  'lần đầu ${_fmt(i['firstSeenAt'])} · gần nhất ${_fmt(i['lastSeenAt'])}'
                  '${i['osFirstInstallAt'] == null ? '' : ' · cài lúc ${_fmt(i['osFirstInstallAt'])}'}'
                  '${(i['pendingOfflineSales'] as num? ?? 0) > 0 ? ' · còn ${i['pendingOfflineSales']} đơn chưa gửi' : ''}'
                  '${i['lastUserName'] == null ? '' : ' · ${i['lastUserName']}'}',
                ), style: const TextStyle(fontSize: 12.5)),
              ),
            const SizedBox(height: 6),
          ],
        ]),
        _card('Dải số hóa đơn offline đã cấp', [
          if (blocks.isEmpty) Text(tr('Chưa cấp dải số nào.'), style: const TextStyle(color: SboxColors.slate500)),
          for (final b in blocks)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                (b['suspicious'] as List? ?? []).isEmpty ? Icons.confirmation_number_outlined : Icons.gpp_bad,
                color: (b['suspicious'] as List? ?? []).isEmpty ? SboxColors.slate500 : const Color(0xFFD32F2F),
              ),
              title: Text(tr('${b['from']} – ${b['to']} · ${b['deviceName'] ?? b['deviceKey']}')),
              subtitle: Text(tr(
                'Đã dùng ${b['used']}${b['lastUsed'] == null ? '' : ' (tới ${b['lastUsed']})'}'
                '${(b['gaps'] as List? ?? []).isEmpty ? '' : ' · nhảy cóc: ${(b['gaps'] as List).join(', ')}'}'
                '${(b['missingReported'] as List? ?? []).isEmpty ? '' : ' · máy báo đã bán chưa về: ${(b['missingReported'] as List).join(', ')}'}'
                '${b['installReplaced'] == true ? ' · máy đã cài lại' : ''}',
              )),
            ),
        ]),
        _card('Đơn offline đã đồng bộ (${sales.length})', [
          for (final s in sales.take(100))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(tr('${s['offlineNo']} → ${s['orderNo']} · ${_money.format((s['total'] as num?) ?? 0)}đ')),
              subtitle: Text(tr(
                'Bán ${_fmt(s['offlineAt'])} · gửi ${_fmt(s['syncedAt'])} (trễ ${s['delayMinutes']} phút) · '
                '${s['device'] ?? ''} · ${s['createdBy'] ?? ''}',
              )),
            ),
        ]),
      ],
    );
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

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 210,
              child: Text(tr(label), style: const TextStyle(color: SboxColors.slate500, fontSize: 13)),
            ),
            Expanded(child: Text(tr(value), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          ],
        ),
      );

  Widget _card(String title, List<Widget> children) => Card(
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
}
