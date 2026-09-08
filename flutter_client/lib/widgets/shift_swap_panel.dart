import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/hrm.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'hrm_page_chrome.dart';
import 'shift_swap_ui.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

enum _SwapListMode { all, respond, approve }

/// Panel đổi ca — dùng trong màn riêng hoặc tab Duyệt lịch làm việc.
class ShiftSwapPanel extends StatefulWidget {
  final bool embedded;

  const ShiftSwapPanel({
    super.key,
    this.embedded = false,
  });

  @override
  State<ShiftSwapPanel> createState() => ShiftSwapPanelState();
}

class ShiftSwapPanelState extends State<ShiftSwapPanel>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabs;
  bool _loading = true;

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _forMe = [];
  List<Map<String, dynamic>> _pendingApproval = [];
  List<Shift> _shifts = [];
  List<Map<String, dynamic>> _colleagues = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final swapAll = await _api.getShiftSwaps();
      final swapForMe = await _api.getShiftSwapsPendingForMe();
      final swapPending = await _api.getShiftSwapsPendingApproval();
      final shiftsRaw = await _api.getShifts();
      final colleaguesResp = await _api.getShiftSwapColleagues();

      if (!mounted) return;
      final myUserId =
          Provider.of<AuthProvider>(context, listen: false).user?.id;
      setState(() {
        if (swapAll['isSuccess'] == true) {
          _all = parseShiftSwapList(swapAll['data']);
        }
        if (swapForMe['isSuccess'] == true) {
          _forMe = parseShiftSwapList(swapForMe['data'])
              .where((s) =>
                  s['targetUserId']?.toString() == myUserId &&
                  (s['status']?.toString() == '0' ||
                      s['status']?.toString() == 'Pending'))
              .toList();
        }
        if (swapPending['isSuccess'] == true) {
          _pendingApproval = parseShiftSwapList(swapPending['data']);
        }
        _shifts = shiftsRaw
            .whereType<Map>()
            .map((s) => Shift.fromJson(Map<String, dynamic>.from(s)))
            .toList();
        if (colleaguesResp['isSuccess'] == true &&
            colleaguesResp['data'] is List) {
          _colleagues = List<Map<String, dynamic>>.from(colleaguesResp['data']);
        }
      });
    } catch (e) {
      debugPrint('ShiftSwapPanel load: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> reload() => _load();

  void showFlowHelp() => showShiftSwapFlowHelpDialog(context);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          labelColor: HrmPageChrome.primaryNavy,
          unselectedLabelColor: const Color(0xFF71717A),
          indicatorColor: HrmPageChrome.primaryNavy,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: EdgeInsets.symmetric(
            horizontal: widget.embedded ? 12 : 16,
          ),
          tabs: [
            Tab(text: tr('Tất cả (${_all.length})')),
            Tab(text: tr('Cần phản hồi (${_forMe.length})')),
            Tab(text: tr('Chờ QL duyệt (${_pendingApproval.length})')),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _list(_all, _SwapListMode.all),
                    _list(_forMe, _SwapListMode.respond),
                    _list(_pendingApproval, _SwapListMode.approve),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _list(List<Map<String, dynamic>> items, _SwapListMode mode) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              tr(mode == _SwapListMode.respond
                  ? 'Không có yêu cầu cần bạn phản hồi'
                  : mode == _SwapListMode.approve
                      ? 'Không có yêu cầu chờ quản lý duyệt'
                      : 'Chưa có yêu cầu đổi ca'),
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(tr('Mở menu góc phải → Yêu cầu đổi ca'),
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (_, i) => _card(items[i], mode),
      ),
    );
  }

  Widget _card(Map<String, dynamic> swap, _SwapListMode mode) {
    final status = swap['status'];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showShiftSwapDetailSheet(context, swap),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('${swap['requesterName'] ?? '—'} ↔ ${swap['targetName'] ?? '—'}'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: shiftSwapStatusColor(status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tr(shiftSwapStatusText(status)),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: shiftSwapStatusColor(status))),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                tr('${swap['requesterShiftName'] ?? ''} ${formatSwapDate(swap['requesterDate'])}'
                '  →  ${swap['targetShiftName'] ?? ''} ${formatSwapDate(swap['targetDate'])}'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 4),
              Text(tr('Bấm để xem chi tiết'),
                  style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
              if (mode != _SwapListMode.all) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (mode == _SwapListMode.respond) ...[
                      TextButton.icon(
                        onPressed: () => _respond(swap['id'], false),
                        icon: const Icon(Icons.close, size: 16),
                        label: Text(tr('Từ chối')),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _respond(swap['id'], true),
                        icon: const Icon(Icons.check, size: 16),
                        label: Text(tr('Đồng ý')),
                        style: FilledButton.styleFrom(
                            backgroundColor: HrmPageChrome.primaryNavy),
                      ),
                    ],
                    if (mode == _SwapListMode.approve) ...[
                      TextButton.icon(
                        onPressed: () => _approve(swap['id'], false),
                        icon: const Icon(Icons.close, size: 16),
                        label: Text(tr('Từ chối')),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _approve(swap['id'], true),
                        icon: const Icon(Icons.verified, size: 16),
                        label: Text(tr('Duyệt')),
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A)),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _respond(dynamic id, bool accept) async {
    final result = await _api.respondToShiftSwap(id.toString(), accept: accept);
    if (!mounted) return;
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: accept ? 'Đã đồng ý' : 'Đã từ chối',
          message: accept
              ? 'Yêu cầu chuyển sang chờ quản lý duyệt'
              : 'Đã từ chối yêu cầu đổi ca');
      _load();
    } else {
      appNotification.showError(
          title: 'Lỗi', message: result['message']?.toString() ?? 'Thất bại');
    }
  }

  Future<void> _approve(dynamic id, bool approve) async {
    final result =
        await _api.approveShiftSwap(id.toString(), approve: approve);
    if (!mounted) return;
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: approve ? 'Đã duyệt' : 'Đã từ chối',
          message: approve
              ? 'Lịch làm việc đã được cập nhật'
              : 'Đã từ chối yêu cầu đổi ca');
      _load();
    } else {
      appNotification.showError(
          title: 'Lỗi', message: result['message']?.toString() ?? 'Thất bại');
    }
  }

  /// Dialog tạo yêu cầu — có thể gọi từ FAB hoặc Lịch làm việc.
  Future<void> showCreateDialog({
    Shift? prefillShift,
    DateTime? prefillDate,
  }) async {
    if (_shifts.isEmpty) {
      final shifts = await _api.getShifts();
      _shifts = shifts.map((s) => Shift.fromJson(s)).toList();
    }
    if (_colleagues.isEmpty) {
      final col = await _api.getShiftSwapColleagues();
      if (col['isSuccess'] == true && col['data'] is List) {
        _colleagues = List<Map<String, dynamic>>.from(col['data']);
      }
    }

    String? targetUserId;
    String? requesterShiftId =
        prefillShift?.id ?? (_shifts.isNotEmpty ? _shifts.first.id : null);
    String? targetShiftId = requesterShiftId;
    DateTime requesterDate = prefillDate ?? DateTime.now();
    DateTime targetDate = requesterDate;
    final reasonCtrl = TextEditingController();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => ScrollableAlertDialog(
          title: Row(
            children: [
              Icon(Icons.swap_horiz, color: HrmPageChrome.primaryNavy),
              SizedBox(width: 8),
              Expanded(child: Text(tr('Yêu cầu đổi ca'))),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_colleagues.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        tr('Không có đồng nghiệp để đổi ca. Kiểm tra nhân viên đang làm đã gắn tài khoản.'),
                        style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    value: requesterShiftId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr('Ca của bạn *'),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _shifts
                        .map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(tr(s.name), overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setDlg(() {
                      requesterShiftId = v;
                      targetShiftId ??= v;
                    }),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Ngày ca của bạn'),
                        style: TextStyle(fontSize: 13)),
                    subtitle: Text(tr(DateFormat('dd/MM/yyyy').format(requesterDate))),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: requesterDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 7)),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (d != null) setDlg(() => requesterDate = d);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: targetUserId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr('Đồng nghiệp muốn đổi *'),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _colleagues
                        .map((c) => DropdownMenuItem(
                              value: c['userId']?.toString(),
                              child: Text(
                                tr('${c['fullName']} (${c['employeeCode']})'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setDlg(() => targetUserId = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: targetShiftId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr('Ca muốn nhận *'),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _shifts
                        .map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(tr(s.name), overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setDlg(() => targetShiftId = v),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Ngày ca muốn nhận'),
                        style: TextStyle(fontSize: 13)),
                    subtitle: Text(tr(DateFormat('dd/MM/yyyy').format(targetDate))),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: targetDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 7)),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (d != null) setDlg(() => targetDate = d);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonCtrl,
                    decoration: InputDecoration(
                      labelText: tr('Lý do (tùy chọn)'),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton.icon(
              onPressed: targetUserId == null ||
                      requesterShiftId == null ||
                      targetShiftId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final result = await _api.createShiftSwap(
                        targetUserId: targetUserId!,
                        requesterShiftId: requesterShiftId!,
                        requesterDate: requesterDate,
                        targetShiftId: targetShiftId!,
                        targetDate: targetDate,
                        reason: reasonCtrl.text.trim(),
                      );
                      if (!mounted) return;
                      if (result['isSuccess'] == true) {
                        appNotification.showSuccess(
                            title: 'Đã gửi',
                            message: tr('Yêu cầu đã gửi tới đồng nghiệp. Họ cần đồng ý trước khi QL duyệt.'));
                        _load();
                      } else {
                        appNotification.showError(
                            title: 'Không gửi được',
                            message: result['message']?.toString() ??
                                'Vui lòng thử lại');
                      }
                    },
              icon: const Icon(Icons.send, size: 16),
              label: Text(tr('Gửi yêu cầu')),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }
}
