import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:latlong2/latlong.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/responsive_helper.dart';
import '../models/mobile_attendance.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/map_location_picker.dart';
import '../widgets/camera_face_capture.dart';
import 'settings_hub_screen.dart';

class MobileAttendanceSettingsScreen extends StatefulWidget {
  const MobileAttendanceSettingsScreen({super.key});

  @override
  State<MobileAttendanceSettingsScreen> createState() => _MobileAttendanceSettingsScreenState();
}

class _MobileAttendanceSettingsScreenState extends State<MobileAttendanceSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool _isSaving = false;
  
  // Settings
  MobileAttendanceSettings _settings = MobileAttendanceSettings();
  
  // Data
  List<WorkLocation> _locations = [];
  String _locationSearchQuery = '';
  List<FaceRegistration> _faceRegistrations = [];
  List<AuthorizedDevice> _authorizedDevices = [];
  bool _showMobileFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  List<WorkLocation> get _filteredLocations {
    if (_locationSearchQuery.isEmpty) return _locations;
    final q = _locationSearchQuery.toLowerCase();
    return _locations.where((loc) =>
      loc.name.toLowerCase().contains(q) ||
      loc.address.toLowerCase().contains(q)
    ).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getMobileAttendanceSettings(),
        _apiService.getWorkLocations(),
        _apiService.getFaceRegistrations(),
        _apiService.getAuthorizedDevices(),
      ]);

      if (!mounted) return;

      // Settings
      if (results[0]['isSuccess'] == true && results[0]['data'] != null) {
        final data = results[0]['data'];
        if (data is Map<String, dynamic>) {
          _settings = MobileAttendanceSettings.fromJson(data);
        }
      }

      // Locations
      if (results[1]['isSuccess'] == true && results[1]['data'] != null) {
        final data = results[1]['data'];
        if (data is List) {
          _locations = data.map((e) => WorkLocation.fromJson(e as Map<String, dynamic>)).toList();
        }
      }

      // Face registrations
      if (results[2]['isSuccess'] == true && results[2]['data'] != null) {
        final data = results[2]['data'];
        if (data is List) {
          _faceRegistrations = data.map((e) => FaceRegistration.fromJson(e as Map<String, dynamic>)).toList();
        }
      }

      // Authorized devices
      if (results[3]['isSuccess'] == true && results[3]['data'] != null) {
        final data = results[3]['data'];
        if (data is List) {
          _authorizedDevices = data.map((e) => AuthorizedDevice.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('Error loading mobile attendance data: $e');
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể tải dữ liệu chấm công mobile',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Responsive.isMobile(context) ? null : IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
          onPressed: () => SettingsHubScreen.goBack(context),
        ),
        title: const Text(
          'Chấm Công Mobile',
          style: TextStyle(
            color: Color(0xFF18181B),
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF1E3A5F),
          unselectedLabelColor: const Color(0xFF71717A),
          indicatorColor: const Color(0xFF1E3A5F),
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: 'Cài đặt'),
            Tab(icon: Icon(Icons.location_on), text: 'Vị trí'),
            Tab(icon: Icon(Icons.face), text: 'Khuôn mặt'),
            Tab(icon: Icon(Icons.phone_android), text: 'Thiết bị'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSettingsTab(),
                _buildLocationsTab(),
                _buildFaceRegistrationTab(),
                _buildDevicesTab(),
              ],
            ),
    );
  }

  // ==================== TAB 1: CÀI ĐẶT CHUNG ====================
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingsCard(
            title: 'Phương thức xác thực',
            icon: Icons.verified_user,
            color: const Color(0xFF1E3A5F),
            children: [
              _buildSwitchTile(
                title: 'Bật xác thực Face ID',
                subtitle: 'Cho phép chấm công bằng khuôn mặt',
                value: _settings.enableFaceId,
                onChanged: (v) => setState(() => _settings = MobileAttendanceSettings(
                  enableFaceId: v,
                  enableGps: _settings.enableGps,
                  enableWifi: _settings.enableWifi,
                  verificationMode: _settings.verificationMode,
                  gpsRadiusMeters: _settings.gpsRadiusMeters,
                  minFaceMatchScore: _settings.minFaceMatchScore,
                  autoApproveInRange: _settings.autoApproveInRange,
                  allowManualApproval: _settings.allowManualApproval,
                  maxPhotosPerRegistration: _settings.maxPhotosPerRegistration,
                  requireLivenessDetection: _settings.requireLivenessDetection,
                )),
              ),
              _buildSwitchTile(
                title: 'Bật xác thực GPS',
                subtitle: 'Cho phép xác thực vị trí khi chấm công',
                value: _settings.enableGps,
                onChanged: (v) => setState(() => _settings = MobileAttendanceSettings(
                  enableFaceId: _settings.enableFaceId,
                  enableGps: v,
                  enableWifi: _settings.enableWifi,
                  verificationMode: _settings.verificationMode,
                  gpsRadiusMeters: _settings.gpsRadiusMeters,
                  minFaceMatchScore: _settings.minFaceMatchScore,
                  autoApproveInRange: _settings.autoApproveInRange,
                  allowManualApproval: _settings.allowManualApproval,
                  maxPhotosPerRegistration: _settings.maxPhotosPerRegistration,
                  requireLivenessDetection: _settings.requireLivenessDetection,
                )),
              ),
              _buildSwitchTile(
                title: 'Bật xác thực WiFi văn phòng',
                subtitle: 'Cho phép chấm công qua WiFi đã đăng ký',
                value: _settings.enableWifi,
                onChanged: (v) => setState(() => _settings = MobileAttendanceSettings(
                  enableFaceId: _settings.enableFaceId,
                  enableGps: _settings.enableGps,
                  enableWifi: v,
                  verificationMode: _settings.verificationMode,
                  gpsRadiusMeters: _settings.gpsRadiusMeters,
                  minFaceMatchScore: _settings.minFaceMatchScore,
                  autoApproveInRange: _settings.autoApproveInRange,
                  allowManualApproval: _settings.allowManualApproval,
                  maxPhotosPerRegistration: _settings.maxPhotosPerRegistration,
                  requireLivenessDetection: _settings.requireLivenessDetection,
                )),
              ),
              const Divider(),
              _buildVerificationModeSelector(),
              const Divider(),
              _buildSwitchTile(
                title: 'Phát hiện người thật (Liveness)',
                subtitle: 'Chống giả mạo bằng ảnh/video',
                value: _settings.requireLivenessDetection,
                onChanged: (v) => setState(() => _settings = MobileAttendanceSettings(
                  enableFaceId: _settings.enableFaceId,
                  enableGps: _settings.enableGps,
                  enableWifi: _settings.enableWifi,
                  verificationMode: _settings.verificationMode,
                  gpsRadiusMeters: _settings.gpsRadiusMeters,
                  minFaceMatchScore: _settings.minFaceMatchScore,
                  autoApproveInRange: _settings.autoApproveInRange,
                  allowManualApproval: _settings.allowManualApproval,
                  maxPhotosPerRegistration: _settings.maxPhotosPerRegistration,
                  requireLivenessDetection: v,
                )),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSettingsCard(
            title: 'Cài đặt GPS',
            icon: Icons.gps_fixed,
            color: const Color(0xFF1E3A5F),
            children: [
              _buildSliderTile(
                title: 'Bán kính cho phép',
                subtitle: '${_settings.gpsRadiusMeters} mét từ vị trí công ty',
                value: _settings.gpsRadiusMeters.toDouble(),
                min: 50,
                max: 500,
                divisions: 9,
                onChanged: (v) => setState(() => _settings = MobileAttendanceSettings(
                  enableFaceId: _settings.enableFaceId,
                  enableGps: _settings.enableGps,
                  enableWifi: _settings.enableWifi,
                  verificationMode: _settings.verificationMode,
                  gpsRadiusMeters: v.toInt(),
                  minFaceMatchScore: _settings.minFaceMatchScore,
                  autoApproveInRange: _settings.autoApproveInRange,
                  allowManualApproval: _settings.allowManualApproval,
                  maxPhotosPerRegistration: _settings.maxPhotosPerRegistration,
                  requireLivenessDetection: _settings.requireLivenessDetection,
                )),
              ),
              _buildSwitchTile(
                title: 'Tự động duyệt trong phạm vi',
                subtitle: 'Duyệt tự động nếu trong bán kính cho phép',
                value: _settings.autoApproveInRange,
                onChanged: (v) => setState(() => _settings = MobileAttendanceSettings(
                  enableFaceId: _settings.enableFaceId,
                  enableGps: _settings.enableGps,
                  enableWifi: _settings.enableWifi,
                  verificationMode: _settings.verificationMode,
                  gpsRadiusMeters: _settings.gpsRadiusMeters,
                  minFaceMatchScore: _settings.minFaceMatchScore,
                  autoApproveInRange: v,
                  allowManualApproval: _settings.allowManualApproval,
                  maxPhotosPerRegistration: _settings.maxPhotosPerRegistration,
                  requireLivenessDetection: _settings.requireLivenessDetection,
                )),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSettingsCard(
            title: 'Cài đặt Face ID',
            icon: Icons.face_retouching_natural,
            color: const Color(0xFF0F2340),
            children: [
              _buildSliderTile(
                title: 'Độ chính xác tối thiểu',
                subtitle: '${_settings.minFaceMatchScore.toInt()}% độ khớp khuôn mặt',
                value: _settings.minFaceMatchScore,
                min: 60,
                max: 99,
                divisions: 39,
                onChanged: (v) => setState(() => _settings = MobileAttendanceSettings(
                  enableFaceId: _settings.enableFaceId,
                  enableGps: _settings.enableGps,
                  enableWifi: _settings.enableWifi,
                  verificationMode: _settings.verificationMode,
                  gpsRadiusMeters: _settings.gpsRadiusMeters,
                  minFaceMatchScore: v,
                  autoApproveInRange: _settings.autoApproveInRange,
                  allowManualApproval: _settings.allowManualApproval,
                  maxPhotosPerRegistration: _settings.maxPhotosPerRegistration,
                  requireLivenessDetection: _settings.requireLivenessDetection,
                )),
              ),
              _buildSliderTile(
                title: 'Số ảnh đăng ký tối đa',
                subtitle: '${_settings.maxPhotosPerRegistration} ảnh cho mỗi nhân viên',
                value: _settings.maxPhotosPerRegistration.toDouble(),
                min: 3,
                max: 10,
                divisions: 7,
                onChanged: (v) => setState(() => _settings = MobileAttendanceSettings(
                  enableFaceId: _settings.enableFaceId,
                  enableGps: _settings.enableGps,
                  enableWifi: _settings.enableWifi,
                  verificationMode: _settings.verificationMode,
                  gpsRadiusMeters: _settings.gpsRadiusMeters,
                  minFaceMatchScore: _settings.minFaceMatchScore,
                  autoApproveInRange: _settings.autoApproveInRange,
                  allowManualApproval: _settings.allowManualApproval,
                  maxPhotosPerRegistration: v.toInt(),
                  requireLivenessDetection: _settings.requireLivenessDetection,
                )),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSettingsCard(
            title: 'Quy trình duyệt',
            icon: Icons.approval,
            color: const Color(0xFFF59E0B),
            children: [
              _buildSwitchTile(
                title: 'Cho phép duyệt thủ công',
                subtitle: 'HR có thể duyệt các trường hợp ngoài phạm vi',
                value: _settings.allowManualApproval,
                onChanged: (v) => setState(() => _settings = MobileAttendanceSettings(
                  enableFaceId: _settings.enableFaceId,
                  enableGps: _settings.enableGps,
                  enableWifi: _settings.enableWifi,
                  verificationMode: _settings.verificationMode,
                  gpsRadiusMeters: _settings.gpsRadiusMeters,
                  minFaceMatchScore: _settings.minFaceMatchScore,
                  autoApproveInRange: _settings.autoApproveInRange,
                  allowManualApproval: v,
                  maxPhotosPerRegistration: _settings.maxPhotosPerRegistration,
                  requireLivenessDetection: _settings.requireLivenessDetection,
                )),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSettingsCard(
            title: 'Chống chấm trùng',
            icon: Icons.timer_outlined,
            color: const Color(0xFFE11D48),
            children: [
              _buildSliderTile(
                title: 'Khoảng cách tối thiểu',
                subtitle: '${_settings.minPunchIntervalMinutes} phút giữa 2 lần chấm',
                value: _settings.minPunchIntervalMinutes.toDouble(),
                min: 0,
                max: 30,
                divisions: 6,
                onChanged: (v) => setState(() => _settings = _settings.copyWith(
                  minPunchIntervalMinutes: v.toInt(),
                )),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  _settings.minPunchIntervalMinutes == 0
                      ? 'Tắt kiểm tra chấm trùng - cho phép chấm liên tục'
                      : 'Nếu chấm công dưới ${_settings.minPunchIntervalMinutes} phút sẽ bị từ chối là chấm trùng',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Đang lưu...' : 'Lưu cài đặt'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF18181B),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24, color: Color(0xFFE4E4E7)),
          ...children,
        ],
      ),
    );
  }

  Widget _buildVerificationModeSelector() {
    final enabledCount = [
      _settings.enableFaceId,
      _settings.enableGps,
      _settings.enableWifi,
    ].where((e) => e).length;

    final enabledNames = <String>[];
    if (_settings.enableFaceId) enabledNames.add('Face');
    if (_settings.enableGps) enabledNames.add('GPS');
    if (_settings.enableWifi) enabledNames.add('WiFi');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chế độ xác thực',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF18181B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            enabledCount <= 1
                ? 'Chỉ có ${enabledNames.isNotEmpty ? enabledNames.first : "0"} phương thức bật'
                : 'Đang bật: ${enabledNames.join(", ")}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildModeOption(
                  label: 'Bất kỳ 1',
                  subtitle: 'Chỉ cần 1 phương thức đạt',
                  icon: Icons.looks_one,
                  selected: _settings.verificationMode == 'any',
                  onTap: () => setState(() => _settings = MobileAttendanceSettings(
                    enableFaceId: _settings.enableFaceId,
                    enableGps: _settings.enableGps,
                    enableWifi: _settings.enableWifi,
                    verificationMode: 'any',
                    gpsRadiusMeters: _settings.gpsRadiusMeters,
                    minFaceMatchScore: _settings.minFaceMatchScore,
                    autoApproveInRange: _settings.autoApproveInRange,
                    allowManualApproval: _settings.allowManualApproval,
                    maxPhotosPerRegistration: _settings.maxPhotosPerRegistration,
                    requireLivenessDetection: _settings.requireLivenessDetection,
                  )),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeOption(
                  label: 'Tất cả',
                  subtitle: 'Phải đạt mọi phương thức',
                  icon: Icons.done_all,
                  selected: _settings.verificationMode == 'all',
                  onTap: () => setState(() => _settings = MobileAttendanceSettings(
                    enableFaceId: _settings.enableFaceId,
                    enableGps: _settings.enableGps,
                    enableWifi: _settings.enableWifi,
                    verificationMode: 'all',
                    gpsRadiusMeters: _settings.gpsRadiusMeters,
                    minFaceMatchScore: _settings.minFaceMatchScore,
                    autoApproveInRange: _settings.autoApproveInRange,
                    allowManualApproval: _settings.allowManualApproval,
                    maxPhotosPerRegistration: _settings.maxPhotosPerRegistration,
                    requireLivenessDetection: _settings.requireLivenessDetection,
                  )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF1E3A5F) : const Color(0xFFE4E4E7),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? const Color(0xFF1E3A5F) : const Color(0xFF71717A), size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: selected ? const Color(0xFF1E3A5F) : const Color(0xFF71717A),
              ),
            ),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: selected ? const Color(0xFF1E3A5F).withValues(alpha: 0.7) : const Color(0xFF71717A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF71717A),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF1E3A5F),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF18181B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E3A5F),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: const Color(0xFF1E3A5F),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final response = await _apiService.updateMobileAttendanceSettings(
        enableFaceId: _settings.enableFaceId,
        enableGps: _settings.enableGps,
        enableWifi: _settings.enableWifi,
        verificationMode: _settings.verificationMode,
        enableLivenessDetection: _settings.requireLivenessDetection,
        gpsRadiusMeters: _settings.gpsRadiusMeters.toDouble(),
        minFaceMatchScore: _settings.minFaceMatchScore,
        autoApproveInRange: _settings.autoApproveInRange,
        allowManualApproval: _settings.allowManualApproval,
        minPunchIntervalMinutes: _settings.minPunchIntervalMinutes,
      );

      if (!mounted) return;

      if (response['isSuccess'] == true) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã lưu cài đặt chấm công mobile',
        );
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: response['message'] ?? 'Không thể lưu cài đặt',
        );
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể lưu cài đặt: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ==================== TAB 2: VỊ TRÍ LÀM VIỆC ====================
  Widget _buildLocationsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (!Responsive.isMobile(context) || _showMobileFilters)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                  ),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Tìm kiếm vị trí...',
                      border: InputBorder.none,
                      icon: Icon(Icons.search, color: Color(0xFF71717A)),
                    ),
                    onChanged: (value) => setState(() => _locationSearchQuery = value),
                  ),
                ),
              ),
              if (!Responsive.isMobile(context) || _showMobileFilters)
              const SizedBox(width: 12),
              if (Responsive.isMobile(context)) ...[
                GestureDetector(
                  onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _showMobileFilters ? Colors.orange.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        Icon(
                          _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                          color: _showMobileFilters ? Colors.orange : const Color(0xFF71717A),
                          size: 22,
                        ),
                        if (_locationSearchQuery.isNotEmpty)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                onPressed: () => _showAddLocationDialog(),
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Thêm'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _locations.isEmpty
              ? _buildEmptyState(
                  icon: Icons.location_off,
                  title: 'Chưa có vị trí nào',
                  subtitle: 'Thêm vị trí làm việc để nhân viên có thể chấm công',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _filteredLocations.length,
                  itemBuilder: (_, index) => Padding(
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
                      child: _buildLocationDeckItem(_filteredLocations[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLocationDeckItem(WorkLocation location) {
    return InkWell(
      onTap: () => _showEditLocationDialog(location),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.location_on, size: 18, color: Color(0xFF1E3A5F)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(location.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF18181B)), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${location.address} · ${location.radius}m · ${location.autoApproveInRange ? 'Tự động' : 'Duyệt tay'}${location.wifiSsid != null && location.wifiSsid!.isNotEmpty ? ' · 📶 ${location.wifiSsid}' : ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (location.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Hoạt động', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E3A5F))),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF71717A)),
          ],
        ),
      ),
    );
  }

  void _showAddLocationDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final radiusController = TextEditingController(text: '100');
    final wifiBssidController = TextEditingController();
    final isMobile = Responsive.isMobile(context);
    double? selectedLat;
    double? selectedLng;
    bool isDetectingBssid = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<Null> onSave() async {
            if (nameController.text.isEmpty || addressController.text.isEmpty) {
              appNotification.showError(title: 'Lỗi', message: 'Vui lòng nhập tên vị trí và địa chỉ');
              return;
            }
            if (selectedLat == null || selectedLng == null) {
              appNotification.showError(title: 'Lỗi', message: 'Vui lòng chọn vị trí trên bản đồ');
              return;
            }
            try {
              final response = await _apiService.addWorkLocation(
                name: nameController.text,
                address: addressController.text,
                latitude: selectedLat!,
                longitude: selectedLng!,
                radius: double.tryParse(radiusController.text) ?? 100,
                wifiBssid: wifiBssidController.text.isNotEmpty ? wifiBssidController.text : null,
              );
              if (context.mounted) {
                if (response['isSuccess'] == true) {
                  Navigator.pop(context);
                  appNotification.showSuccess(title: 'Thành công', message: 'Đã thêm vị trí mới');
                  _loadData();
                } else {
                  appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Không thể thêm vị trí');
                }
              }
            } catch (e) {
              if (mounted) {
                appNotification.showError(title: 'Lỗi', message: 'Không thể thêm vị trí: $e');
              }
            }
          }

          final formContent = SingleChildScrollView(
            padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Tên vị trí *',
                    hintText: 'VD: Văn phòng chính',
                    prefixIcon: const Icon(Icons.business),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  decoration: InputDecoration(
                    labelText: 'Địa chỉ *',
                    hintText: 'VD: 123 Nguyễn Huệ, Q1',
                    prefixIcon: const Icon(Icons.location_on),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: radiusController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Bán kính cho phép (mét)',
                    prefixIcon: const Icon(Icons.radar),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: wifiBssidController,
                  decoration: InputDecoration(
                    labelText: 'MAC Router WiFi (BSSID)',
                    hintText: 'VD: AA:BB:CC:DD:EE:FF',
                    prefixIcon: const Icon(Icons.router),
                    suffixIcon: isDetectingBssid
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: const Icon(Icons.wifi_find, color: Color(0xFF1E3A5F)),
                            tooltip: 'Lấy MAC WiFi đang kết nối',
                            onPressed: () async {
                              setDialogState(() => isDetectingBssid = true);
                              try {
                                if (!kIsWeb) {
                                  final locStatus = await Permission.location.request();
                                  if (!locStatus.isGranted) {
                                    if (context.mounted) {
                                      appNotification.showError(title: 'Lỗi', message: 'Cần quyền vị trí để lấy MAC WiFi');
                                    }
                                    return;
                                  }
                                }
                                final info = NetworkInfo();
                                final bssid = await info.getWifiBSSID();
                                if (bssid != null && bssid.isNotEmpty && bssid != '02:00:00:00:00:00') {
                                  setDialogState(() {
                                    wifiBssidController.text = bssid;
                                  });
                                } else {
                                  if (context.mounted) {
                                    appNotification.showError(title: 'Không tìm thấy', message: 'Hãy kết nối WiFi cửa hàng trước');
                                  }
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  appNotification.showError(title: 'Lỗi', message: 'Không thể lấy MAC WiFi: $e');
                                }
                              } finally {
                                setDialogState(() => isDetectingBssid = false);
                              }
                            },
                          ),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                    ),
                    helperText: 'Kết nối WiFi cửa hàng rồi nhấn nút để tự động lấy',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 16),
                // Map picker button
                InkWell(
                  onTap: () async {
                    final result = await showDialog<LatLng>(
                      context: context,
                      builder: (_) => MapLocationPicker(
                        initialLatitude: selectedLat ?? 10.7769,
                        initialLongitude: selectedLng ?? 106.7009,
                        initialZoom: selectedLat != null ? 16 : 12,
                        radius: double.tryParse(radiusController.text),
                      ),
                    );
                    if (result != null) {
                      setDialogState(() {
                        selectedLat = result.latitude;
                        selectedLng = result.longitude;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: selectedLat != null
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedLat != null
                            ? const Color(0xFF16A34A).withValues(alpha: 0.3)
                            : const Color(0xFF1E3A5F).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedLat != null ? Icons.check_circle : Icons.map,
                          color: selectedLat != null
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF1E3A5F),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedLat != null
                                    ? 'Đã chọn vị trí'
                                    : 'Chọn vị trí trên bản đồ',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: selectedLat != null
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF1E3A5F),
                                ),
                              ),
                              if (selectedLat != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '${selectedLat!.toStringAsFixed(6)}, ${selectedLng!.toStringAsFixed(6)}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)),
                                ),
                              ] else ...[
                                const SizedBox(height: 2),
                                const Text(
                                  'Nhấn để mở bản đồ và chọn tọa độ',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF71717A)),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Color(0xFF71717A)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );

          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Thêm vị trí làm việc'),
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: onSave,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F)),
                          child: const Text('Thêm'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.add_location_alt, color: Color(0xFF1E3A5F)),
                SizedBox(width: 12),
                Text('Thêm vị trí làm việc', style: TextStyle(color: Color(0xFF18181B))),
              ],
            ),
            content: SizedBox(width: 480, child: formContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
              ),
              ElevatedButton(
                onPressed: onSave,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F)),
                child: const Text('Thêm'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== TAB 3: ĐĂNG KÝ KHUÔN MẶT ====================
  Widget _buildFaceRegistrationTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                  ),
                  child: const TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm nhân viên...',
                      border: InputBorder.none,
                      icon: Icon(Icons.search, color: Color(0xFF71717A)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showRegisterFaceDialog(),
                icon: const Icon(Icons.face),
                label: const Text('Đăng ký'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F2340),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Stats
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.face,
                  value: _faceRegistrations.length.toString(),
                  label: 'Đã đăng ký',
                  color: const Color(0xFF0F2340),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.verified,
                  value: _faceRegistrations.where((f) => f.isVerified).length.toString(),
                  label: 'Đã xác thực',
                  color: const Color(0xFF1E3A5F),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.pending,
                  value: _faceRegistrations.where((f) => !f.isVerified).length.toString(),
                  label: 'Chờ xác thực',
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _faceRegistrations.isEmpty
              ? _buildEmptyState(
                  icon: Icons.face_retouching_off,
                  title: 'Chưa có đăng ký khuôn mặt',
                  subtitle: 'Đăng ký khuôn mặt cho nhân viên để sử dụng Face ID',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _faceRegistrations.length,
                  itemBuilder: (_, index) => Padding(
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
                      child: _buildFaceDeckItem(_faceRegistrations[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF71717A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaceDeckItem(FaceRegistration registration) {
    final statusColor = registration.isVerified ? const Color(0xFF1E3A5F) : const Color(0xFFF59E0B);
    final hasPhotos = registration.faceImages.isNotEmpty;

    return InkWell(
      onTap: () => _handleFaceRegistrationAction('view', registration),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Face photo thumbnail or fallback icon
            if (hasPhotos)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44, height: 44,
                  child: CachedNetworkImage(
                    imageUrl: _apiService.getFileUrl(registration.faceImages.first),
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: statusColor.withValues(alpha: 0.1),
                      child: Icon(Icons.face, size: 20, color: statusColor),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: statusColor.withValues(alpha: 0.1),
                      child: Icon(Icons.face, size: 20, color: statusColor),
                    ),
                  ),
                ),
              )
            else
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.face, size: 20, color: statusColor),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(registration.employeeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF18181B)), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${registration.employeeCode ?? ''} · ${registration.department ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasPhotos)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${registration.faceImages.length} ảnh đăng ký',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),
                ],
              ),
            ),
            // Small photo strip (up to 5 thumbnails)
            if (hasPhotos && registration.faceImages.length > 1)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: registration.faceImages.skip(1).take(4).map((url) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 24, height: 24,
                          child: CachedNetworkImage(
                            imageUrl: _apiService.getFileUrl(url),
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(color: Colors.grey[200]),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                registration.isVerified ? 'Đã xác thực' : 'Chờ xác thực',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF71717A)),
          ],
        ),
      ),
    );
  }

  void _showRegisterFaceDialog() async {
    // Load employees for selection
    List<dynamic> employees = [];
    try {
      employees = await _apiService.getEmployees(pageSize: 500);
    } catch (e) {
      debugPrint('Load employees error: $e');
    }

    if (!mounted) return;

    // Filter out employees that already have face registration
    final registeredIds = _faceRegistrations
        .map((f) => f.odooEmployeeId)
        .toSet();

    Map<String, dynamic>? selectedEmployee;
    String? selectedEmployeeId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final unregistered = employees
              .where((e) => !registeredIds.contains(e['id']?.toString() ?? ''))
              .toList();

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.face, color: Color(0xFF0F2340)),
                SizedBox(width: 12),
                Text('Đăng ký khuôn mặt', style: TextStyle(color: Color(0xFF18181B))),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Employee selector
                  const Text('Chọn nhân viên', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF18181B))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Chọn nhân viên...',
                      ),
                      isExpanded: true,
                      menuMaxHeight: 300,
                      initialValue: selectedEmployeeId,
                      items: unregistered.map<DropdownMenuItem<String>>((emp) {
                        final name = '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
                        final code = emp['employeeCode'] ?? '';
                        final dept = emp['departmentName'] ?? '';
                        final empId = emp['id']?.toString() ?? '';
                        return DropdownMenuItem(
                          value: empId,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: const Color(0xFF0F2340).withValues(alpha: 0.1),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Color(0xFF0F2340), fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                                    if (code.isNotEmpty || dept.isNotEmpty)
                                      Text('$code${code.isNotEmpty && dept.isNotEmpty ? ' · ' : ''}$dept',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(() {
                        selectedEmployeeId = val;
                        selectedEmployee = val == null ? null : unregistered.firstWhere(
                          (e) => e['id']?.toString() == val,
                          orElse: () => <String, dynamic>{},
                        );
                        if (selectedEmployee != null && selectedEmployee!.isEmpty) selectedEmployee = null;
                      }),
                    ),
                  ),
                  if (employees.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Không tải được danh sách nhân viên', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                    ),
                  if (unregistered.isEmpty && employees.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Tất cả nhân viên đã được đăng ký khuôn mặt', style: TextStyle(color: Color(0xFF71717A), fontSize: 12)),
                    ),
                  const SizedBox(height: 20),

                  // Selected employee preview
                  if (selectedEmployee != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F2340).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF0F2340).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFF0F2340).withValues(alpha: 0.1),
                            child: const Icon(Icons.person, color: Color(0xFF0F2340)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${selectedEmployee!['lastName'] ?? ''} ${selectedEmployee!['firstName'] ?? ''}'.trim(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF18181B)),
                                ),
                                Text(
                                  selectedEmployee!['employeeCode'] ?? '',
                                  style: const TextStyle(color: Color(0xFF71717A), fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.camera_alt, color: Color(0xFF0F2340), size: 28),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Info tip
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lightbulb, color: Color(0xFFF59E0B), size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Camera sẽ mở và chụp 3 ảnh khuôn mặt ở các góc: thẳng, trái, phải',
                            style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
              ),
              ElevatedButton.icon(
                onPressed: selectedEmployee == null
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _startFaceCapture(selectedEmployee!);
                      },
                icon: const Icon(Icons.camera_alt),
                label: const Text('Bắt đầu chụp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F2340),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE4E4E7),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _startFaceCapture(Map<String, dynamic> employee) async {
    final employeeId = employee['id']?.toString() ?? '';
    final employeeName = '${employee['lastName'] ?? ''} ${employee['firstName'] ?? ''}'.trim();

    final result = await CameraFaceCapture.show(
      context,
      employeeName: employeeName,
      requiredPhotos: 3,
    );

    if (result == null || result.base64Images.isEmpty || !mounted) return;

    // Show loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF0F2340)),
                SizedBox(height: 16),
                Text('Đang đăng ký khuôn mặt...', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final response = await _apiService.registerFace(
        employeeId: employeeId,
        employeeName: employeeName,
        faceImages: result.base64Images,
      );

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (response['isSuccess'] == true) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã đăng ký khuôn mặt cho "$employeeName" (${result.base64Images.length} ảnh)',
        );
        _loadData();
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: response['message'] ?? 'Không thể đăng ký khuôn mặt',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close loading
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể đăng ký khuôn mặt: $e',
        );
      }
    }
  }

  // ==================== TAB 4: THIẾT BỊ ĐƯỢC CẤP QUYỀN ====================
  Widget _buildDevicesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                  ),
                  child: const TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm thiết bị...',
                      border: InputBorder.none,
                      icon: Icon(Icons.search, color: Color(0xFF71717A)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showAddDeviceDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Cấp quyền'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _authorizedDevices.isEmpty
              ? _buildEmptyState(
                  icon: Icons.phone_android,
                  title: 'Chưa có thiết bị được cấp quyền',
                  subtitle: 'Cấp quyền cho điện thoại của nhân viên để chấm công',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _authorizedDevices.length,
                  itemBuilder: (_, index) => Padding(
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
                      child: _buildDeviceDeckItem(_authorizedDevices[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildDeviceDeckItem(AuthorizedDevice device) {
    final features = <String>[];
    if (device.canUseFaceId) features.add('Face ID');
    if (device.canUseGps) features.add('GPS');
    if (device.allowOutsideCheckIn) features.add('Ngoài CT');
    final isPending = !device.isAuthorized;
    return InkWell(
      onTap: () => _showDeviceDetailsDialog(device),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: isPending
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.1)
                    : const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                device.deviceModel.toLowerCase().contains('iphone') ? Icons.phone_iphone : Icons.phone_android,
                size: 18, color: isPending ? const Color(0xFFF59E0B) : const Color(0xFF1E3A5F),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(device.deviceName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF18181B)), overflow: TextOverflow.ellipsis),
                      ),
                      if (isPending)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Chờ duyệt', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B))),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${device.employeeName ?? 'Chưa gán'}${features.isNotEmpty ? ' · ${features.join(' · ')}' : ''}'
                    '${device.faceImages.isNotEmpty ? ' · ${device.faceImages.length} ảnh mặt' : ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isPending) ...[
              IconButton(
                onPressed: () => _approveDevice(device, true),
                icon: const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 24),
                tooltip: 'Duyệt',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                onPressed: () => _approveDevice(device, false),
                icon: const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 24),
                tooltip: 'Từ chối',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ] else
              Switch(
                value: device.isAuthorized,
                onChanged: (v) => _toggleDeviceAuthorization(device, v),
                activeThumbColor: const Color(0xFF1E3A5F),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ),
    );
  }

  void _showAddDeviceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.phone_android, color: Color(0xFF1E3A5F)),
            SizedBox(width: 12),
            Text('Cấp quyền thiết bị', style: TextStyle(color: Color(0xFF18181B))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: 'https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=ZKTECO_MOBILE_AUTH_${DateTime.now().millisecondsSinceEpoch}',
                      width: 150,
                      height: 150,
                      placeholder: (_, __) => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      errorWidget: (context, error, stackTrace) => const Icon(
                        Icons.qr_code,
                        size: 150,
                        color: Color(0xFF71717A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Quét mã QR từ ứng dụng mobile',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF18181B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Mã có hiệu lực trong 5 phút',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF71717A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF1E3A5F), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nhân viên cần cài ứng dụng ZKTeco Mobile để quét mã',
                      style: TextStyle(fontSize: 12, color: Color(0xFF1E3A5F)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng', style: TextStyle(color: Color(0xFF71717A))),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: const Color(0xFFA1A1AA)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF71717A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFFA1A1AA),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteLocation(WorkLocation location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa vị trí "${location.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final response = await _apiService.deleteWorkLocation(location.id);
      if (mounted) {
        if (response['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Thành công', message: 'Đã xóa vị trí');
          _loadData();
        } else {
          appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Không thể xóa');
        }
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: 'Không thể xóa: $e');
      }
    }
  }

  Future<void> _deleteDevice(AuthorizedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa thiết bị "${device.deviceName}" của ${device.employeeName ?? 'nhân viên'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final response = await _apiService.revokeDevice(device.id);
      if (mounted) {
        if (response['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Thành công', message: 'Đã xóa thiết bị');
          _loadData();
        } else {
          appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Không thể xóa');
        }
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: 'Không thể xóa: $e');
      }
    }
  }

  // ==================== API HELPER METHODS ====================

  void _showEditLocationDialog(WorkLocation location) {
    final nameController = TextEditingController(text: location.name);
    final addressController = TextEditingController(text: location.address);
    final radiusController = TextEditingController(text: location.radius.toString());
    final wifiBssidController = TextEditingController(text: location.wifiBssid ?? '');
    final isMobile = Responsive.isMobile(context);
    double editLat = location.latitude;
    double editLng = location.longitude;
    bool isDetectingBssid = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<Null> onSave() async {
            if (nameController.text.isEmpty || addressController.text.isEmpty) {
              appNotification.showError(title: 'Lỗi', message: 'Vui lòng nhập tên vị trí và địa chỉ');
              return;
            }
            try {
              final response = await _apiService.updateWorkLocation(
                id: location.id,
                name: nameController.text,
                address: addressController.text,
                latitude: editLat,
                longitude: editLng,
                radius: double.tryParse(radiusController.text) ?? 100,
                autoApproveInRange: location.autoApproveInRange,
                wifiBssid: wifiBssidController.text.isNotEmpty ? wifiBssidController.text : null,
              );
              if (context.mounted) {
                if (response['isSuccess'] == true) {
                  Navigator.pop(context);
                  appNotification.showSuccess(title: 'Thành công', message: 'Đã cập nhật vị trí');
                  _loadData();
                } else {
                  appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Không thể cập nhật');
                }
              }
            } catch (e) {
              if (mounted) {
                appNotification.showError(title: 'Lỗi', message: 'Không thể cập nhật: $e');
              }
            }
          }

          final bool hasCoords = editLat != 0 || editLng != 0;

          final formContent = SingleChildScrollView(
            padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Tên vị trí *',
                    prefixIcon: const Icon(Icons.business),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  decoration: InputDecoration(
                    labelText: 'Địa chỉ *',
                    prefixIcon: const Icon(Icons.location_on),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: radiusController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Bán kính cho phép (mét)',
                    prefixIcon: const Icon(Icons.radar),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: wifiBssidController,
                  decoration: InputDecoration(
                    labelText: 'MAC Router WiFi (BSSID)',
                    hintText: 'VD: AA:BB:CC:DD:EE:FF',
                    prefixIcon: const Icon(Icons.router),
                    suffixIcon: isDetectingBssid
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: const Icon(Icons.wifi_find, color: Color(0xFF1E3A5F)),
                            tooltip: 'Lấy MAC WiFi đang kết nối',
                            onPressed: () async {
                              setDialogState(() => isDetectingBssid = true);
                              try {
                                if (!kIsWeb) {
                                  final locStatus = await Permission.location.request();
                                  if (!locStatus.isGranted) {
                                    if (context.mounted) {
                                      appNotification.showError(title: 'Lỗi', message: 'Cần quyền vị trí để lấy MAC WiFi');
                                    }
                                    return;
                                  }
                                }
                                final info = NetworkInfo();
                                final bssid = await info.getWifiBSSID();
                                if (bssid != null && bssid.isNotEmpty && bssid != '02:00:00:00:00:00') {
                                  setDialogState(() {
                                    wifiBssidController.text = bssid;
                                  });
                                } else {
                                  if (context.mounted) {
                                    appNotification.showError(title: 'Không tìm thấy', message: 'Hãy kết nối WiFi cửa hàng trước');
                                  }
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  appNotification.showError(title: 'Lỗi', message: 'Không thể lấy MAC WiFi: $e');
                                }
                              } finally {
                                setDialogState(() => isDetectingBssid = false);
                              }
                            },
                          ),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    helperText: 'Kết nối WiFi cửa hàng rồi nhấn nút để tự động lấy',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 16),
                // Map picker button
                InkWell(
                  onTap: () async {
                    final result = await showDialog<LatLng>(
                      context: context,
                      builder: (_) => MapLocationPicker(
                        initialLatitude: editLat != 0 ? editLat : 10.7769,
                        initialLongitude: editLng != 0 ? editLng : 106.7009,
                        initialZoom: editLat != 0 ? 16 : 12,
                        radius: double.tryParse(radiusController.text),
                      ),
                    );
                    if (result != null) {
                      setDialogState(() {
                        editLat = result.latitude;
                        editLng = result.longitude;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: hasCoords
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasCoords
                            ? const Color(0xFF16A34A).withValues(alpha: 0.3)
                            : const Color(0xFF1E3A5F).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasCoords ? Icons.check_circle : Icons.map,
                          color: hasCoords
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF1E3A5F),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hasCoords
                                    ? 'Vị trí đã chọn'
                                    : 'Chọn vị trí trên bản đồ',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: hasCoords
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF1E3A5F),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hasCoords
                                    ? '${editLat.toStringAsFixed(6)}, ${editLng.toStringAsFixed(6)}'
                                    : 'Nhấn để mở bản đồ và chọn tọa độ',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Color(0xFF71717A)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );

          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Sửa vị trí làm việc'),
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteLocation(location);
                          },
                          icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                          label: const Text('Xóa', style: TextStyle(color: Color(0xFFEF4444))),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: onSave,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F)),
                          child: const Text('Lưu'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.edit_location_alt, color: Color(0xFFF59E0B)),
                SizedBox(width: 12),
                Text('Sửa vị trí làm việc', style: TextStyle(color: Color(0xFF18181B))),
              ],
            ),
            content: SizedBox(width: 480, child: formContent),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteLocation(location);
                },
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                label: const Text('Xóa', style: TextStyle(color: Color(0xFFEF4444))),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
              ),
              ElevatedButton(
                onPressed: onSave,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F)),
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleFaceRegistrationAction(String action, FaceRegistration registration) async {
    switch (action) {
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Xác nhận xóa'),
            content: Text('Xóa đăng ký khuôn mặt của "${registration.employeeName}"?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                child: const Text('Xóa'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        try {
          final response = await _apiService.deleteFaceRegistration(registration.id);
          if (mounted) {
            if (response['isSuccess'] == true) {
              appNotification.showSuccess(title: 'Thành công', message: 'Đã xóa đăng ký khuôn mặt');
              _loadData();
            } else {
              appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Không thể xóa');
            }
          }
        } catch (e) {
          if (mounted) {
            appNotification.showError(title: 'Lỗi', message: 'Không thể xóa: $e');
          }
        }
        break;
      case 'view':
        _showFaceImagesDialog(registration);
        break;
      case 'retake':
        _retakeFaceRegistration(registration);
        break;
    }
  }

  void _showFaceImagesDialog(FaceRegistration registration) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: isMobile ? const RoundedRectangleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F2340),
            foregroundColor: Colors.white,
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(registration.employeeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (registration.employeeCode != null)
                  Text(registration.employeeCode!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (registration.isVerified ? Colors.white : const Color(0xFFF59E0B)).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  registration.isVerified ? 'Đã xác thực' : 'Chờ xác thực',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: registration.isVerified ? Colors.white : const Color(0xFFFEF3C7)),
                ),
              ),
            ],
          ),
          body: registration.faceImages.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_not_supported, size: 48, color: Color(0xFF71717A)),
                      SizedBox(height: 8),
                      Text('Chưa có ảnh khuôn mặt', style: TextStyle(color: Color(0xFF71717A))),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${registration.faceImages.length} ảnh đã đăng ký',
                          style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isMobile ? 2 : 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: registration.faceImages.length,
                        itemBuilder: (_, index) {
                          final imageUrl = registration.faceImages[index];
                          final fullUrl = _apiService.getFileUrl(imageUrl);
                          return GestureDetector(
                            onTap: () => _showFullScreenImage(fullUrl, registration.employeeName),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: fullUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: const Color(0xFFF4F4F5),
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                                errorWidget: (_, url, error) => Container(
                                  color: const Color(0xFFF4F4F5),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.broken_image, color: Color(0xFF71717A)),
                                      const SizedBox(height: 4),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: Text(url, style: const TextStyle(fontSize: 8, color: Color(0xFF71717A)), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (registration.registeredAt != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Đăng ký: ${registration.registeredAt!.day}/${registration.registeredAt!.month}/${registration.registeredAt!.year}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                        ),
                      ],
                    ],
                  ),
                ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _handleFaceRegistrationAction('delete', registration);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                    label: const Text('Xóa', style: TextStyle(color: Color(0xFFEF4444))),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _retakeFaceRegistration(registration);
                    },
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Chụp lại'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F2340),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                errorWidget: (_, url, error) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                      const SizedBox(height: 8),
                      Text('Không tải được ảnh', style: const TextStyle(color: Colors.white54)),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(url, style: const TextStyle(fontSize: 10, color: Colors.white38), textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 16,
              left: 48,
              right: 48,
              child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retakeFaceRegistration(FaceRegistration registration) async {
    // First delete old registration
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chụp lại khuôn mặt'),
        content: Text('Ảnh khuôn mặt cũ của "${registration.employeeName}" sẽ bị xóa và chụp lại ảnh mới.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F2340)),
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Delete old registration
    try {
      await _apiService.deleteFaceRegistration(registration.id);
    } catch (e) {
      debugPrint('Delete face registration error: $e');
    }

    if (!mounted) return;

    // Start new capture
    final result = await CameraFaceCapture.show(
      context,
      employeeName: registration.employeeName,
      requiredPhotos: 3,
    );

    if (result == null || result.base64Images.isEmpty || !mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF0F2340)),
                SizedBox(height: 16),
                Text('Đang đăng ký lại khuôn mặt...', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final response = await _apiService.registerFace(
        employeeId: registration.odooEmployeeId,
        employeeName: registration.employeeName,
        faceImages: result.base64Images,
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (response['isSuccess'] == true) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã chụp lại khuôn mặt cho "${registration.employeeName}"',
        );
        _loadData();
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: response['message'] ?? 'Không thể đăng ký khuôn mặt',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        appNotification.showError(title: 'Lỗi', message: 'Không thể đăng ký: $e');
      }
    }
  }

  Future<void> _toggleDeviceAuthorization(AuthorizedDevice device, bool authorize) async {
    try {
      final Map<String, dynamic> response;
      if (!authorize) {
        response = await _apiService.revokeDevice(device.id);
      } else {
        response = await _apiService.authorizeDevice(
          deviceId: device.deviceId,
          deviceName: device.deviceName,
          deviceModel: device.deviceModel,
          employeeId: device.employeeId ?? '',
          employeeName: device.employeeName ?? '',
        );
      }
      if (mounted) {
        if (response['isSuccess'] == true) {
          appNotification.showSuccess(
            title: 'Thành công',
            message: authorize ? 'Đã cấp quyền thiết bị' : 'Đã thu hồi quyền thiết bị',
          );
          _loadData();
        } else {
          appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Không thể thay đổi quyền');
        }
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: 'Không thể thay đổi quyền: $e');
      }
    }
  }

  Future<void> _toggleAllowOutsideCheckIn(AuthorizedDevice device) async {
    final newValue = !device.allowOutsideCheckIn;
    try {
      final response = await _apiService.authorizeDevice(
        deviceId: device.deviceId,
        deviceName: device.deviceName,
        deviceModel: device.deviceModel,
        employeeId: device.employeeId ?? '',
        employeeName: device.employeeName ?? '',
        canUseFaceId: device.canUseFaceId,
        canUseGps: device.canUseGps,
        allowOutsideCheckIn: newValue,
      );
      if (mounted) {
        if (response['isSuccess'] == true) {
          appNotification.showSuccess(
            title: 'Thành công',
            message: newValue ? 'Đã cho phép chấm công ngoài công ty' : 'Đã tắt chấm công ngoài công ty',
          );
          _loadData();
        } else {
          appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Không thể thay đổi cài đặt');
        }
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: 'Lỗi: $e');
      }
    }
  }

  Future<void> _approveDevice(AuthorizedDevice device, bool approve) async {
    if (!approve) {
      // Ask for rejection reason
      final reason = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final controller = TextEditingController();
          return AlertDialog(
            title: const Text('Từ chối đăng ký'),
            content: SingleChildScrollView(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Lý do từ chối (không bắt buộc)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                child: const Text('Từ chối'),
              ),
            ],
          );
        },
      );
      if (reason == null || !mounted) return; // User cancelled
    }

    try {
      debugPrint('=== APPROVE DEVICE ===');
      debugPrint('Device ID: ${device.id}');
      debugPrint('Approve: $approve');
      final response = await _apiService.approveMobileDevice(
        deviceId: device.id,
        approved: approve,
      );
      debugPrint('Response: $response');

      if (mounted) {
        if (response['isSuccess'] == true) {
          appNotification.showSuccess(
            title: 'Thành công',
            message: approve ? 'Đã duyệt đăng ký thiết bị' : 'Đã từ chối đăng ký thiết bị',
          );
          _loadData();
        } else {
          appNotification.showError(
            title: 'Lỗi',
            message: response['message'] ?? 'Không thể xử lý yêu cầu',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: 'Lỗi: $e');
      }
    }
  }

  void _showDeviceDetailsDialog(AuthorizedDevice device) {
    final isPending = !device.isAuthorized;
    final isMobile = MediaQuery.of(context).size.width < 600;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: isMobile ? const RoundedRectangleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F2340),
            foregroundColor: Colors.white,
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.deviceName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(device.deviceModel, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
            actions: [
              if (isPending)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Chờ duyệt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFFEF3C7))),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Model', device.deviceModel),
                _buildDetailRow('Hệ điều hành', device.osVersion ?? 'N/A'),
                _buildDetailRow('Mã thiết bị', device.deviceId),
                _buildDetailRow('Nhân viên', device.employeeName ?? 'Chưa gán'),
                _buildDetailRow('Face ID', device.canUseFaceId ? 'Cho phép' : 'Không'),
                _buildDetailRow('GPS', device.canUseGps ? 'Cho phép' : 'Không'),
                _buildDetailRow('Chấm công ngoài CT', device.allowOutsideCheckIn ? 'Cho phép' : 'Không'),
                _buildDetailRow('MAC WiFi (BSSID)', device.wifiBssid ?? 'Chưa có'),
                _buildDetailRow('Trạng thái', isPending ? 'Chờ duyệt' : (device.isAuthorized ? 'Đã cấp quyền' : 'Đã thu hồi')),
                if (device.authorizedAt != null)
                  _buildDetailRow('Ngày đăng ký', '${device.authorizedAt!.day}/${device.authorizedAt!.month}/${device.authorizedAt!.year}'),

                // Face images section
                if (device.faceImages.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Khuôn mặt đã đăng ký', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF18181B))),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isMobile ? 3 : 4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: device.faceImages.length,
                    itemBuilder: (_, index) {
                      final imageUrl = device.faceImages[index];
                      final fullUrl = _apiService.getFileUrl(imageUrl);
                      return GestureDetector(
                        onTap: () => _showFullScreenImage(fullUrl, device.employeeName ?? device.deviceName),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: fullUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: const Color(0xFFF4F4F5),
                              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                            errorWidget: (_, url, error) => Container(
                              color: const Color(0xFFF4F4F5),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.broken_image, color: Color(0xFF71717A), size: 20),
                                  const SizedBox(height: 2),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: Text(url, style: const TextStyle(fontSize: 7, color: Color(0xFF71717A)), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteDevice(device);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                    label: const Text('Xóa', style: TextStyle(color: Color(0xFFEF4444))),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _toggleAllowOutsideCheckIn(device);
                    },
                    icon: Icon(
                      device.allowOutsideCheckIn ? Icons.location_off : Icons.location_on,
                      size: 18,
                      color: device.allowOutsideCheckIn ? const Color(0xFFF59E0B) : const Color(0xFF6B7280),
                    ),
                    label: Text(
                      device.allowOutsideCheckIn ? 'Tắt ngoài CT' : 'Bật ngoài CT',
                      style: TextStyle(color: device.allowOutsideCheckIn ? const Color(0xFFF59E0B) : const Color(0xFF6B7280)),
                    ),
                  ),
                  if (isPending) ...[
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _approveDevice(device, false);
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Từ chối'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _approveDevice(device, true);
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Duyệt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }
}
