import 'dart:async';
import '../../utils/export_permission_guard.dart';

import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/excel_report_builder.dart';
import '../../utils/file_saver.dart' as file_saver;
import '../../widgets/sbox/sbox_charts.dart';
import 'meal_ui.dart';

/// Báo cáo suất ăn: mỗi người ăn bao nhiêu suất (theo từng buổi), thành tiền, đã trả, còn phải thu;
/// biểu đồ số suất theo ngày; xuất Excel để thu tiền / trừ lương.
class MealReportView extends StatefulWidget {
  const MealReportView({super.key, this.onCollect});

  /// Mở màn công nợ để ghi nhận thu tiền (chỉ quản lý).
  final VoidCallback? onCollect;

  @override
  State<MealReportView> createState() => _MealReportViewState();
}

enum _Range { today, week, month, lastMonth, custom }

class _MealReportViewState extends State<MealReportView> {
  final _api = ApiService();
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  _Range _range = _Range.month;
  late DateTime _from;
  late DateTime _to;
  String? _department;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyRange(_Range.month, load: false);
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _applyRange(_Range r, {bool load = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (r) {
      case _Range.today:
        _from = today;
        _to = today;
      case _Range.week:
        _from = today.subtract(Duration(days: today.weekday - 1));
        _to = today;
      case _Range.month:
        _from = DateTime(now.year, now.month, 1);
        _to = today;
      case _Range.lastMonth:
        _from = DateTime(now.year, now.month - 1, 1);
        _to = DateTime(now.year, now.month, 0);
      case _Range.custom:
        break;
    }
    _range = r;
    if (load) _load();
  }

  Future<void> _pickCustom() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 31)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r == null) return;
    setState(() {
      _range = _Range.custom;
      _from = r.start;
      _to = r.end;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getMealReport(
        from: _from, to: _to, department: _department, search: _searchCtl.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true) {
        _data = res['data'] as Map<String, dynamic>?;
        _error = null;
      } else {
        _error = res['message']?.toString() ?? 'Không tải được báo cáo';
      }
    });
  }

  List<Map<String, dynamic>> _list(String key) => [
        for (final x in (_data?[key] as List? ?? const []))
          if (x is Map<String, dynamic>) x,
      ];

  String _rangeLabel() =>
      MealUi.sameDay(_from, _to) ? MealUi.dateLong(_from) : '${_d(_from)} – ${_d(_to)}';
  String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final t = _data?['totals'] as Map<String, dynamic>? ?? const {};
    final sessions = _list('sessions');
    final rows = _list('rows');
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final pad = c.maxWidth < 600 ? 12.0 : 20.0;
        final mobile = c.maxWidth < 760;
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 40),
          children: [
            _filters(),
            const SizedBox(height: 14),
            if (_loading && _data == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              MealUi.card(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)))
            else ...[
              MealUi.statGrid([
                MealUi.stat('Người ăn', '${MealUi.n(t['employees']).toInt()}', icon: Icons.people_alt_rounded),
                MealUi.stat('Tổng suất', '${MealUi.n(t['meals']).toInt()}',
                    icon: Icons.restaurant_rounded, color: SboxColors.violet),
                MealUi.stat('Thành tiền', MealUi.money(t['amount']),
                    icon: Icons.payments_rounded, color: SboxColors.warning),
                MealUi.stat('Đã thu', MealUi.money(t['paid']),
                    icon: Icons.task_alt_rounded, color: SboxColors.success),
                MealUi.stat('Còn phải thu', MealUi.money(t['balance']),
                    icon: Icons.receipt_long_rounded,
                    color: MealUi.n(t['balance']) > 0 ? SboxColors.danger : SboxColors.success),
              ], minWidth: 170),
              if (sessions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in sessions)
                    Chip(
                      avatar: Icon(MealUi.sessionIcon(s['name'].toString()), size: 16),
                      label: Text(
                          '${s['name']}: ${MealUi.n((t['bySession'] as Map?)?[s['id']]).toInt()} suất'),
                    ),
                ]),
              ],
              const SizedBox(height: 16),
              _dailyChart(sessions),
              const SizedBox(height: 16),
              MealUi.sectionTitle('Chi tiết theo nhân viên (${rows.length})',
                  icon: Icons.table_rows_rounded,
                  trailing: Wrap(spacing: 8, children: [
                    if (widget.onCollect != null)
                      TextButton.icon(
                        onPressed: widget.onCollect,
                        icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
                        label: Text(tr('Thu tiền ăn')),
                      ),
                    OutlinedButton.icon(
                      onPressed: rows.isEmpty ? null : () => _exportExcel(sessions, rows),
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: Text(tr('Xuất Excel')),
                    ),
                  ])),
              if (rows.isEmpty)
                MealUi.card(
                  child: Center(
                    child: Text(tr('Không có suất ăn trong khoảng đã chọn'),
                        style: const TextStyle(color: SboxColors.slate500)),
                  ),
                )
              else if (mobile)
                ...rows.map((r) => _mobileRow(r, sessions))
              else
                _table(rows, sessions),
            ],
          ],
        );
      }),
    );
  }

  Widget _filters() {
    final departments = [for (final d in (_data?['departments'] as List? ?? const [])) d.toString()];
    Widget chip(_Range r, String label) => ChoiceChip(
          label: Text(tr(label)),
          selected: _range == r,
          onSelected: (_) => setState(() => _applyRange(r)),
        );
    return MealUi.card(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          chip(_Range.today, 'Hôm nay'),
          chip(_Range.week, 'Tuần này'),
          chip(_Range.month, 'Tháng này'),
          chip(_Range.lastMonth, 'Tháng trước'),
          ActionChip(
            avatar: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(_range == _Range.custom ? _rangeLabel() : tr('Chọn khoảng ngày')),
            onPressed: _pickCustom,
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: tr('Tìm tên / mã nhân viên'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 450), _load);
              },
            ),
          ),
          if (departments.isNotEmpty || _department != null)
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                initialValue: _department,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('Bộ phận'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('Tất cả bộ phận'))),
                  for (final d in {...departments, if (_department != null) _department!})
                    DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  setState(() => _department = v);
                  _load();
                },
              ),
            ),
        ]),
      ]),
    );
  }

  static const _palette = [
    SboxColors.brand500,
    SboxColors.success,
    SboxColors.warning,
    SboxColors.violet,
    SboxColors.danger,
    SboxColors.slate500,
  ];

  Widget _dailyChart(List<Map<String, dynamic>> sessions) {
    final days = _list('byDay');
    if (days.length < 2) return const SizedBox.shrink();
    return MealUi.card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MealUi.sectionTitle('Số suất theo ngày', icon: Icons.stacked_bar_chart_rounded),
        SboxBarChart(
          labels: [
            for (final d in days)
              () {
                final dt = DateTime.tryParse(d['date'].toString()) ?? DateTime.now();
                return '${dt.day}/${dt.month}';
              }(),
          ],
          series: [
            for (var i = 0; i < sessions.length; i++)
              SboxSeries(
                name: sessions[i]['name'].toString(),
                values: [
                  for (final d in days) MealUi.n((d['bySession'] as Map?)?[sessions[i]['id']]).toDouble(),
                ],
                color: _palette[i % _palette.length],
              ),
          ],
          stacked: true,
          height: 230,
          maxLabels: 16,
          valueFormat: (v) => SboxFmt.number(v),
          axisFormat: (v) => SboxFmt.number(v),
        ),
      ]),
    );
  }

  Widget _table(List<Map<String, dynamic>> rows, List<Map<String, dynamic>> sessions) {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate600);
    return MealUi.card(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: const WidgetStatePropertyAll(SboxColors.slate50),
          columnSpacing: 22,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 52,
          columns: [
            const DataColumn(label: Text('MÃ NV', style: head)),
            const DataColumn(label: Text('HỌ TÊN', style: head)),
            const DataColumn(label: Text('BỘ PHẬN', style: head)),
            for (final s in sessions)
              DataColumn(numeric: true, label: Text(s['name'].toString().toUpperCase(), style: head)),
            const DataColumn(numeric: true, label: Text('TỔNG SUẤT', style: head)),
            const DataColumn(numeric: true, label: Text('SỐ NGÀY', style: head)),
            const DataColumn(numeric: true, label: Text('THÀNH TIỀN', style: head)),
            const DataColumn(numeric: true, label: Text('ĐÃ TRẢ', style: head)),
            const DataColumn(numeric: true, label: Text('CÒN NỢ', style: head)),
          ],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                DataCell(Text(r['code']?.toString() ?? '')),
                DataCell(Text(r['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(r['department']?.toString() ?? '')),
                for (final s in sessions) DataCell(Text('${MealUi.n((r['bySession'] as Map?)?[s['id']]).toInt()}')),
                DataCell(Text('${MealUi.n(r['meals']).toInt()}', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('${MealUi.n(r['days']).toInt()}')),
                DataCell(Text(MealUi.money(r['amount']))),
                DataCell(Text(MealUi.money(r['paid']), style: const TextStyle(color: SboxColors.success))),
                DataCell(Text(MealUi.money(r['balance']),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: MealUi.n(r['balance']) > 0 ? SboxColors.danger : SboxColors.slate500))),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _mobileRow(Map<String, dynamic> r, List<Map<String, dynamic>> sessions) {
    final balance = MealUi.n(r['balance']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MealUi.card(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: SboxColors.brand50,
              child: Text('${MealUi.n(r['meals']).toInt()}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.brand700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [r['code'], r['department']].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(MealUi.money(r['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(balance > 0 ? tr('Nợ ${MealUi.money(balance)}') : tr('Đã trả đủ'),
                  style: TextStyle(fontSize: 12, color: balance > 0 ? SboxColors.danger : SboxColors.success)),
            ]),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in sessions)
              if (MealUi.n((r['bySession'] as Map?)?[s['id']]) > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: SboxColors.slate100, borderRadius: BorderRadius.circular(99)),
                  child: Text('${s['name']}: ${MealUi.n((r['bySession'] as Map?)?[s['id']]).toInt()}',
                      style: const TextStyle(fontSize: 12)),
                ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _exportExcel(List<Map<String, dynamic>> sessions, List<Map<String, dynamic>> rows) async {
    if (!ensureCanExport(context, 'Meal')) return;
    final headers = [
      'Mã NV',
      'Họ tên',
      'Bộ phận',
      for (final s in sessions) s['name'].toString(),
      'Tổng suất',
      'Số ngày',
      'Thành tiền',
      'Đã trả',
      'Còn nợ',
    ];
    const sheetName = 'Bao cao suat an';
    final wb = ExcelReportBuilder.createWorkbook(sheetName: sheetName);
    final sh = wb[sheetName];
    final auth = context.read<AuthProvider>();
    final ctx = ExcelReportContext.resolve(
      token: auth.token,
      email: auth.user?.email,
      fullName: auth.user?.fullName,
    );
    final layout = ExcelReportBuilder.applyMeta(
      sh,
      title: 'BÁO CÁO SUẤT ĂN ${_d(_from)} - ${_d(_to)}',
      columnCount: headers.length,
      storeName: ctx.storeName,
      exportedBy: ctx.exportedBy,
      rowCount: rows.length,
    );
    ExcelReportBuilder.applyHeaderRow(sh, layout.headerRow, headers);
    var i = layout.dataStartRow;
    for (final r in rows) {
      ExcelReportBuilder.writeRow(sh, i++, [
        excel_lib.TextCellValue(r['code']?.toString() ?? ''),
        excel_lib.TextCellValue(r['name']?.toString() ?? ''),
        excel_lib.TextCellValue(r['department']?.toString() ?? ''),
        for (final s in sessions) excel_lib.IntCellValue(MealUi.n((r['bySession'] as Map?)?[s['id']]).toInt()),
        excel_lib.IntCellValue(MealUi.n(r['meals']).toInt()),
        excel_lib.IntCellValue(MealUi.n(r['days']).toInt()),
        excel_lib.DoubleCellValue(MealUi.n(r['amount']).toDouble()),
        excel_lib.DoubleCellValue(MealUi.n(r['paid']).toDouble()),
        excel_lib.DoubleCellValue(MealUi.n(r['balance']).toDouble()),
      ]);
    }
    final bytes = ExcelReportBuilder.encodeReport(wb);
    if (bytes == null) return;
    await file_saver.saveFileBytes(
      bytes,
      'bao-cao-suat-an-${MealUi.ymd(_from)}_${MealUi.ymd(_to)}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }
}
