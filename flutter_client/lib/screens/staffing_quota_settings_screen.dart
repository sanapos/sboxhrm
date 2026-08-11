import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/hrm/hrm_settings_mobile_kit.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_theme.dart';
import '../utils/staffing_quota_utils.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Thiết lập định mức nhân sự tối thiểu/tối đa theo ca, phòng ban, từng thứ T2–CN.
class StaffingQuotaSettingsScreen extends StatefulWidget {
  const StaffingQuotaSettingsScreen({super.key});

  @override
  State<StaffingQuotaSettingsScreen> createState() =>
      _StaffingQuotaSettingsScreenState();
}

class _StaffingQuotaSettingsScreenState
    extends State<StaffingQuotaSettingsScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _quotas = [];
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _departments = [];

  bool get _canEdit =>
      Provider.of<PermissionProvider>(context, listen: false)
          .canEdit('WorkSchedule');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getStaffingQuotas(),
        _api.getShifts(),
        _api.getDepartments(pageSize: 200, isActive: true),
      ]);
      final qResp = results[0] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          if (qResp['isSuccess'] == true && qResp['data'] is List) {
            _quotas = List<Map<String, dynamic>>.from(qResp['data']);
          }
          _shifts = (results[1] as List)
              .whereType<Map>()
              .map((s) => Map<String, dynamic>.from(s))
              .toList();
          final dResp = results[2] as Map<String, dynamic>;
          if (dResp['isSuccess'] == true) {
            final data = dResp['data'];
            final items = data is List ? data : (data?['items'] ?? []);
            _departments = List<Map<String, dynamic>>.from(items);
          }
        });
      }
    } catch (e) {
      debugPrint('StaffingQuotaSettings load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _weekdaySummary(Map<String, dynamic> q) {
    final rows = StaffingQuotaUtils.dailyRowsFromQuota(q);
    final parts = <String>[];
    for (var i = 0; i < 7; i++) {
      final row = rows[i];
      final min = row['minEmployees'];
      final max = row['maxEmployees'];
      parts.add('${StaffingQuotaUtils.weekdayLabels[i]}:$min-$max');
    }
    return parts.join(' · ');
  }

  Future<void> _deleteQuota(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa định mức?')),
        content: Text(tr('Thao tác này không thể hoàn tác.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await _api.deleteStaffingQuota(id);
    if (!mounted) return;
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(title: 'Đã xóa', message: tr('Định mức đã được xóa'));
      await _load();
    } else {
      appNotification.showError(
          title: 'Lỗi', message: result['message']?.toString() ?? 'Không thể xóa');
    }
  }

  void _openEditor({Map<String, dynamic>? existing}) {
    if (!_canEdit) return;

    String? shiftId = existing?['shiftTemplateId']?.toString() ??
        (_shifts.isNotEmpty ? _shifts.first['id']?.toString() : null);
    String? department = existing?['department']?.toString();
    if (department != null && department.isEmpty) department = null;
    var warningThreshold =
        (existing?['warningThreshold'] as num?)?.toInt() ?? 2;
    var dailyRows = StaffingQuotaUtils.dailyRowsFromQuota(existing);
    var defaultMin = (existing?['minEmployees'] as num?)?.toInt() ?? 1;
    var defaultMax = (existing?['maxEmployees'] as num?)?.toInt() ?? 10;
    var saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.groups, color: Color(0xFF7C3AED)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(existing == null ? 'Thêm định mức' : 'Sửa định mức'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('Cấu hình số nhân viên tối thiểu / tối đa cho từng thứ trong tuần.'),
                    style: TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: shiftId,
                    decoration: _fieldDeco('Ca làm việc'),
                    items: _shifts
                        .map((s) => DropdownMenuItem(
                              value: s['id']?.toString(),
                              child: Text(tr(s['name']?.toString() ?? '')),
                            ))
                        .toList(),
                    onChanged: existing == null
                        ? (v) => setDlg(() => shiftId = v)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    value: department,
                    decoration: _fieldDeco('Phòng ban / bộ phận'),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(tr('Tất cả phòng ban')),
                      ),
                      ..._departments.map((d) => DropdownMenuItem<String?>(
                            value: d['name']?.toString(),
                            child: Text(tr(d['name']?.toString() ?? '')),
                          )),
                    ],
                    onChanged: existing == null
                        ? (v) => setDlg(() => department = v)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: '$warningThreshold',
                    keyboardType: TextInputType.number,
                    decoration: _fieldDeco(
                      'Ngưỡng cảnh báo sắp đủ (còn ≤ N chỗ)',
                      helper: 'Dùng trên lịch làm việc để báo vàng trước khi đạt max',
                    ),
                    onChanged: (v) =>
                        warningThreshold = int.tryParse(v) ?? warningThreshold,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(tr('Định mức theo thứ'),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setDlg(() {
                          dailyRows = StaffingQuotaUtils.defaultWeeklyRows(
                            min: defaultMin,
                            max: defaultMax,
                          );
                        }),
                        child: Text(tr('Áp dụng mặc định'), style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F4F5),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10)),
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: 36, child: Text(tr('Thứ'), style: _hdr)),
                              Expanded(child: Text(tr('Tối thiểu'), style: _hdr, textAlign: TextAlign.center)),
                              Expanded(child: Text(tr('Tối đa'), style: _hdr, textAlign: TextAlign.center)),
                            ],
                          ),
                        ),
                        ...List.generate(7, (i) {
                          final row = dailyRows[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 36,
                                  child: Text(
                                    tr(StaffingQuotaUtils.weekdayLabels[i]),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        '${row['minEmployees']}',
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    decoration: _cellDeco(),
                                    onChanged: (v) => dailyRows[i] = {
                                      ...dailyRows[i],
                                      'minEmployees': int.tryParse(v) ?? 0,
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        '${row['maxEmployees']}',
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    decoration: _cellDeco(),
                                    onChanged: (v) => dailyRows[i] = {
                                      ...dailyRows[i],
                                      'maxEmployees': int.tryParse(v) ?? 0,
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton.icon(
              onPressed: saving || shiftId == null
                  ? null
                  : () async {
                      setDlg(() => saving = true);
                      final body = <String, dynamic>{
                        'shiftTemplateId': shiftId,
                        if (department != null) 'department': department,
                        'minEmployees': dailyRows.first['minEmployees'] ?? defaultMin,
                        'maxEmployees': dailyRows.first['maxEmployees'] ?? defaultMax,
                        'warningThreshold': warningThreshold,
                        'dailyQuotas': dailyRows,
                      };
                      final result = await _api.upsertStaffingQuota(body);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (result['isSuccess'] == true) {
                        appNotification.showSuccess(
                            title: 'Đã lưu', message: tr('Định mức nhân sự đã cập nhật'));
                        await _load();
                      } else {
                        appNotification.showError(
                            title: 'Lỗi',
                            message:
                                result['message']?.toString() ?? 'Không thể lưu');
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save, size: 16),
              label: Text(tr('Lưu')),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _hdr = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Color(0xFF71717A),
  );

  InputDecoration _fieldDeco(String label, {String? helper}) => InputDecoration(
        labelText: tr(label),
        helperText: trN(helper),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );

  InputDecoration _cellDeco() => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: HrmPageChrome.scaffoldBackground(context),
        body: LoadingWidget(message: tr('Đang tải định mức...')),
      );
    }

    final embeddedMobile = HrmSettingsMobileKit.active(context);
    final pagePad = embeddedMobile
        ? HrmSettingsMobileKit.pagePadding(context)
        : const EdgeInsets.all(16);

    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: pagePad,
          children: [
            if (!embeddedMobile)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: PosTheme.mobileCardDecoration(),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: PosTheme.kiotBlueLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.groups,
                          color: PosTheme.kiotBlue, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Định mức nhân sự theo ca'),
                              style: const TextStyle(
                                  color: PosTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                              tr('Min/Max từng thứ T2–CN · theo ca & phòng ban · cảnh báo trên Lịch làm việc'),
                              style: const TextStyle(
                                  color: PosTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (!embeddedMobile) const SizedBox(height: 12),
            if (_canEdit)
              Align(
                alignment: Alignment.centerRight,
                child: embeddedMobile
                    ? HrmSettingsAddButton(
                        label: 'Thêm định mức',
                        compact: true,
                        onPressed: () => _openEditor(),
                      )
                    : FilledButton.icon(
                        onPressed: () => _openEditor(),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(tr('Thêm định mức')),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                        ),
                      ),
              ),
            const SizedBox(height: 12),
            if (_quotas.isEmpty)
              Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(tr('Chưa có định mức. Thêm cấu hình để cảnh báo thiếu / thừa nhân sự trên lịch làm việc.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF71717A)),
                    ),
                  ),
                ),
              )
            else if (embeddedMobile ||
                HrmSettingsMobileKit.preferCardList(context))
              HrmSettingsEntityGrid(
                itemCount: _quotas.length,
                columns: 2,
                childAspectRatio: 0.95,
                itemBuilder: (context, index) => _buildQuotaTile(_quotas[index]),
              )
            else
              ..._quotas.map((q) => _buildQuotaCard(q)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotaTile(Map<String, dynamic> q) {
    final dept = q['department']?.toString();
    return HrmSettingsEntityTile(
      title: q['shiftName']?.toString() ?? 'Ca',
      subtitle: dept != null && dept.isNotEmpty ? dept : 'Tất cả PB',
      meta: _weekdaySummary(q),
      icon: Icons.groups,
      iconColor: const Color(0xFF7C3AED),
      menuItems: _canEdit
          ? [
              PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
              PopupMenuItem(value: 'delete', child: Text(tr('Xóa'))),
            ]
          : null,
      onMenuSelected: _canEdit
          ? (v) {
              if (v == 'edit') _openEditor(existing: q);
              if (v == 'delete') _deleteQuota(q['id'].toString());
            }
          : null,
      onTap: _canEdit ? () => _openEditor(existing: q) : null,
    );
  }

  Widget _buildQuotaCard(Map<String, dynamic> q) {
    final dept = q['department']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(
          tr('${q['shiftName'] ?? 'Ca'}${dept != null && dept.isNotEmpty ? ' · $dept' : ' · Tất cả PB'}'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('${tr('Cảnh báo sắp đủ: ≤ ')}${q['warningThreshold'] ?? 2} chỗ'),
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              tr(_weekdaySummary(q)),
              style: const TextStyle(fontSize: 10, color: Color(0xFF71717A)),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: _canEdit
            ? PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _openEditor(existing: q);
                  if (v == 'delete') _deleteQuota(q['id'].toString());
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('Xóa'))),
                ],
              )
            : null,
      ),
    );
  }
}
