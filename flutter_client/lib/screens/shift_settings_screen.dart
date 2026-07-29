import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../widgets/app_scroll_safe.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../utils/responsive_helper.dart';
import '../models/hrm.dart';
import '../models/employee.dart';
import '../widgets/app_button.dart';
import '../widgets/hrm/hrm_settings_mobile_kit.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import '../design_system/design_system.dart';
class ShiftSettingsScreen extends StatefulWidget {
  const ShiftSettingsScreen({super.key});

  @override
  State<ShiftSettingsScreen> createState() => _ShiftSettingsScreenState();
}

class _ShiftSettingsScreenState extends State<ShiftSettingsScreen> {
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  final ApiService _apiService = ApiService();
  List<Shift> _shifts = [];
  List<Employee> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Shift? _selectedShift;
  String? _filterBranchId;
  List<Map<String, dynamic>> _branches = [];

  // Pagination
  int _shiftPage = 1;
  final int _shiftPageSize = 50;

  static const _primaryColor = HrmPageChrome.primaryNavy;
  static const _bgColor = Color(0xFFFAFAFA);
  static const _borderColor = Color(0xFFE4E4E7);
  static const _textDark = Color(0xFF18181B);
  static const _textMuted = Color(0xFF71717A);

  final List<Color> _badgeColors = [
    HrmPageChrome.primaryNavy,
    HrmPageChrome.primaryNavy,
    const Color(0xFFF59E0B),
    HrmPageChrome.primaryNavy,
    const Color(0xFFEC4899),
    const Color(0xFFEF4444),
    const Color(0xFF2D5F8B),
    HrmPageChrome.primaryNavy,
  ];

