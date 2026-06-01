import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/scrollable_dialog_body.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/meal.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/employee_search_picker.dart';

/// Tab đăng ký suất ăn (NV) + tổng hợp đăng ký (quản lý) + chấm QR.
class MealRegistrationTab extends StatefulWidget {
  final List<MealSession> sessions;
  final ApiService apiService;
  final bool canCreate;
  final bool isManager;
  final List<Map<String, dynamic>> employees;

  const MealRegistrationTab({
    super.key,
    required this.sessions,
    required this.apiService,
    required this.canCreate,
    required this.isManager,
    required this.employees,
  });

  @override
  State<MealRegistrationTab> createState() => _MealRegistrationTabState();
}

class _MealRegistrationTabState extends State<MealRegistrationTab> {
  bool _loading = true;
  bool _saving = false;
  DateTime _weekStart = _monday(DateTime.now());
  final Map<String, bool> _cellRegistered = {};
  Map<String, dynamic>? _managerSummary;
  List<Map<String, dynamic>> _managerRegs = [];
  DateTime _managerDate = DateTime.now();

  static DateTime _monday(DateTime d) =>
      d.subtract(Duration(days: d.weekday - 1));

  String _cellKey(DateTime day, String sessionId) =>
      '${DateFormat('yyyy-MM-dd').format(day)}|$sessionId';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await _loadMyWeek();
    if (widget.isManager) await _loadManagerData();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMyWeek() async {
    _cellRegistered.clear();
    final to = _weekStart.add(const Duration(days: 6));
    final res = await widget.apiService.getMyMealRegistrations(
      fromDate: _weekStart,
      toDate: to,
    );
    if (res['isSuccess'] == true && res['data'] is List) {
      for (final raw in res['data'] as List) {
        final m = raw as Map<String, dynamic>;
        if (m['isRegistered'] != true) continue;
        final dateStr = m['date']?.toString() ?? '';
        final sid = m['mealSessionId']?.toString() ?? '';
        if (dateStr.isNotEmpty && sid.isNotEmpty) {
          final d = DateTime.tryParse(dateStr.split('T').first);
          if (d != null) _cellRegistered[_cellKey(d, sid)] = true;
        }
      }
    }
  }

