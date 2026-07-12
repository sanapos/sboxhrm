import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/notification_preferences_cache.dart';
import '../utils/notification_category_utils.dart';
import '../utils/notification_group_settings.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/hrm_page_chrome.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _apiService = ApiService();
  bool _isLoading = true;
  bool _isSaving = false;
  List<_PreferenceItem> _preferences = [];
  bool _attendanceEnabled = true;
  bool _workEnabled = true;

  /// Nhóm chấm công: attendance, device
  static final _attendanceCodes = NotificationCategoryUtils.attendanceGroupCodes;
  /// Nhóm công việc: tất cả còn lại
  List<_PreferenceItem> get _attendancePrefs =>
      _preferences.where((p) => _attendanceCodes.contains(p.categoryCode)).toList();
  List<_PreferenceItem> get _workPrefs =>
      _preferences.where((p) => !_attendanceCodes.contains(p.categoryCode)).toList();

  static const _bgColor = Color(0xFFFAFAFA);
  static const _textDark = Color(0xFF0F172A);
  static const _textMuted = Color(0xFF71717A);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreferences());
  }

  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.getNotificationPreferences();
      if (result['isSuccess'] == true && result['data'] != null) {
        final list = result['data'] as List;
        setState(() {
          _preferences = list
              .map((e) => _PreferenceItem(
                    categoryCode: e['categoryCode'] ?? '',
                    displayName: e['categoryDisplayName'] ?? '',
                    description: e['categoryDescription'] ?? '',
                    icon: e['categoryIcon'] ?? 'notifications',
                    displayOrder: e['displayOrder'] ?? 0,
                    isEnabled: e['isEnabled'] ?? true,
                  ))
              .toList()
            ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          _syncGroupTogglesFromPreferences();
        });
        NotificationPreferencesCache.instance.applyFromPreferenceList(
          list.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        );
        await NotificationGroupSettings.syncFromPreferenceList(
          list.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
    } catch (e) {
      debugPrint('Error loading notification preferences: $e');
      _attendanceEnabled = await NotificationGroupSettings.isAttendanceEnabled();
      _workEnabled = await NotificationGroupSettings.isWorkEnabled();
    }
    setState(() => _isLoading = false);
  }

  void _syncGroupTogglesFromPreferences() {
    _attendanceEnabled =
        _attendancePrefs.isEmpty || _attendancePrefs.any((p) => p.isEnabled);
    _workEnabled = _workPrefs.isEmpty || _workPrefs.any((p) => p.isEnabled);
  }

  Future<void> _savePreferences() async {
    setState(() => _isSaving = true);
    try {
      final prefs = _preferences
          .map((p) => {
                'categoryCode': p.categoryCode,
                'isEnabled': p.isEnabled,
              })
          .toList();
      final result = await _apiService.updateNotificationPreferences(prefs);
      if (result['isSuccess'] == true) {
        NotificationPreferencesCache.instance.applyFromPreferenceList(prefs);
        await NotificationGroupSettings.syncFromPreferenceList(prefs);
        if (mounted) {
          NotificationOverlayManager().showSuccess(
            title: 'Thành công',
            message: 'Đã lưu thiết lập thông báo',
          );
        }
      } else if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Lưu thất bại',
          message: result['message']?.toString() ??
              'Không lưu được lên server. FCM vẫn có thể gửi thông báo.',
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Lưu thất bại',
          message:
              'Không kết nối được server. Thiết lập chưa được áp dụng — FCM vẫn có thể gửi thông báo.',
        );
      }
    }
    setState(() => _isSaving = false);
  }

  IconData _getIconData(String iconName) {
    const iconMap = {
      'fingerprint': Icons.fingerprint,
      'event_busy': Icons.event_busy,
      'more_time': Icons.more_time,
      'payments': Icons.payments,
      'task_alt': Icons.task_alt,
      'approval': Icons.approval,
      'router': Icons.router,
      'people': Icons.people,
      'settings': Icons.settings,
      'notifications': Icons.notifications,
      'trending_up': Icons.trending_up,
      'campaign': Icons.campaign,
    };
    return iconMap[iconName] ?? Icons.notifications;
  }

  Color _getCategoryColor(String code) {
    const colorMap = {
      'attendance': HrmPageChrome.primaryNavy,
      'leave': HrmPageChrome.primaryNavy,
      'overtime': Color(0xFFF97316),
      'payroll': HrmPageChrome.primaryNavy,
      'task': HrmPageChrome.primaryNavy,
      'approval': Color(0xFFEF4444),
      'device': HrmPageChrome.primaryNavy,
      'hr': Color(0xFFEC4899),
      'system': Color(0xFF71717A),
      'kpi': Color(0xFF059669),
      'internal_comm': Color(0xFF8B5CF6),
    };
    return colorMap[code] ?? HrmPageChrome.primaryNavy;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  // Nhóm 1: Thông báo chấm công
                  _buildGroupCard(
                    title: 'Thông báo chấm công',
                    subtitle: 'Chấm công, đi đường, thiết bị kết nối/ngắt kết nối',
                    icon: Icons.fingerprint,
                    color: HrmPageChrome.primaryNavy,
                    isEnabled: _attendanceEnabled,
                    onToggle: (val) {
                      setState(() {
                        _attendanceEnabled = val;
                        for (final p in _attendancePrefs) {
                          p.isEnabled = val;
                        }
                      });
                    },
                    children: _attendancePrefs,
                  ),
                  const SizedBox(height: 16),
                  // Nhóm 2: Thông báo công việc
                  _buildGroupCard(
                    title: 'Thông báo công việc',
                    subtitle: 'Nghỉ phép, tăng ca, lương, KPI, phê duyệt, ...',
                    icon: Icons.work_outline,
                    color: HrmPageChrome.primaryNavy,
                    isEnabled: _workEnabled,
                    onToggle: (val) {
                      setState(() {
                        _workEnabled = val;
                        for (final p in _workPrefs) {
                          p.isEnabled = val;
                        }
                      });
                    },
                    children: _workPrefs,
                  ),
                  const SizedBox(height: 24),
                  _buildSaveButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildGroupCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isEnabled,
    required ValueChanged<bool> onToggle,
    required List<_PreferenceItem> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnabled ? color.withValues(alpha: 0.3) : const Color(0xFFE4E4E7),
        ),
        boxShadow: [
          BoxShadow(
            color: isEnabled ? color.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Group header with main toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isEnabled ? color.withValues(alpha: 0.05) : const Color(0xFFF8F9FA),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isEnabled ? color.withValues(alpha: 0.12) : const Color(0xFFE4E4E7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 24, color: isEnabled ? color : _textMuted),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isEnabled ? _textDark : _textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: _textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: onToggle,
                  activeThumbColor: color,
                ),
              ],
            ),
          ),
          // Sub-categories
          if (isEnabled && children.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFFE4E4E7)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: children.map((item) => _buildSubPreferenceRow(item)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubPreferenceRow(_PreferenceItem item) {
    final color = _getCategoryColor(item.categoryCode);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: item.isEnabled ? color.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getIconData(item.icon),
              size: 16,
              color: item.isEnabled ? color : _textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.displayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: item.isEnabled ? _textDark : _textMuted,
              ),
            ),
          ),
          Switch(
            value: item.isEnabled,
            onChanged: (val) {
              setState(() => item.isEnabled = val);
            },
            activeThumbColor: color,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), HrmPageChrome.primaryNavy, HrmPageChrome.primaryNavy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0x180F172A), blurRadius: 20, offset: Offset(0, 10))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                const Icon(Icons.notifications_active, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Thiết lập thông báo',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Chọn nhóm thông báo bạn muốn nhận. Tắt nhóm nào sẽ không nhận thông báo loại đó.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _savePreferences,
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.save, size: 18),
        label: Text(_isSaving ? 'Đang lưu...' : 'Lưu thiết lập'),
        style: ElevatedButton.styleFrom(
          backgroundColor: HrmPageChrome.primaryNavy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _PreferenceItem {
  final String categoryCode;
  final String displayName;
  final String description;
  final String icon;
  final int displayOrder;
  bool isEnabled;

  _PreferenceItem({
    required this.categoryCode,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.displayOrder,
    required this.isEnabled,
  });
}
