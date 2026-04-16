import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';

/// Màn hình Thiết lập hệ thống
/// - Giờ kết thúc ngày (day_end_time): mặc định 00:00:00
/// - Số ngày công chuẩn (standard_work_days): mặc định 26
/// - Số giờ công chuẩn/ngày (standard_work_hours): mặc định 8
/// - Quy tắc làm tròn giờ công (rounding_rule): mặc định 'none'
/// - Cho phép chấm công bù (allow_manual_correction): mặc định true
/// - Ngày chốt công hàng tháng (payroll_cutoff_day): mặc định 25
class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  bool _isSaving = false;

  // Giờ kết thúc ngày
  int _dayEndHour = 0;
  int _dayEndMinute = 0;
  int _dayEndSecond = 0;

  // Số cấp phê duyệt chấm công (1, 2, 3)
  int _approvalLevels = 1;

  // Số ngày công chuẩn
  int _standardWorkDays = 26;

  // Số giờ công chuẩn/ngày
  int _standardWorkHours = 8;

  // Quy tắc làm tròn giờ công
  String _roundingRule = 'none';

  // Cho phép chấm công bù
  bool _allowManualCorrection = true;

  // Ngày chốt công hàng tháng
  int _payrollCutoffDay = 25;

  // Số cấp phê duyệt đơn nghỉ phép (1, 2, 3)
  int _leaveApprovalLevels = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      // Load tất cả settings song song
      final results = await Future.wait([
        _apiService.getAppSetting('day_end_time'),
        _apiService.getAppSetting('attendance_approval_levels'),
        _apiService.getAppSetting('standard_work_days'),
        _apiService.getAppSetting('standard_work_hours'),
        _apiService.getAppSetting('rounding_rule'),
        _apiService.getAppSetting('allow_manual_correction'),
        _apiService.getAppSetting('payroll_cutoff_day'),
        _apiService.getAppSetting('leave_approval_levels'),
      ]);

      if (!mounted) return;

      // day_end_time
      if (results[0]['isSuccess'] == true && results[0]['data'] is Map) {
        final data0 = results[0]['data'] as Map;
        _parseDayEndTime(data0['value']?.toString() ?? '00:00:00');
      }
      // attendance_approval_levels
      if (results[1]['isSuccess'] == true && results[1]['data'] is Map) {
        final data1 = results[1]['data'] as Map;
        _approvalLevels = int.tryParse(data1['value']?.toString() ?? '1') ?? 1;
      }
      // standard_work_days
      if (results[2]['isSuccess'] == true && results[2]['data'] is Map) {
        final data2 = results[2]['data'] as Map;
        _standardWorkDays = int.tryParse(data2['value']?.toString() ?? '26') ?? 26;
      }
      // standard_work_hours
      if (results[3]['isSuccess'] == true && results[3]['data'] is Map) {
        final data3 = results[3]['data'] as Map;
        _standardWorkHours = int.tryParse(data3['value']?.toString() ?? '8') ?? 8;
      }
      // rounding_rule
      if (results[4]['isSuccess'] == true && results[4]['data'] is Map) {
        final data4 = results[4]['data'] as Map;
        _roundingRule = data4['value']?.toString() ?? 'none';
      }
      // allow_manual_correction
      if (results[5]['isSuccess'] == true && results[5]['data'] is Map) {
        final data5 = results[5]['data'] as Map;
        _allowManualCorrection = data5['value']?.toString() != 'false';
      }
      // payroll_cutoff_day
      if (results[6]['isSuccess'] == true && results[6]['data'] is Map) {
        final data6 = results[6]['data'] as Map;
        _payrollCutoffDay = int.tryParse(data6['value']?.toString() ?? '25') ?? 25;
      }
      // leave_approval_levels
      if (results[7]['isSuccess'] == true && results[7]['data'] is Map) {
        final data7 = results[7]['data'] as Map;
        _leaveApprovalLevels = int.tryParse(data7['value']?.toString() ?? '1') ?? 1;
      }
    } catch (e) {
      debugPrint('Error loading system settings: $e');
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: 'Không thể tải thiết lập hệ thống');
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _parseDayEndTime(String value) {
    final parts = value.split(':');
    if (parts.length >= 2) {
      _dayEndHour = int.tryParse(parts[0]) ?? 0;
      _dayEndMinute = int.tryParse(parts[1]) ?? 0;
      _dayEndSecond = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 0) : 0;
    }
  }

  String get _dayEndTimeString =>
      '${_dayEndHour.toString().padLeft(2, '0')}:${_dayEndMinute.toString().padLeft(2, '0')}:${_dayEndSecond.toString().padLeft(2, '0')}';

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final results = await Future.wait([
        _apiService.upsertAppSetting(
          key: 'day_end_time',
          value: _dayEndTimeString,
          description: 'Giờ kết thúc ngày làm việc',
        ),
        _apiService.upsertAppSetting(
          key: 'attendance_approval_levels',
          value: _approvalLevels.toString(),
          description: 'Số cấp phê duyệt yêu cầu chấm công',
        ),
        _apiService.upsertAppSetting(
          key: 'standard_work_days',
          value: _standardWorkDays.toString(),
          description: 'Số ngày công chuẩn trong tháng',
        ),
        _apiService.upsertAppSetting(
          key: 'standard_work_hours',
          value: _standardWorkHours.toString(),
          description: 'Số giờ công chuẩn mỗi ngày',
        ),
        _apiService.upsertAppSetting(
          key: 'rounding_rule',
          value: _roundingRule,
          description: 'Quy tắc làm tròn giờ công',
        ),
        _apiService.upsertAppSetting(
          key: 'allow_manual_correction',
          value: _allowManualCorrection.toString(),
          description: 'Cho phép chấm công bù',
        ),
        _apiService.upsertAppSetting(
          key: 'payroll_cutoff_day',
          value: _payrollCutoffDay.toString(),
          description: 'Ngày chốt công hàng tháng',
        ),
        _apiService.upsertAppSetting(
          key: 'leave_approval_levels',
          value: _leaveApprovalLevels.toString(),
          description: 'Số cấp phê duyệt đơn nghỉ phép',
        ),
      ]);

      if (!mounted) return;

      // Check if any save failed
      final failed = results.where((r) => r['isSuccess'] != true).toList();
      if (failed.isNotEmpty) {
        debugPrint('❌ Save settings failed: ${failed.map((r) => r['message']).join(', ')}');
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể lưu: ${failed.first['message'] ?? 'Lỗi không xác định'}',
        );
      } else {
        appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã lưu thiết lập hệ thống',
        );
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể lưu: $e',
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _dayEndHour, minute: _dayEndMinute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dayEndHour = picked.hour;
        _dayEndMinute = picked.minute;
        _dayEndSecond = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        automaticallyImplyLeading: !Responsive.isMobile(context),
        title: const Text('Thiết lập hệ thống'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF18181B),
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save, size: 18),
              label: const Text('Lưu thiết lập'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.isMobile(context) ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Giờ kết thúc ngày + Phê duyệt chấm công
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildDayEndTimeCard()),
                            const SizedBox(width: 20),
                            Expanded(child: _buildApprovalCard()),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _buildDayEndTimeCard(),
                          const SizedBox(height: 20),
                          _buildApprovalCard(),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // Row 1.5: Phê duyệt nghỉ phép
                  _buildLeaveApprovalCard(),
                  const SizedBox(height: 20),
                  // Row 2: Ngày công chuẩn + Giờ công chuẩn
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildStandardWorkDaysCard()),
                            const SizedBox(width: 20),
                            Expanded(child: _buildStandardWorkHoursCard()),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _buildStandardWorkDaysCard(),
                          const SizedBox(height: 20),
                          _buildStandardWorkHoursCard(),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // Row 3: Quy tắc làm tròn + Chấm công bù + Ngày chốt công
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildRoundingRuleCard()),
                            const SizedBox(width: 20),
                            Expanded(child: _buildManualCorrectionAndCutoffCard()),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _buildRoundingRuleCard(),
                          const SizedBox(height: 20),
                          _buildManualCorrectionAndCutoffCard(),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  // ══════════════════════════════════════════════════
  // CARD: Giờ kết thúc ngày
  // ══════════════════════════════════════════════════
  Widget _buildDayEndTimeCard() {
    return _buildSettingCard(
      icon: Icons.access_time_filled,
      iconColor: const Color(0xFF1E3A5F),
      title: 'Giờ kết thúc ngày',
      subtitle: 'Thời điểm phân chia ngày chấm công',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time display + picker
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                onTap: _pickTime,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, color: Color(0xFF1E3A5F), size: 22),
                      const SizedBox(width: 10),
                      Text(
                        _dayEndTimeString,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF18181B),
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.edit, size: 15),
                label: const Text('Đổi giờ'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E3A5F),
                  side: const BorderSide(color: Color(0xFF1E3A5F)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Quick presets
          const Text('Chọn nhanh:', style: TextStyle(color: Color(0xFF52525B), fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildPresetChip('00:00', 0, 0),
              _buildPresetChip('02:00', 2, 0),
              _buildPresetChip('04:00', 4, 0),
              _buildPresetChip('05:00', 5, 0),
              _buildPresetChip('06:00', 6, 0),
            ],
          ),
          const SizedBox(height: 14),
          // Info
          _buildInfoBox(
            'Giờ kết thúc ngày xác định thời điểm "ngày chấm công" kết thúc.\n'
            '• Mặc định 00:00 - Ngày chấm công = ngày lịch\n'
            '• Đặt 06:00 → chấm công lúc 2h sáng tính cho ngày hôm trước (phù hợp ca đêm)',
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════
  // CARD: Cài đặt phê duyệt chấm công
  // ══════════════════════════════════════════════════
  Widget _buildApprovalCard() {
    return _buildSettingCard(
      icon: Icons.approval,
      iconColor: const Color(0xFF0F2340),
      title: 'Phê duyệt chấm công',
      subtitle: 'Cài đặt quy trình phê duyệt yêu cầu sửa chấm công',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Số cấp phê duyệt:',
            style: TextStyle(
              color: Color(0xFF52525B),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          // Approval levels options
          ..._approvalLevelOptions.map((opt) => _buildApprovalLevelOption(
                value: opt['value'] as int,
                label: opt['label'] as String,
                desc: opt['desc'] as String,
                icon: opt['icon'] as IconData,
              )),
          const SizedBox(height: 14),
          _buildInfoBox(
            '• 1 cấp: Quản lý trực tiếp duyệt → Hoàn tất\n'
            '• 2 cấp: Quản lý trực tiếp → HR/Giám đốc duyệt\n'
            '• 3 cấp: Quản lý trực tiếp → Trưởng phòng → HR/Giám đốc',
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _approvalLevelOptions => [
        {
          'value': 1,
          'label': '1 cấp (Quản lý trực tiếp)',
          'desc': 'Chỉ cần 1 người phê duyệt',
          'icon': Icons.person,
        },
        {
          'value': 2,
          'label': '2 cấp (Quản lý + HR)',
          'desc': 'Quản lý duyệt trước, sau đó HR duyệt',
          'icon': Icons.people,
        },
        {
          'value': 3,
          'label': '3 cấp (Quản lý + Trưởng phòng + HR)',
          'desc': 'Duyệt qua 3 cấp quản lý',
          'icon': Icons.groups,
        },
      ];

  Widget _buildApprovalLevelOption({
    required int value,
    required String label,
    required String desc,
    required IconData icon,
  }) {
    final isSelected = _approvalLevels == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => setState(() => _approvalLevels = value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF0F2340).withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF0F2340).withValues(alpha: 0.4)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: isSelected ? const Color(0xFF0F2340) : Colors.grey.shade400,
              ),
              const SizedBox(width: 10),
              Icon(icon, size: 18, color: isSelected ? const Color(0xFF0F2340) : Colors.grey.shade500),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 13,
                        color: const Color(0xFF18181B),
                      ),
                    ),
                    Text(
                      desc,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════
  // SHARED WIDGETS
  // ══════════════════════════════════════════════════

  Widget _buildSettingCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFA),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFCD34D).withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.brown.shade700, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, int hour, int minute) {
    final isSelected = _dayEndHour == hour && _dayEndMinute == minute;
    return ActionChip(
      label: Text(label),
      avatar: isSelected
          ? const Icon(Icons.check_circle, size: 14, color: Color(0xFF1E3A5F))
          : null,
      backgroundColor: isSelected
          ? const Color(0xFF1E3A5F).withValues(alpha: 0.1)
          : Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFF52525B),
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        fontFamily: 'monospace',
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected
            ? const Color(0xFF1E3A5F).withValues(alpha: 0.3)
            : Colors.grey.shade300,
      ),
      onPressed: () {
        setState(() {
          _dayEndHour = hour;
          _dayEndMinute = minute;
          _dayEndSecond = 0;
        });
      },
    );
  }

  // ══════════════════════════════════════════════════
  // CARD: Số ngày công chuẩn
  // ══════════════════════════════════════════════════
  Widget _buildStandardWorkDaysCard() {
    return _buildSettingCard(
      icon: Icons.calendar_month,
      iconColor: const Color(0xFF0F2340),
      title: 'Ngày công chuẩn',
      subtitle: 'Số ngày công chuẩn trong 1 tháng',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2340).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF0F2340).withValues(alpha: 0.2)),
                ),
                child: Text(
                  '$_standardWorkDays ngày',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF18181B),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  IconButton(
                    onPressed: _standardWorkDays < 31 ? () => setState(() => _standardWorkDays++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                    color: const Color(0xFF0F2340),
                  ),
                  IconButton(
                    onPressed: _standardWorkDays > 20 ? () => setState(() => _standardWorkDays--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: const Color(0xFF0F2340),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [22, 24, 26, 28, 30].map((d) => ActionChip(
              label: Text('$d'),
              backgroundColor: _standardWorkDays == d
                  ? const Color(0xFF0F2340).withValues(alpha: 0.1)
                  : Colors.grey.shade100,
              labelStyle: TextStyle(
                color: _standardWorkDays == d ? const Color(0xFF0F2340) : const Color(0xFF52525B),
                fontWeight: _standardWorkDays == d ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide(
                color: _standardWorkDays == d
                    ? const Color(0xFF0F2340).withValues(alpha: 0.3)
                    : Colors.grey.shade300,
              ),
              onPressed: () => setState(() => _standardWorkDays = d),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════
  // CARD: Số giờ công chuẩn/ngày
  // ══════════════════════════════════════════════════
  Widget _buildStandardWorkHoursCard() {
    return _buildSettingCard(
      icon: Icons.timer,
      iconColor: const Color(0xFF1E3A5F),
      title: 'Giờ công chuẩn/ngày',
      subtitle: 'Số giờ làm việc tiêu chuẩn mỗi ngày',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.2)),
                ),
                child: Text(
                  '$_standardWorkHours giờ',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF18181B),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  IconButton(
                    onPressed: _standardWorkHours < 12 ? () => setState(() => _standardWorkHours++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                    color: const Color(0xFF1E3A5F),
                  ),
                  IconButton(
                    onPressed: _standardWorkHours > 4 ? () => setState(() => _standardWorkHours--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: const Color(0xFF1E3A5F),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [6, 7, 8, 9, 10].map((h) => ActionChip(
              label: Text('$h giờ'),
              backgroundColor: _standardWorkHours == h
                  ? const Color(0xFF1E3A5F).withValues(alpha: 0.1)
                  : Colors.grey.shade100,
              labelStyle: TextStyle(
                color: _standardWorkHours == h ? const Color(0xFF1E3A5F) : const Color(0xFF52525B),
                fontWeight: _standardWorkHours == h ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide(
                color: _standardWorkHours == h
                    ? const Color(0xFF1E3A5F).withValues(alpha: 0.3)
                    : Colors.grey.shade300,
              ),
              onPressed: () => setState(() => _standardWorkHours = h),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════
  // CARD: Quy tắc làm tròn giờ công
  // ══════════════════════════════════════════════════
  Widget _buildRoundingRuleCard() {
    return _buildSettingCard(
      icon: Icons.tune,
      iconColor: const Color(0xFF7C3AED),
      title: 'Làm tròn giờ công',
      subtitle: 'Quy tắc làm tròn khi tính giờ công',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._roundingRuleOptions.map((opt) {
            final isSelected = _roundingRule == opt['value'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () => setState(() => _roundingRule = opt['value'] as String),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF7C3AED).withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF7C3AED).withValues(alpha: 0.4)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 20,
                        color: isSelected ? const Color(0xFF7C3AED) : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt['label'] as String,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 13,
                                color: const Color(0xFF18181B),
                              ),
                            ),
                            Text(
                              opt['desc'] as String,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  List<Map<String, String>> get _roundingRuleOptions => [
    {'value': 'none', 'label': 'Không làm tròn', 'desc': 'Tính chính xác theo phút'},
    {'value': 'round_up', 'label': 'Làm tròn lên', 'desc': 'Luôn làm tròn lên (có lợi cho nhân viên)'},
    {'value': 'round_down', 'label': 'Làm tròn xuống', 'desc': 'Luôn làm tròn xuống'},
    {'value': 'round_nearest', 'label': 'Làm tròn gần nhất', 'desc': 'Làm tròn đến 15 phút gần nhất'},
  ];

  // ══════════════════════════════════════════════════
  // CARD: Chấm công bù + Ngày chốt công
  // ══════════════════════════════════════════════════
  Widget _buildManualCorrectionAndCutoffCard() {
    return _buildSettingCard(
      icon: Icons.edit_calendar,
      iconColor: const Color(0xFFD97706),
      title: 'Chấm công bù & Chốt công',
      subtitle: 'Quy tắc bổ sung và chu kỳ tính lương',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Allow manual correction toggle
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cho phép chấm công bù',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF18181B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nhân viên có thể yêu cầu bổ sung chấm công',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _allowManualCorrection,
                onChanged: (v) => setState(() => _allowManualCorrection = v),
                activeThumbColor: const Color(0xFF1E3A5F),
              ),
            ],
          ),
          const Divider(height: 32),
          // Payroll cutoff day
          const Text(
            'Ngày chốt công hàng tháng:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF18181B)),
          ),
          const SizedBox(height: 4),
          Text(
            'Chấm công sẽ được chốt vào ngày này mỗi tháng',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.2)),
                ),
                child: Text(
                  'Ngày $_payrollCutoffDay',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF18181B),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  IconButton(
                    onPressed: _payrollCutoffDay < 31 ? () => setState(() => _payrollCutoffDay++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                    color: const Color(0xFFD97706),
                    iconSize: 20,
                  ),
                  IconButton(
                    onPressed: _payrollCutoffDay > 1 ? () => setState(() => _payrollCutoffDay--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: const Color(0xFFD97706),
                    iconSize: 20,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [1, 15, 20, 25, 28].map((d) => ActionChip(
              label: Text('Ngày $d'),
              backgroundColor: _payrollCutoffDay == d
                  ? const Color(0xFFD97706).withValues(alpha: 0.1)
                  : Colors.grey.shade100,
              labelStyle: TextStyle(
                color: _payrollCutoffDay == d ? const Color(0xFFD97706) : const Color(0xFF52525B),
                fontWeight: _payrollCutoffDay == d ? FontWeight.w600 : FontWeight.normal,
                fontSize: 12,
              ),
              side: BorderSide(
                color: _payrollCutoffDay == d
                    ? const Color(0xFFD97706).withValues(alpha: 0.3)
                    : Colors.grey.shade300,
              ),
              onPressed: () => setState(() => _payrollCutoffDay = d),
            )).toList(),
          ),
          const SizedBox(height: 14),
          _buildInfoBox(
            '• Ngày chốt công xác định kỳ tính lương\n'
            '• VD: Ngày 25 → Chu kỳ từ 26 tháng trước đến 25 tháng này',
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════
  // CARD: Phê duyệt nghỉ phép
  // ══════════════════════════════════════════════════
  Widget _buildLeaveApprovalCard() {
    return _buildSettingCard(
      icon: Icons.event_busy,
      iconColor: const Color(0xFF059669),
      title: 'Phê duyệt nghỉ phép',
      subtitle: 'Cài đặt quy trình phê duyệt đơn nghỉ phép',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Số cấp phê duyệt:',
            style: TextStyle(
              color: Color(0xFF52525B),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          ..._leaveApprovalLevelOptions.map((opt) {
            final value = opt['value'] as int;
            final isSelected = _leaveApprovalLevels == value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () => setState(() => _leaveApprovalLevels = value),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF059669).withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF059669).withValues(alpha: 0.4)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 20,
                        color: isSelected ? const Color(0xFF059669) : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 10),
                      Icon(opt['icon'] as IconData, size: 18, color: isSelected ? const Color(0xFF059669) : Colors.grey.shade500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt['label'] as String,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 13,
                                color: const Color(0xFF18181B),
                              ),
                            ),
                            Text(
                              opt['desc'] as String,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 14),
          _buildInfoBox(
            '• 1 cấp: Quản lý trực tiếp duyệt → Hoàn tất\n'
            '• 2 cấp: Quản lý trực tiếp → Quản lý cấp cao duyệt\n'
            '• 3 cấp: Quản lý trực tiếp → Trưởng phòng → Admin duyệt\n'
            '• Admin luôn nhận được thông báo tất cả đơn nghỉ phép',
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _leaveApprovalLevelOptions => [
        {
          'value': 1,
          'label': '1 cấp (Quản lý trực tiếp)',
          'desc': 'Chỉ quản lý trực tiếp phê duyệt',
          'icon': Icons.person,
        },
        {
          'value': 2,
          'label': '2 cấp (Quản lý trực tiếp + Quản lý cấp cao)',
          'desc': 'Quản lý trực tiếp duyệt, sau đó quản lý cấp cao duyệt',
          'icon': Icons.people,
        },
        {
          'value': 3,
          'label': '3 cấp (Quản lý + Trưởng phòng + Admin)',
          'desc': 'Duyệt qua 3 cấp quản lý',
          'icon': Icons.groups,
        },
      ];
}
