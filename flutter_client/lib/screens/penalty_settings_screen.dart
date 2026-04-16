import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../utils/number_formatter.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import 'settings_hub_screen.dart';

class PenaltySettingsScreen extends StatefulWidget {
  const PenaltySettingsScreen({super.key});

  @override
  State<PenaltySettingsScreen> createState() => _PenaltySettingsScreenState();
}

class _PenaltySettingsScreenState extends State<PenaltySettingsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers for Late penalties (3 levels)
  final _lateMinutes1Controller = TextEditingController();
  final _latePenalty1Controller = TextEditingController();
  final _lateMinutes2Controller = TextEditingController();
  final _latePenalty2Controller = TextEditingController();
  final _lateMinutes3Controller = TextEditingController();
  final _latePenalty3Controller = TextEditingController();

  // Controllers for Early leave penalties (3 levels)
  final _earlyMinutes1Controller = TextEditingController();
  final _earlyPenalty1Controller = TextEditingController();
  final _earlyMinutes2Controller = TextEditingController();
  final _earlyPenalty2Controller = TextEditingController();
  final _earlyMinutes3Controller = TextEditingController();
  final _earlyPenalty3Controller = TextEditingController();

  // Controllers for Repeat offense penalties (3 levels)
  final _repeatTimes1Controller = TextEditingController();
  final _repeatPenalty1Controller = TextEditingController();
  final _repeatTimes2Controller = TextEditingController();
  final _repeatPenalty2Controller = TextEditingController();
  final _repeatTimes3Controller = TextEditingController();
  final _repeatPenalty3Controller = TextEditingController();

  // Controllers for Other penalties
  final _forgotCheckPenaltyController = TextEditingController();
  final _unauthorizedAbsencePenaltyController = TextEditingController();
  final _violationPenaltyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPenaltySettings();
  }

  @override
  void dispose() {
    _lateMinutes1Controller.dispose();
    _latePenalty1Controller.dispose();
    _lateMinutes2Controller.dispose();
    _latePenalty2Controller.dispose();
    _lateMinutes3Controller.dispose();
    _latePenalty3Controller.dispose();
    _earlyMinutes1Controller.dispose();
    _earlyPenalty1Controller.dispose();
    _earlyMinutes2Controller.dispose();
    _earlyPenalty2Controller.dispose();
    _earlyMinutes3Controller.dispose();
    _earlyPenalty3Controller.dispose();
    _repeatTimes1Controller.dispose();
    _repeatPenalty1Controller.dispose();
    _repeatTimes2Controller.dispose();
    _repeatPenalty2Controller.dispose();
    _repeatTimes3Controller.dispose();
    _repeatPenalty3Controller.dispose();
    _forgotCheckPenaltyController.dispose();
    _unauthorizedAbsencePenaltyController.dispose();
    _violationPenaltyController.dispose();
    super.dispose();
  }

  Future<void> _loadPenaltySettings() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getPenaltySettings();
      final settings = (response['isSuccess'] == true && response['data'] is Map<String, dynamic>)
          ? response['data'] as Map<String, dynamic>
          : response;
      if (response['isSuccess'] == true) {
        _populateControllers(settings);
      } else {
        debugPrint('Penalty settings API not successful, using defaults');
      }
    } catch (e) {
      debugPrint('Error loading penalty settings: $e');
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể tải thiết lập phạt, đang dùng giá trị mặc định',
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _populateControllers(Map<String, dynamic> settings) {
    // Late penalties
    _lateMinutes1Controller.text = (settings['lateMinutes1'] ?? 15).toString();
    _latePenalty1Controller.text = formatNumber(settings['latePenalty1'] ?? 50000);
    _lateMinutes2Controller.text = (settings['lateMinutes2'] ?? 30).toString();
    _latePenalty2Controller.text = formatNumber(settings['latePenalty2'] ?? 100000);
    _lateMinutes3Controller.text = (settings['lateMinutes3'] ?? 60).toString();
    _latePenalty3Controller.text = formatNumber(settings['latePenalty3'] ?? 200000);

    // Early leave penalties
    _earlyMinutes1Controller.text = (settings['earlyMinutes1'] ?? 15).toString();
    _earlyPenalty1Controller.text = formatNumber(settings['earlyPenalty1'] ?? 50000);
    _earlyMinutes2Controller.text = (settings['earlyMinutes2'] ?? 30).toString();
    _earlyPenalty2Controller.text = formatNumber(settings['earlyPenalty2'] ?? 100000);
    _earlyMinutes3Controller.text = (settings['earlyMinutes3'] ?? 60).toString();
    _earlyPenalty3Controller.text = formatNumber(settings['earlyPenalty3'] ?? 200000);

    // Repeat offense penalties
    _repeatTimes1Controller.text = (settings['repeatCount1'] ?? 3).toString();
    _repeatPenalty1Controller.text = formatNumber(settings['repeatPenalty1'] ?? 100000);
    _repeatTimes2Controller.text = (settings['repeatCount2'] ?? 5).toString();
    _repeatPenalty2Controller.text = formatNumber(settings['repeatPenalty2'] ?? 200000);
    _repeatTimes3Controller.text = (settings['repeatCount3'] ?? 10).toString();
    _repeatPenalty3Controller.text = formatNumber(settings['repeatPenalty3'] ?? 500000);

    // Other penalties
    _forgotCheckPenaltyController.text = formatNumber(settings['forgotCheckPenalty'] ?? 100000);
    _unauthorizedAbsencePenaltyController.text = formatNumber(settings['unauthorizedLeavePenalty'] ?? 500000);
    _violationPenaltyController.text = formatNumber(settings['violationPenalty'] ?? 200000);
  }

  Future<void> _savePenaltySettings() async {
    setState(() => _isSaving = true);
    try {
      final data = {
        // Late penalties
        'lateMinutes1': int.tryParse(_lateMinutes1Controller.text) ?? 15,
        'latePenalty1': parseFormattedNumber(_latePenalty1Controller.text)?.toDouble() ?? 50000,
        'lateMinutes2': int.tryParse(_lateMinutes2Controller.text) ?? 30,
        'latePenalty2': parseFormattedNumber(_latePenalty2Controller.text)?.toDouble() ?? 100000,
        'lateMinutes3': int.tryParse(_lateMinutes3Controller.text) ?? 60,
        'latePenalty3': parseFormattedNumber(_latePenalty3Controller.text)?.toDouble() ?? 200000,
        // Early leave penalties
        'earlyMinutes1': int.tryParse(_earlyMinutes1Controller.text) ?? 15,
        'earlyPenalty1': parseFormattedNumber(_earlyPenalty1Controller.text)?.toDouble() ?? 50000,
        'earlyMinutes2': int.tryParse(_earlyMinutes2Controller.text) ?? 30,
        'earlyPenalty2': parseFormattedNumber(_earlyPenalty2Controller.text)?.toDouble() ?? 100000,
        'earlyMinutes3': int.tryParse(_earlyMinutes3Controller.text) ?? 60,
        'earlyPenalty3': parseFormattedNumber(_earlyPenalty3Controller.text)?.toDouble() ?? 200000,
        // Repeat offense penalties
        'repeatCount1': int.tryParse(_repeatTimes1Controller.text) ?? 3,
        'repeatPenalty1': parseFormattedNumber(_repeatPenalty1Controller.text)?.toDouble() ?? 100000,
        'repeatCount2': int.tryParse(_repeatTimes2Controller.text) ?? 5,
        'repeatPenalty2': parseFormattedNumber(_repeatPenalty2Controller.text)?.toDouble() ?? 200000,
        'repeatCount3': int.tryParse(_repeatTimes3Controller.text) ?? 10,
        'repeatPenalty3': parseFormattedNumber(_repeatPenalty3Controller.text)?.toDouble() ?? 500000,
        // Other penalties
        'forgotCheckPenalty': parseFormattedNumber(_forgotCheckPenaltyController.text)?.toDouble() ?? 100000,
        'unauthorizedLeavePenalty': parseFormattedNumber(_unauthorizedAbsencePenaltyController.text)?.toDouble() ?? 500000,
        'violationPenalty': parseFormattedNumber(_violationPenaltyController.text)?.toDouble() ?? 200000,
      };

      final response = await _apiService.savePenaltySettings(data);
      if (mounted) {
        if (response['isSuccess'] == true) {
          appNotification.showSuccess(
            title: 'Thành công',
            message: 'Đã lưu thiết lập phạt',
          );
        } else {
          appNotification.showError(
            title: 'Lỗi',
            message: response['message'] ?? 'Lỗi khi lưu thiết lập',
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving penalty settings: $e');
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể lưu thiết lập: $e',
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 1200;
    final isMediumScreen = screenWidth > 800 && screenWidth <= 1200;
    
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: _isLoading
          ? const LoadingWidget()
          : Responsive.isMobile(context)
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 12),
                    _buildTitleSection(),
                    const SizedBox(height: 16),
                    _buildLatePenaltyCard(),
                    const SizedBox(height: 16),
                    _buildEarlyLeavePenaltyCard(),
                    const SizedBox(height: 16),
                    _buildRepeatOffensePenaltyCard(),
                    const SizedBox(height: 16),
                    _buildOtherPenaltiesCard(),
                  ],
                ),
              )
            : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTitleSection(),
                        const SizedBox(height: 24),
                        
                        // Four columns layout
                        if (isWideScreen)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildLatePenaltyCard()),
                              const SizedBox(width: 20),
                              Expanded(child: _buildEarlyLeavePenaltyCard()),
                              const SizedBox(width: 20),
                              Expanded(child: _buildRepeatOffensePenaltyCard()),
                              const SizedBox(width: 20),
                              Expanded(child: _buildOtherPenaltiesCard()),
                            ],
                          )
                        else if (isMediumScreen)
                          Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildLatePenaltyCard()),
                                  const SizedBox(width: 20),
                                  Expanded(child: _buildEarlyLeavePenaltyCard()),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildRepeatOffensePenaltyCard()),
                                  const SizedBox(width: 20),
                                  Expanded(child: _buildOtherPenaltiesCard()),
                                ],
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              _buildLatePenaltyCard(),
                              const SizedBox(height: 20),
                              _buildEarlyLeavePenaltyCard(),
                              const SizedBox(height: 20),
                              _buildRepeatOffensePenaltyCard(),
                              const SizedBox(height: 20),
                              _buildOtherPenaltiesCard(),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Row(
        children: [
          if (!Responsive.isMobile(context)) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
              onPressed: () => SettingsHubScreen.goBack(context),
              tooltip: 'Quay lại',
            ),
            const SizedBox(width: 8),
          ],
          const Text(
            'Thiết lập Phạt',
            style: TextStyle(
              color: Color(0xFF18181B),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.gavel,
              color: Color(0xFF1E3A5F),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thiết lập Phạt',
                  style: TextStyle(
                    color: Color(0xFF1E3A5F),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Cấu hình mức phạt đi trễ, về sớm, tái phạm và các vi phạm khác',
                  style: TextStyle(
                    color: Color(0xFF71717A),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          // Save button
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _savePenaltySettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(_isSaving ? 'Đang lưu...' : 'Lưu thiết lập'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatePenaltyCard() {
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFF87171)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.schedule,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Phạt Đi trễ',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Thiết lập mức phạt theo số phút đi trễ',
                        style: TextStyle(
                          color: Color(0xFF71717A),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE4E4E7), height: 1),
          
          // Level 1
          _buildPenaltyLevelRow(
            level: 1,
            labelPrefix: 'Từ',
            labelSuffix: 'phút',
            minutesController: _lateMinutes1Controller,
            penaltyController: _latePenalty1Controller,
          ),
          
          // Level 2
          _buildPenaltyLevelRow(
            level: 2,
            labelPrefix: 'Từ',
            labelSuffix: 'phút',
            minutesController: _lateMinutes2Controller,
            penaltyController: _latePenalty2Controller,
          ),
          
          // Level 3
          _buildPenaltyLevelRow(
            level: 3,
            labelPrefix: 'Từ',
            labelSuffix: 'phút',
            minutesController: _lateMinutes3Controller,
            penaltyController: _latePenalty3Controller,
          ),
        ],
      ),
    );
  }

  Widget _buildEarlyLeavePenaltyCard() {
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E3A5F), Color(0xFF2D5F8B)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.logout,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Phạt Về sớm',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Thiết lập mức phạt theo số phút về sớm',
                        style: TextStyle(
                          color: Color(0xFF71717A),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE4E4E7), height: 1),
          
          // Level 1
          _buildPenaltyLevelRow(
            level: 1,
            labelPrefix: 'Từ',
            labelSuffix: 'phút',
            minutesController: _earlyMinutes1Controller,
            penaltyController: _earlyPenalty1Controller,
          ),
          
          // Level 2
          _buildPenaltyLevelRow(
            level: 2,
            labelPrefix: 'Từ',
            labelSuffix: 'phút',
            minutesController: _earlyMinutes2Controller,
            penaltyController: _earlyPenalty2Controller,
          ),
          
          // Level 3
          _buildPenaltyLevelRow(
            level: 3,
            labelPrefix: 'Từ',
            labelSuffix: 'phút',
            minutesController: _earlyMinutes3Controller,
            penaltyController: _earlyPenalty3Controller,
          ),
        ],
      ),
    );
  }

  Widget _buildRepeatOffensePenaltyCard() {
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF59E0B), width: 2),
                  ),
                  child: const Icon(
                    Icons.refresh,
                    color: Color(0xFFF59E0B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Phạt Tái phạm',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Phạt thêm khi vi phạm nhiều lần trong tháng',
                        style: TextStyle(
                          color: Color(0xFF71717A),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE4E4E7), height: 1),
          
          // Level 1
          _buildRepeatLevelRow(
            level: 1,
            timesController: _repeatTimes1Controller,
            penaltyController: _repeatPenalty1Controller,
          ),
          
          // Level 2
          _buildRepeatLevelRow(
            level: 2,
            timesController: _repeatTimes2Controller,
            penaltyController: _repeatPenalty2Controller,
          ),
          
          // Level 3
          _buildRepeatLevelRow(
            level: 3,
            timesController: _repeatTimes3Controller,
            penaltyController: _repeatPenalty3Controller,
          ),
        ],
      ),
    );
  }

  Widget _buildOtherPenaltiesCard() {
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFF97316)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.warning_amber,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Các loại Phạt khác',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Phạt quên chấm công, nghỉ không phép, vi phạm quy định',
                        style: TextStyle(
                          color: Color(0xFF71717A),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE4E4E7), height: 1),
          
          // Forgot check penalty
          _buildOtherPenaltyRow(
            icon: Icons.fingerprint,
            iconColor: const Color(0xFFF59E0B),
            title: 'Quên chấm công',
            description: 'Không chấm công vào hoặc ra',
            controller: _forgotCheckPenaltyController,
            suffix: 'đ/lần',
          ),
          
          const Divider(color: Color(0xFFE4E4E7), height: 1, indent: 20, endIndent: 20),
          
          // Unauthorized absence penalty
          _buildOtherPenaltyRow(
            icon: Icons.event_busy,
            iconColor: const Color(0xFF1E3A5F),
            title: 'Nghỉ không phép',
            description: 'Nghỉ không xin phép hoặc không thông báo',
            controller: _unauthorizedAbsencePenaltyController,
            suffix: 'đ/ngày',
          ),
          
          const Divider(color: Color(0xFFE4E4E7), height: 1, indent: 20, endIndent: 20),
          
          // Violation penalty
          _buildOtherPenaltyRow(
            icon: Icons.rule,
            iconColor: const Color(0xFF0F2340),
            title: 'Vi phạm quy định công ty',
            description: 'Vi phạm các quy định nội bộ công ty',
            controller: _violationPenaltyController,
            suffix: 'đ/lần',
          ),
        ],
      ),
    );
  }

  Widget _buildPenaltyLevelRow({
    required int level,
    required String labelPrefix,
    required String labelSuffix,
    required TextEditingController minutesController,
    required TextEditingController penaltyController,
  }) {
    Color levelColor;
    switch (level) {
      case 1:
        levelColor = const Color(0xFF1E3A5F);
        break;
      case 2:
        levelColor = const Color(0xFF1E3A5F);
        break;
      case 3:
        levelColor = const Color(0xFFEF4444);
        break;
      default:
        levelColor = const Color(0xFF71717A);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'MỨC $level',
              style: TextStyle(
                color: levelColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            labelPrefix,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildCompactTextField(minutesController),
          ),
          const SizedBox(width: 4),
          Text(
            labelSuffix,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13),
          ),
          const SizedBox(width: 8),
          const Text(
            'Phạt',
            style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildCompactTextField(penaltyController, isMoney: true),
          ),
          const SizedBox(width: 4),
          const Text(
            'đ',
            style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildRepeatLevelRow({
    required int level,
    required TextEditingController timesController,
    required TextEditingController penaltyController,
  }) {
    Color levelColor;
    switch (level) {
      case 1:
        levelColor = const Color(0xFF1E3A5F);
        break;
      case 2:
        levelColor = const Color(0xFF1E3A5F);
        break;
      case 3:
        levelColor = const Color(0xFFEF4444);
        break;
      default:
        levelColor = const Color(0xFF71717A);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'MỨC $level',
              style: TextStyle(
                color: levelColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Từ lần',
            style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildCompactTextField(timesController),
          ),
          const SizedBox(width: 4),
          const Text(
            'lần',
            style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
          ),
          const SizedBox(width: 8),
          const Text(
            'Phạt',
            style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildCompactTextField(penaltyController, isMoney: true),
          ),
          const SizedBox(width: 4),
          const Text(
            'đ',
            style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherPenaltyRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required TextEditingController controller,
    required String suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF18181B),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF71717A),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _buildCompactTextField(controller, isMoney: true),
          ),
          const SizedBox(width: 6),
          Text(
            suffix,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactTextField(TextEditingController controller, {bool isMoney = false}) {
    return TextField(
      controller: controller,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF18181B),
        fontWeight: FontWeight.w500,
      ),
      keyboardType: TextInputType.number,
      inputFormatters: isMoney ? [ThousandSeparatorFormatter()] : null,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1E3A5F), width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
      ),
    );
  }
}
