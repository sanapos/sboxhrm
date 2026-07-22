import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm/hrm_settings_mobile_kit.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import '../utils/shift_records_calculator.dart';

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
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  bool _isSaving = false;

  // Giờ kết thúc ngày
  int _dayEndHour = 0;
  int _dayEndMinute = 0;
  int _dayEndSecond = 0;

  // Số cấp phê duyệt chấm công (1, 2, 3)
  int _approvalLevels = 1;

  // Quy tắc làm tròn giờ công
  String _roundingRule = 'none';

  // Cho phép chấm công bù
  bool _allowManualCorrection = true;

  // Ngày chốt công hàng tháng
  int _payrollCutoffDay = 25;

  /// % giờ chuẩn trong ngày để đủ 1 công (mặc định 80). Chỉ dùng khi tắt thập phân.
  double _minWorkDayPercent = 80;
  final _minPercentController = TextEditingController(text: '80');
  /// Giờ tối thiểu để tính nửa công (mặc định 1h).
  double _minHalfDayHours = 1;
  final _minHalfDayController = TextEditingController(text: '1');
  bool _decimalWorkDayEnabled = false;

  // Số cấp phê duyệt đơn nghỉ phép (1, 2, 3)
  int _leaveApprovalLevels = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _minPercentController.dispose();
    _minHalfDayController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      // Load tất cả settings song song
      final results = await Future.wait([
        _apiService.getAppSetting('day_end_time'),
        _apiService.getAppSetting('attendance_approval_levels'),
        _apiService.getAppSetting('rounding_rule'),
        _apiService.getAppSetting('allow_manual_correction'),
        _apiService.getAppSetting('payroll_cutoff_day'),
        _apiService.getAppSetting('leave_approval_levels'),
        _apiService.getAppSetting('min_work_day_percent'),
        _apiService.getAppSetting('decimal_work_day_enabled'),
        _apiService.getAppSetting('min_hours_for_work_day'),
        _apiService.getAppSetting('min_half_day_hours'),
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
      // rounding_rule
      if (results[2]['isSuccess'] == true && results[2]['data'] is Map) {
        final data2 = results[2]['data'] as Map;
        _roundingRule = data2['value']?.toString() ?? 'none';
      }
      // allow_manual_correction
      if (results[3]['isSuccess'] == true && results[3]['data'] is Map) {
        final data3 = results[3]['data'] as Map;
        _allowManualCorrection = data3['value']?.toString() != 'false';
      }
      // payroll_cutoff_day
      if (results[4]['isSuccess'] == true && results[4]['data'] is Map) {
        final data4 = results[4]['data'] as Map;
        _payrollCutoffDay =
            int.tryParse(data4['value']?.toString() ?? '25') ?? 25;
      }
      // leave_approval_levels
      if (results[5]['isSuccess'] == true && results[5]['data'] is Map) {
        final data5 = results[5]['data'] as Map;
        _leaveApprovalLevels =
            int.tryParse(data5['value']?.toString() ?? '1') ?? 1;
      }
      final percentRaw = results[6]['isSuccess'] == true && results[6]['data'] is Map
          ? (results[6]['data'] as Map)['value']?.toString()
          : null;
      final legacyHoursRaw =
          results[8]['isSuccess'] == true && results[8]['data'] is Map
              ? (results[8]['data'] as Map)['value']?.toString()
              : null;
      _minWorkDayPercent = parseMinWorkDayPercent(
        percentAppSettingValue: percentRaw,
        legacyHoursAppSettingValue: legacyHoursRaw,
      );
      _minPercentController.text = _minWorkDayPercent == _minWorkDayPercent.roundToDouble()
          ? _minWorkDayPercent.toInt().toString()
          : _minWorkDayPercent.toStringAsFixed(0);
      if (results[7]['isSuccess'] == true && results[7]['data'] is Map) {
        _decimalWorkDayEnabled = parseDecimalWorkDayEnabled(
          appSettingValue:
              (results[7]['data'] as Map)['value']?.toString(),
        );
      }
      final halfRaw = results[9]['isSuccess'] == true && results[9]['data'] is Map
          ? (results[9]['data'] as Map)['value']?.toString()
          : null;
      _minHalfDayHours = parseMinHalfDayHours(appSettingValue: halfRaw);
      _minHalfDayController.text = _minHalfDayHours == _minHalfDayHours.roundToDouble()
          ? _minHalfDayHours.toInt().toString()
          : _minHalfDayHours.toStringAsFixed(1);
    } catch (e) {
      debugPrint('Error loading system settings: $e');
      if (mounted) {
        appNotification.showError(
            title: 'Lỗi', message: 'Không thể tải thiết lập hệ thống');
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
    final percentText = _minPercentController.text.trim().replaceAll(',', '.');
    final parsedPercent = percentText.isEmpty
        ? 80.0
        : (double.tryParse(percentText) ?? -1);
    if (parsedPercent < 1 || parsedPercent > 100) {
      appNotification.showError(
        title: 'Lỗi',
        message: '% đủ 1 công phải từ 1 đến 100 (mặc định 80)',
      );
      return;
    }
    final halfText = _minHalfDayController.text.trim().replaceAll(',', '.');
    final parsedHalf =
        halfText.isEmpty ? 1.0 : (double.tryParse(halfText) ?? -1);
    if (parsedHalf < 0 || parsedHalf > 24) {
      appNotification.showError(
        title: 'Lỗi',
        message: 'Giờ tối thiểu nửa công phải từ 0 đến 24 (mặc định 1)',
      );
      return;
    }
    _minWorkDayPercent = parsedPercent;
    _minHalfDayHours = parsedHalf;

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
        _apiService.upsertAppSetting(
          key: 'min_work_day_percent',
          value: _minWorkDayPercent.toString(),
          description: '% giờ chuẩn trong ngày để đủ 1 công (mặc định 80)',
        ),
        _apiService.upsertAppSetting(
          key: 'min_half_day_hours',
          value: _minHalfDayHours.toString(),
          description: 'Giờ tối thiểu để tính nửa công (mặc định 1)',
        ),
        _apiService.upsertAppSetting(
          key: 'decimal_work_day_enabled',
          value: _decimalWorkDayEnabled.toString(),
          description: 'Tính công theo thập phân (0.1–1.0, tắt ngưỡng %)',
        ),
      ]);

      if (!mounted) return;

      // Check if any save failed
      final failed = results.where((r) => r['isSuccess'] != true).toList();
      if (failed.isNotEmpty) {
        debugPrint(
            '❌ Save settings failed: ${failed.map((r) => r['message']).join(', ')}');
        appNotification.showError(
          title: 'Lỗi',
          message:
              'Không thể lưu: ${failed.first['message'] ?? 'Lỗi không xác định'}',
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
    final saveButton = _perm.canEdit('SystemSettings')
        ? FilledButton.icon(
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
              backgroundColor: HrmPageChrome.primaryNavy,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          )
        : const SizedBox.shrink();

    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      appBar: HrmPageChrome.appBar(
        title: 'Thiết lập hệ thống',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: saveButton,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: HrmSettingsMobileKit.active(context)
                  ? HrmSettingsMobileKit.pagePadding(context)
                  : EdgeInsets.all(Responsive.isMobile(context) ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (HrmPageChrome.isEmbedded) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: saveButton,
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Row 1: Giờ kết thúc ngày + Phê duyệt chấm công
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final colThreshold =
                          HrmSettingsMobileKit.active(context) ? 360.0 : 900.0;
                      if (constraints.maxWidth > colThreshold) {
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
                  _buildMinHoursForWorkDayCard(),
                  const SizedBox(height: 20),
                  // Row 2: Quy tắc làm tròn + Chấm công bù + Ngày chốt công
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final colThreshold =
                          HrmSettingsMobileKit.active(context) ? 360.0 : 900.0;
                      if (constraints.maxWidth > colThreshold) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildRoundingRuleCard()),
                            const SizedBox(width: 20),
                            Expanded(
                                child: _buildManualCorrectionAndCutoffCard()),
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
      iconColor: HrmPageChrome.primaryNavy,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: HrmPageChrome.primaryNavy.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: HrmPageChrome.primaryNavy.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule,
                          color: HrmPageChrome.primaryNavy, size: 22),
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
                  foregroundColor: HrmPageChrome.primaryNavy,
                  side: const BorderSide(color: HrmPageChrome.primaryNavy),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Quick presets
          const Text('Chọn nhanh:',
              style: TextStyle(
                  color: Color(0xFF52525B),
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
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
            'Nguồn duy nhất cho ranh giới ngày chấm công / báo cáo / phạt.\n'
            '• Mặc định 00:00 — ngày chấm công = ngày lịch\n'
            '• Đặt 06:00 → chấm công lúc 2h sáng tính cho ngày hôm trước (phù hợp ca đêm)\n'
            '• Ca đêm chỉ cần chọn loại ca + hệ số lương; không cấu hình giờ cắt riêng trên ca',
          ),
        ],
      ),
    );
  }

  Widget _buildMinHoursForWorkDayCard() {
    final thresholdEnabled = !_decimalWorkDayEnabled;
    return _buildSettingCard(
      icon: Icons.hourglass_bottom,
      iconColor: const Color(0xFF059669),
      title: 'Quy tắc tính công',
      subtitle: 'Theo tổng giờ làm trong ngày (không tính từng ca riêng)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Tính công theo thập phân',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: const Text(
              'Bật: làm tròn gần 0.1 / 0.2 … 1.0 theo tỷ lệ giờ — tắt ngưỡng % đủ công / nửa công cố định',
              style: TextStyle(fontSize: 12),
            ),
            value: _decimalWorkDayEnabled,
            activeColor: HrmPageChrome.primaryNavy,
            onChanged: _perm.canEdit('SystemSettings')
                ? (v) => setState(() => _decimalWorkDayEnabled = v)
                : null,
          ),
          const Divider(height: 24),
          TextField(
            controller: _minHalfDayController,
            enabled: _perm.canEdit('SystemSettings'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Giờ tối thiểu tính nửa công / có công',
              hintText: 'VD: 1',
              suffixText: 'giờ',
              helperText:
                  'Dưới mức này (VD 0.5h) → 0 công. Mặc định 1 giờ. Áp dụng cả khi bật thập phân.',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildMinHalfChip('0.5h', '0.5'),
              _buildMinHalfChip('1h', '1'),
              _buildMinHalfChip('1.5h', '1.5'),
              _buildMinHalfChip('2h', '2'),
              _buildMinHalfChip('3h', '3'),
            ],
          ),
          const SizedBox(height: 16),
          Opacity(
            opacity: thresholdEnabled ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !thresholdEnabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thresholdEnabled
                        ? '% đủ 1 công (chế độ ngưỡng)'
                        : '% đủ 1 công (đã tắt — đang dùng thập phân)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF52525B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _minPercentController,
                    enabled: thresholdEnabled &&
                        _perm.canEdit('SystemSettings'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '% đủ 1 công',
                      hintText: 'VD: 80',
                      suffixText: '%',
                      helperText: thresholdEnabled
                          ? '≥ % giờ chuẩn NV → đủ 1 công; dưới đó (≥ min nửa công) → 0.5'
                          : 'Không dùng khi bật thập phân',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildMinPercentChip('50%', '50'),
                      _buildMinPercentChip('60%', '60'),
                      _buildMinPercentChip('70%', '70'),
                      _buildMinPercentChip('80%', '80'),
                      _buildMinPercentChip('90%', '90'),
                      _buildMinPercentChip('100%', '100'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildInfoBox(
            _decimalWorkDayEnabled
                ? 'Đang bật thập phân:\n'
                    '• Công = làm tròn (giờ làm ÷ giờ chuẩn NV) đến bậc 0.1 gần nhất.\n'
                    '• VD: 3.6/8 ≈ 0.45 → 0.5 công; 7.2/8 = 0.9 → 0.9 công.\n'
                    '• Dưới “giờ tối thiểu nửa công” → 0 (tránh 30 phút ra 0.1).\n'
                    '• Ngưỡng % đủ công / nửa công cố định: tắt.'
                : 'Đang dùng chế độ ngưỡng:\n'
                    '• ≥ (giờ chuẩn × %) → 1 công.\n'
                    '• ≥ giờ tối thiểu nửa công và dưới % → 0.5 công.\n'
                    '• Dưới giờ tối thiểu nửa công → 0 công.\n'
                    '• VD: chuẩn 8h, min nửa công 1h, 80% → ≥6.4h = đủ công; 1–6.4h = nửa công; dưới 1h = 0.',
          ),
        ],
      ),
    );
  }

  Widget _buildMinHalfChip(String label, String value) {
    final selected = _minHalfDayController.text.trim() == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: _perm.canEdit('SystemSettings')
          ? (_) {
              setState(() {
                _minHalfDayController.text = value;
                _minHalfDayHours = double.tryParse(value) ?? 1;
              });
            }
          : null,
      selectedColor: const Color(0xFF059669).withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF059669) : const Color(0xFF52525B),
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  Widget _buildMinPercentChip(String label, String value) {
    final selected = _minPercentController.text.trim() == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: _perm.canEdit('SystemSettings')
          ? (_) {
              setState(() {
                _minPercentController.text = value;
                _minWorkDayPercent = double.tryParse(value) ?? 80;
              });
            }
          : null,
      selectedColor: HrmPageChrome.primaryNavy.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? HrmPageChrome.primaryNavy : const Color(0xFF52525B),
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  // ══════════════════════════════════════════════════
  // CARD: Cài đặt phê duyệt chấm công
  // ══════════════════════════════════════════════════
  Widget _buildApprovalCard() {
    return _buildSettingCard(
      icon: Icons.approval,
      iconColor: HrmPageChrome.primaryNavy,
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
                ? HrmPageChrome.primaryNavy.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? HrmPageChrome.primaryNavy.withValues(alpha: 0.4)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color:
                    isSelected ? HrmPageChrome.primaryNavy : Colors.grey.shade400,
              ),
              const SizedBox(width: 10),
              Icon(icon,
                  size: 18,
                  color: isSelected
                      ? HrmPageChrome.primaryNavy
                      : Colors.grey.shade500),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 13,
                        color: const Color(0xFF18181B),
                      ),
                    ),
                    Text(
                      desc,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
                      Text(title,
                          style: const TextStyle(
                              color: Color(0xFF18181B),
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Color(0xFF71717A), fontSize: 12)),
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
        border:
            Border.all(color: const Color(0xFFFCD34D).withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  color: Colors.brown.shade700, fontSize: 11, height: 1.5),
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
          ? const Icon(Icons.check_circle, size: 14, color: HrmPageChrome.primaryNavy)
          : null,
      backgroundColor: isSelected
          ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1)
          : Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isSelected ? HrmPageChrome.primaryNavy : const Color(0xFF52525B),
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        fontFamily: 'monospace',
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected
            ? HrmPageChrome.primaryNavy.withValues(alpha: 0.3)
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
          // Cảnh báo chưa áp dụng
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.construction_outlined,
                    color: Color(0xFFD97706), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đặt được lưu, nhưng chưa áp dụng vào tính toán giờ công. Sẽ được kết nối vào engine tính lương.',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade800,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          ..._roundingRuleOptions.map((opt) {
            final isSelected = _roundingRule == opt['value'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () =>
                    setState(() => _roundingRule = opt['value'] as String),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: isSelected
                            ? const Color(0xFF7C3AED)
                            : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt['label'] as String,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 13,
                                color: const Color(0xFF18181B),
                              ),
                            ),
                            Text(
                              opt['desc'] as String,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500),
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
        {
          'value': 'none',
          'label': 'Không làm tròn',
          'desc': 'Tính chính xác theo phút'
        },
        {
          'value': 'round_up',
          'label': 'Làm tròn lên',
          'desc': 'Luôn làm tròn lên (có lợi cho nhân viên)'
        },
        {
          'value': 'round_down',
          'label': 'Làm tròn xuống',
          'desc': 'Luôn làm tròn xuống'
        },
        {
          'value': 'round_nearest',
          'label': 'Làm tròn gần nhất',
          'desc': 'Làm tròn đến 15 phút gần nhất'
        },
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
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF18181B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nhân viên có thể yêu cầu bổ sung chấm công',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _allowManualCorrection,
                onChanged: (v) => setState(() => _allowManualCorrection = v),
                activeThumbColor: HrmPageChrome.primaryNavy,
              ),
            ],
          ),
          const Divider(height: 32),
          // Payroll cutoff day
          const Text(
            'Ngày chốt công hàng tháng:',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF18181B)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFD97706).withValues(alpha: 0.2)),
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
                    onPressed: _payrollCutoffDay < 31
                        ? () => setState(() => _payrollCutoffDay++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                    color: const Color(0xFFD97706),
                    iconSize: 20,
                  ),
                  IconButton(
                    onPressed: _payrollCutoffDay > 1
                        ? () => setState(() => _payrollCutoffDay--)
                        : null,
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
            children: [1, 15, 20, 25, 28]
                .map((d) => ActionChip(
                      label: Text('Ngày $d'),
                      backgroundColor: _payrollCutoffDay == d
                          ? const Color(0xFFD97706).withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                      labelStyle: TextStyle(
                        color: _payrollCutoffDay == d
                            ? const Color(0xFFD97706)
                            : const Color(0xFF52525B),
                        fontWeight: _payrollCutoffDay == d
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontSize: 12,
                      ),
                      side: BorderSide(
                        color: _payrollCutoffDay == d
                            ? const Color(0xFFD97706).withValues(alpha: 0.3)
                            : Colors.grey.shade300,
                      ),
                      onPressed: () => setState(() => _payrollCutoffDay = d),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          _buildInfoBox(
            '• Ngày chốt công xác định chu kỳ tính lương\n'
            '• VD: Ngày 25 → Chu kỳ từ 26/tháng trước đến 25/tháng này\n'
            '• Ngày 1 → Chốt theo tháng lịch (1–31 mỗi tháng)\n'
            '• Thiết lập này được lưu và sẽ được dùng khi module Tổng hợp lương được cập nhật',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: isSelected
                            ? const Color(0xFF059669)
                            : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 10),
                      Icon(opt['icon'] as IconData,
                          size: 18,
                          color: isSelected
                              ? const Color(0xFF059669)
                              : Colors.grey.shade500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt['label'] as String,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 13,
                                color: const Color(0xFF18181B),
                              ),
                            ),
                            Text(
                              opt['desc'] as String,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500),
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
