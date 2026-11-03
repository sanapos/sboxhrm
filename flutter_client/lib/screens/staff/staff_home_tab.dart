import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import '../notifications_screen.dart';
import 'staff_entries.dart';
import 'staff_nav.dart';

/// Trang chủ app SBOX Nhân Viên: ca hôm nay, giờ vào / ra, nút chấm công,
/// thống kê công tháng này và ô thao tác nhanh. Dữ liệu từ `/api/dashboard/employee`.
class StaffHomeTab extends StatefulWidget {
  const StaffHomeTab({super.key, this.onOpenSchedule});

  /// Chuyển sang tab Lịch của khung [StaffShell].
  final VoidCallback? onOpenSchedule;

  @override
  State<StaffHomeTab> createState() => _StaffHomeTabState();
}

class _StaffHomeTabState extends State<StaffHomeTab> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.attendance.addListener(_load);
    ScreenRefreshNotifier.dashboard.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.attendance.removeListener(_load);
    ScreenRefreshNotifier.dashboard.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = _data == null);
    final r = await _api.getEmployeeDashboard(period: 'month');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && r['data'] is Map) {
        _data = Map<String, dynamic>.from(r['data'] as Map);
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Không tải được dữ liệu';
      }
    });
  }

  Map<String, dynamic>? _map(String key) {
    final v = _data?[key];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  static DateTime? _time(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  static String _hm(DateTime? t) => t == null
      ? '--:--'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _dm(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

  Future<void> _openPunch() async {
    await StaffEntries.punch.open(context);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final name = (user?.fullName ?? '').trim();
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.white,
        surfaceTintColor: SboxColors.white,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? tr('Xin chào') : '${tr('Xin chào')}, $name',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            if ((user?.position ?? user?.department ?? '').isNotEmpty)
              Text(
                user?.position ?? user?.department ?? '',
                style: const TextStyle(fontSize: 12, color: SboxColors.textMuted),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr('Thông báo'),
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => openStaffPage(
              context,
              title: 'Thông báo',
              child: const NotificationsScreen(),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _todayCard(),
            const SizedBox(height: 12),
            _statsRow(),
            const SizedBox(height: 16),
            _quickActions(),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SboxColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SboxColors.border),
        ),
        child: child,
      );

  Widget _todayCard() {
    if (_loading) {
      return _card(
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final shift = _map('todayShift');
    final next = _map('nextShift');
    final att = _map('currentAttendance');
    final status = att?['status']?.toString() ?? 'not-started';
    final checkIn = _time(att?['checkInTime']);
    final checkOut = _time(att?['checkOutTime']);
    final late = att?['isLate'] == true;
    final lateMin = att?['lateMinutes'];
    final canPunch = staffCanOpen(context, StaffEntries.punch.moduleCode);

    final (statusText, statusColor) = switch (status) {
      'checked-in' => ('Đang trong ca', SboxColors.success),
      'checked-out' => ('Đã ra ca', SboxColors.textSecondary),
      _ => ('Chưa chấm công', SboxColors.warning),
    };

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                tr('Hôm nay'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tr(statusText),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            shift == null
                ? tr('Hôm nay không có ca')
                : '${tr('Ca')} ${_hm(_time(shift['startTime']))} – ${_hm(_time(shift['endTime']))}'
                    '${(shift['description']?.toString() ?? '').isEmpty ? '' : ' · ${shift['description']}'}',
            style: const TextStyle(fontSize: 14, color: SboxColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _timeBox('Vào', _hm(checkIn))),
              const SizedBox(width: 10),
              Expanded(child: _timeBox('Ra', _hm(checkOut))),
            ],
          ),
          if (late) ...[
            const SizedBox(height: 8),
            Text(
              lateMin is num && lateMin > 0
                  ? '${tr('Đi muộn')} ${lateMin.round()} ${tr('phút')}'
                  : tr('Đi muộn'),
              style: const TextStyle(fontSize: 12, color: SboxColors.warning),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              tr(_error!),
              style: const TextStyle(fontSize: 12, color: SboxColors.textMuted),
            ),
          ],
          if (canPunch) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _openPunch,
                icon: const Icon(Icons.fingerprint),
                label: Text(
                  tr(status == 'checked-in' ? 'Chấm công ra' : 'Chấm công'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
          if (shift == null && next != null) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: widget.onOpenSchedule,
              child: Text(
                '${tr('Ca tiếp theo')}: ${_dm(_time(next['startTime']) ?? DateTime.now())} '
                '${_hm(_time(next['startTime']))} – ${_hm(_time(next['endTime']))}',
                style: const TextStyle(fontSize: 13, color: SboxColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeBox(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: SboxColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(label),
                style: const TextStyle(fontSize: 12, color: SboxColors.textMuted)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _statsRow() {
    final s = _map('attendanceStats');
    if (s == null) return const SizedBox.shrink();
    String n(String k) {
      final v = s[k];
      return v is num ? v.round().toString() : (v?.toString() ?? '0');
    }

    return Row(
      children: [
        Expanded(
          child: _stat('Ngày công', '${n('presentDays')}/${n('totalWorkDays')}'),
        ),
        const SizedBox(width: 10),
        Expanded(child: _stat('Đi muộn', n('lateCheckIns'))),
        const SizedBox(width: 10),
        Expanded(child: _stat('Giờ TB/ngày', s['averageWorkHours']?.toString() ?? '0')),
      ],
    );
  }

  Widget _stat(String label, String value) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              tr(label),
              style: const TextStyle(fontSize: 12, color: SboxColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );

  Widget _quickActions() {
    final items = [
      for (final e in StaffEntries.quickActions)
        if (staffCanOpen(context, e.moduleCode)) e,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            tr('Thao tác nhanh'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SboxColors.textSecondary,
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            for (final e in items)
              Material(
                color: SboxColors.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => e.open(context),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SboxColors.border),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(e.icon, color: e.color, size: 26),
                        const SizedBox(height: 6),
                        Text(
                          tr(e.title),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
