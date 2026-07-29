import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../features/leave/leave_catalog.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../utils/api_datetime.dart';
import '../utils/leave_salary_shifts.dart';
import '../utils/responsive_helper.dart';
import 'employee_search_picker.dart';
import 'notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

export '../features/leave/leave_catalog.dart' show normalizeLeaveType;

const _primary = Color(0xFF1E3A5F);
const _primaryDark = Color(0xFF0F2340);
const _border = Color(0xFFE4E4E7);
const _muted = Color(0xFF71717A);
const _text = Color(0xFF18181B);
const _bg = Color(0xFFF8FAFC);

/// Form tạo/sửa đơn nghỉ phép — wizard theo nhóm pháp lý.
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
      useRootNavigator: true,
      builder: (dialogContext) => LeaveRequestFormDialog(
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
  final _bhxhNoteController = TextEditingController();
  final _pageController = PageController();

  int _step = 0;
  LeaveLegalCategory? _category;
  LeaveCatalogEntry? _entry;

  List<String> _selectedShiftIds = [];
  String? _selectedReplacementId;
  String? _selectedEmployeeId;
  String? _selectedEmployeeUserId;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _isHalfShift = false;
  bool _countAsWork = false;
  bool _autoApprove = false;
  bool _isSubmitting = false;

  List<dynamic> _filteredShifts = [];
  bool _isLoadingShifts = false;
  bool _hasSalaryShifts = false;

  double? _annualBalanceRemaining;
  double? _annualBalanceEntitlement;
  bool _loadingAnnualBalance = false;

  bool get _isEditMode => widget.existingLeave != null;
  int get _totalSteps => _isEditMode ? 1 : 3;
  bool get _needsBhxhNote => _entry?.requiresBhxhNote == true;

  @override
  void initState() {
    super.initState();
    _initEmployee();
    _initFromExistingOrAi();
    _loadShiftsForDate();
    _loadAnnualBalance();
  }

  double get _daysNeeded {
    final d = _endDate.difference(_startDate).inDays + 1;
    final days = d < 1 ? 1 : d;
    return _isHalfShift ? days * 0.5 : days.toDouble();
  }

  Future<void> _loadAnnualBalance() async {
    final entry = _entry;
    if (entry == null || !entry.usesAnnualBalance || _countAsWork) {
      if (mounted) {
        setState(() {
          _annualBalanceRemaining = null;
          _annualBalanceEntitlement = null;
        });
      }
      return;
    }
    final employeeId = _selectedEmployeeId;
    if (employeeId == null) return;

    setState(() => _loadingAnnualBalance = true);
    try {
      final result =
          await widget.apiService.getAnnualLeaveBalance(employeeId);
      if (!mounted) return;
      if (result['isSuccess'] == true && result['data'] != null) {
        final raw = result['data'];
        if (raw is! Map) return;
        final data = Map<String, dynamic>.from(raw);
        setState(() {
          _annualBalanceRemaining =
              (data['remainingDays'] as num?)?.toDouble();
          _annualBalanceEntitlement =
              (data['entitlementDays'] as num?)?.toDouble();
        });
      } else {
        setState(() {
          _annualBalanceRemaining = null;
          _annualBalanceEntitlement = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingAnnualBalance = false);
    }
  }

  Widget _buildAnnualBalanceCard() {
    final entry = _entry;
    if (entry == null || !entry.usesAnnualBalance || _countAsWork) {
      return const SizedBox.shrink();
    }

    if (_loadingAnnualBalance) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (_annualBalanceRemaining == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(tr('Chưa có quỹ phép năm (gắn hồ sơ lương trong Thiết lập lương).'),
          style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
        ),
      );
    }

    final remaining = _annualBalanceRemaining!;
    final needed = _daysNeeded;
    final insufficient = needed > remaining;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: insufficient
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: insufficient
              ? const Color(0xFFFECACA)
              : const Color(0xFF6EE7B7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                insufficient ? Icons.warning_amber_rounded : Icons.beach_access,
                color: insufficient
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF059669),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('${tr('Phép năm còn: ')}${remaining.toStringAsFixed(remaining.truncateToDouble() == remaining ? 0 : 1)} ngày'
                  '${_annualBalanceEntitlement != null ? ' / ${_annualBalanceEntitlement!.toStringAsFixed(0)} ngày/năm' : ''}'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: insufficient
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF047857),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(tr('${tr('Đơn này cần: ')}${needed.toStringAsFixed(needed.truncateToDouble() == needed ? 0 : 1)} ngày'
            '${_isHalfShift ? ' (nửa ca)' : ''}. '
            '${insufficient ? 'Không đủ phép — không thể duyệt.' : 'Sẽ trừ khi duyệt xong.'}'),
            style: TextStyle(
              fontSize: 12,
              color: insufficient
                  ? const Color(0xFFB91C1C)
                  : const Color(0xFF065F46),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _bhxhNoteController.dispose();
    _pageController.dispose();
    super.dispose();
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
    final l = widget.existingLeave;
    if (l != null) {
      final type = normalizeLeaveType(l['type']);
      final sm = SickLeaveMode.fromValue(l['sickLeaveMode'] ?? 0);
      _entry = LeaveCatalog.findEntry(leaveType: type, sickMode: sm);
      _category = _entry?.category;
      _isHalfShift = l['isHalfShift'] == true;
      _countAsWork = l['countAsWork'] == true;
      _reasonController.text = l['reason']?.toString() ?? '';
      _bhxhNoteController.text = l['bhxhDocumentNote']?.toString() ?? '';
      _startDate =
          parseApiCalendarDate(l['startDate']) ?? DateTime.now();
      _endDate = parseApiCalendarDate(l['endDate']) ?? _startDate;
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      final ids = l['shiftIds'];
      if (ids is List && ids.isNotEmpty) {
        _selectedShiftIds = ids.map((e) => e.toString()).toList();
      } else if (l['shiftId'] != null) {
        _selectedShiftIds = [l['shiftId'].toString()];
      }
      final repId = l['replacementEmployeeId']?.toString();
      if (repId != null) _selectedReplacementId = repId;
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
      if (pre['startDate'] != null) {
        _startDate = parseApiCalendarDate(pre['startDate']) ?? _startDate;
      }
      if (pre['endDate'] != null) {
        _endDate = parseApiCalendarDate(pre['endDate']) ?? _startDate;
      }
      if (pre['reason'] != null) _reasonController.text = pre['reason']!;
      if (pre['isHalfShift'] == 'true') _isHalfShift = true;
    }
  }

  Future<void> _loadShiftsForDate() async {
    setState(() => _isLoadingShifts = true);
    try {
      final employeeId = _selectedEmployeeId;
      if (employeeId != null) {
        final profile =
            await widget.apiService.getEmployeeSalaryProfile(employeeId);
        final ids = LeaveSalaryShifts.templateIdsFromSalaryProfile(
          profile != null ? Map<String, dynamic>.from(profile) : null,
          widget.shifts,
        );
        _filteredShifts = ids.isEmpty
            ? []
            : widget.shifts
                .where((s) => ids.contains(s['id']?.toString()))
                .toList();
        _hasSalaryShifts = ids.isNotEmpty;
      } else {
        _filteredShifts = [];
        _hasSalaryShifts = false;
      }
    } catch (_) {
      _filteredShifts = [];
      _hasSalaryShifts = false;
    }
    if (mounted) setState(() => _isLoadingShifts = false);
  }

  void _goStep(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_step == 0 && _category == null) {
      _toast('Chọn nhóm loại nghỉ', error: true);
      return;
    }
    if (_step == 1 && _entry == null) {
      _toast('Chọn loại nghỉ cụ thể', error: true);
      return;
    }
    if (_step < _totalSteps - 1) _goStep(_step + 1);
  }

  void _back() {
    if (_step > 0) _goStep(_step - 1);
  }

  void _toast(String msg, {bool error = false}) {
    if (error) {
      NotificationOverlayManager().showError(title: 'Thiếu thông tin', message: msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final title = _isEditMode ? 'Sửa đơn nghỉ phép' : 'Đăng ký nghỉ phép';

    final content = Column(
      children: [
        _buildStepIndicator(),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _totalSteps,
            itemBuilder: (context, index) {
              if (_isEditMode) return _buildDetailsStep();
              switch (index) {
                case 0:
                  return _buildCategoryStep();
                case 1:
                  return _buildSubtypeStep();
                default:
                  return _buildDetailsStep();
              }
            },
          ),
        ),
        _buildBottomBar(title),
      ],
    );

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _primaryDark,
            foregroundColor: Colors.white,
            title: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w600)),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline_rounded),
                onPressed: _showLegalGuide,
              ),
            ],
          ),
          body: content,
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          children: [
            _buildDialogHeader(title),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
            child: Text(tr(title),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: _showLegalGuide,
            icon: const Icon(Icons.help_outline_rounded, color: Colors.white70),
          ),
          IconButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final labels =
        _isEditMode ? ['Chi tiết'] : ['Nhóm', 'Loại', 'Chi tiết'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i <= _step;
          return Expanded(
            child: Row(
              children: [
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: active ? _primary : _border,
                    ),
                  ),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: active ? _primary : _border,
                  child: Text(
                    tr('${i + 1}'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: active ? Colors.white : _muted,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCategoryStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr('Bước 1 — Chọn nhóm chế độ'),
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _text),
        ),
        const SizedBox(height: 6),
        Text(tr('Mỗi ngày nghỉ chỉ áp dụng một chế độ chi trả.'),
          style: TextStyle(fontSize: 13, color: _muted),
        ),
        const SizedBox(height: 16),
        ...LeaveLegalCategory.values.map((cat) {
          final selected = _category == cat;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: selected
                  ? LeaveCatalog.categoryColor(cat).withValues(alpha: 0.1)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _category = cat;
                    _entry = null;
                  });
                  _goStep(1);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? LeaveCatalog.categoryColor(cat)
                          : _border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            LeaveCatalog.categoryColor(cat).withValues(alpha: 0.15),
                        child: Icon(LeaveCatalog.categoryIcon(cat),
                            color: LeaveCatalog.categoryColor(cat)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(LeaveCatalog.categoryTitle(cat)),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tr(LeaveCatalog.categoryDescription(cat)),
                              style: const TextStyle(fontSize: 12, color: _muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: selected
                              ? LeaveCatalog.categoryColor(cat)
                              : _muted),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSubtypeStep() {
    final cat = _category;
    if (cat == null) {
      return Center(
        child: Text(tr('Chọn nhóm loại nghỉ ở bước trước'),
            style: TextStyle(color: _muted, fontSize: 14)),
      );
    }
    final entries = LeaveCatalog.forCategory(cat);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr('Bước 2 — ${LeaveCatalog.categoryTitle(cat)}'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _text),
        ),
        const SizedBox(height: 12),
        ...entries.map((e) {
          final selected = _entry == e;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: selected ? e.color.withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  setState(() => _entry = e);
                  _loadAnnualBalance();
                  _goStep(2);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selected ? e.color : _border,
                        width: selected ? 2 : 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(e.icon, color: e.color, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(e.title),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            Text(tr(e.subtitle),
                                style: TextStyle(fontSize: 12, color: e.color)),
                            const SizedBox(height: 6),
                            Text(tr(e.legalHint),
                                style: const TextStyle(fontSize: 11, color: _muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDetailsStep() {
    final l10n = AppLocalizations.of(context);
    final entry = _entry;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (entry != null) _buildSelectedTypeBanner(entry),
          _buildAnnualBalanceCard(),
          if (widget.isManager) ...[
            _labeledSection('Nhân viên', Icons.person_rounded, _buildEmployeePicker()),
            const SizedBox(height: 12),
          ],
          _labeledSection('Thời gian', Icons.date_range_rounded, _buildDateSection(l10n)),
          const SizedBox(height: 12),
          _labeledSection('Ca nghỉ', Icons.schedule_rounded, _buildShiftSection()),
          const SizedBox(height: 12),
          _labeledSection(
              'Người thay ca (tùy chọn)', Icons.swap_horiz_rounded, _buildReplacementPicker()),
          if (_needsBhxhNote) ...[
            const SizedBox(height: 12),
            _labeledSection(
              'Giấy nghỉ / hồ sơ BHXH',
              Icons.description_rounded,
              TextFormField(
                controller: _bhxhNoteController,
                decoration: InputDecoration(
                  hintText: tr('Số seri giấy nghỉ, mã hồ sơ BHXH…'),
                  filled: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Bắt buộc với chế độ BHXH' : null,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _labeledSection(
            l10n.reason,
            Icons.notes_rounded,
            TextFormField(
              controller: _reasonController,
              maxLines: 3,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Vui lòng nhập lý do' : null,
              decoration: InputDecoration(
                hintText: tr('Mô tả ngắn gọn lý do nghỉ…'),
                filled: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (widget.isManager) ...[
            const SizedBox(height: 12),
            _buildManagerOptions(),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedTypeBanner(LeaveCatalogEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: entry.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: entry.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(entry.icon, color: entry.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(entry.title),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: entry.color,
                        fontSize: 15)),
                Text(tr(entry.paymentSource.label),
                    style: const TextStyle(fontSize: 12, color: _muted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: entry.paymentSource.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(tr(entry.paymentSource.label),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: entry.paymentSource.color)),
          ),
        ],
      ),
    );
  }

  Widget _labeledSection(String title, IconData icon, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: _primary),
            const SizedBox(width: 6),
            Text(tr(title),
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14, color: _text)),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildManagerOptions() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _border),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: Text(tr('Phép duyệt nhưng vẫn tính công'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(tr('Không ghi "Phép" trên chấm công'),
                style: TextStyle(fontSize: 12)),
            value: _countAsWork,
            onChanged: (v) {
              setState(() => _countAsWork = v);
              _loadAnnualBalance();
            },
          ),
          if (!_isEditMode)
            SwitchListTile(
              title: Text(tr('Duyệt luôn khi tạo'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              value: _autoApprove,
              onChanged: (v) => setState(() => _autoApprove = v),
            ),
        ],
      ),
    );
  }

  Widget _buildDateSection(AppLocalizations l10n) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _dateTile('Từ ngày', _startDate, _pickStart)),
            const SizedBox(width: 8),
            Expanded(child: _dateTile('Đến ngày', _endDate, _pickEnd)),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _isHalfShift,
          title: Text(tr(l10n.halfShift)),
          subtitle: Text(tr('0.5 công / ngày'), style: TextStyle(fontSize: 12)),
          onChanged: (v) {
            setState(() => _isHalfShift = v);
            _loadAnnualBalance();
          },
        ),
      ],
    );
  }

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(label), style: const TextStyle(fontSize: 11, color: _muted)),
            Text(tr(DateFormat('dd/MM/yyyy').format(date)),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftSection() {
    if (_isLoadingShifts) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (!_hasSalaryShifts) {
      return Text(
        tr(_selectedEmployeeId == null
            ? 'Chọn nhân viên trước.'
            : 'Chưa gắn ca trong Thiết lập lương.'),
        style: const TextStyle(color: Color(0xFFB45309), fontSize: 13),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _filteredShifts.map((s) {
        final id = s['id']?.toString() ?? '';
        final name = s['name']?.toString() ?? 'Ca';
        final sel = _selectedShiftIds.contains(id);
        return FilterChip(
          label: Text(tr(name)),
          selected: sel,
          onSelected: (_) {
            setState(() {
              if (sel) {
                _selectedShiftIds.remove(id);
              } else {
                _selectedShiftIds.add(id);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildEmployeePicker() {
    return ListTile(
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _border),
      ),
      title: Text(tr(_employeeName() ?? 'Chọn nhân viên')),
      trailing: const Icon(Icons.chevron_right),
      onTap: _pickEmployee,
    );
  }

  Widget _buildReplacementPicker() {
    return ListTile(
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _border),
      ),
      title: Text(tr(_replacementName() ?? 'Không chọn')),
      trailing: const Icon(Icons.person_search),
      onTap: _pickReplacement,
    );
  }

  String? _employeeName() {
    if (_selectedEmployeeId == null) return null;
    for (final e in widget.employees) {
      if (e['id']?.toString() == _selectedEmployeeId) {
        final n = '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim();
        return n.isEmpty ? e['employeeCode']?.toString() : n;
      }
    }
    return null;
  }

  String? _replacementName() => _replacementLabel();

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

  List<dynamic> _replacementCandidates() {
    final others = widget.employees
        .where((e) => e['id']?.toString() != _selectedEmployeeId)
        .toList();
    String? deptId;
    for (final emp in widget.employees) {
      if (emp['id']?.toString() == _selectedEmployeeId) {
        deptId = emp['departmentId']?.toString();
        if (deptId == null && emp['department'] is Map) {
          deptId = emp['department']['id']?.toString();
        }
        break;
      }
    }
    if (deptId == null || deptId.isEmpty) return others;
    return others.where((e) {
      if (e['departmentId']?.toString() == deptId) return true;
      if (e['department'] is Map &&
          e['department']['id']?.toString() == deptId) {
        return true;
      }
      return false;
    }).toList();
  }

  Future<void> _pickEmployee() async {
    final picked = await EmployeeSearchPicker.pickId(
      context,
      items: EmployeePickerItem.fromMaps(
        widget.employees.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      ),
      selectedId: _selectedEmployeeId,
      title: 'Chọn nhân viên',
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedEmployeeId = picked;
        _selectedShiftIds.clear();
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

  Future<void> _pickReplacement() async {
    final items = EmployeePickerItem.fromMaps(
      _replacementCandidates()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
    final picked = await EmployeeSearchPicker.pickId(
      context,
      items: items,
      selectedId: _selectedReplacementId,
      title: 'Chọn người thay ca',
      allowClear: true,
    );
    if (mounted) setState(() => _selectedReplacementId = picked);
  }

  Future<void> _pickStart() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (p != null) {
      setState(() {
        _startDate = p;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
        _selectedShiftIds.clear();
      });
      _loadShiftsForDate();
      _loadAnnualBalance();
    }
  }

  Future<void> _pickEnd() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (p != null) {
      setState(() => _endDate = p);
      _loadAnnualBalance();
    }
  }

  Widget _buildBottomBar(String title) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _border)),
        ),
        child: Row(
          children: [
            if (_step > 0 && !_isEditMode)
              TextButton(onPressed: _isSubmitting ? null : _back, child: Text(tr('Quay lại'))),
            const Spacer(),
            if (_step < _totalSteps - 1 && !_isEditMode)
              FilledButton(onPressed: _next, child: Text(tr('Tiếp')))
            else
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(tr(_isEditMode ? 'Cập nhật' : 'Gửi đơn')),
              ),
          ],
        ),
      ),
    );
  }

  void _showLegalGuide() {
    showDialog<void>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Quy định nghỉ phép (tóm tắt)')),
        content: SingleChildScrollView(
          child: Text(
            tr('• DN trả lương: phép năm, lễ, VR có lương, nghỉ bù, ốm dùng phép năm.\n'
            '• Không lương: VR không lương, nghỉ dài hạn không lương.\n'
            '• BHXH: ốm hưởng BHXH, thai sản — cần giấy tờ, không trùng lương DN cùng ngày.\n'
            '• Mỗi ngày chỉ một chế độ.\n'
            '• Ca nghỉ theo Thiết lập lương; người thay ca cùng phòng ban.'),
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final entry = _entry ??
        (_isEditMode && widget.existingLeave != null
            ? LeaveCatalog.findEntry(
                leaveType: normalizeLeaveType(widget.existingLeave!['type']),
                sickMode: SickLeaveMode.fromValue(
                    widget.existingLeave!['sickLeaveMode'] ?? 0),
              )
            : null);
    if (entry == null) {
      _toast('Chọn loại nghỉ', error: true);
      return;
    }
    if (widget.isManager && !_isEditMode && _selectedEmployeeId == null) {
      _toast('Chọn nhân viên', error: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (entry.usesAnnualBalance &&
        !_countAsWork &&
        _annualBalanceRemaining != null &&
        _daysNeeded > _annualBalanceRemaining!) {
      _toast(
        'Không đủ phép năm (còn ${_annualBalanceRemaining!.toStringAsFixed(1)}, cần ${_daysNeeded.toStringAsFixed(1)})',
        error: true,
      );
      return;
    }
    if (_selectedShiftIds.isEmpty) {
      _toast('Chọn ít nhất một ca', error: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final Map<String, dynamic> result;
      final sickMode = entry.sickLeaveMode.value;
      final bhxh = _bhxhNoteController.text.trim();

      if (_isEditMode) {
        result = await widget.apiService.updateLeave(
          leaveId: widget.existingLeave!['id'],
          shiftIds: _selectedShiftIds,
          startDate: _startDate,
          endDate: _endDate,
          type: entry.leaveType,
          isHalfShift: _isHalfShift,
          reason: _reasonController.text.trim(),
          replacementEmployeeId: _selectedReplacementId,
          countAsWork: widget.isManager ? _countAsWork : null,
          sickLeaveMode: sickMode,
          bhxhDocumentNote: bhxh.isEmpty ? null : bhxh,
        );
      } else {
        result = await widget.apiService.createLeave(
          shiftIds: _selectedShiftIds,
          startDate: _startDate,
          endDate: _endDate,
          type: entry.leaveType,
          isHalfShift: _isHalfShift,
          reason: _reasonController.text.trim(),
          replacementEmployeeId: _selectedReplacementId,
          employeeUserId: widget.isManager ? _selectedEmployeeUserId : null,
          employeeId: widget.isManager ? _selectedEmployeeId : null,
          countAsWork: widget.isManager ? _countAsWork : null,
          autoApprove: widget.isManager ? _autoApprove : null,
          sickLeaveMode: sickMode,
          bhxhDocumentNote: bhxh.isEmpty ? null : bhxh,
        );
      }

      if (!mounted) return;
      if (result['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(
          title: 'Thành công',
          message: _isEditMode ? 'Đã cập nhật đơn' : 'Đã gửi đơn nghỉ phép',
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