  final List<String> _shiftTypes = ['Hành chính', 'Tăng ca', 'Qua đêm'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getShifts(),
        _apiService.getEmployeesForSelect(),
      ]);
      final shifts = results[0];
      final emps = results[1];
      setState(() {
        _shifts = shifts.map((s) => Shift.fromJson(s)).toList();
        _employees = emps.map((e) => Employee.fromJson(e)).toList();
        if (_selectedShift != null) {
          final idx = _shifts.indexWhere((s) => s.id == _selectedShift!.id);
          _selectedShift = idx >= 0 ? _shifts[idx] : null;
        }
      });
      // Load branches after employees
      try {
        final br = await _apiService.getBranchesForSelect();
        final bd = br['data'];
        if (bd is List && mounted) {
          setState(() => _branches =
              bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Error loading shift data: $e');
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi tải dữ liệu',
          message: tr('Không thể tải danh sách ca: $e'),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Shift> get _filteredShifts {
    if (_searchQuery.isEmpty) return _shifts;
    return _shifts
        .where((s) =>
            s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            s.code.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  String _getShiftType(Shift shift) {
    // Read from dedicated shiftType field if available
    final st = shift.shiftType?.toLowerCase() ?? '';
    if (st.contains('tăng ca') || st.contains('overtime') || st == 'tangca') {
      return 'Tăng ca';
    }
    if (st.contains('qua đêm') || st.contains('overnight') || st == 'quadem') {
      return 'Qua đêm';
    }
    if (st.isNotEmpty) return 'Hành chính';
    // Fallback to description for old data
    final desc = shift.description?.toLowerCase() ?? '';
    if (desc.contains('qua đêm') || desc.contains('overnight')) {
      return 'Qua đêm';
    }
    if (desc.contains('tăng ca') || desc.contains('overtime')) return 'Tăng ca';
    return 'Hành chính';
  }

  Color _getShiftTypeColor(String type) {
    switch (type) {
      case 'Tăng ca':
        return const Color(0xFFF59E0B);
      case 'Qua đêm':
        return HrmPageChrome.primaryNavy;
      default:
        return HrmPageChrome.primaryNavy;
    }
  }

  IconData _getShiftTypeIcon(String type) {
    switch (type) {
      case 'Tăng ca':
        return Icons.more_time;
      case 'Qua đêm':
        return Icons.nightlight_round;
      default:
        return Icons.wb_sunny_outlined;
    }
  }

  String _formatTime(String time) {
    final parts = time.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return time;
  }

  String _calculateWorkHours(String startTime, String endTime,
      {TimeOfDay? lunchStart, TimeOfDay? lunchEnd}) {
    try {
      final sp = startTime.split(':');
      final ep = endTime.split(':');
      int startMin = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      int endMin = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      if (endMin <= startMin) endMin += 24 * 60;
      var diff = endMin - startMin;
      if (lunchStart != null && lunchEnd != null) {
        final lunchStartMin = lunchStart.hour * 60 + lunchStart.minute;
        final lunchEndMin = lunchEnd.hour * 60 + lunchEnd.minute;
        if (lunchEndMin > lunchStartMin) diff -= lunchEndMin - lunchStartMin;
      }
      if (diff < 0) diff = 0;
      return '${(diff ~/ 60).toString().padLeft(2, '0')}:${(diff % 60).toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--';
    }
  }

  TimeOfDay? _timeOfDayFromShiftString(String? t) {
    if (t == null || t.isEmpty) return null;
    final parts = t.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String _timeOfDayToApi(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  String _getShiftAbbreviation(Shift shift) {
    if (shift.code.isNotEmpty && shift.code.length <= 3) {
      return shift.code.toUpperCase();
    }
    final words = shift.name.split(' ');
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}'.toUpperCase();
    return shift.name
        .substring(0, shift.name.length >= 2 ? 2 : shift.name.length)
        .toUpperCase();
  }

  /// Thanh tìm ca — luôn hiển thị (không ẩn sau nút filter).
  Widget _buildShiftSearchField() {
    return TextField(
      decoration: InputDecoration(
        hintText: tr('Tìm theo tên ca...'),
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => setState(() {
                  _searchQuery = '';
                  _shiftPage = 1;
                }),
              )
            : null,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _borderColor)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _borderColor)),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        isDense: true,
        filled: true,
        fillColor: _bgColor,
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (v) => setState(() {
        _searchQuery = v;
        _shiftPage = 1;
      }),
    );
  }

  Widget _buildGuideButton({bool compact = false}) {
    return InkWell(
      onTap: _showShiftGuide,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12, vertical: compact ? 8 : 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: const Color(0xFFFB923C).withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined,
                size: 16, color: Color(0xFFEA580C)),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(tr('Hướng dẫn'),
                  style: TextStyle(
                      color: Color(0xFFEA580C),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddShiftButton({bool compact = false}) {
    if (!_perm.canCreate('ShiftSetup')) return const SizedBox.shrink();
    if (HrmSettingsMobileKit.active(context) && compact) {
      return HrmSettingsAddButton(
        label: 'Thêm ca',
        compact: true,
        onPressed: () => _showShiftDialog(),
      );
    }
    return FilledButton.icon(
      onPressed: () => _showShiftDialog(),
      icon: const Icon(Icons.add, size: 18),
      label: Text(tr(compact ? 'Thêm' : 'Thêm ca')),
      style: FilledButton.styleFrom(
        backgroundColor: HrmPageChrome.primaryNavy,
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 20, vertical: compact ? 8 : 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      body: _isLoading
          ? const LoadingWidget()
          : isMobile
              ? _buildMainContent()
              : Row(
                  children: [
                    Expanded(
                      flex: _selectedShift != null ? 6 : 1,
                      child: _buildMainContent(),
                    ),
                    if (_selectedShift != null) ...[
                      Container(width: 1, color: _borderColor),
                      Expanded(
                          flex: 4, child: _buildDetailPanel(_selectedShift!)),
                    ],
                  ],
                ),
    );
  }

  Widget _buildMainContent() {
    final isMobile = Responsive.isMobile(context);
    if (isMobile) {
      return _buildMobileContent();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 12 : 20,
              isMobile ? 16 : 24, isMobile ? 12 : 16),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!HrmPageChrome.isEmbedded) ...[
                Row(
                  children: [
                    const Icon(Icons.schedule,
                        color: HrmPageChrome.primaryNavy, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tr('Thiết lập Ca & Chấm công'),
                          style: TextStyle(
                              fontSize: isMobile ? 16 : 20,
                              fontWeight: FontWeight.bold,
                              color: _textDark)),
                    ),
                    _buildGuideButton(compact: isMobile),
                    const SizedBox(width: 8),
                    _buildAddShiftButton(compact: isMobile),
                  ],
                ),
                const SizedBox(height: 12),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _buildShiftSearchField()),
                    const SizedBox(width: 10),
                    _buildGuideButton(compact: isMobile),
                    const SizedBox(width: 8),
                    _buildAddShiftButton(compact: isMobile),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (HrmPageChrome.isEmbedded)
                _buildShiftStatsBar()
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _buildShiftStatsBar()),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 280,
                      child: _buildShiftSearchField(),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Content - Cards on mobile, Table on desktop
        Expanded(
          child: _filteredShifts.isEmpty
              ? _buildEmptyState()
              : isMobile
                  ? _buildShiftCardList()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              minWidth: MediaQuery.of(context).size.width - 48),
                          child: Container(
                            width: 650,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _borderColor),
                            ),
                            child: Column(
                              children: [
                                // Table header
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  decoration: const BoxDecoration(
                                    color: _bgColor,
                                    borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(12),
                                        topRight: Radius.circular(12)),
                                  ),
                                  child: Row(
                                    children: [
                                      _tableHeader('Ca làm việc', flex: 3),
                                      _tableHeader('Giờ vào', flex: 2),
                                      _tableHeader('Giờ ra', flex: 2),
                                      _tableHeader('Tổng giờ', flex: 2),
                                      _tableHeader('Loại ca', flex: 2),
                                      _tableHeader('Trạng thái', flex: 2),
                                    ],
                                  ),
                                ),
                                const Divider(height: 24, color: _borderColor),
                                // Table rows - paginated
                                Builder(builder: (_) {
                                  final allShifts = _filteredShifts;
                                  final totalPages =
                                      (allShifts.length / _shiftPageSize)
                                          .ceil();
                                  final safePage = _shiftPage.clamp(
                                      1, totalPages == 0 ? 1 : totalPages);
                                  final startIdx =
                                      (safePage - 1) * _shiftPageSize;
                                  final endIdx = (startIdx + _shiftPageSize)
                                      .clamp(0, allShifts.length);
                                  return Column(children: [
                                    ...List.generate(endIdx - startIdx, (i) {
                                      final index = startIdx + i;
                                      final shift = allShifts[index];
                                      final isSelected =
                                          _selectedShift?.id == shift.id;
                                      return _buildTableRow(
                                          shift, index, isSelected);
                                    }),
                                    if (totalPages > 1)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            IconButton(
                                                icon: const Icon(
                                                    Icons.first_page),
                                                onPressed: safePage > 1
                                                    ? () => setState(
                                                        () => _shiftPage = 1)
                                                    : null),
                                            IconButton(
                                                icon: const Icon(
                                                    Icons.chevron_left),
                                                onPressed: safePage > 1
                                                    ? () => setState(
                                                        () => _shiftPage--)
                                                    : null),
                                            Text(
                                                tr('Trang $safePage / $totalPages (${allShifts.length} ca)'),
                                                style: const TextStyle(
                                                    fontSize: 13)),
                                            IconButton(
                                                icon: const Icon(
                                                    Icons.chevron_right),
                                                onPressed: safePage < totalPages
                                                    ? () => setState(
                                                        () => _shiftPage++)
                                                    : null),
                                            IconButton(
                                                icon:
                                                    const Icon(Icons.last_page),
                                                onPressed: safePage < totalPages
                                                    ? () => setState(() =>
                                                        _shiftPage = totalPages)
                                                    : null),
                                          ],
                                        ),
                                      ),
                                  ]);
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _tableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(tr(text),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _textMuted,
              letterSpacing: 0.5)),
    );
  }

  Widget _buildTableRow(Shift shift, int index, bool isSelected) {
    final color = _badgeColors[index % _badgeColors.length];
    final shiftType = _getShiftType(shift);
    final typeColor = _getShiftTypeColor(shiftType);
    final workHours = _calculateWorkHours(shift.startTime, shift.endTime);

    final tooltipMsg =
        'Chấm sớm: ${shift.earlyCheckInMinutes ?? 30}p  •  Trễ TĐ: ${shift.maximumAllowedLateMinutes ?? 30}p  •  Về sớm TĐ: ${shift.maximumAllowedEarlyLeaveMinutes ?? 30}p\n'
        'Grace trễ: ${shift.lateGraceMinutes ?? 5}p  •  Grace về sớm: ${shift.earlyLeaveGraceMinutes ?? 5}p'
        '${shift.lunchBreakStartTime != null && shift.lunchBreakEndTime != null ? '\nNghỉ giữa ca: ${_formatTime(shift.lunchBreakStartTime!)} – ${_formatTime(shift.lunchBreakEndTime!)} (chấm trong khung → tăng ca)' : ''}'
        '${(shift.breakMinutes ?? 0) > 0 ? '  •  Nghỉ giữa ca (phút): ${shift.breakMinutes}p' : ''}'
        '${(shift.overtimeMinutesThreshold ?? 0) > 0 ? '  •  Tăng ca sau ca: ${shift.overtimeMinutesThreshold}p' : ''}'
        '${(shift.earlyOvertimeMinutesThreshold ?? 0) > 0 ? '  •  Tăng ca trước ca: ${shift.earlyOvertimeMinutesThreshold}p' : ''}';

    return Tooltip(
      message: tooltipMsg,
      waitDuration: const Duration(milliseconds: 400),
      textStyle:
          const TextStyle(fontSize: 12, color: Colors.white, height: 1.5),
      decoration: BoxDecoration(
          color: const Color(0xFF334155),
          borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: InkWell(
        onTap: () => setState(() => _selectedShift = shift),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? _primaryColor.withValues(alpha: 0.06)
                : Colors.white,
            border: Border(
              bottom: const BorderSide(color: _borderColor, width: 0.5),
              left: isSelected
                  ? const BorderSide(color: _primaryColor, width: 3)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              // Shift name with badge
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8)),
                      child: Center(
                          child: Text(tr(_getShiftAbbreviation(shift)),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: color))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(shift.name),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _textDark),
                              overflow: TextOverflow.ellipsis),
                          Text(tr(shift.code),
                              style: const TextStyle(
                                  fontSize: 11, color: _textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Start time
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Icon(Icons.login, size: 14, color: Colors.green[400]),
                    const SizedBox(width: 4),
                    Text(tr(_formatTime(shift.startTime)),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _textDark)),
                  ],
                ),
              ),
              // End time
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 14, color: Colors.red[400]),
                    const SizedBox(width: 4),
                    Text(tr(_formatTime(shift.endTime)),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _textDark)),
                  ],
                ),
              ),
              // Total hours
              Expanded(
                flex: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: _bgColor, borderRadius: BorderRadius.circular(6)),
                  child: Text(tr(workHours),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textDark),
                      textAlign: TextAlign.center),
                ),
              ),
              // Type
              Expanded(
                flex: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getShiftTypeIcon(shiftType),
                          size: 13, color: typeColor),
                      const SizedBox(width: 4),
                      Flexible(
                          child: Text(tr(shiftType),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: typeColor),
                              overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
              // Status
              Expanded(
                flex: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: shift.isActive
                        ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          shift.isActive
                              ? Icons.check_circle
                              : Icons.pause_circle,
                          size: 13,
                          color: shift.isActive
                              ? HrmPageChrome.primaryNavy
                              : Colors.grey),
                      const SizedBox(width: 4),
                      Text(tr(shift.isActive ? 'Kích hoạt' : 'Tạm dừng'),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: shift.isActive
                                  ? HrmPageChrome.primaryNavy
                                  : Colors.grey)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== MOBILE FULL-SCROLL LAYOUT =====
  Widget _buildMobileContent() {
    final allShifts = _filteredShifts;
    final embeddedKit = HrmSettingsMobileKit.active(context);

    if (embeddedKit) {
      return ColoredBox(
        color: PosTheme.background,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HrmSettingsSearchToolbar(
                      search: _buildShiftSearchField(),
                      actions: [
                        _buildGuideButton(compact: true),
                        _buildAddShiftButton(compact: true),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildShiftStatsBar(),
                  ],
                ),
              ),
            ),
            if (allShifts.isEmpty)
              SliverFillRemaining(child: _buildEmptyState())
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: HrmSettingsEntityGrid(
                    itemCount: allShifts.length,
                    columns: 2,
                    childAspectRatio: 0.95,
                    itemBuilder: (ctx, i) =>
                        _buildShiftGridTile(allShifts[i], i),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // Header scrolls with content
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!HrmPageChrome.isEmbedded)
                  Row(
                    children: [
                      const Icon(Icons.schedule,
                          color: HrmPageChrome.primaryNavy, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('Thiết lập Ca & Chấm công'),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _textDark)),
                      ),
                    ],
                  ),
                if (!HrmPageChrome.isEmbedded) const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _buildShiftSearchField()),
                    const SizedBox(width: 8),
                    _buildGuideButton(compact: true),
                    const SizedBox(width: 8),
                    _buildAddShiftButton(compact: true),
                  ],
                ),
                const SizedBox(height: 12),
                _buildShiftStatsBar(),
              ],
            ),
          ),
        ),
        // Cards - all items, no pagination
        if (allShifts.isEmpty)
          SliverFillRemaining(child: _buildEmptyState())
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: List.generate(
                    allShifts.length,
                    (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFE4E4E7)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: _buildShiftDeckItem(allShifts[i], i),
                          ),
                        )),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildShiftGridTile(Shift shift, int index) {
    final shiftType = _getShiftType(shift);
    final typeColor = _getShiftTypeColor(shiftType);
    final color = _badgeColors[index % _badgeColors.length];

    return HrmSettingsEntityTile(
      title: shift.name,
      subtitle:
          '${_formatTime(shift.startTime)} – ${_formatTime(shift.endTime)}',
      icon: _getShiftTypeIcon(shiftType),
      iconColor: color,
      badge: shiftType,
      badgeColor: typeColor,
      onTap: () => _showShiftDialog(shift: shift),
    );
  }

  // ===== MOBILE CARD VIEW =====
  Widget _buildShiftCardList() {
    final allShifts = _filteredShifts;
    final totalPages = (allShifts.length / _shiftPageSize).ceil();
    final safePage = _shiftPage.clamp(1, totalPages == 0 ? 1 : totalPages);
    final startIdx = (safePage - 1) * _shiftPageSize;
    final endIdx = (startIdx + _shiftPageSize).clamp(0, allShifts.length);
    final pageShifts = allShifts.sublist(startIdx, endIdx);

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: pageShifts.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _buildShiftDeckItem(pageShifts[i], startIdx + i),
              ),
            ),
          ),
        ),
        if (totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: safePage > 1
                        ? () => setState(() => _shiftPage--)
                        : null),
                Text(tr('$safePage / $totalPages'),
                    style: const TextStyle(fontSize: 13)),
                IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed: safePage < totalPages
                        ? () => setState(() => _shiftPage++)
                        : null),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildShiftDeckItem(Shift shift, int index) {
    final color = _badgeColors[index % _badgeColors.length];
    final shiftType = _getShiftType(shift);
    final typeColor = _getShiftTypeColor(shiftType);
    final workHours = _calculateWorkHours(shift.startTime, shift.endTime);

    return InkWell(
      onTap: () => _showMobileDetailSheet(shift),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Center(
                  child: Text(tr(_getShiftAbbreviation(shift)),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(shift.name),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _textDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    tr('${_formatTime(shift.startTime)} – ${_formatTime(shift.endTime)} · $workHours'),
                    style: const TextStyle(fontSize: 12, color: _textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(tr(shiftType),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: typeColor)),
            ),
            const SizedBox(width: 6),
            Icon(shift.isActive ? Icons.check_circle : Icons.pause_circle,
                size: 14,
                color: shift.isActive ? HrmPageChrome.primaryNavy : Colors.grey),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: _textMuted),
          ],
        ),
      ),
    );
  }

  void _showMobileDetailSheet(Shift shift) {
    showAppSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child:
                    _buildDetailPanel(shift, onClose: () => Navigator.pop(ctx)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== DETAIL PANEL =====
  Widget _buildDetailPanel(Shift shift, {VoidCallback? onClose}) {
    final shiftType = _getShiftType(shift);
    final typeColor = _getShiftTypeColor(shiftType);
    final color = _badgeColors[_shifts.indexOf(shift) % _badgeColors.length];
    final workHours = _calculateWorkHours(shift.startTime, shift.endTime);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Panel header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _borderColor))),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(10)),
                  child: Center(
                      child: Text(tr(_getShiftAbbreviation(shift)),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(shift.name),
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _textDark)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(tr(shiftType),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: typeColor)),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: shift.isActive
                                  ? HrmPageChrome.primaryNavy
                                      .withValues(alpha: 0.1)
                                  : Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tr(shift.isActive ? 'Kích hoạt' : 'Tạm dừng'),
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: shift.isActive
                                      ? HrmPageChrome.primaryNavy
                                      : Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed:
                      onClose ?? () => setState(() => _selectedShift = null),
                  icon: const Icon(Icons.close, size: 20, color: _textMuted),
                ),
              ],
            ),
          ),

          // Panel content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: _bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _borderColor)),
                    child: Row(
                      children: [
                        _buildTimeBlock('Giờ vào', _formatTime(shift.startTime),
                            Icons.login, Colors.green),
                        const SizedBox(width: 12),
                        Column(
                          children: [
                            Icon(Icons.arrow_forward,
                                color: Colors.grey[400], size: 16),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: _primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(tr(workHours),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _primaryColor)),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        _buildTimeBlock('Giờ ra', _formatTime(shift.endTime),
                            Icons.logout, Colors.red),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Attendance parameters
                  Text(tr('Thông số chấm công'),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _textDark)),
                  const SizedBox(height: 10),
                  _buildParamRow(Icons.fast_forward, 'Cho phép chấm sớm',
                      '${shift.earlyCheckInMinutes ?? 30} phút', AppColors.info),
                  _buildParamRow(
                      Icons.schedule,
                      'Cho phép chấm trễ',
                      '${shift.maximumAllowedLateMinutes ?? 30} phút',
                      Colors.orange),
                  _buildParamRow(
                      Icons.exit_to_app,
                      'Cho phép về sớm',
                      '${shift.maximumAllowedEarlyLeaveMinutes ?? 30} phút',
                      Colors.purple),
                  _buildParamRow(Icons.alarm, 'Tính đi trễ sau',
                      '${shift.lateGraceMinutes ?? 5} phút', Colors.red),
                  _buildParamRow(Icons.alarm_off, 'Tính về sớm sau',
                      '${shift.earlyLeaveGraceMinutes ?? 5} phút', Colors.pink),
                  if (shift.lunchBreakStartTime != null &&
                      shift.lunchBreakEndTime != null)
                    _buildParamRow(
                        Icons.free_breakfast,
                        'Nghỉ giữa ca',
                        '${_formatTime(shift.lunchBreakStartTime!)} – ${_formatTime(shift.lunchBreakEndTime!)}',
                        Colors.brown),
                  if (shift.breakMinutes != null && shift.breakMinutes! > 0)
                    _buildParamRow(Icons.coffee, 'Nghỉ giữa ca (phút)',
                        '${shift.breakMinutes} phút', Colors.teal),
                  if (shift.overtimeMinutesThreshold != null &&
                      shift.overtimeMinutesThreshold! > 0)
                    _buildParamRow(Icons.more_time, 'Tăng ca sau ca',
                        '${shift.overtimeMinutesThreshold} phút', Colors.amber),
                  if (shift.earlyOvertimeMinutesThreshold != null &&
                      shift.earlyOvertimeMinutesThreshold! > 0)
                    _buildParamRow(Icons.more_time, 'Tăng ca trước ca',
                        '${shift.earlyOvertimeMinutesThreshold} phút',
                        Colors.orange),
                  const SizedBox(height: 20),

                  // Shift info
                  Text(tr('Thông tin khác'),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _textDark)),
                  const SizedBox(height: 10),
                  _buildInfoRow('Mã viết tắt', shift.code),
                  _buildInfoRow('Ngày tạo',
                      '${shift.createdAt.day}/${shift.createdAt.month}/${shift.createdAt.year}'),
                  if (shift.description != null &&
                      shift.description!.isNotEmpty)
                    _buildInfoRow('Ghi chú', shift.description!),
                ],
              ),
            ),
          ),

          // Action buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _borderColor))),
            child: Row(
              children: [
                if (_perm.canEdit('ShiftSetup'))
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showShiftDialog(shift: shift),
                      icon: const Icon(Icons.edit, size: 16),
                      label: Text(tr('Sửa'), style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryColor,
                        side: const BorderSide(color: _primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                if (_perm.canEdit('ShiftSetup')) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showShiftSalaryDialog(shift),
                      icon: const Icon(Icons.payments, size: 16),
                      label: Text(tr('Lương ca'),
                          style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF59E0B),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
                if (_perm.canDelete('ShiftSetup')) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _deleteShift(shift),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBlock(
      String label, String time, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color.withValues(alpha: 0.7), size: 20),
          const SizedBox(height: 4),
          Text(tr(time),
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(tr(label), style: const TextStyle(fontSize: 11, color: _textMuted)),
        ],
      ),
    );
  }

  Widget _buildParamRow(
      IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(tr(label),
                    style: const TextStyle(fontSize: 13, color: _textDark))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(tr(value),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(tr(label),
                  style: const TextStyle(fontSize: 12, color: _textMuted))),
          Expanded(
              child: Text(tr(value),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _textDark))),
        ],
      ),
    );
  }

  Widget _buildShiftStatsBar() {
    return HrmPageChrome.horizontalStatCards(
      cards: [
        _buildStatCard(Icons.schedule, '${_shifts.length}', 'Tổng ca',
            HrmPageChrome.primaryNavy),
        _buildStatCard(
            Icons.check_circle,
            '${_shifts.where((s) => s.isActive).length}',
            'Kích hoạt',
            HrmPageChrome.primaryNavy),
        _buildStatCard(
            Icons.more_time,
            '${_shifts.where((s) => _getShiftType(s) == 'Tăng ca').length}',
            'Tăng ca',
            const Color(0xFFF59E0B)),
        _buildStatCard(
            Icons.nightlight_round,
            '${_shifts.where((s) => _getShiftType(s) == 'Qua đêm').length}',
            'Qua đêm',
            HrmPageChrome.primaryNavy),
      ],
      minCardWidth: 120,
      gap: 10,
    );
  }

  Widget _buildStatCard(
      IconData icon, String value, String label, Color color) {
    return HrmStatSummaryCard(
      icon: icon,
      value: value,
      label: label,
      color: color,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(tr('Chưa có ca làm việc'),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text(tr('Nhấn "Thêm ca" để bắt đầu tạo ca mới'),
              style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _showShiftDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(tr('Thêm ca mới')),
            style: FilledButton.styleFrom(
              backgroundColor: HrmPageChrome.primaryNavy,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ===== SHIFT FORM DIALOG =====
  // ==================== HƯỚNG DẪN SET CA & CHẤM CÔNG ====================
  void _showShiftGuide() {
    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.menu_book, color: Color(0xFFEA580C)),
            SizedBox(width: 8),
            Expanded(
              child: Text(tr('Hướng dẫn thiết lập ca & chấm công'),
                style: TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 17),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: Responsive.dialogWidth(context),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGuideSection(
                  '1. Tạo và thiết lập ca',
                  Icons.add_circle_outline,
                  HrmPageChrome.primaryNavy,
                  [
                    'Bấm «Thêm ca» → nhập tên, mã, giờ vào / giờ ra.',
                    'Chọn loại ca: Hành chính (ca chính), Tăng ca (OT riêng), hoặc Qua đêm.',
                    'Điền thông số chấm công (chấm sớm, trễ, về sớm, tăng ca…).',
                    'Lưu ca → gán ca cho nhân viên trong hồ sơ / lịch làm việc.',
                  ],
                ),
                const Divider(height: 28),
                _buildGuideSection(
                  '2. Ý nghĩa các thông số chấm công',
                  Icons.tune,
                  const Color(0xFF0EA5E9),
                  [
                    'Cho phép chấm sớm: cửa sổ ghép ca. Chấm sớm hơn ngưỡng này → không khớp ca.',
                    'Cho phép chấm trễ / về sớm: giới hạn tối đa vẫn còn thuộc ca.',
                    'Tính đi trễ sau / về sớm sau (grace): trong khoảng này không bị trừ trễ/sớm.',
                    'Tăng ca trước ca: chấm vào sớm hơn ngưỡng này mới được tính OT trước giờ vào ca.',
                    'Tăng ca sau ca: ra muộn hơn ngưỡng này mới được tính OT sau giờ tan ca.',
                    'Nên đặt «Cho phép chấm sớm» ≥ «Tăng ca trước ca» (+1 phút) để OT trước ca có hiệu lực.',
                  ],
                ),
                const Divider(height: 28),
                _buildGuideSection(
                  '3. Ví dụ cấu hình (ca 07:00–11:00)',
                  Icons.lightbulb_outline,
                  const Color(0xFFF59E0B),
                  [
                    'Cho phép chấm sớm = 60 phút → nhận chấm từ 06:00.',
                    'Tăng ca trước ca = 30 phút → vào 06:15 tính OT 45p; vào 06:31 không tính OT.',
                    'Tăng ca sau ca = 30 phút → ra 11:31 tính OT 31p; ra 11:30 không tính OT.',
                    'Giờ làm ca vẫn tính theo khung 07:00–11:00 khi đúng giờ (không trễ/sớm/OT).',
                  ],
                ),
                _buildGuideExampleCard(
                  title: 'Ví dụ tăng ca trước ca',
                  rows: const [
                    'Vào 06:15 → Ra 11:00 → OT trước ca 45 phút',
                    'Vào 06:31 → Ra 11:00 → Không OT (sớm ≤ 30p)',
                  ],
                ),
                const Divider(height: 28),
                _buildGuideSection(
                  '4. Cách chấm công cho nhân viên (ca hành chính)',
                  Icons.fingerprint,
                  const Color(0xFF059669),
                  [
                    'Ca bình thường: Vào đầu ca → Ra cuối ca (1 cặp Vào/Ra).',
                    'Làm OT sau ca (khuyến nghị): Không chấm Ra lúc hết ca — chỉ Ra khi xong OT.',
                    'Ví dụ: ca 07:00–11:00, làm đến 13:00 → Vào 07:00, Ra 13:00 → OT 120 phút.',
                    'Chưa chấm Ra: hệ thống báo thiếu chấm, không tính OT.',
                  ],
                ),
                _buildGuideExampleCard(
                  title: 'Đúng / Sai khi làm OT sau ca',
                  rows: const [
                    '✅ Vào 07:00 → Ra 13:00 (không Ra lúc 11:00) → OT đúng',
                    '❌ Vào 07:00 → Ra 11:00 → Ra 13:00 → dễ mất OT 11:00–13:00',
                    '❌ Vào 07:00, không Ra → thiếu chấm, OT = 0',
                  ],
                ),
                const Divider(height: 28),
                _buildGuideSection(
                  '5. Khi muốn chấm Ra đúng giờ tan ca rồi làm OT tiếp',
                  Icons.more_time,
                  const Color(0xFFEA580C),
                  [
                    'Tạo thêm ca loại «Tăng ca» (VD 11:30–13:00) và gán cho nhân viên.',
                    'Nhân viên: Vào/Ra ca hành chính → rồi Vào/Ra ca tăng ca riêng.',
                    'Ví dụ: 07:00–11:00 (ca HC) + 11:30–13:00 (ca Tăng ca) → OT lấy từ ca Tăng ca.',
                    'Không có ca Tăng ca mà vẫn Vào lại sau tan ca → thường không khớp ca HC.',
                  ],
                ),
                const Divider(height: 28),
                _buildGuideSection(
                  '6. Loại ca',
                  Icons.category_outlined,
                  HrmPageChrome.primaryNavy,
                  [
                    'Hành chính: ca chính — tính trễ, sớm, OT trước/sau ca theo ngưỡng.',
                    'Tăng ca: toàn bộ giờ làm thực tế tính vào OT (không tính đi trễ/về sớm).',
                    'Qua đêm: ca qua nửa đêm — hệ số lương ca đêm áp dụng theo quy định.',
                  ],
                ),
                const Divider(height: 28),
                _buildGuideSection(
                  '7. Checklist nhanh cho quản lý',
                  Icons.checklist,
                  const Color(0xFF7C3AED),
                  [
                    'Đã tạo đủ ca HC (và ca Tăng ca nếu cần OT tách riêng).',
                    'Đã gán ca cho nhân viên / lịch làm việc.',
                    'Cho phép chấm sớm đủ lớn so với Tăng ca trước ca.',
                    'Đã hướng dẫn NV: 1 cặp Vào–Ra khi làm liền OT sau ca.',
                    'Kiểm tra «Tổng hợp theo ca» sau ngày làm mẫu.',
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
                backgroundColor: HrmPageChrome.primaryNavy),
            child: Text(tr('Đã hiểu')),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideSection(
      String title, IconData icon, Color color, List<String> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr(title),
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...steps.map((step) => Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('• '), style: TextStyle(color: _textMuted)),
                  Expanded(
                    child: Text(tr(step),
                        style: const TextStyle(
                            color: Color(0xFF52525B),
                            fontSize: 13,
                            height: 1.45)),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildGuideExampleCard({
    required String title,
    required List<String> rows,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(title),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _textDark)),
            const SizedBox(height: 8),
            ...rows.map((row) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(tr(row),
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: Color(0xFF475569))),
                )),
          ],
        ),
      ),
    );
  }

  void _showShiftDialog({Shift? shift}) {
    final isEditing = shift != null;
    final nameCtrl = TextEditingController(text: tr(shift?.name ?? ''));
    final codeCtrl = TextEditingController(text: tr(shift?.code ?? ''));
    TimeOfDay startTime = TimeOfDay(
      hour: int.tryParse(shift?.startTime.split(':')[0] ?? '8') ?? 8,
      minute: int.tryParse(shift?.startTime.split(':')[1] ?? '0') ?? 0,
    );
    TimeOfDay endTime = TimeOfDay(
      hour: int.tryParse(shift?.endTime.split(':')[0] ?? '17') ?? 17,
      minute: int.tryParse(shift?.endTime.split(':')[1] ?? '0') ?? 0,
    );
    bool isActive = shift?.isActive ?? true;
    String shiftType = _getShiftType(shift ??
        Shift(
            id: '',
            name: '',
            code: '',
            startTime: '08:00:00',
            endTime: '17:00:00',
            isActive: true,
            createdAt: DateTime.now()));

    // Attendance params
    int earlyCheckIn = shift?.earlyCheckInMinutes ?? 30;
    int allowLate = shift?.maximumAllowedLateMinutes ?? 30;
    int allowEarlyLeave = shift?.maximumAllowedEarlyLeaveMinutes ?? 30;
    int lateGrace = shift?.lateGraceMinutes ?? 5;
    int earlyLeaveGrace = shift?.earlyLeaveGraceMinutes ?? 5;
    int breakMinutes = shift?.breakMinutes ?? 30;
    int overtimeThreshold = shift?.overtimeMinutesThreshold ?? 30;
    int earlyOvertimeThreshold = shift?.earlyOvertimeMinutesThreshold ?? 30;
    TimeOfDay lunchBreakStart = _timeOfDayFromShiftString(
            shift?.lunchBreakStartTime) ??
        const TimeOfDay(hour: 11, minute: 30);
    TimeOfDay lunchBreakEnd =
        _timeOfDayFromShiftString(shift?.lunchBreakEndTime) ??
            const TimeOfDay(hour: 13, minute: 0);
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final totalHours = _calculateWorkHours(
            '${startTime.hour}:${startTime.minute}:00',
            '${endTime.hour}:${endTime.minute}:00',
            lunchStart: lunchBreakStart,
            lunchEnd: lunchBreakEnd,
          );

          final isMobile = Responsive.isMobile(context);
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(isMobile ? 0 : 16)),
            insetPadding: isMobile
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Container(
              width: isMobile
                  ? double.infinity
                  : math.min(600, MediaQuery.of(context).size.width - 32),
              constraints: BoxConstraints(
                  maxHeight: isMobile
                      ? double.infinity
                      : MediaQuery.of(context).size.height * 0.9),
              height: isMobile ? MediaQuery.of(context).size.height : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                    decoration: const BoxDecoration(
                        border:
                            Border(bottom: BorderSide(color: _borderColor))),
                    child: Row(
                      children: [
                        Icon(isEditing ? Icons.edit : Icons.add_circle,
                            color: _primaryColor, size: 22),
                        const SizedBox(width: 10),
                        Text(tr(isEditing ? 'Sửa ca làm việc' : 'Thêm ca làm việc'),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _textDark)),
                        const Spacer(),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: _textMuted),
                            visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ),

                  // Form body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: Name + Code
                          Row(
                            children: [
                              Expanded(
                                  flex: 2,
                                  child: _dialogField(
                                      'Tên ca *',
                                      TextField(
                                          controller: nameCtrl,
                                          decoration: _inputDecor(
                                              'VD: Ca sáng, Ca chiều'),
                                          style:
                                              const TextStyle(fontSize: 14)))),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: _dialogField(
                                      'Viết tắt',
                                      TextField(
                                          controller: codeCtrl,
                                          decoration: _inputDecor('VD: S, C'),
                                          style:
                                              const TextStyle(fontSize: 14)))),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Row 2: Time In + Time Out + Total
                          Row(
                            children: [
                              Expanded(
                                child: _dialogField(
                                    'Giờ vào',
                                    InkWell(
                                      onTap: () async {
                                        final t = await showTimePicker(
                                            context: ctx,
                                            initialTime: startTime);
                                        if (t != null) {
                                          setDialogState(() => startTime = t);
                                        }
                                      },
                                      child: _timeBox(
                                          startTime, Icons.login, Colors.green),
                                    )),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _dialogField(
                                    'Giờ ra',
                                    InkWell(
                                      onTap: () async {
                                        final t = await showTimePicker(
                                            context: ctx, initialTime: endTime);
                                        if (t != null) {
                                          setDialogState(() => endTime = t);
                                        }
                                      },
                                      child: _timeBox(
                                          endTime, Icons.logout, Colors.red),
                                    )),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _dialogField(
                                    'Tổng giờ',
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 12),
                                      decoration: BoxDecoration(
                                          color: _bgColor,
                                          border:
                                              Border.all(color: _borderColor),
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Row(
                                        children: [
                                          Expanded(
                                              child: Text(tr(totalHours),
                                                  style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600))),
                                          const Icon(Icons.timer,
                                              color: _textMuted, size: 18),
                                        ],
                                      ),
                                    )),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Row 3: Type + Status
                          Row(
                            children: [
                              Expanded(
                                child: _dialogField(
                                    'Loại ca',
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      decoration: BoxDecoration(
                                          border:
                                              Border.all(color: _borderColor),
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _shiftTypes.contains(shiftType)
                                              ? shiftType
                                              : 'Hành chính',
                                          isExpanded: true,
                                          icon: Icon(Icons.keyboard_arrow_down,
                                              color: Colors.grey[400]),
                                          items: _shiftTypes
                                              .map((t) => DropdownMenuItem(
                                                  value: t,
                                                  child: Row(
                                                    children: [
                                                      Icon(_getShiftTypeIcon(t),
                                                          size: 16,
                                                          color:
                                                              _getShiftTypeColor(
                                                                  t)),
                                                      const SizedBox(width: 8),
                                                      Text(tr(t),
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      14)),
                                                    ],
                                                  )))
                                              .toList(),
                                          onChanged: (v) => setDialogState(() =>
                                              shiftType = v ?? 'Hành chính'),
                                        ),
                                      ),
                                    )),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _dialogField(
                                    'Trạng thái',
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      decoration: BoxDecoration(
                                          border:
                                              Border.all(color: _borderColor),
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<bool>(
                                          value: isActive,
                                          isExpanded: true,
                                          icon: Icon(Icons.keyboard_arrow_down,
                                              color: Colors.grey[400]),
                                          items: [
                                            DropdownMenuItem(
                                                value: true,
                                                child: Row(children: [
                                                  Icon(Icons.check_circle,
                                                      size: 16,
                                                      color: Colors.green[400]),
                                                  const SizedBox(width: 8),
                                                  Text(tr('Kích hoạt'),
                                                      style: TextStyle(
                                                          fontSize: 14))
                                                ])),
                                            DropdownMenuItem(
                                                value: false,
                                                child: Row(children: [
                                                  Icon(Icons.pause_circle,
                                                      size: 16,
                                                      color: Colors.grey[400]),
                                                  const SizedBox(width: 8),
                                                  Text(tr('Tạm dừng'),
                                                      style: TextStyle(
                                                          fontSize: 14))
                                                ])),
                                          ],
                                          onChanged: (v) => setDialogState(
                                              () => isActive = v ?? true),
                                        ),
                                      ),
                                    )),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Ca qua đêm: chỉ loại ca (+ hệ số lương ở cấu hình lương).
                          // Ranh giới ngày = Thiết lập hệ thống → Giờ kết thúc ngày.
                          if (shiftType == 'Qua đêm') ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: HrmPageChrome.primaryNavy
                                    .withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: HrmPageChrome.primaryNavy
                                        .withValues(alpha: 0.25)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.nightlight_round,
                                          size: 16,
                                          color: HrmPageChrome.primaryNavy),
                                      SizedBox(width: 6),
                                      Text(tr('Ca qua đêm'),
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  HrmPageChrome.primaryNavy)),
                                    ],
                                  ),
                                  SizedBox(height: 6),
                                  Text(tr('Ranh giới ngày chấm công lấy từ Thiết lập hệ thống → Giờ kết thúc ngày (day_end_time). Hệ số lương ca đêm cấu hình ở bậc lương / phụ cấp.'),
                                    style: TextStyle(
                                        fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          const SizedBox(height: 16),

                          // Lunch break window
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFFED7AA)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.free_breakfast,
                                        color: Color(0xFFEA580C), size: 20),
                                    SizedBox(width: 8),
                                    Text(tr('Nghỉ giữa ca / tăng ca trưa'),
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: _textDark)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(tr('Chấm trong khung này (máy MealOut/MealIn hoặc app) được tính tăng ca. Giờ làm chính sẽ trừ khoảng nghỉ.'),
                                  style: TextStyle(
                                      fontSize: 12, color: Color(0xFF64748B)),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _dialogField(
                                          'Bắt đầu nghỉ',
                                          InkWell(
                                            onTap: () async {
                                              final t = await showTimePicker(
                                                  context: ctx,
                                                  initialTime: lunchBreakStart);
                                              if (t != null) {
                                                setDialogState(
                                                    () => lunchBreakStart = t);
                                              }
                                            },
                                            child: _timeBox(lunchBreakStart,
                                                Icons.coffee, Colors.orange),
                                          )),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _dialogField(
                                          'Vào làm sau nghỉ',
                                          InkWell(
                                            onTap: () async {
                                              final t = await showTimePicker(
                                                  context: ctx,
                                                  initialTime: lunchBreakEnd);
                                              if (t != null) {
                                                setDialogState(
                                                    () => lunchBreakEnd = t);
                                              }
                                            },
                                            child: _timeBox(lunchBreakEnd,
                                                Icons.login, Colors.green),
                                          )),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Attendance parameters section
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F9FF),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFBAE6FD)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.fingerprint,
                                        color: _primaryColor, size: 20),
                                    SizedBox(width: 8),
                                    Text(tr('Thông số chấm công'),
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: _textDark)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildAttendanceMinuteFieldsGrid(
                                  isMobile: isMobile,
                                  earlyCheckIn: earlyCheckIn,
                                  allowLate: allowLate,
                                  allowEarlyLeave: allowEarlyLeave,
                                  lateGrace: lateGrace,
                                  earlyLeaveGrace: earlyLeaveGrace,
                                  breakMinutes: breakMinutes,
                                  overtimeThreshold: overtimeThreshold,
                                  earlyOvertimeThreshold: earlyOvertimeThreshold,
                                  onEarlyCheckIn: (v) =>
                                      setDialogState(() => earlyCheckIn = v),
                                  onAllowLate: (v) =>
                                      setDialogState(() => allowLate = v),
                                  onAllowEarlyLeave: (v) => setDialogState(
                                      () => allowEarlyLeave = v),
                                  onLateGrace: (v) =>
                                      setDialogState(() => lateGrace = v),
                                  onEarlyLeaveGrace: (v) => setDialogState(
                                      () => earlyLeaveGrace = v),
                                  onBreakMinutes: (v) =>
                                      setDialogState(() => breakMinutes = v),
                                  onOvertimeThreshold: (v) => setDialogState(
                                      () => overtimeThreshold = v),
                                  onEarlyOvertimeThreshold: (v) =>
                                      setDialogState(
                                          () => earlyOvertimeThreshold = v),
                                ),
                                if (_earlyOvertimeExceedsCheckIn(
                                    earlyCheckIn, earlyOvertimeThreshold))
                                  _buildEarlyOvertimeCheckInWarning(
                                    earlyCheckIn: earlyCheckIn,
                                    earlyOvertimeThreshold:
                                        earlyOvertimeThreshold,
                                    onApplySuggested: () => setDialogState(() =>
                                        earlyCheckIn =
                                            earlyOvertimeThreshold + 1),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Actions
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: _borderColor))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: isSaving ? null : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _textMuted,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            side: const BorderSide(color: _borderColor),
                          ),
                          child: Text(tr('Hủy')),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (nameCtrl.text.isEmpty) {
                                    appNotification.showWarning(
                                        title: 'Thiếu thông tin',
                                        message: tr('Vui lòng nhập tên ca'));
                                    return;
                                  }
                                  if (_earlyOvertimeExceedsCheckIn(
                                      earlyCheckIn, earlyOvertimeThreshold)) {
                                    appNotification.showWarning(
                                      title: 'Cấu hình chấm công',
                                      message: tr('Tăng ca trước ca ($earlyOvertimeThreshold phút) cần Cho phép chấm sớm ít nhất ${earlyOvertimeThreshold + 1} phút để nhân viên khớp ca và tính được tăng ca.'),
                                    );
                                    return;
                                  }
                                  setDialogState(() => isSaving = true);

                                  final data = {
                                    'name': nameCtrl.text,
                                    'code': codeCtrl.text.isNotEmpty
                                        ? codeCtrl.text
                                        : nameCtrl.text,
                                    'startTime':
                                        '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00',
                                    'endTime':
                                        '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00',
                                    'isActive': isActive,
                                    'shiftType': shiftType,
                                    'description': shift?.description,
                                    'earlyCheckInMinutes': earlyCheckIn,
                                    'maximumAllowedLateMinutes': allowLate,
                                    'maximumAllowedEarlyLeaveMinutes':
                                        allowEarlyLeave,
                                    'lateGraceMinutes': lateGrace,
                                    'earlyLeaveGraceMinutes': earlyLeaveGrace,
                                    'breakTimeMinutes': breakMinutes,
                                    'lunchBreakStartTime':
                                        _timeOfDayToApi(lunchBreakStart),
                                    'lunchBreakEndTime':
                                        _timeOfDayToApi(lunchBreakEnd),
                                    'overtimeMinutesThreshold': overtimeThreshold,
                                    'earlyOvertimeMinutesThreshold':
                                        earlyOvertimeThreshold,
                                  };

                                  try {
                                    final result = isEditing
                                        ? await _apiService.updateShift(
                                            shift.id, data)
                                        : await _apiService.createShift(data);
                                    if (!ctx.mounted) return;
                                    if (result['isSuccess'] == true) {
                                      Navigator.pop(ctx);
                                      _loadData();
                                      appNotification.showSuccess(
                                          title: 'Thành công',
                                          message: isEditing
                                              ? 'Đã cập nhật ca'
                                              : 'Đã thêm ca mới');
                                    } else {
                                      setDialogState(() => isSaving = false);
                                      appNotification.showError(
                                          title: 'Lỗi',
                                          message: result['message'] ??
                                              'Không thể lưu ca');
                                    }
                                  } catch (e) {
                                    setDialogState(() => isSaving = false);
                                    appNotification.showError(
                                        title: 'Lỗi kết nối', message: '$e');
                                  }
                                },
                          icon: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save, size: 18),
                          label: Text(tr(isSaving ? 'Đang lưu...' : 'Lưu')),
                          style: FilledButton.styleFrom(
                            backgroundColor: HrmPageChrome.primaryNavy,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _dialogField(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(label),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500, color: _textMuted)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  InputDecoration _inputDecor(String hint) {
    return InputDecoration(
      hintText: tr(hint),
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _borderColor)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _borderColor)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primaryColor, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _timeBox(TimeOfDay time, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
          border: Border.all(color: _borderColor),
          borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, color: color.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  tr('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500))),
          Icon(Icons.access_time, color: Colors.grey[400], size: 18),
        ],
      ),
    );
  }

  Widget _buildAttendanceMinuteFieldsGrid({
    required bool isMobile,
    required int earlyCheckIn,
    required int allowLate,
    required int allowEarlyLeave,
    required int lateGrace,
    required int earlyLeaveGrace,
    required int breakMinutes,
    required int overtimeThreshold,
    required int earlyOvertimeThreshold,
    required ValueChanged<int> onEarlyCheckIn,
    required ValueChanged<int> onAllowLate,
    required ValueChanged<int> onAllowEarlyLeave,
    required ValueChanged<int> onLateGrace,
    required ValueChanged<int> onEarlyLeaveGrace,
    required ValueChanged<int> onBreakMinutes,
    required ValueChanged<int> onOvertimeThreshold,
    required ValueChanged<int> onEarlyOvertimeThreshold,
  }) {
    final fields = <Widget>[
      _minuteField('Cho phép chấm sớm', earlyCheckIn, onEarlyCheckIn),
      _minuteField('Cho phép chấm trễ', allowLate, onAllowLate),
      _minuteField('Cho phép về sớm', allowEarlyLeave, onAllowEarlyLeave),
      _minuteField('Tính đi trễ sau', lateGrace, onLateGrace),
      _minuteField('Tính về sớm sau', earlyLeaveGrace, onEarlyLeaveGrace),
      _minuteField('Nghỉ giữa ca', breakMinutes, onBreakMinutes),
      _minuteField('Tăng ca trước ca', earlyOvertimeThreshold,
          onEarlyOvertimeThreshold),
      _minuteField('Tăng ca sau ca', overtimeThreshold, onOvertimeThreshold),
    ];

    final columns = isMobile ? 2 : 3;
    final gap = isMobile ? 10.0 : 12.0;
    final rows = <Widget>[];

    for (var i = 0; i < fields.length; i += columns) {
      if (i > 0) rows.add(SizedBox(height: gap));
      final rowChildren = <Widget>[];
      for (var c = 0; c < columns; c++) {
        final idx = i + c;
        if (c > 0) rowChildren.add(SizedBox(width: gap));
        rowChildren.add(
          Expanded(
            child: idx < fields.length ? fields[idx] : const SizedBox.shrink(),
          ),
        );
      }
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: rowChildren));
    }

    return Column(children: rows);
  }

  /// Tăng ca trước ca chỉ tính khi chấm sớm hơn ngưỡng (> threshold).
  /// Ghép ca cần Cho phép chấm sớm ≥ số phút sớm đó.
  bool _earlyOvertimeExceedsCheckIn(
    int earlyCheckIn,
    int earlyOvertimeThreshold,
  ) =>
      earlyOvertimeThreshold > 0 && earlyCheckIn <= earlyOvertimeThreshold;

  Widget _buildEarlyOvertimeCheckInWarning({
    required int earlyCheckIn,
    required int earlyOvertimeThreshold,
    required VoidCallback onApplySuggested,
  }) {
    final suggested = earlyOvertimeThreshold + 1;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFEA580C), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(tr('Cần tăng Cho phép chấm sớm'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9A3412),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr('Tăng ca trước ca ($earlyOvertimeThreshold phút) lớn hơn hoặc bằng Cho phép chấm sớm ($earlyCheckIn phút). '
              'Nhân viên chấm đủ sớm để tính tăng ca có thể không khớp ca. '
              'Nên đặt Cho phép chấm sớm ít nhất $suggested phút.'),
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Color(0xFF9A3412),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onApplySuggested,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEA580C),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(tr('Đặt chấm sớm = $suggested phút')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _minuteField(String label, int value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(label),
          style: const TextStyle(fontSize: 11, color: _textMuted),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
              border: Border.all(color: _borderColor),
              borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  if (value > 0) onChanged(value - 5);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Icon(Icons.remove,
                      size: 14,
                      color: value > 0 ? _primaryColor : Colors.grey[300]),
                ),
              ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr('$value'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(tr(' phút'),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () => onChanged(value + 5),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Icon(Icons.add, size: 14, color: _primaryColor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===== SHIFT SALARY DIALOG =====
  void _showShiftSalaryDialog(Shift shift) {
    List<Map<String, dynamic>> salaryLevels = [];
    bool isLoadingSalary = true;
    bool hasLoaded = false;
    final isMobile = Responsive.isMobile(context);

    Future<void> loadSalaryLevels(StateSetter setDialogState) async {
      setDialogState(() => isLoadingSalary = true);
      final resp = await _apiService.getShiftSalaryLevels();
      if (resp['isSuccess'] == true && resp['data'] != null) {
        final data = resp['data'];
        List allItems;
        if (data is Map && data['items'] is List) {
          allItems = data['items'] as List;
        } else if (data is List) {
          allItems = data;
        } else {
          allItems = [];
        }
        salaryLevels = allItems
            .where((s) => s['shiftTemplateId']?.toString() == shift.id)
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
        salaryLevels.sort(
            (a, b) => (a['sortOrder'] ?? 0).compareTo(b['sortOrder'] ?? 0));
      }
      hasLoaded = true;
      setDialogState(() => isLoadingSalary = false);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (!hasLoaded && isLoadingSalary) {
            loadSalaryLevels(setDialogState);
          }

          final addButton = FilledButton.icon(
            onPressed: () => _showAddEditSalaryLevel(
                shift, null, () => loadSalaryLevels(setDialogState)),
            icon: const Icon(Icons.add, size: 16),
            label: Text(tr('Thêm mức lương'), style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          );

          final bodyContent = isLoadingSalary
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator()))
              : salaryLevels.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.payments_outlined,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(tr('Chưa có mức lương nào'),
                                style:
                                    TextStyle(fontSize: 15, color: _textMuted)),
                            const SizedBox(height: 4),
                            Text(tr('Nhấn "Thêm mức lương" để tạo loại lương, đơn giá và nhóm nhân viên'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[400])),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      shrinkWrap: !isMobile,
                      itemCount: salaryLevels.length,
                      itemBuilder: (_, i) {
                        final sl = salaryLevels[i];
                        final rateType = sl['rateType']?.toString() ?? 'fixed';
                        final empIds = sl['employeeIds'];
                        int empCount = 0;
                        if (empIds is List) {
                          empCount = empIds.length;
                        } else if (empIds is String && empIds.isNotEmpty) {
                          try {
                            final parsed = empIds.startsWith('[')
                                ? (jsonDecode(empIds) as List)
                                : empIds.split(',');
                            empCount = parsed.length;
                          } catch (_) {}
                        }

                        String rateLabel;
                        String rateValue;
                        Color rateColor;
                        if (rateType == 'hourly') {
                          rateLabel = 'Lương theo giờ';
                          rateValue =
                              '${_formatCurrency(sl['hourlyRate'])} /giờ';
                          rateColor = AppColors.info;
                        } else if (rateType == 'multiplier') {
                          rateLabel = 'Nhân hệ số';
                          rateValue = 'x${sl['multiplier'] ?? 1.0}';
                          rateColor = Colors.purple;
                        } else {
                          rateLabel = 'Cố định';
                          rateValue = '${_formatCurrency(sl['fixedRate'])} /ca';
                          rateColor = Colors.green;
                        }

                        final isActive = sl['isActive'] != false;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                                color: isActive
                                    ? _borderColor
                                    : Colors.red.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(tr(sl['levelName'] ?? ''),
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: _textDark)),
                                    ),
                                    if (!isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        child: Text(tr('Tắt'),
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.red.shade700)),
                                      ),
                                    if (!isActive) const SizedBox(width: 6),
                                    if (_perm.canEdit('ShiftSetup'))
                                      IconButton(
                                        icon: const Icon(Icons.edit,
                                            size: 18, color: _primaryColor),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            _showAddEditSalaryLevel(
                                                shift,
                                                sl,
                                                () => loadSalaryLevels(
                                                    setDialogState)),
                                      ),
                                    if (_perm.canDelete('ShiftSetup'))
                                      IconButton(
                                        icon: Icon(Icons.delete,
                                            size: 18,
                                            color: Colors.red.shade400),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (c) => ScrollableAlertDialog(
                                            title: Text(tr('Xác nhận xóa')),
                                            content: Text(tr('${tr('Xóa mức lương "')}${sl['levelName']}"?')),
                                            actions: [
                                              AppDialogActions.delete(
                                                  onCancel: () =>
                                                      Navigator.pop(c, false),
                                                  onConfirm: () =>
                                                      Navigator.pop(c, true))
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          final resp = await _apiService
                                              .deleteShiftSalaryLevel(
                                                  sl['id'].toString());
                                          if (resp['isSuccess'] == true) {
                                            appNotification.showSuccess(
                                                title: 'Đã xóa',
                                                message: 'Đã xóa mức lương "${sl['levelName']}"');
                                            loadSalaryLevels(setDialogState);
                                          } else {
                                            appNotification.showError(
                                                title: 'Lỗi',
                                                message: resp['message'] ??
                                                    'Không thể xóa');
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const Divider(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _salaryChip(
                                        rateLabel, rateValue, rateColor),
                                    _salaryChip(
                                        'Nhân viên',
                                        empCount == 0
                                            ? 'Tất cả'
                                            : '$empCount người',
                                        Colors.teal),
                                  ],
                                ),
                                if (sl['description'] != null &&
                                    sl['description']
                                        .toString()
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(tr(sl['description']),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: _textMuted,
                                          fontStyle: FontStyle.italic)),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    );

          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Thiết lập lương ca'),
                            style: TextStyle(fontSize: 16)),
                        Text(
                            tr('Ca: ${shift.name} (${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)})'),
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                    actions: [addButton, const SizedBox(width: 8)],
                  ),
                  body: bodyContent,
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: math.min(700, MediaQuery.of(context).size.width - 32),
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                    decoration: const BoxDecoration(
                        border:
                            Border(bottom: BorderSide(color: _borderColor))),
                    child: Row(
                      children: [
                        const Icon(Icons.payments,
                            color: Color(0xFFF59E0B), size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Thiết lập lương ca'),
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _textDark)),
                              const SizedBox(height: 2),
                              Text(
                                  tr('Ca: ${shift.name} (${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)})'),
                                  style: const TextStyle(
                                      fontSize: 12, color: _textMuted)),
                            ],
                          ),
                        ),
                        addButton,
                        const SizedBox(width: 8),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: _textMuted),
                            visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ),

                  // Body
                  Flexible(child: bodyContent),

                  // Footer
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: _borderColor))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _textMuted,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            side: const BorderSide(color: _borderColor),
                          ),
                          child: Text(tr('Đóng')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _salaryChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('$label: '),
              style:
                  TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
          Text(tr(value),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  String _formatCurrency(dynamic value) {
    final num = (value ?? 0).toDouble();
    if (num >= 1000000) {
      return '${(num / 1000000).toStringAsFixed(num % 1000000 == 0 ? 0 : 1)}tr';
    }
    if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(num % 1000 == 0 ? 0 : 0)}k';
    }
    return num.toStringAsFixed(0);
  }

  void _showAddEditSalaryLevel(
      Shift shift, Map<String, dynamic>? existing, VoidCallback onDone) {
    final isEditing = existing != null;
    final nameCtrl = TextEditingController(text: tr(existing?['levelName'] ?? ''));
    final fixedRateCtrl =
        TextEditingController(text: tr(formatNumber(existing?['fixedRate'])));
    final hourlyRateCtrl =
        TextEditingController(text: tr(formatNumber(existing?['hourlyRate'])));
    final multiplierCtrl = TextEditingController(
        text: tr((existing?['multiplier'] ?? 1.0).toString()));
    final descCtrl =
        TextEditingController(text: tr(existing?['description'] ?? ''));
    String rateType = existing?['rateType']?.toString() ?? 'fixed';
    bool isActive = existing?['isActive'] != false;
    List<String> selectedEmployeeIds = [];

    if (existing != null && existing['employeeIds'] != null) {
      final empIds = existing['employeeIds'];
      if (empIds is List) {
        selectedEmployeeIds = empIds.map((e) => e.toString()).toList();
      } else if (empIds is String && empIds.isNotEmpty) {
        try {
          selectedEmployeeIds = empIds
              .replaceAll('[', '')
              .replaceAll(']', '')
              .replaceAll('"', '')
              .split(',')
              .where((s) => s.trim().isNotEmpty)
              .toList();
        } catch (_) {}
      }
    }

    bool isSaving = false;
    final isMobileSalary = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: isMobileSalary
                ? const EdgeInsets.all(16)
                : const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogField(
                    'Tên mức lương *',
                    TextField(
                        controller: nameCtrl,
                        decoration: _inputDecor('VD: Mức 1 - Công nhân'),
                        style: const TextStyle(fontSize: 14))),
                const SizedBox(height: 16),
                _dialogField(
                    'Loại lương',
                    DropdownButtonFormField<String>(
                      initialValue: rateType,
                      decoration: _inputDecor(''),
                      style: const TextStyle(fontSize: 14, color: _textDark),
                      items: [
                        DropdownMenuItem(
                            value: 'fixed', child: Text(tr('Cố định lương ca'))),
                        DropdownMenuItem(
                            value: 'multiplier',
                            child: Text(tr('Nhân hệ số lương ca'))),
                        DropdownMenuItem(
                            value: 'hourly', child: Text(tr('Lương theo giờ'))),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => rateType = v ?? 'fixed'),
                    )),
                const SizedBox(height: 16),
                if (rateType == 'fixed')
                  _dialogField(
                      'Đơn giá cố định (VNĐ/ca)',
                      TextField(
                        controller: fixedRateCtrl,
                        decoration: _inputDecor('VD: 400.000'),
                        style: const TextStyle(fontSize: 14),
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandSeparatorFormatter()],
                      )),
                if (rateType == 'hourly')
                  _dialogField(
                      'Đơn giá theo giờ (VNĐ/giờ)',
                      TextField(
                        controller: hourlyRateCtrl,
                        decoration: _inputDecor('VD: 50.000'),
                        style: const TextStyle(fontSize: 14),
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandSeparatorFormatter()],
                      )),
                if (rateType == 'multiplier')
                  _dialogField(
                      'Hệ số nhân lương cơ bản',
                      TextField(
                        controller: multiplierCtrl,
                        decoration: _inputDecor('VD: 1.5'),
                        style: const TextStyle(fontSize: 14),
                        keyboardType: TextInputType.number,
                      )),
                const SizedBox(height: 16),
                _dialogField(
                    'Mô tả',
                    TextField(
                        controller: descCtrl,
                        decoration: _inputDecor('Ghi chú thêm...'),
                        style: const TextStyle(fontSize: 14),
                        maxLines: 2)),
                const SizedBox(height: 20),
                Text(tr('Nhóm nhân viên áp dụng'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textDark)),
                const SizedBox(height: 4),
                Text(tr('Bỏ trống = áp dụng cho tất cả nhân viên'),
                    style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                if (_branches.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _borderColor),
                    ),
                    child: Row(children: [
                      const Icon(Icons.account_tree_outlined,
                          size: 15, color: Color(0xFF6B7280)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _filterBranchId,
                            isExpanded: true,
                            isDense: true,
                            style:
                                const TextStyle(fontSize: 12, color: _textDark),
                            icon: const Icon(Icons.keyboard_arrow_down,
                                size: 16, color: Color(0xFF9CA3AF)),
                            items: [
                              DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(tr('T\u1ea5t c\u1ea3 chi nh\u00e1nh'),
                                      style: TextStyle(fontSize: 12))),
                              ..._branches.map((b) => DropdownMenuItem<String?>(
                                  value: b['id']?.toString(),
                                  child: Text(tr(b['name']?.toString() ?? ''),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12)))),
                            ],
                            onChanged: (v) =>
                                setDialogState(() => _filterBranchId = v),
                          ),
                        ),
                      ),
                      if (_filterBranchId != null)
                        InkWell(
                          onTap: () =>
                              setDialogState(() => _filterBranchId = null),
                          child: const Padding(
                              padding: EdgeInsets.all(3),
                              child: Icon(Icons.close,
                                  size: 13, color: Color(0xFF9CA3AF))),
                        ),
                    ]),
                  ),
                ],
                const SizedBox(height: 10),
                Builder(builder: (ctx) {
                  final displayEmps = _filterBranchId == null
                      ? _employees
                      : _employees
                          .where((e) => e.branchId == _filterBranchId)
                          .toList();
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    InkWell(
                      onTap: () {
                        setDialogState(() {
                          if (selectedEmployeeIds.length ==
                              displayEmps.length) {
                            selectedEmployeeIds.clear();
                          } else {
                            selectedEmployeeIds =
                                displayEmps.map((e) => e.id).toList();
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                            color: _bgColor,
                            borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8)),
                            border: Border.all(color: _borderColor)),
                        child: Row(
                          children: [
                            Icon(
                              selectedEmployeeIds.length == displayEmps.length
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 20,
                              color: _primaryColor,
                            ),
                            const SizedBox(width: 10),
                            Text(tr('Chọn tất cả (${selectedEmployeeIds.length}/${displayEmps.length})'),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _textDark)),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: _borderColor),
                        borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8)),
                      ),
                      child: displayEmps.isEmpty
                          ? Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(
                                  child: Text(tr('Chưa có nhân viên'),
                                      style: TextStyle(
                                          color: _textMuted, fontSize: 13))))
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: displayEmps.length,
                              separatorBuilder: (_, __) => const Divider(
                                  height: 24, color: _borderColor),
                              itemBuilder: (_, i) {
                                final emp = displayEmps[i];
                                final isChecked =
                                    selectedEmployeeIds.contains(emp.id);
                                return InkWell(
                                  onTap: () {
                                    setDialogState(() {
                                      if (isChecked) {
                                        selectedEmployeeIds.remove(emp.id);
                                      } else {
                                        selectedEmployeeIds.add(emp.id);
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                            isChecked
                                                ? Icons.check_box
                                                : Icons.check_box_outline_blank,
                                            size: 20,
                                            color: isChecked
                                                ? _primaryColor
                                                : Colors.grey[400]),
                                        const SizedBox(width: 10),
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: _badgeColors[
                                                  i % _badgeColors.length]
                                              .withValues(alpha: 0.15),
                                          child: Text(
                                              tr(emp.fullName.isNotEmpty
                                                  ? emp.fullName[0]
                                                  : '?'),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: _badgeColors[i %
                                                      _badgeColors.length])),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(tr(emp.fullName),
                                                  style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: _textDark)),
                                              Text(
                                                  tr('${emp.department ?? ''} • ${emp.position ?? ''}'),
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      color: _textMuted)),
                                            ],
                                          ),
                                        ),
                                        Text(tr(emp.employeeCode),
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: _textMuted)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ]); // end Column
                }), // end Builder
              ],
            ),
          );
          final onSave = isSaving
              ? null
              : () async {
                  if (nameCtrl.text.trim().isEmpty) {
                    appNotification.showError(
                        title: 'Lỗi', message: tr('Vui lòng nhập tên mức lương'));
                    return;
                  }
                  setDialogState(() => isSaving = true);
                  final data = {
                    'shiftTemplateId': shift.id,
                    'levelName': nameCtrl.text.trim(),
                    'sortOrder': existing?['sortOrder'] ?? 0,
                    'rateType': rateType,
                    'fixedRate':
                        parseFormattedNumber(fixedRateCtrl.text)?.toDouble() ??
                            0,
                    'hourlyRate':
                        parseFormattedNumber(hourlyRateCtrl.text)?.toDouble() ??
                            0,
                    'multiplier': double.tryParse(multiplierCtrl.text) ?? 1.0,
                    'shiftAllowance': 0,
                    'isNightShift': false,
                    'employeeIds': selectedEmployeeIds.isEmpty
                        ? null
                        : selectedEmployeeIds,
                    'description': descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    if (isEditing) 'isActive': isActive,
                  };

                  final resp = isEditing
                      ? await _apiService.updateShiftSalaryLevel(
                          existing['id'].toString(), data)
                      : await _apiService.createShiftSalaryLevel(data);

                  setDialogState(() => isSaving = false);
                  if (!ctx2.mounted) return;

                  if (resp['isSuccess'] == true) {
                    Navigator.pop(ctx2);
                    appNotification.showSuccess(
                      title: 'Thành công',
                      message: isEditing
                          ? 'Đã cập nhật mức lương'
                          : 'Đã tạo mức lương mới',
                    );
                    onDone();
                  } else {
                    appNotification.showError(
                        title: 'Lỗi',
                        message: resp['message'] ?? 'Không thể lưu');
                  }
                };
          final saveIcon = isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 18);
          final saveLabel = Text(tr(isSaving ? 'Đang lưu...' : 'Lưu'),
              style: const TextStyle(fontSize: 13));

          if (isMobileSalary) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(tr(isEditing ? 'Sửa mức lương' : 'Thêm mức lương')),
                    leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx2)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx2),
                              child: Text(tr('Hủy'))),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: onSave,
                            icon: saveIcon,
                            label: saveLabel,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ]),
                  ),
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: math.min(600, MediaQuery.of(context).size.width - 32),
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                    decoration: const BoxDecoration(
                        border:
                            Border(bottom: BorderSide(color: _borderColor))),
                    child: Row(
                      children: [
                        Icon(isEditing ? Icons.edit : Icons.add_circle,
                            color: const Color(0xFFF59E0B), size: 22),
                        const SizedBox(width: 10),
                        Text(tr(isEditing ? 'Sửa mức lương' : 'Thêm mức lương'),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _textDark)),
                        const Spacer(),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx2),
                            icon: const Icon(Icons.close, color: _textMuted),
                            visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ),
                  Flexible(child: formContent),
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: _borderColor))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx2),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _textMuted,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            side: const BorderSide(color: _borderColor),
                          ),
                          child: Text(tr('Hủy')),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: onSave,
                          icon: saveIcon,
                          label: saveLabel,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _deleteShift(Shift shift) {
    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(tr('Xác nhận xóa'), style: TextStyle(color: _textDark)),
        content: Text(tr('Bạn có chắc muốn xóa ca "${shift.name}"?'),
            style: const TextStyle(color: _textMuted)),
        actions: [
          AppDialogActions.delete(onConfirm: () async {
            Navigator.pop(context);
            try {
              final response = await _apiService.deleteShift(shift.id);
              if (response['isSuccess'] == true) {
                if (_selectedShift?.id == shift.id) {
                  setState(() => _selectedShift = null);
                }
                _loadData();
                appNotification.showSuccess(
                    title: 'Thành công', message: tr('Đã xóa ca "${shift.name}"'));
              } else {
                appNotification.showError(
                    title: 'Lỗi',
                    message: response['message'] ?? 'Không thể xóa ca');
              }
            } catch (e) {
              appNotification.showError(title: 'Lỗi', message: tr('Lỗi: $e'));
            }
          })
        ],
      ),
    );
  }
}