  Future<void> _loadManagerData() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_managerDate);
    final sumRes = await widget.apiService.getMealRegistrationSummary(
      date: dateStr,
    );
    final listRes = await widget.apiService.getMealRegistrations(date: dateStr);
    if (mounted) {
      setState(() {
        _managerSummary =
            sumRes['isSuccess'] == true ? sumRes['data'] as Map<String, dynamic>? : null;
        _managerRegs = listRes['isSuccess'] == true && listRes['data'] is List
            ? List<Map<String, dynamic>>.from(listRes['data'] as List)
            : [];
      });
    }
  }

  Future<void> _saveWeek() async {
    if (!widget.canCreate) return;
    setState(() => _saving = true);
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < 7; i++) {
      final day = _weekStart.add(Duration(days: i));
      for (final s in widget.sessions) {
        final key = _cellKey(day, s.id);
        items.add({
          'mealSessionId': s.id,
          'date': DateFormat('yyyy-MM-dd').format(day),
          'isRegistered': _cellRegistered[key] == true,
        });
      }
    }
    final res = await widget.apiService.batchRegisterMeal(items);
    setState(() => _saving = false);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã lưu', message: res['data']?['message']?.toString() ?? 'Đăng ký tuần');
      if (widget.isManager) _loadManagerData();
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không lưu được');
    }
  }

  void _showQrSheet() {
    if (!widget.canCreate) {
      NotificationOverlayManager().showError(
          title: 'Quyền', message: 'Bạn không có quyền chấm cơm');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _MealQrCheckInSheet(
        sessions: widget.sessions,
        apiService: widget.apiService,
      ),
    );
  }

  void _showManagerAddDialog() {
    String? employeeUserId;
    String? employeeName;
    String? sessionId =
        widget.sessions.isNotEmpty ? widget.sessions.first.id : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Đăng ký ăn cho nhân viên'),
          content: ScrollableDialogBody.wrap(
            context,
            maxWidth: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmployeePickerFormField(
                  labelText: 'Nhân viên *',
                  candidates: EmployeePickerItem.fromMaps(
                      widget.employees.cast<Map<String, dynamic>>()),
                  pickerTitle: 'Chọn nhân viên',
                  onChanged: (item) {
                    if (item == null) {
                      employeeUserId = null;
                      employeeName = null;
                      return;
                    }
                    final e = widget.employees.cast<Map<String, dynamic>>().firstWhere(
                      (x) => x['id']?.toString() == item.id,
                      orElse: () => <String, dynamic>{},
                    );
                    employeeUserId = e['userId']?.toString() ??
                        e['applicationUserId']?.toString();
                    employeeName = e['fullName']?.toString() ?? item.name;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: sessionId,
                  decoration: const InputDecoration(
                      labelText: 'Buổi ăn', border: OutlineInputBorder()),
                  items: widget.sessions
                      .map((s) =>
                          DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setDlg(() => sessionId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                if (employeeUserId == null || sessionId == null) return;
                Navigator.pop(ctx);
                final res = await widget.apiService.createMealRegistration({
                  'employeeUserId': employeeUserId,
                  'employeeName': employeeName ?? '',
                  'mealSessionId': sessionId,
                  'date': DateFormat('yyyy-MM-dd').format(_managerDate),
                });
                if (!mounted) return;
                if (res['isSuccess'] == true) {
                  NotificationOverlayManager()
                      .showSuccess(title: 'OK', message: 'Đã đăng ký');
                  _loadManagerData();
                } else {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi',
                      message: res['message']?.toString() ?? 'Thất bại');
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sessions.isEmpty) {
      return const Center(
          child: Text('Chưa cấu hình buổi ăn (menu Cài đặt → Buổi ăn)'));
    }

    return Column(
      children: [
        Material(
          color: const Color(0xFFEFF6FF),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.canCreate
                        ? 'Chọn ô để đăng ký/hủy suất ăn trong tuần'
                        : 'Xem đăng ký suất ăn (chệ xem)',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (widget.canCreate) ...[
                  OutlinedButton.icon(
                    onPressed: _showQrSheet,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('Chấm QR'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveWeek,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save, size: 18),
                    label: const Text('Lưu tuần'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (widget.isManager) _buildManagerHeader(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _buildWeekNav(),
                      const SizedBox(height: 12),
                      _buildWeekGrid(),
                      if (widget.isManager) ...[
                        const SizedBox(height: 24),
                        _buildManagerList(),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildWeekNav() {
    final end = _weekStart.add(const Duration(days: 6));
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() =>
                _weekStart = _weekStart.subtract(const Duration(days: 7)));
            _reload();
          },
        ),
        Expanded(
          child: Text(
            '${DateFormat('dd/MM').format(_weekStart)} – ${DateFormat('dd/MM/yyyy').format(end)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));
            _reload();
          },
        ),
        TextButton(
          onPressed: () {
            setState(() => _weekStart = _monday(DateTime.now()));
            _reload();
          },
          child: const Text('Tuần này'),
        ),
      ],
    );
  }

  Widget _buildWeekGrid() {
    const dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 44,
        columns: [
          const DataColumn(label: Text('Ngày')),
          ...widget.sessions.map((s) => DataColumn(label: Text(s.name))),
        ],
        rows: List.generate(7, (i) {
          final day = _weekStart.add(Duration(days: i));
          final isPast = day.isBefore(
              DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));
          return DataRow(
            cells: [
              DataCell(Text('${dayLabels[i]}\n${DateFormat('dd/MM').format(day)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: isPast ? Colors.grey : null))),
              ...widget.sessions.map((s) {
                final key = _cellKey(day, s.id);
                final on = _cellRegistered[key] == true;
                return DataCell(
                  Checkbox(
                    value: on,
                    onChanged: (!widget.canCreate || isPast)
                        ? null
                        : (v) => setState(() => _cellRegistered[key] = v == true),
                  ),
                );
              }),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildManagerHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _managerDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) {
                      setState(() => _managerDate = d);
                      _loadManagerData();
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Ngày quản lý đăng ký',
                        border: OutlineInputBorder(),
                        isDense: true),
                    child: Text(DateFormat('dd/MM/yyyy').format(_managerDate)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.canCreate)
                IconButton.filled(
                  tooltip: 'Thêm đăng ký',
                  onPressed: _showManagerAddDialog,
                  icon: const Icon(Icons.person_add),
                ),
            ],
          ),
          if (_managerSummary != null) ...[
            const SizedBox(height: 8),
            Text(
              'Tổng đăng ký: ${_managerSummary!['totalRegistered'] ?? 0}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Color(0xFF0369A1)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManagerList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Danh sách đăng ký (quản lý)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_managerRegs.isEmpty)
          const Text('Chưa có đăng ký trong ngày',
              style: TextStyle(color: Colors.grey))
        else
          ..._managerRegs.map((r) {
            final sid = r['mealSessionId']?.toString() ?? '';
            final matched =
                widget.sessions.where((s) => s.id == sid).toList();
            final session =
                matched.isEmpty ? null : matched.first.name;
            return Card(
              child: ListTile(
                dense: true,
                title: Text(r['employeeName']?.toString() ?? '—'),
                subtitle: Text(session ?? sid),
                trailing: r['registeredAt'] != null
                    ? Text(DateFormat('HH:mm').format(
                        DateTime.tryParse(r['registeredAt'].toString()) ??
                            DateTime.now()))
                    : null,
              ),
            );
          }),
      ],
    );
  }
}

class _MealQrCheckInSheet extends StatefulWidget {
  final List<MealSession> sessions;
  final ApiService apiService;

  const _MealQrCheckInSheet({
    required this.sessions,
    required this.apiService,
  });

  @override
  State<_MealQrCheckInSheet> createState() => _MealQrCheckInSheetState();
}

class _MealQrCheckInSheetState extends State<_MealQrCheckInSheet> {
  String? _sessionId;
  bool _scanning = false;
  bool _busy = false;
  final MobileScannerController _scanner = MobileScannerController();

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _checkIn({String? qrCode}) async {
    setState(() => _busy = true);
    final res = await widget.apiService.qrMealCheckIn(
      mealSessionId: _sessionId,
      qrCode: qrCode,
    );
    setState(() => _busy = false);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final msg = res['data']?['message']?.toString() ?? 'Chấm cơm thành công';
      NotificationOverlayManager().showSuccess(title: 'OK', message: msg);
      Navigator.pop(context);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Thất bại');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Chấm cơm',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _sessionId ?? (widget.sessions.isNotEmpty ? widget.sessions.first.id : null),
            decoration: const InputDecoration(
                labelText: 'Buổi ăn (để trống = tự nhận theo giờ)',
                border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('Tự động')),
              ...widget.sessions.map((s) =>
                  DropdownMenuItem(value: s.id, child: Text(s.name))),
            ],
            onChanged: (v) => setState(() => _sessionId = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _checkIn(),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.restaurant),
            label: const Text('Chấm cơm ngay'),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _scanning = !_scanning),
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(_scanning ? 'Ẩn camera' : 'Quét mã QR'),
            ),
            if (_scanning) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    controller: _scanner,
                    onDetect: (capture) {
                      final code = capture.barcodes.firstOrNull?.rawValue;
                      if (code != null && !_busy) {
                        setState(() => _scanning = false);
                        _checkIn(qrCode: code);
                      }
                    },
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
