import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_einvoice.dart';
import '../../services/api_service.dart';
import '../../utils/pos_einvoice_actions.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/pos_report_open.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'pos_einvoice_provider_list_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
/// Quản lý vòng đời HĐĐT: danh sách, nháp, phát hành, xem lại, email, thay thế, hủy,
/// đồng bộ hàng loạt, tải danh sách từ hãng, mở trang quản lý của hãng, báo cáo.
class PosEInvoiceReportScreen extends StatefulWidget {
  const PosEInvoiceReportScreen({super.key});

  @override
  State<PosEInvoiceReportScreen> createState() =>
      _PosEInvoiceReportScreenState();
}

class _PosEInvoiceReportScreenState extends State<PosEInvoiceReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM HH:mm');
  final _searchCtrl = TextEditingController();

  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  String _status = 'all';
  bool _loading = true;
  String? _busyId;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _portal;
  bool _bulkSyncing = false;
  List<PosEInvoiceRow> _items = [];
  int _total = 0;

  static const _filters = <(String id, String label)>[
    ('all', 'Tất cả'),
    ('Issued', 'Đã xuất'),
    ('Draft', 'Nháp'),
    ('Pending', 'Chờ ký'),
    ('Failed', 'Lỗi'),
    ('Cancelled', 'Đã hủy'),
    ('replacement', 'Thay thế'),
    ('email', 'Đã gửi mail'),
    ('None', 'Chưa xuất'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final from = _time.from;
    final to = _time.to;
    final sumF = _api.getPosEInvoiceSummary(from: from, to: to);
    final listF = _api.getPosEInvoiceInvoices(
      from: from,
      to: to,
      status: _status,
      q: _searchCtrl.text,
      page: 1,
      pageSize: 80,
    );
    final reportF = _api.getPosEInvoiceReport(from: from, to: to);
    final portalF = _portal == null ? _api.getPosEInvoicePortal() : null;
    final sum = await sumF;
    final list = await listF;
    final report = await reportF;
    final portal = portalF == null ? null : await portalF;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (report['isSuccess'] == true && report['data'] is Map) {
        _report = Map<String, dynamic>.from(report['data'] as Map);
      }
      if (portal != null && portal['isSuccess'] == true && portal['data'] is Map) {
        _portal = Map<String, dynamic>.from(portal['data'] as Map);
      }
      _summary = sum['isSuccess'] == true && sum['data'] is Map
          ? Map<String, dynamic>.from(sum['data'] as Map)
          : null;
      if (list['isSuccess'] == true && list['data'] is Map) {
        final data = Map<String, dynamic>.from(list['data'] as Map);
        _total = (data['total'] as num?)?.toInt() ?? 0;
        final raw = data['items'] ?? data['Items'];
        _items = raw is List
            ? raw
                .whereType<Map>()
                .map((e) => PosEInvoiceRow.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [];
      } else {
        _items = [];
        _total = 0;
      }
    });
  }

  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  Future<void> _run(
    PosEInvoiceRow row,
    String title,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    setState(() => _busyId = row.id);
    final res = await action();
    if (!mounted) return;
    setState(() => _busyId = null);
    if (res['isSuccess'] == true) {
      final data = res['data'];
      final st = data is Map
          ? (data['eInvoiceStatus'] ?? data['EInvoiceStatus'])?.toString()
          : null;
      if (st == 'Failed') {
        NotificationOverlayManager().showError(
          title: '$title thất bại',
          message: data is Map
              ? (data['eInvoiceError'] ?? data['EInvoiceError'] ?? 'Nhà cung cấp từ chối')
                  .toString()
              : 'Nhà cung cấp từ chối',
        );
      } else {
        NotificationOverlayManager().showSuccess(
          title: title,
          message: tr(_resultNo(res) ?? row.orderNo),
        );
      }
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: '$title thất bại',
        message: res['message']?.toString() ?? 'Nhà cung cấp từ chối',
      );
      await _load();
    }
  }

  String? _resultNo(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is! Map) return null;
    return (data['eInvoiceNo'] ?? data['EInvoiceNo'])?.toString();
  }

  Future<String?> _prompt(String title, String hint, {String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr(hint)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            child: Text(tr('OK')),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return null;
    return text;
  }

  Future<void> _issue(PosEInvoiceRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Phát hành HĐĐT')),
        content: Text(tr('Xuất hóa đơn điện tử cho đơn ${row.orderNo}?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Không'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            child: Text(tr('Xuất')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(row, 'Đã xuất HĐĐT', () => _api.issuePosEInvoice(row.id));
  }

  Future<void> _draft(PosEInvoiceRow row) async {
    await _run(row, 'Đã lưu nháp HĐĐT', () => _api.draftPosEInvoice(row.id));
  }

  Future<void> _email(PosEInvoiceRow row) async {
    final mail = await _prompt(
      'Gửi hóa đơn qua email',
      'Email khách hàng',
      initial: row.buyerEmail ?? row.emailTo,
    );
    if (mail == null || !mounted) return;
    if (mail.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiếu email',
        message: tr('Nhập email khách để gửi hóa đơn'),
      );
      return;
    }
    await _run(row, 'Đã gửi email HĐĐT',
        () => _api.emailPosEInvoice(row.id, email: mail));
  }

  Future<void> _replace(PosEInvoiceRow row) async {
    final input = await PosEInvoiceActions.askReplace(context, row);
    if (input == null || !mounted) return;
    await _run(
      row,
      'Đã thay thế HĐĐT',
      () => _api.replacePosEInvoice(row.id,
          reason: input.reason, buyer: input.buyer),
    );
  }

  String get _providerName => posEInvoiceProviderName(
      _portal?['providerName']?.toString() ?? _portal?['provider']?.toString());

  Future<void> _syncAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đồng bộ hàng loạt')),
        content: Text(tr(
            'Cập nhật số hóa đơn / trạng thái (đã hủy, chờ ký, lỗi) từ $_providerName '
            'cho tối đa 100 đơn trong khoảng «${_time.displayLabel}».')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Không'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            child: Text(tr('Đồng bộ')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _bulkSyncing = true);
    final res = await _api.syncPosEInvoiceRange(from: _time.from, to: _time.to);
    if (!mounted) return;
    setState(() => _bulkSyncing = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      final d = Map<String, dynamic>.from(res['data'] as Map);
      final errors = (d['errors'] is List) ? (d['errors'] as List).join('\n') : '';
      final msg = 'Đã kiểm tra ${d['total']} đơn · thay đổi ${d['changed']} · lỗi ${d['failed']}'
          '${errors.isEmpty ? '' : '\n$errors'}';
      if (_num(d['failed']) > 0) {
        NotificationOverlayManager().showError(
          title: 'Đồng bộ xong, có lỗi',
          message: msg,
          duration: const Duration(seconds: 8),
        );
      } else {
        NotificationOverlayManager().showSuccess(title: 'Đã đồng bộ', message: msg);
      }
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Đồng bộ thất bại',
        message: res['message']?.toString() ?? 'Lỗi đồng bộ',
      );
    }
  }

  void _openProviderList() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PosEInvoiceProviderListScreen(
          initialTime: _time,
          portal: _portal,
        ),
      ),
    );
  }

  Widget _toolsBar() {
    Widget chip(IconData icon, String label, VoidCallback? onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ActionChip(
            avatar: Icon(icon, size: 16, color: PosTheme.kiotBlue),
            label: Text(tr(label), style: const TextStyle(fontSize: 12)),
            onPressed: onTap,
          ),
        );
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        children: [
          chip(Icons.open_in_new, 'Trang quản lý $_providerName',
              _portal == null ? null : () => PosEInvoiceActions.openPortal(_portal)),
          chip(Icons.cloud_download_outlined, 'Tải danh sách từ hãng',
              _openProviderList),
          chip(
            _bulkSyncing ? Icons.hourglass_top : Icons.sync,
            _bulkSyncing ? 'Đang đồng bộ…' : 'Đồng bộ hàng loạt',
            _bulkSyncing ? null : _syncAll,
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(PosEInvoiceRow row) async {
    final reason = await _prompt(
      'Hủy hóa đơn ${row.invoiceNo ?? row.orderNo}',
      'Lý do hủy / thỏa thuận',
      initial: 'Hủy hóa đơn theo yêu cầu',
    );
    if (reason == null || !mounted) return;
    await _run(
      row,
      'Đã hủy HĐĐT',
      () => _api.cancelPosEInvoice(row.id, reason: reason, agreementDesc: reason),
    );
  }

  Future<void> _sync(PosEInvoiceRow row) async {
    await _run(row, 'Đã đồng bộ HĐĐT', () => _api.syncPosEInvoice(row.id));
  }

  void _openActions(PosEInvoiceRow row) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        Widget tile(IconData icon, String label, VoidCallback onTap,
            {Color? color}) {
          return ListTile(
            leading: Icon(icon, color: color ?? PosTheme.kiotBlue),
            title: Text(tr(label)),
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${row.orderNo}${row.invoiceNo == null || row.invoiceNo!.isEmpty ? '' : ' · ${row.invoiceNo}'}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                    Text(
                      tr(posEInvoiceStatusLabel(row.status)),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: posEInvoiceStatusColor(row.status),
                      ),
                    ),
                  ],
                ),
              ),
              if (posEInvoiceCanView(row.status))
                tile(Icons.picture_as_pdf_outlined, 'Xem lại hóa đơn (PDF)',
                    () => PosEInvoiceActions.view(context, _api, row)),
              if (row.status == 'Issued')
                tile(Icons.share_outlined, 'Gửi HĐĐT qua ứng dụng khác (Zalo, email…)',
                    () => PosEInvoiceActions.share(
                        context, _api, PosEInvoiceTarget.fromRow(row))),
              if (posEInvoiceCanPreviewDraft(row.status)) ...[
                tile(Icons.preview_outlined, 'Xem bản nháp (chưa ký)',
                    () => PosEInvoiceActions.view(context, _api, row)),
                tile(Icons.ios_share, 'Gửi bản nháp cho khách kiểm tra',
                    () => PosEInvoiceActions.share(
                        context, _api, PosEInvoiceTarget.fromRow(row))),
              ],
              if (posEInvoiceCanIssue(row.status))
                tile(Icons.send_outlined, 'Phát hành / xuất lại', () => _issue(row)),
              if (posEInvoiceCanDraft(row.status) &&
                  _portal?['supportsDraft'] != false)
                tile(Icons.note_add_outlined, 'Xuất nháp (chưa ký)',
                    () => _draft(row)),
              if (posEInvoiceCanEmail(row.status))
                tile(
                  row.emailSent
                      ? Icons.mark_email_read_outlined
                      : Icons.email_outlined,
                  row.emailSent ? 'Gửi lại email khách' : 'Gửi email cho khách',
                  () => _email(row),
                ),
              if (posEInvoiceCanReplace(row.status))
                tile(Icons.find_replace, 'Thay thế hóa đơn', () => _replace(row)),
              if (posEInvoiceCanCancel(row.status))
                tile(Icons.cancel_outlined, 'Hủy hóa đơn', () => _cancel(row),
                    color: Colors.red.shade700),
              if (posEInvoiceCanSync(row.status))
                tile(Icons.sync, 'Đồng bộ từ nhà cung cấp', () => _sync(row)),
              tile(Icons.receipt_long_outlined, 'Mở đơn bán hàng', () {
                unawaited(PosReportOpen.sale(context, row.id));
              }),
              if (_portal != null)
                tile(Icons.open_in_new, 'Mở trang quản lý $_providerName',
                    () => PosEInvoiceActions.openPortal(_portal)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final issued = _num(_summary?['issuedCount']);
    final draft = _num(_summary?['draftCount']);
    final pending = _num(_summary?['pendingCount']);
    final failed = _num(_summary?['failedCount']);
    final cancelled = _num(_summary?['cancelledCount']);
    final emailed = _num(_summary?['emailSentCount']);

    return PosReportMobileScaffold(
      title: 'Quản lý hóa đơn điện tử',
      time: _time,
      onTimeChanged: (PosKiotTimeFilterState s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      onExportExcel: _items.isEmpty
          ? null
          : () => unawaited(PosReportExport.excel(
                context: context,
                title: 'Hóa đơn điện tử',
                sheetName: 'HDDT',
                filePrefix: 'POS_HDDT',
                periodLabel: _time.displayLabel,
                filterLabel: _status == 'all' ? null : _status,
                headers: const [
                  'Mã đơn',
                  'Số HĐĐT',
                  'Ngày',
                  'Khách',
                  'Trạng thái',
                  'Tổng',
                  'Email',
                  'Lỗi',
                ],
                rows: [
                  for (final r in _items)
                    [
                      r.orderNo,
                      r.invoiceNo ?? '',
                      r.saleDate == null
                          ? ''
                          : _dateFmt.format(r.saleDate!.toLocal()),
                      r.customerName ?? r.buyerName ?? '',
                      posEInvoiceStatusLabel(r.status),
                      r.total,
                      r.emailTo ?? r.buyerEmail ?? '',
                      r.error ?? '',
                    ],
                ],
                summaryLines: [
                  'Tổng $_total hóa đơn',
                  'Đã xuất: ${_num(_summary?['issuedCount']).toInt()}',
                ],
              )),
      filterBar: Column(
        children: [
          _toolsBar(),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(tr(f.$2),
                          style: const TextStyle(fontSize: 12)),
                      selected: _status == f.$1,
                      onSelected: (_) {
                        setState(() => _status = f.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('Tìm số đơn, số HĐ, khách, email'),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  onPressed: _load,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? ListView(
              children: const [
                SizedBox(
                  height: 240,
                  child: Center(
                    child: CircularProgressIndicator(color: PosTheme.kiotBlue),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Tổng hợp HĐĐT',
                  child: Column(
                    children: [
                      PosReportMetricTiles(
                        tiles: [
                          (
                            label: posEInvoiceStatusLabel('Issued'),
                            value: issued,
                            color: SboxColors.successText,
                          ),
                          (
                            label: 'Đã gửi email',
                            value: emailed,
                            color: PosTheme.kiotBlue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      PosReportMetricTiles(
                        tiles: [
                          (
                            label: 'Nháp / chờ ký',
                            value: draft + pending,
                            color: SboxColors.warningText,
                          ),
                          (
                            label: posEInvoiceStatusLabel('Failed'),
                            value: failed,
                            color: Colors.red.shade700,
                          ),
                          (
                            label: posEInvoiceStatusLabel('Cancelled'),
                            value: cancelled,
                            color: SboxColors.slate500,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: 'Doanh thu đã xuất',
                  child: PosReportMetricTiles(
                    moneyFmt: _moneyFmt,
                    tiles: [
                      (
                        label: 'Đã xuất',
                        value: _num(_summary?['issuedAmount']),
                        color: SboxColors.successText,
                      ),
                      (
                        label: 'Lỗi xuất',
                        value: _num(_summary?['failedAmount']),
                        color: Colors.red.shade700,
                      ),
                    ],
                  ),
                ),
                ..._reportCards(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    tr('Danh sách ${_items.length}/$_total hóa đơn'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('Không có hóa đơn trong khoảng thời gian này'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SboxColors.slate600),
                    ),
                  ),
                for (final row in _items) _rowCard(row),
              ],
            ),
    );
  }

  List<Widget> _reportCards() {
    final r = _report;
    if (r == null) return const [];
    final byProvider = (r['byProvider'] is List)
        ? (r['byProvider'] as List).whereType<Map>().toList()
        : const <Map>[];
    return [
      PosReportCard(
        title: 'Tỷ lệ xuất HĐĐT trên doanh thu',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PosReportMetricTiles(
              moneyFmt: _moneyFmt,
              tiles: [
                (
                  label: 'Doanh thu',
                  value: _num(r['revenue']),
                  color: PosTheme.kiotBlue,
                ),
                (
                  label: 'Đã xuất HĐĐT',
                  value: _num(r['issuedAmount']),
                  color: SboxColors.successText,
                ),
                (
                  label: 'Thuế GTGT đã xuất',
                  value: _num(_summary?['issuedVatAmount']),
                  color: SboxColors.slate700,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (_num(r['coveragePct']) / 100).clamp(0, 1).toDouble(),
              minHeight: 8,
              borderRadius: BorderRadius.circular(6),
              color: SboxColors.success,
              backgroundColor: SboxColors.slate200,
            ),
            const SizedBox(height: 6),
            Text(
              tr('${_num(r['coveragePct']).toStringAsFixed(1)}% doanh thu đã có HĐĐT · '
                  '${_num(r['replacementCount']).toInt()} HĐ thay thế · '
                  'chưa xuất ${_moneyFmt.format(_num(_summary?['noneAmount']))}'),
              style: TextStyle(fontSize: 12, color: SboxColors.slate700),
            ),
            if (byProvider.length > 1) ...[
              const SizedBox(height: 8),
              for (final p in byProvider)
                Text(
                  '${p['providerName']}: ${_num(p['count']).toInt()} HĐ · ${_moneyFmt.format(_num(p['amount']))}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ],
        ),
      ),
      ..._dailyChart(),
    ];
  }

  List<Widget> _dailyChart() {
    final daily = (_report?['daily'] is List)
        ? (_report!['daily'] as List).whereType<Map>().toList()
        : const <Map>[];
    if (daily.isEmpty) return const [];
    return [
      PosReportCard(
        title: 'HĐĐT theo ngày',
        child: Column(
          children: [
            for (final d in daily.reversed.take(14))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        d['date'].toString().substring(5).split('-').reversed.join('/'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${_num(d['issuedCount']).toInt()}/${_num(d['orders']).toInt()} đơn',
                        style: TextStyle(fontSize: 12, color: SboxColors.slate700),
                      ),
                    ),
                    Text(
                      _moneyFmt.format(_num(d['issuedAmount'])),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _rowCard(PosEInvoiceRow row) {
    final busy = _busyId == row.id;
    final dt = row.saleDate ?? row.issuedAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE8ECF0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : () => _openActions(row),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.orderNo,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: posEInvoiceStatusColor(row.status)
                                .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            tr(posEInvoiceStatusLabel(row.status)),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: posEInvoiceStatusColor(row.status),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if ((row.invoiceNo ?? '').isNotEmpty) 'HĐ ${row.invoiceNo}',
                        if (row.isReplacement) 'Thay thế ${row.originalNo ?? ''}',
                        if (row.emailSent) 'Đã gửi mail',
                        if ((row.provider ?? '').isNotEmpty) posEInvoiceProviderName(row.provider),
                      ].where((e) => e.trim().isNotEmpty).join(' · '),
                      style: TextStyle(
                          fontSize: 12, color: SboxColors.slate700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${row.customerName ?? row.buyerName ?? 'Khách lẻ'} · ${_moneyFmt.format(row.total)}${dt == null ? '' : ' · ${_dateFmt.format(dt.toLocal())}'}',
                      style: TextStyle(
                          fontSize: 12, color: SboxColors.slate600),
                    ),
                    if ((row.error ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          row.error!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: Colors.red.shade700),
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.more_vert, color: SboxColors.slate400),
            ],
          ),
        ),
      ),
    );
  }
}
