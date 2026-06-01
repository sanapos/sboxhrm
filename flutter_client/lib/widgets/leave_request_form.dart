import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import 'notification_overlay.dart';
import 'employee_search_picker.dart';

/// Chuẩn hóa loại nghỉ từ API / AI (int hoặc string).
int normalizeLeaveType(dynamic type) {
  if (type is int) return type.clamp(0, 7);
  final s = type?.toString().toLowerCase() ?? '';
  switch (s) {
    case 'annualleave':
    case 'annual':
    case '0':
      return 0;
    case 'holiday':
    case '1':
      return 1;
    case 'personalpaid':
    case '2':
      return 2;
    case 'personalunpaid':
    case '3':
      return 3;
    case 'sickleave':
    case 'sick':
    case '4':
      return 4;
    case 'maternityleave':
    case 'maternity':
    case '5':
      return 5;
    case 'compensatoryleave':
    case 'compensatory':
    case '6':
      return 6;
    case 'longtermleave':
    case 'longterm':
    case '7':
      return 7;
    default:
      return int.tryParse(s) ?? 0;
  }
}

class LeaveTypeOption {
  final int value;
  final String label;
  final IconData icon;
  final Color color;
  const LeaveTypeOption(this.value, this.label, this.icon, this.color);
}

const _leaveTypes = [
  LeaveTypeOption(0, 'Phép năm', Icons.beach_access_rounded, Color(0xFF0D9488)),
  LeaveTypeOption(1, 'Lễ tết', Icons.celebration_rounded, Color(0xFFEA580C)),
  LeaveTypeOption(2, 'VR có lương', Icons.paid_rounded, Color(0xFF2563EB)),
  LeaveTypeOption(3, 'VR không lương', Icons.money_off_rounded, Color(0xFFD97706)),
  LeaveTypeOption(4, 'Ốm đau', Icons.local_hospital_rounded, Color(0xFFDC2626)),
  LeaveTypeOption(5, 'Thai sản', Icons.child_friendly_rounded, Color(0xFFDB2777)),
  LeaveTypeOption(6, 'Nghỉ bù', Icons.swap_horiz_rounded, Color(0xFF4F46E5)),
  LeaveTypeOption(7, 'Nghỉ dài hạn', Icons.hourglass_full_rounded, Color(0xFF78716C)),
];

const _primary = Color(0xFF1E3A5F);
const _primaryDark = Color(0xFF0F2340);
const _border = Color(0xFFE4E4E7);
const _muted = Color(0xFF71717A);
const _text = Color(0xFF18181B);

/// Dialog / fullscreen form tạo hoặc sửa đơn nghỉ phép.
class LeaveRequestFormDialog extends StatefulWidget {
  final List<dynamic> shifts;
  final List<dynamic> employees;
  final ApiService apiService;
  final Map<String, dynamic>? existingLeave;
  final Map<String, String>? aiPrefill;
  final String? currentUserId;
  final bool isManager;

  const LeaveRequestFormDialog({
    super.key,
    required this.shifts,
    required this.employees,
    required this.apiService,
    this.existingLeave,
    this.aiPrefill,
    this.currentUserId,
    this.isManager = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required List<dynamic> shifts,
    required List<dynamic> employees,
    required ApiService apiService,
    Map<String, dynamic>? existingLeave,
    Map<String, String>? aiPrefill,
    String? currentUserId,
    bool isManager = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LeaveRequestFormDialog(
        shifts: shifts,
        employees: employees,
        apiService: apiService,
        existingLeave: existingLeave,
        aiPrefill: aiPrefill,
        currentUserId: currentUserId,
        isManager: isManager,
      ),
    );
  }

  @override
  State<LeaveRequestFormDialog> createState() => _LeaveRequestFormDialogState();
}

