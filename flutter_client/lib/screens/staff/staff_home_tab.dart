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
  const StaffHomeTab({super.key, this.onOpenSchedule, this.onOpenMe});

  /// Chuyển sang tab Lịch của khung [StaffShell].
  final VoidCallback? onOpenSchedule;

  /// Chuyển sang tab Tôi (bấm ảnh đại diện).
  final VoidCallback? onOpenMe;

  @override
  State<StaffHomeTab> createState() => _StaffHomeTabState();
}

class _StaffHomeTabState extends State<StaffHomeTab> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.attendance.addListener(_load);
    ScreenRefreshNotifier.dashboard.addListener(_load);
    ScreenRefreshNotifier.notifications.addListener(_refreshUnread);
    _load();
    _refreshUnread();
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.attendance.removeListener(_load);
    ScreenRefreshNotifier.dashboard.removeListener(_load);
    ScreenRefreshNotifier.notifications.removeListener(_refreshUnread);
    super.dispose();
  }

  Future<void> _refreshUnread() async {
    try {
      final n = (await _api.getNotificationSummary())['unreadCount'];
      if (mounted) setState(() => _unread = n is int ? n : int.tryParse('$n') ?? 0);
    } catch (_) {}
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    return h < 11 ? 'Chào buổi sáng' : (h < 18 ? 'Chào buổi chiều' : 'Chào buổi tối');
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
    final role = user?.position ?? user?.department ?? '';
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.chrome,
        surfaceTintColor: Colors.transparent,
        title: Text(tr('Trang chủ')),
        actions: [
          IconButton(
            // Số trên chuông nói trong nhãn nút, không để trình đọc màn hình chỉ đọc «6».
            tooltip: _unread > 0 ? '${tr('Thông báo')} ($_unread)' : tr('Thông báo'),
            icon: ExcludeSemantics(
              child: Badge(
                isLabelVisible: _unread > 0,
                label: Text(_unread > 99 ? '99+' : '$_unread'),
                backgroundColor: SboxColors.danger,
                child: const Icon(Icons.notifications_none_rounded),
              ),
            ),
            onPressed: () async {
              await openStaffPage(
                context,
                title: 'Thông báo',
                child: const NotificationsScreen(),
              );
              _refreshUnread();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: SboxSpace.md, left: SboxSpace.xs),
            child: Semantics(
              button: true,
              label: tr('Tôi'),
              child: GestureDetector(
                onTap: widget.onOpenMe,
                child: StaffAvatar(name: name, radius: 18),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refreshUnread();
          await _load();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.xs, SboxSpace.lg, SboxSpace.lg),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(_greeting()), style: SboxType.smallStyle(SboxColors.textMuted)),
                Text(
                  name.isEmpty ? tr('Xin chào') : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SboxType.titleStyle(),
                ),
                if (role.isNotEmpty) Text(role, style: SboxType.smallStyle(SboxColors.textMuted)),
              ],
            ),
            const SizedBox(height: SboxSpace.md),
            _todayCard(),
            const SizedBox(height: SboxSpace.md),
            _statsRow(),
            const SizedBox(height: SboxSpace.md),
            StaffQuickGrid(
              title: 'Truy cập nhanh',
              icon: Icons.bolt_rounded,
              entries: StaffEntries.quickActions,
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => StaffCard(child: child);

  Widget _todayCard() {
    if (_loading) {
      return _card(
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    // Chưa tải được lần nào: không hiện «Chưa chấm công», «Hôm nay không có ca» như dữ liệu thật.
    if (_data == null) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(_error ?? 'Không tải được dữ liệu'),
              style: const TextStyle(fontSize: 14, color: SboxColors.textSecondary),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(tr('Thử lại')),
            ),
          ],
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
      // Không có ca hôm nay mà vẫn chấm vào: không ghi «trong ca».
      'checked-in' => (shift == null ? 'Đã chấm vào' : 'Đang trong ca', SboxColors.success),
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
              '${tr(_error!)} ${tr('Đang hiện dữ liệu lần tải trước.')}',
              style: const TextStyle(fontSize: 12, color: SboxColors.warning),
            ),
          ],
          if (canPunch) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _openPunch,
                icon: const Icon(Icons.fingerprint_rounded),
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
          color: SboxColors.page,
          borderRadius: SboxRadius.mdAll,
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

    // Không có lịch ca, máy chủ trả tổng = số ngày đã chấm («2/2» trông như đủ công): khi đó chỉ hiện số ngày.
    final present = n('presentDays');
    final total = n('totalWorkDays');
    final days = (int.tryParse(total) ?? 0) > (int.tryParse(present) ?? 0) ? '$present/$total' : present;
    return StaffCard(
      padding: const EdgeInsets.symmetric(vertical: SboxSpace.md),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(child: _stat('Ngày công', days)),
            const VerticalDivider(width: 1, color: SboxColors.divider),
            Expanded(child: _stat('Đi muộn', n('lateCheckIns'))),
            const VerticalDivider(width: 1, color: SboxColors.divider),
            Expanded(child: _stat('Giờ TB/ngày', s['averageWorkHours']?.toString() ?? '0')),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value, style: SboxType.titleStyle(SboxColors.brand700)),
          const SizedBox(height: 2),
          Text(
            tr(label),
            style: SboxType.captionStyle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
}