class _LeaveRequestFormDialogState extends State<LeaveRequestFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  List<String> _selectedShiftIds = [];
  String? _selectedReplacementId;
  String? _selectedEmployeeId;
  String? _selectedEmployeeUserId;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  int _leaveType = 0;
  bool _isHalfShift = false;
  bool _isSubmitting = false;
  bool _shiftsManuallyCleared = false;

  List<dynamic> _filteredShifts = [];
  bool _isLoadingShifts = false;
  bool _hasScheduleForDate = false;

  bool get _isEditMode => widget.existingLeave != null;

  int get _dayCount {
    final d = _endDate.difference(_startDate).inDays + 1;
    return d < 1 ? 1 : d;
  }

  LeaveTypeOption get _typeOption =>
      _leaveTypes.firstWhere((t) => t.value == _leaveType, orElse: () => _leaveTypes.first);

  String? get _employeeDisplayName {
    if (_isEditMode) {
      return widget.existingLeave?['employeeName']?.toString();
    }
    if (_selectedEmployeeId == null) return null;
    for (final emp in widget.employees) {
      if (emp['id']?.toString() == _selectedEmployeeId) {
        final name =
            '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
        if (name.isNotEmpty) return name;
        return emp['employeeCode']?.toString();
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _initEmployee();
    _initFromExistingOrAi();
    _filteredShifts = List.from(widget.shifts);
    _loadShiftsForDate();
  }

  void _initEmployee() {
    if (widget.currentUserId == null) return;
    for (final emp in widget.employees) {
      if (emp['applicationUserId']?.toString() == widget.currentUserId) {
        _selectedEmployeeId = emp['id']?.toString();
        _selectedEmployeeUserId = emp['applicationUserId']?.toString();
        break;
      }
    }
  }

  void _initFromExistingOrAi() {
    if (_isEditMode) {
      final l = widget.existingLeave!;
      _leaveType = normalizeLeaveType(l['type']);
      _isHalfShift = l['isHalfShift'] == true;
      _reasonController.text = l['reason']?.toString() ?? '';
      final repId = l['replacementEmployeeId']?.toString();
      if (repId != null &&
          widget.employees.any((e) => e['id']?.toString() == repId)) {
        _selectedReplacementId = repId;
      }
      _startDate =
          DateTime.tryParse(l['startDate']?.toString() ?? '') ?? DateTime.now();
      _endDate = DateTime.tryParse(l['endDate']?.toString() ?? '') ?? _startDate;
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      final ids = l['shiftIds'];
      if (ids is List && ids.isNotEmpty) {
        _selectedShiftIds = ids.map((e) => e.toString()).toList();
      } else if (l['shiftId'] != null && l['shiftId'].toString().isNotEmpty) {
        _selectedShiftIds = [l['shiftId'].toString()];
      }
      if (l['employeeUserId'] != null) {
        _selectedEmployeeUserId = l['employeeUserId']?.toString();
        for (final emp in widget.employees) {
          if (emp['applicationUserId']?.toString() == _selectedEmployeeUserId) {
            _selectedEmployeeId = emp['id']?.toString();
            break;
          }
        }
      }
      return;
    }

    final pre = widget.aiPrefill;
    if (pre != null) {
      final startStr = pre['date'] ?? pre['startDate'];
      final endStr = pre['endDate'] ?? startStr;
      if (startStr != null) {
        _startDate = DateTime.tryParse(startStr) ?? _startDate;
      }
      if (endStr != null) {
        _endDate = DateTime.tryParse(endStr) ?? _startDate;
      } else {
        _endDate = _startDate;
      }
      if (pre['reason'] != null) _reasonController.text = pre['reason']!;
      final typeStr = pre['type'] ?? pre['leaveType'];
      if (typeStr != null) _leaveType = normalizeLeaveType(typeStr);
      if (pre['isHalfShift'] == 'true') _isHalfShift = true;
      final empId = pre['employeeId'];
      if (empId != null && empId.isNotEmpty) {
        _selectedEmployeeId = empId;
      }
    }
  }

  Future<void> _loadShiftsForDate() async {
    setState(() => _isLoadingShifts = true);
    try {
      final employeeId = _selectedEmployeeId;
      if (employeeId != null) {
        final scheduleShiftIds = <String>{};

        final wsResult = await widget.apiService.getWorkSchedules(
          employeeId: employeeId,
          fromDate: _startDate,
          toDate: _startDate,
          isDayOff: false,
        );
        if (wsResult['isSuccess'] == true && wsResult['data'] != null) {
          final data = wsResult['data'];
          final items = data is List ? data : (data['items'] ?? []);
          for (final item in items) {
            final sid = item['shiftId']?.toString();
            if (sid != null && sid.isNotEmpty) scheduleShiftIds.add(sid);
          }
        }

        try {
          final srResult = await widget.apiService.getScheduleRegistrations(
            employeeId: employeeId,
            fromDate: _startDate,
            toDate: _startDate,
          );
          if (srResult['isSuccess'] == true && srResult['data'] != null) {
            final data = srResult['data'];
            final items = data is List ? data : (data['items'] ?? []);
            for (final item in items) {
              if (item['isDayOff'] != true &&
                  item['status'] != 2 &&
                  item['status'] != 3) {
                final sid = item['shiftId']?.toString();
                if (sid != null && sid.isNotEmpty) scheduleShiftIds.add(sid);
              }
            }
          }
        } catch (_) {}

        if (scheduleShiftIds.isNotEmpty) {
          _filteredShifts = widget.shifts
              .where((s) => scheduleShiftIds.contains(s['id']?.toString()))
              .toList();
          _hasScheduleForDate = true;
        } else {
          _filteredShifts = List.from(widget.shifts);
          _hasScheduleForDate = false;
        }
      } else {
        _filteredShifts = List.from(widget.shifts);
        _hasScheduleForDate = false;
      }
    } catch (_) {
      _filteredShifts = List.from(widget.shifts);
      _hasScheduleForDate = false;
    }

    if (!_shiftsManuallyCleared &&
        _hasScheduleForDate &&
        _filteredShifts.isNotEmpty &&
        !_isEditMode) {
      _selectedShiftIds = _filteredShifts
          .map((s) => s['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    }

    if (mounted) setState(() => _isLoadingShifts = false);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isMobile = Responsive.isMobile(context);
    final title = _isEditMode ? 'Sửa đơn nghỉ phép' : 'Tạo đơn nghỉ phép';

    final body = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 16),
          if (widget.isManager) ...[
            _sectionCard(
              title: 'Nhân viên',
              icon: Icons.person_rounded,
              required: true,
              child: _buildEmployeeField(),
            ),
            const SizedBox(height: 12),
          ],
          _sectionCard(
            title: l10n.leaveType,
            icon: Icons.category_rounded,
            required: true,
            child: _buildLeaveTypeGrid(),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Thời gian nghỉ',
            icon: Icons.date_range_rounded,
            required: true,
            child: _buildDateSection(l10n),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: l10n.shiftLabel,
            icon: Icons.schedule_rounded,
            required: true,
            child: _buildShiftSection(),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Nhân viên thay ca',
            icon: Icons.swap_horiz_rounded,
            child: _buildReplacementField(),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: l10n.reason,
            icon: Icons.notes_rounded,
            required: true,
            child: TextFormField(
              controller: _reasonController,
              maxLines: 4,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Mô tả lý do xin nghỉ (bắt buộc)...',
                hintStyle: const TextStyle(color: _muted, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Vui lòng nhập lý do'
                  : null,
            ),
          ),
        ],
      ),
    );

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: const Color(0xFFFAFAFA),
          appBar: AppBar(
            backgroundColor: _primaryDark,
            foregroundColor: Colors.white,
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: body,
          ),
          bottomNavigationBar: _buildBottomBar(l10n),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogHeader(title),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: body,
              ),
            ),
            _buildBottomBar(l10n, compact: true),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primaryDark, _primary],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_note_rounded, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 16,
        12,
        compact ? 16 : 16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border.withValues(alpha: 0.8))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(l10n.cancel),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_isEditMode ? Icons.save_rounded : Icons.send_rounded,
                      size: 20),
              label: Text(_isEditMode ? l10n.save : 'Gửi đơn'),
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final shiftNames = _selectedShiftIds.map((id) {
      for (final s in widget.shifts) {
        if (s['id']?.toString() == id) {
          return s['name']?.toString() ?? id;
        }
      }
      return id;
    }).toList();

    final dateLabel = _dayCount == 1
        ? DateFormat('dd/MM/yyyy').format(_startDate)
        : '${DateFormat('dd/MM').format(_startDate)} – ${DateFormat('dd/MM/yyyy').format(_endDate)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _typeOption.color.withValues(alpha: 0.12),
            _primary.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _typeOption.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_typeOption.icon, color: _typeOption.color, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _typeOption.label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _typeOption.color,
                      ),
                    ),
                    if (_employeeDisplayName != null)
                      Text(
                        _employeeDisplayName!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _text,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isHalfShift ? 'Nửa ca' : '$_dayCount ngày',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryRow(Icons.calendar_today_rounded, 'Ngày nghỉ', dateLabel),
          _summaryRow(
            Icons.schedule_rounded,
            'Ca đã chọn',
            shiftNames.isEmpty
                ? 'Chưa chọn ca'
                : shiftNames.join(', '),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _muted),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 13, color: _muted)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    bool required = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: _primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
              ),
              if (required)
                const Text(' *', style: TextStyle(color: Color(0xFFDC2626))),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildLeaveTypeGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 520 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.35,
          ),
          itemCount: _leaveTypes.length,
          itemBuilder: (_, i) {
            final t = _leaveTypes[i];
            final selected = _leaveType == t.value;
            return Material(
              color: selected ? t.color.withValues(alpha: 0.12) : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => setState(() => _leaveType = t.value),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? t.color : _border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(t.icon, color: selected ? t.color : _muted, size: 26),
                      const SizedBox(height: 6),
                      Text(
                        t.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? t.color : _muted,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDateSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _dateTile('Từ ngày', _startDate, _pickStartDate)),
            const SizedBox(width: 10),
            Expanded(child: _dateTile('Đến ngày', _endDate, _pickEndDate)),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _isHalfShift,
          activeThumbColor: _primary,
          title: Text(
            l10n.halfShift,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: const Text(
            'Chỉ nghỉ một phần ca trong ngày (0.5 công)',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          onChanged: (v) => setState(() => _isHalfShift = v),
        ),
        if (_dayCount > 1)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Đơn nghỉ $_dayCount ngày liên tiếp. Ca làm việc áp dụng theo lịch ngày bắt đầu.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF1D4ED8)),
            ),
          ),
      ],
    );
  }

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_month, size: 18, color: _primary),
                const SizedBox(width: 8),
                Text(
                  DateFormat('dd/MM/yyyy').format(date),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _text,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _hasScheduleForDate
                    ? 'Ca theo lịch ${DateFormat('dd/MM').format(_startDate)}'
                    : 'Chọn ca nghỉ (có thể chọn nhiều)',
                style: TextStyle(
                  fontSize: 13,
                  color: _hasScheduleForDate
                      ? const Color(0xFF2563EB)
                      : _muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (_filteredShifts.isNotEmpty && !_isLoadingShifts)
              TextButton(
                onPressed: () {
                  setState(() {
                    _shiftsManuallyCleared = true;
                    if (_selectedShiftIds.length == _filteredShifts.length) {
                      _selectedShiftIds.clear();
                    } else {
                      _selectedShiftIds = _filteredShifts
                          .map((s) => s['id']?.toString() ?? '')
                          .where((id) => id.isNotEmpty)
                          .toList();
                    }
                  });
                },
                child: Text(
                  _selectedShiftIds.length == _filteredShifts.length
                      ? 'Bỏ chọn'
                      : 'Chọn tất cả',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingShifts)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_filteredShifts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Không có ca cho ngày đã chọn. Đổi ngày hoặc liên hệ HR xếp lịch.',
              style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filteredShifts.map<Widget>((shift) {
              final id = shift['id']?.toString() ?? '';
              final name = shift['name']?.toString() ?? 'Ca';
              final selected = _selectedShiftIds.contains(id);
              return FilterChip(
                label: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                selected: selected,
                showCheckmark: true,
                selectedColor: _primary.withValues(alpha: 0.15),
                checkmarkColor: _primary,
                side: BorderSide(
                  color: selected ? _primary : _border,
                ),
                onSelected: (s) {
                  setState(() {
                    _shiftsManuallyCleared = true;
                    if (s) {
                      _selectedShiftIds.add(id);
                    } else {
                      _selectedShiftIds.remove(id);
                    }
                  });
                },
              );
            }).toList(),
          ),
        if (_selectedShiftIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Đã chọn ${_selectedShiftIds.length} ca',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _primary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmployeeField() {
    if (_isEditMode) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            const Icon(Icons.person, color: _muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.existingLeave?['employeeName']?.toString() ?? 'N/A',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.lock_outline, size: 18, color: _muted),
          ],
        ),
      );
    }

    final name = _employeeDisplayName ?? 'Chọn nhân viên';
    return InkWell(
      onTap: _pickEmployee,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          errorText: _selectedEmployeeId == null ? null : null,
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: _selectedEmployeeId != null
                ? FontWeight.w600
                : FontWeight.normal,
            color: _selectedEmployeeId != null ? _text : _muted,
          ),
        ),
      ),
    );
  }

  Future<void> _pickEmployee() async {
    final items = EmployeePickerItem.fromMaps(
      widget.employees
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
    final picked = await EmployeeSearchPicker.pickId(
      context,
      items: items,
      selectedId: _selectedEmployeeId,
      title: 'Chọn nhân viên',
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedEmployeeId = picked;
        _selectedShiftIds.clear();
        _shiftsManuallyCleared = false;
        for (final emp in widget.employees) {
          if (emp['id']?.toString() == picked) {
            _selectedEmployeeUserId = emp['applicationUserId']?.toString();
            break;
          }
        }
      });
      _loadShiftsForDate();
    }
  }

  Widget _buildReplacementField() {
    return InkWell(
      onTap: _pickReplacement,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: const Icon(Icons.person_search),
        ),
        child: Text(
          _replacementLabel() ?? 'Không chọn (tùy chọn)',
          style: TextStyle(
            fontSize: 15,
            color: _replacementLabel() != null ? _text : _muted,
          ),
        ),
      ),
    );
  }

  String? _replacementLabel() {
    if (_selectedReplacementId == null) return null;
    for (final emp in widget.employees) {
      if (emp['id']?.toString() == _selectedReplacementId) {
        final name =
            '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
        return name.isEmpty ? emp['employeeCode']?.toString() : name;
      }
    }
    return null;
  }

  Future<void> _pickReplacement() async {
    final others = widget.employees
        .where((e) => e['id']?.toString() != _selectedEmployeeId)
        .toList();
    final items = EmployeePickerItem.fromMaps(
      others.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
    final picked = await EmployeeSearchPicker.pickId(
      context,
      items: items,
      selectedId: _selectedReplacementId,
      title: 'Chọn người thay ca',
      allowClear: true,
    );
    if (mounted) {
      setState(() => _selectedReplacementId = picked);
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
        _selectedShiftIds.clear();
        _shiftsManuallyCleared = false;
      });
      _loadShiftsForDate();
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _submit() async {
    if (widget.isManager && !_isEditMode && _selectedEmployeeId == null) {
      NotificationOverlayManager().showError(
        title: 'Thiếu thông tin',
        message: 'Vui lòng chọn nhân viên',
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_selectedShiftIds.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiếu thông tin',
        message: 'Vui lòng chọn ít nhất một ca làm việc',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final Map<String, dynamic> result;
      if (_isEditMode) {
        result = await widget.apiService.updateLeave(
          leaveId: widget.existingLeave!['id'],
          shiftIds: _selectedShiftIds,
          startDate: _startDate,
          endDate: _endDate,
          type: _leaveType,
          isHalfShift: _isHalfShift,
          reason: _reasonController.text.trim(),
          replacementEmployeeId: _selectedReplacementId,
          employeeUserId: widget.isManager ? _selectedEmployeeUserId : null,
          employeeId: widget.isManager ? _selectedEmployeeId : null,
        );
      } else {
        result = await widget.apiService.createLeave(
          shiftIds: _selectedShiftIds,
          startDate: _startDate,
          endDate: _endDate,
          type: _leaveType,
          isHalfShift: _isHalfShift,
          reason: _reasonController.text.trim(),
          replacementEmployeeId: _selectedReplacementId,
          employeeUserId: widget.isManager ? _selectedEmployeeUserId : null,
          employeeId: widget.isManager ? _selectedEmployeeId : null,
        );
      }

      if (!mounted) return;
      if (result['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(
          title: 'Thành công',
          message: _isEditMode
              ? 'Cập nhật đơn thành công'
              : 'Tạo đơn nghỉ phép thành công',
        );
        Navigator.pop(context, true);
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: result['message']?.toString() ?? 'Không rõ nguyên nhân',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
