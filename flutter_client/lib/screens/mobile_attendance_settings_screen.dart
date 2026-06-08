import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:latlong2/latlong.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/responsive_helper.dart';
import '../models/mobile_attendance.dart';
import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../utils/device_site_photo_prefs.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/map_location_picker.dart';
import '../widgets/camera_face_capture.dart';
import '../widgets/auth_cached_image.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import '../utils/navigation_notifier.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
enum _DeviceOutsideCheckInFilter { all, outsideOn, outsideOff }

class MobileAttendanceSettingsScreen extends StatefulWidget {
  const MobileAttendanceSettingsScreen({super.key});

  @override
  State<MobileAttendanceSettingsScreen> createState() => _MobileAttendanceSettingsScreenState();
}

class _MobileAttendanceSettingsScreenState extends State<MobileAttendanceSettingsScreen>
    with SingleTickerProviderStateMixin {
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  late TabController _tabController;
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool _isSaving = false;
  
  // Settings
  MobileAttendanceSettings _settings = MobileAttendanceSettings();
  
  // Data
  List<WorkLocation> _locations = [];
  String _locationSearchQuery = '';
  /// Số NV đã gán theo từng vị trí (locationId → count).
  Map<String, int> _locationEmployeeCounts = {};
  bool _loadingLocationEmployeeCounts = false;
  List<FaceRegistration> _faceRegistrations = [];
  String _faceSearchQuery = '';
  List<AuthorizedDevice> _authorizedDevices = [];
  String _deviceSearchQuery = '';
  _DeviceOutsideCheckInFilter _deviceOutsideFilter = _DeviceOutsideCheckInFilter.all;
  List<Map<String, dynamic>> _deviceChangeRequests = [];
  final _faceSearchController = TextEditingController();
  final _deviceSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final pendingTab = NavigationNotifier.mobileAttendanceSettingsTab.value;
    final initialTab =
        pendingTab != null && pendingTab >= 0 && pendingTab < 3 ? pendingTab : 0;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialTab,
    );
    if (pendingTab != null) {
      NavigationNotifier.mobileAttendanceSettingsTab.value = null;
    }
    NavigationNotifier.mobileAttendanceSettingsTab
        .addListener(_onPendingSettingsTab);
    ScreenRefreshNotifier.mobileAttendanceSettings.addListener(_onExternalRefresh);
    _loadData();
  }

  void _onPendingSettingsTab() {
    final tab = NavigationNotifier.mobileAttendanceSettingsTab.value;
    if (tab == null || !mounted || tab < 0 || tab >= 3) return;
    NavigationNotifier.mobileAttendanceSettingsTab.value = null;
    if (_tabController.index != tab) {
      _tabController.animateTo(tab);
    }
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    _loadData();
    if (_tabController.index != 2) {
      _tabController.animateTo(2);
    }
  }

  List<WorkLocation> get _filteredLocations {
    if (_locationSearchQuery.isEmpty) return _locations;
    final q = _locationSearchQuery.toLowerCase();
    return _locations.where((loc) =>
      loc.name.toLowerCase().contains(q) ||
      loc.address.toLowerCase().contains(q)
    ).toList();
  }

  List<FaceRegistration> get _filteredFaceRegistrations {
    if (_faceSearchQuery.isEmpty) return _faceRegistrations;
    final q = _faceSearchQuery.toLowerCase().trim();
    return _faceRegistrations.where((f) =>
      f.employeeName.toLowerCase().contains(q) ||
      (f.employeeCode ?? '').toLowerCase().contains(q) ||
      (f.department ?? '').toLowerCase().contains(q) ||
      f.odooEmployeeId.toLowerCase().contains(q)
    ).toList();
  }

  List<AuthorizedDevice> get _searchMatchedDevices {
    if (_deviceSearchQuery.isEmpty) return _authorizedDevices;
    return _authorizedDevices.where(_deviceMatchesSearch).toList();
  }

  List<AuthorizedDevice> get _filteredAuthorizedDevices {
    var list = _searchMatchedDevices;
    switch (_deviceOutsideFilter) {
      case _DeviceOutsideCheckInFilter.outsideOn:
        return list.where((d) => d.allowOutsideCheckIn).toList();
      case _DeviceOutsideCheckInFilter.outsideOff:
        return list.where((d) => !d.allowOutsideCheckIn).toList();
      case _DeviceOutsideCheckInFilter.all:
        return list;
    }
  }

  int get _deviceCountOutsideOn =>
      _searchMatchedDevices.where((d) => d.allowOutsideCheckIn).length;

  int get _deviceCountOutsideOff =>
      _searchMatchedDevices.where((d) => !d.allowOutsideCheckIn).length;

  bool get _hasActiveDeviceOutsideFilter =>
      _deviceOutsideFilter != _DeviceOutsideCheckInFilter.all;

  String get _deviceOutsideFilterLabel {
    switch (_deviceOutsideFilter) {
      case _DeviceOutsideCheckInFilter.outsideOn:
        return 'Chấm ngoài CT: Bật';
      case _DeviceOutsideCheckInFilter.outsideOff:
        return 'Chấm ngoài CT: Tắt';
      case _DeviceOutsideCheckInFilter.all:
        return 'Tất cả';
    }
  }

  void _setDeviceOutsideFilter(_DeviceOutsideCheckInFilter filter) {
    setState(() {
      if (_deviceOutsideFilter == filter &&
          filter != _DeviceOutsideCheckInFilter.all) {
        _deviceOutsideFilter = _DeviceOutsideCheckInFilter.all;
      } else {
        _deviceOutsideFilter = filter;
      }
    });
  }

  List<Map<String, dynamic>> get _filteredDeviceChangeRequests {
    if (_deviceSearchQuery.isEmpty) return _deviceChangeRequests;
    final q = _deviceSearchQuery.toLowerCase().trim();
    return _deviceChangeRequests.where((req) {
      final employeeName = (req['employeeName'] ?? '').toString().toLowerCase();
      final oldName = (req['oldDeviceName'] ?? '').toString().toLowerCase();
      final newName = (req['newDeviceName'] ?? '').toString().toLowerCase();
      return employeeName.contains(q) || oldName.contains(q) || newName.contains(q);
    }).toList();
  }

  bool _deviceMatchesSearch(AuthorizedDevice device) {
    final q = _deviceSearchQuery.toLowerCase().trim();
    return (device.employeeName ?? '').toLowerCase().contains(q) ||
        (device.employeeId ?? '').toLowerCase().contains(q) ||
        device.deviceName.toLowerCase().contains(q) ||
        device.deviceModel.toLowerCase().contains(q) ||
        device.deviceId.toLowerCase().contains(q);
  }

  String _deviceEmployeeLabel(AuthorizedDevice device) {
    final name = device.employeeName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Chưa gán nhân viên';
  }

  static const _deviceFaceStepLabels = ['Thẳng', 'Trái', 'Phải', 'Trên', 'Dưới'];

  Widget _buildStoredFaceImagesGrid({
    required List<String> imagePaths,
    required String previewName,
    required bool isMobile,
  }) {
    if (imagePaths.isEmpty) return const SizedBox.shrink();
    final cols = isMobile ? 2 : 3;
    const spacing = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        const itemHeight = 118.0;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: List.generate(imagePaths.length, (index) {
            final label = index < _deviceFaceStepLabels.length
                ? _deviceFaceStepLabels[index]
                : 'Ảnh ${index + 1}';
            return SizedBox(
              width: itemWidth,
              height: itemHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showFullScreenImage(imagePaths[index], previewName),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AuthCachedImage(
                          imagePath: imagePaths[index],
                          apiService: _apiService,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, __) => Container(
                            color: const Color(0xFFF4F4F5),
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFFF4F4F5),
                            child: const Icon(Icons.broken_image, color: Color(0xFF71717A)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF71717A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  @override
  void dispose() {
    NavigationNotifier.mobileAttendanceSettingsTab
        .removeListener(_onPendingSettingsTab);
    ScreenRefreshNotifier.mobileAttendanceSettings.removeListener(_onExternalRefresh);
    _tabController.dispose();
    _faceSearchController.dispose();
    _deviceSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getMobileAttendanceSettings(),
        _apiService.getWorkLocations(),
        _apiService.getAuthorizedDevices(),
        _apiService.getDeviceChangeRequests(status: 0),
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

      // Authorized devices (+ merge cờ ảnh CT đã lưu trên máy)
      if (results[2]['isSuccess'] == true && results[2]['data'] != null) {
        final data = results[2]['data'];
        if (data is List) {
          final devices = data
              .map((e) => AuthorizedDevice.fromJson(e as Map<String, dynamic>))
              .toList();
          final merged = <AuthorizedDevice>[];
          for (final d in devices) {
            final localOn =
                await DeviceSitePhotoPrefs.getDeviceEnabled(d.deviceId);
            merged.add(
                localOn ? d.copyWith(requirePhotoProof: true) : d);
          }
          _authorizedDevices = merged;
        }
      }

      final storePhotoLocal = await DeviceSitePhotoPrefs.getStoreEnabled();
      if (storePhotoLocal || _settings.requirePhotoProof) {
        _settings = _settings.copyWith(requirePhotoProof: true);
        await DeviceSitePhotoPrefs.setStoreEnabled(true);
      }

      // Device change requests
      if (results[3]['isSuccess'] == true && results[3]['data'] != null) {
        final data = results[3]['data'];
        if (data is List) {
          _deviceChangeRequests = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }

      final loadErrors = <String>[];
      void checkLoad(Map<String, dynamic> r, String label) {
        if (r['isSuccess'] == true) return;
        final code = r['statusCode'];
        final msg = r['message']?.toString().trim();
        if (code == 403) {
          loadErrors.add('$label: không có quyền (403)');
        } else if (msg != null && msg.isNotEmpty) {
          loadErrors.add('$label: $msg');
        } else if (code != null) {
          loadErrors.add('$label: lỗi $code');
        }
      }
      checkLoad(results[0], 'Cài đặt');
      checkLoad(results[1], 'Vị trí chấm công');
      checkLoad(results[2], 'Thiết bị đã duyệt');
      checkLoad(results[3], 'Yêu cầu đổi máy');
      if (mounted) {
        // Tải số NV đã gán cho từng vị trí (không chặn spinner chính).
        // ignore: discarded_futures
        _refreshLocationEmployeeCounts();
      }

      if (loadErrors.isNotEmpty && mounted) {
        appNotification.showWarning(
          title: 'Tải dữ liệu không đầy đủ',
          message: loadErrors.join('\n'),
        );
      }
    } catch (e) {
      debugPrint('Error loading mobile attendance data: $e');
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể tải dữ liệu chấm công mobile: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final embedded = HrmPageChrome.isEmbedded;
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: null,
        toolbarHeight: embedded ? 0 : kToolbarHeight,
        title: embedded
            ? null
            : const Text(
                'Chấm Công Mobile',
                style: TextStyle(
                  color: Color(0xFF18181B),
                  fontWeight: FontWeight.bold,
                ),
              ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: HrmPageChrome.primaryNavy,
          unselectedLabelColor: const Color(0xFF71717A),
          indicatorColor: HrmPageChrome.primaryNavy,
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: 'Cài đặt'),
            Tab(icon: Icon(Icons.location_on), text: 'Vị trí'),
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
            color: HrmPageChrome.primaryNavy,
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
            color: HrmPageChrome.primaryNavy,
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
            color: HrmPageChrome.primaryNavy,
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
            title: 'Ảnh hiện trường',
            icon: Icons.photo_camera_outlined,
            color: const Color(0xFF059669),
            children: [
              _buildSwitchTile(
                title: 'Ảnh hiện trường (cửa hàng)',
                subtitle: _settings.requirePhotoProof
                    ? 'ĐANG BẬT — bật thêm từng máy ở tab Thiết bị'
                    : 'ĐANG TẮT — chưa yêu cầu chụp ảnh sau chấm',
                value: _settings.requirePhotoProof,
                onChanged: (v) async {
                  setState(
                      () => _settings = _settings.copyWith(requirePhotoProof: v));
                  await DeviceSitePhotoPrefs.setStoreEnabled(v);
                  await _saveSettings();
                },
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
          if (_perm.canEdit('MobileAttendance'))
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Đang lưu...' : 'Lưu cài đặt'),
                style: FilledButton.styleFrom(
                  backgroundColor: HrmPageChrome.primaryNavy,
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
          color: selected ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1) : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? HrmPageChrome.primaryNavy : const Color(0xFFE4E4E7),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? HrmPageChrome.primaryNavy : const Color(0xFF71717A), size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: selected ? HrmPageChrome.primaryNavy : const Color(0xFF71717A),
              ),
            ),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: selected ? HrmPageChrome.primaryNavy.withValues(alpha: 0.7) : const Color(0xFF71717A),
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
            activeThumbColor: HrmPageChrome.primaryNavy,
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
                    color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HrmPageChrome.primaryNavy,
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
            activeColor: HrmPageChrome.primaryNavy,
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
        requirePhotoProof: _settings.requirePhotoProof,
        minPunchIntervalMinutes: _settings.minPunchIntervalMinutes,
      );

      if (!mounted) return;

      if (response['isSuccess'] == true) {
        await DeviceSitePhotoPrefs.setStoreEnabled(_settings.requirePhotoProof);
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
              
              if (_perm.canCreate('MobileAttendance')) ...[
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _showAddLocationDialog(),
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Thêm'),
                  style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                  ),
                ),
              ],
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

  String _locationEmployeeCountLabel(String locationId) {
    if (_loadingLocationEmployeeCounts &&
        !_locationEmployeeCounts.containsKey(locationId)) {
      return 'Đang tải…';
    }
    final count = _locationEmployeeCounts[locationId];
    if (count == null) return '— NV';
    if (count == 0) return 'Chưa gán NV';
    return '$count NV';
  }

  Future<void> _refreshLocationEmployeeCounts() async {
    if (_loadingLocationEmployeeCounts) return;
    if (_locations.isEmpty) {
      if (mounted) {
        setState(() {
          _locationEmployeeCounts = {};
          _loadingLocationEmployeeCounts = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loadingLocationEmployeeCounts = true);
    final counts = <String, int>{};
    final results = await Future.wait(
      _locations.map((loc) => _apiService.getLocationEmployees(loc.id)),
    );
    for (var i = 0; i < _locations.length; i++) {
      final r = results[i];
      if (r['isSuccess'] == true && r['data'] is List) {
        counts[_locations[i].id] = (r['data'] as List).length;
      } else {
        counts[_locations[i].id] = _locationEmployeeCounts[_locations[i].id] ?? 0;
      }
    }
    if (!mounted) return;
    setState(() {
      _locationEmployeeCounts = counts;
      _loadingLocationEmployeeCounts = false;
    });
  }

  Widget _buildLocationDeckItem(WorkLocation location) {
    final empLabel = _locationEmployeeCountLabel(location.id);
    final empCount = _locationEmployeeCounts[location.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: _perm.canEdit('MobileAttendance')
                  ? () => _showEditLocationDialog(location)
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.location_on,
                        size: 18, color: HrmPageChrome.primaryNavy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(location.name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF18181B)),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          '${location.address} · ${location.radius}m · ${location.autoApproveInRange ? 'Tự động' : 'Duyệt tay'}${location.wifiSsid != null && location.wifiSsid!.isNotEmpty ? ' · 📶 ${location.wifiSsid}' : ''}',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF71717A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showLocationEmployeesDialog(location),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 14,
                                color: empCount > 0
                                    ? HrmPageChrome.primaryNavy
                                    : const Color(0xFF71717A),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                empLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: empCount > 0
                                      ? HrmPageChrome.primaryNavy
                                      : const Color(0xFF71717A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (location.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Hoạt động',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: HrmPageChrome.primaryNavy)),
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFF71717A)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Gán nhân viên',
            onPressed: () => _showLocationEmployeesDialog(location),
            icon: const Icon(Icons.group_add_outlined,
                size: 20, color: HrmPageChrome.primaryNavy),
            style: IconButton.styleFrom(
              backgroundColor:
                  HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLocationEmployeesDialog(WorkLocation location) async {
    final savedCount = await showDialog<int>(
      context: context,
      builder: (ctx) => _LocationEmployeesAssignDialog(
        location: location,
        apiService: _apiService,
      ),
    );
    if (savedCount != null && mounted) {
      setState(() => _locationEmployeeCounts[location.id] = savedCount);
    }
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
                            icon: const Icon(Icons.wifi_find, color: HrmPageChrome.primaryNavy),
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
                            : HrmPageChrome.primaryNavy.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedLat != null ? Icons.check_circle : Icons.map,
                          color: selectedLat != null
                              ? const Color(0xFF16A34A)
                              : HrmPageChrome.primaryNavy,
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
                                      : HrmPageChrome.primaryNavy,
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
                        FilledButton(
                          onPressed: onSave,
                          style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
                          child: const Text('Thêm'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return ScrollableAlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.add_location_alt, color: HrmPageChrome.primaryNavy),
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
              FilledButton(
                onPressed: onSave,
                style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
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
                  child: TextField(
                    controller: _faceSearchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm nhân viên...',
                      border: InputBorder.none,
                      icon: const Icon(Icons.search, color: Color(0xFF71717A)),
                      suffixIcon: _faceSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: Color(0xFF71717A)),
                              onPressed: () {
                                _faceSearchController.clear();
                                setState(() => _faceSearchQuery = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) => setState(() => _faceSearchQuery = value),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _showRegisterFaceDialog(),
                icon: const Icon(Icons.face),
                label: const Text('Đăng ký'),
                style: FilledButton.styleFrom(
                  backgroundColor: HrmPageChrome.primaryNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  color: HrmPageChrome.primaryNavy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.verified,
                  value: _faceRegistrations.where((f) => f.isVerified).length.toString(),
                  label: 'Đã xác thực',
                  color: HrmPageChrome.primaryNavy,
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
              : _filteredFaceRegistrations.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.search_off,
                      title: 'Không tìm thấy nhân viên',
                      subtitle: 'Thử từ khóa khác hoặc xóa bộ lọc',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _filteredFaceRegistrations.length,
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
                          child: _buildFaceDeckItem(_filteredFaceRegistrations[index]),
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
    return HrmStatSummaryCard(
      icon: icon,
      value: value,
      label: label,
      color: color,
    );
  }

  Widget _buildFaceDeckItem(FaceRegistration registration) {
    final statusColor = registration.isVerified ? HrmPageChrome.primaryNavy : const Color(0xFFF59E0B);
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
                  child: AuthCachedImage(
                    imagePath: registration.faceImages.first,
                    apiService: _apiService,
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
                          child: AuthCachedImage(
                            imagePath: url,
                            apiService: _apiService,
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

          return ScrollableAlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.face, color: HrmPageChrome.primaryNavy),
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
                                backgroundColor: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: HrmPageChrome.primaryNavy, fontWeight: FontWeight.bold, fontSize: 14),
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
                        color: HrmPageChrome.primaryNavy.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: HrmPageChrome.primaryNavy.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                            child: const Icon(Icons.person, color: HrmPageChrome.primaryNavy),
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
                          const Icon(Icons.camera_alt, color: HrmPageChrome.primaryNavy, size: 28),
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
                            'Camera sẽ mở và chụp 5 ảnh khuôn mặt: thẳng, trái, phải, trên, dưới',
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
              FilledButton.icon(
                onPressed: selectedEmployee == null
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _startFaceCapture(selectedEmployee!);
                      },
                icon: const Icon(Icons.camera_alt),
                label: const Text('Bắt đầu chụp'),
                style: FilledButton.styleFrom(
                  backgroundColor: HrmPageChrome.primaryNavy,
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
      requiredPhotos: 5,
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
                CircularProgressIndicator(color: HrmPageChrome.primaryNavy),
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
                  child: TextField(
                    controller: _deviceSearchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm theo nhân viên, tên máy...',
                      border: InputBorder.none,
                      icon: const Icon(Icons.search, color: Color(0xFF71717A)),
                      suffixIcon: _deviceSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: Color(0xFF71717A)),
                              onPressed: () {
                                _deviceSearchController.clear();
                                setState(() => _deviceSearchQuery = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) => setState(() => _deviceSearchQuery = value),
                  ),
                ),
              ),
              if (_perm.canCreate('MobileAttendance')) ...[
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _showAddDeviceDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Cấp quyền'),
                  style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDeviceOutsideFilterChip(
                  label: 'Tất cả',
                  count: _searchMatchedDevices.length,
                  filter: _DeviceOutsideCheckInFilter.all,
                  color: HrmPageChrome.primaryNavy,
                  icon: Icons.devices,
                ),
                const SizedBox(width: 8),
                _buildDeviceOutsideFilterChip(
                  label: 'Ngoài CT',
                  count: _deviceCountOutsideOn,
                  filter: _DeviceOutsideCheckInFilter.outsideOn,
                  color: const Color(0xFF2563EB),
                  icon: Icons.location_off_outlined,
                ),
                const SizedBox(width: 8),
                _buildDeviceOutsideFilterChip(
                  label: 'Trong CT',
                  count: _deviceCountOutsideOff,
                  filter: _DeviceOutsideCheckInFilter.outsideOff,
                  color: const Color(0xFF71717A),
                  icon: Icons.business,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _authorizedDevices.isEmpty && _deviceChangeRequests.isEmpty
              ? _buildEmptyState(
                  icon: Icons.phone_android,
                  title: 'Chưa có thiết bị được cấp quyền',
                  subtitle: 'Cấp quyền cho điện thoại của nhân viên để chấm công',
                )
              : _filteredAuthorizedDevices.isEmpty && _filteredDeviceChangeRequests.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.search_off,
                      title: _hasActiveDeviceOutsideFilter || _deviceSearchQuery.isNotEmpty
                          ? 'Không tìm thấy thiết bị'
                          : 'Không tìm thấy thiết bị / nhân viên',
                      subtitle: _hasActiveDeviceOutsideFilter || _deviceSearchQuery.isNotEmpty
                          ? 'Thử bộ lọc hoặc từ khóa khác'
                          : 'Thử từ khóa khác hoặc xóa bộ lọc',
                    )
                  : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    if (_buildActiveDeviceOutsideFilterBanner() != null)
                      _buildActiveDeviceOutsideFilterBanner()!,
                    // Device change requests section
                    if (_filteredDeviceChangeRequests.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.swap_horiz, size: 18, color: Color(0xFF2563EB)),
                            const SizedBox(width: 6),
                            Text(
                              'Yêu cầu đổi máy (${_filteredDeviceChangeRequests.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ..._filteredDeviceChangeRequests.map((req) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _buildDeviceChangeRequestItem(req),
                        ),
                      )),
                      const Divider(height: 24),
                    ],
                    // Regular devices
                    ..._filteredAuthorizedDevices.map((device) => Padding(
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
                        child: _buildDeviceDeckItem(device),
                      ),
                    )),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildDeviceOutsideFilterChip({
    required String label,
    required int count,
    required _DeviceOutsideCheckInFilter filter,
    required Color color,
    required IconData icon,
  }) {
    final isSelected = _deviceOutsideFilter == filter;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _setDeviceOutsideFilter(filter),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFE4E4E7),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? color : const Color(0xFF71717A)),
              const SizedBox(width: 6),
              Text(
                '$label ($count)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? color : const Color(0xFF52525B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildActiveDeviceOutsideFilterBanner() {
    if (!_hasActiveDeviceOutsideFilter) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF2563EB).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _setDeviceOutsideFilter(_DeviceOutsideCheckInFilter.all),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.filter_alt, size: 16, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đang lọc: $_deviceOutsideFilterLabel · ${_filteredAuthorizedDevices.length} thiết bị',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
                const Text(
                  'Bỏ lọc',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceDeckItem(AuthorizedDevice device) {
    final features = <String>[];
    if (device.canUseFaceId) features.add('Face ID');
    if (device.canUseGps) features.add('GPS');
    if (device.allowOutsideCheckIn) features.add('Ngoài CT');
    if (_settings.requirePhotoProof && device.requirePhotoProof) {
      features.add('Ảnh CT: Bật');
    } else if (device.requirePhotoProof) {
      features.add('Ảnh CT: chờ bật CH');
    } else if (_settings.requirePhotoProof) {
      features.add('Ảnh CT: tắt máy');
    }
    final isPending = !device.isAuthorized;
    final employeeLabel = _deviceEmployeeLabel(device);
    final subtitleParts = <String>[device.deviceName, device.deviceModel];
    if (features.isNotEmpty) subtitleParts.add(features.join(' · '));
    if (device.selectedWorkLocations.isNotEmpty ||
        device.selectedWorkLocationIds.isNotEmpty) {
      subtitleParts.add('Vị trí: ${device.selectedWorkLocationsLabel}');
    }
    if (device.faceImages.isNotEmpty) {
      subtitleParts.add('${device.faceImages.length} ảnh mặt trên máy');
    } else if (device.canUseFaceId) {
      subtitleParts.add('Chưa có ảnh mặt trên máy');
    }
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
                    : HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                device.deviceModel.toLowerCase().contains('iphone') ? Icons.phone_iphone : Icons.phone_android,
                size: 18, color: isPending ? const Color(0xFFF59E0B) : HrmPageChrome.primaryNavy,
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
                        child: Text(
                          employeeLabel,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: device.employeeName != null && device.employeeName!.isNotEmpty
                                ? const Color(0xFF18181B)
                                : const Color(0xFF71717A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
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
                    subtitleParts.join(' · '),
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
                activeThumbColor: HrmPageChrome.primaryNavy,
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
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.phone_android, color: HrmPageChrome.primaryNavy),
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
                  Icon(Icons.info_outline, color: HrmPageChrome.primaryNavy, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nhân viên cần cài ứng dụng ZKTeco Mobile để quét mã',
                      style: TextStyle(fontSize: 12, color: HrmPageChrome.primaryNavy),
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
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa vị trí "${location.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
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
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa thiết bị "${device.deviceName}" của ${device.employeeName ?? 'nhân viên'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
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
    final isMobile = Responsive.isCompactViewport(context);
    double editLat = location.latitude;
    double editLng = location.longitude;
    bool isDetectingBssid = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
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
              if (dialogContext.mounted) {
                if (response['isSuccess'] == true) {
                  Navigator.pop(dialogContext);
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
                            icon: const Icon(Icons.wifi_find, color: HrmPageChrome.primaryNavy),
                            tooltip: 'Lấy MAC WiFi đang kết nối',
                            onPressed: () async {
                              setDialogState(() => isDetectingBssid = true);
                              try {
                                if (!kIsWeb) {
                                  final locStatus = await Permission.location.request();
                                  if (!locStatus.isGranted) {
                                    if (dialogContext.mounted) {
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
                                  if (dialogContext.mounted) {
                                    appNotification.showError(title: 'Không tìm thấy', message: 'Hãy kết nối WiFi cửa hàng trước');
                                  }
                                }
                              } catch (e) {
                                if (dialogContext.mounted) {
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
                      context: dialogContext,
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
                            : HrmPageChrome.primaryNavy.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasCoords ? Icons.check_circle : Icons.map,
                          color: hasCoords
                              ? const Color(0xFF16A34A)
                              : HrmPageChrome.primaryNavy,
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
                                      : HrmPageChrome.primaryNavy,
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
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (_perm.canDelete('MobileAttendance'))
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              _deleteLocation(location);
                            },
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: Color(0xFFEF4444)),
                            label: const Text('Xóa',
                                style: TextStyle(color: Color(0xFFEF4444))),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: onSave,
                          style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
                          child: const Text('Lưu'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return ScrollableAlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.edit_location_alt, color: Color(0xFFF59E0B)),
                SizedBox(width: 12),
                Text('Sửa vị trí làm việc', style: TextStyle(color: Color(0xFF18181B))),
              ],
            ),
            content: formContent,
            actions: [
              SizedBox(
                width: 480,
                child: Row(
                  children: [
                    if (_perm.canDelete('MobileAttendance'))
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteLocation(location);
                        },
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Color(0xFFEF4444)),
                        label: const Text('Xóa',
                            style: TextStyle(color: Color(0xFFEF4444))),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: onSave,
                      style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
                      child: const Text('Lưu'),
                    ),
                  ],
                ),
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
          builder: (ctx) => ScrollableAlertDialog(
            title: const Text('Xác nhận xóa'),
            content: Text('Xóa đăng ký khuôn mặt của "${registration.employeeName}"?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
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
            backgroundColor: HrmPageChrome.primaryNavy,
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
                          return GestureDetector(
                            onTap: () => _showFullScreenImage(imageUrl, registration.employeeName),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AuthCachedImage(
                                imagePath: imageUrl,
                                apiService: _apiService,
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
                  if (_perm.canDelete('MobileAttendance'))
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleFaceRegistrationAction('delete', registration);
                      },
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Color(0xFFEF4444)),
                      label: const Text('Xóa',
                          style: TextStyle(color: Color(0xFFEF4444))),
                    ),
                  const Spacer(),
                  if (_perm.canEdit('MobileAttendance'))
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _retakeFaceRegistration(registration);
                      },
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Chụp lại'),
                    style: FilledButton.styleFrom(
                      backgroundColor: HrmPageChrome.primaryNavy,
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

  void _showFullScreenImage(String imagePath, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              child: AuthCachedImage(
                imagePath: imagePath,
                apiService: _apiService,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                errorWidget: (_, url, error) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                      const SizedBox(height: 8),
                      const Text('Không tải được ảnh', style: TextStyle(color: Colors.white54)),
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
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Chụp lại khuôn mặt'),
        content: Text('Ảnh khuôn mặt cũ của "${registration.employeeName}" sẽ bị xóa và chụp lại ảnh mới.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
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
      requiredPhotos: 5,
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
                CircularProgressIndicator(color: HrmPageChrome.primaryNavy),
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
          canUseFaceId: device.canUseFaceId,
          canUseGps: device.canUseGps,
          allowOutsideCheckIn: device.allowOutsideCheckIn,
          requirePhotoProof: device.requirePhotoProof,
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

  void _patchAuthorizedDevice(AuthorizedDevice updated) {
    final i = _authorizedDevices.indexWhere((d) => d.id == updated.id);
    if (i >= 0) {
      setState(() => _authorizedDevices[i] = updated);
    }
  }

  Future<bool> _toggleDeviceRequirePhotoProof(
    AuthorizedDevice device, {
    required bool targetValue,
  }) async {
    if (!_settings.requirePhotoProof && targetValue) {
      appNotification.showError(
        title: 'Chưa bật tính năng',
        message:
            'Vào tab Cài đặt chung → bật «Ảnh hiện trường (cửa hàng)» trước.',
      );
      return false;
    }
    try {
      var response = await _apiService.setDeviceRequirePhotoProof(
        deviceRecordId: device.id,
        requirePhotoProof: targetValue,
      );
      final patchFailed = response['isSuccess'] != true;
      if (patchFailed) {
        // API cũ chưa có PATCH — fallback authorize
        response = await _apiService.authorizeDevice(
          deviceId: device.deviceId,
          deviceName: device.deviceName,
          deviceModel: device.deviceModel,
          employeeId: device.employeeId ?? '',
          employeeName: device.employeeName ?? '',
          canUseFaceId: device.canUseFaceId,
          canUseGps: device.canUseGps,
          allowOutsideCheckIn: device.allowOutsideCheckIn,
          requirePhotoProof: targetValue,
        );
      }
      if (!mounted) return false;
      if (response['isSuccess'] == true) {
        var savedOnDevice = targetValue;
        final data = response['data'];
        if (data is Map) {
          final parsed = AuthorizedDevice.fromJson(
              Map<String, dynamic>.from(data));
          savedOnDevice = parsed.requirePhotoProof;
          _patchAuthorizedDevice(parsed.copyWith(requirePhotoProof: targetValue));
        } else {
          _patchAuthorizedDevice(
            device.copyWith(requirePhotoProof: targetValue),
          );
        }
        if (savedOnDevice != targetValue) {
          _patchAuthorizedDevice(
            device.copyWith(requirePhotoProof: targetValue),
          );
        }
        await DeviceSitePhotoPrefs.setDeviceEnabledForRecord(
          device.deviceId,
          targetValue,
        );
        appNotification.showSuccess(
          title: 'Thành công',
          message: targetValue
              ? 'Đã BẬT chụp ảnh hiện trường cho thiết bị này'
              : 'Đã TẮT chụp ảnh hiện trường cho thiết bị này',
        );
        return true;
      }
      appNotification.showError(
        title: 'Lỗi',
        message: response['message'] ?? 'Không thể thay đổi cài đặt',
      );
      return false;
    } catch (e) {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: 'Lỗi: $e');
      }
      return false;
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
        requirePhotoProof: device.requirePhotoProof,
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

  Widget _buildDeviceChangeRequestItem(Map<String, dynamic> req) {
    final requestedAt = req['requestedAt'] != null
        ? DateTime.tryParse(req['requestedAt'].toString())
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.swap_horiz, size: 18, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  req['employeeName'] ?? '',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF18181B)),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${req['oldDeviceName'] ?? '?'} → ${req['newDeviceName'] ?? '?'}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                  overflow: TextOverflow.ellipsis,
                ),
                if (req['reason'] != null && (req['reason'] as String).isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Lý do: ${req['reason']}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA), fontStyle: FontStyle.italic),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (formatSelectedWorkLocationsFromRequest(req) != 'Chưa chọn') ...[
                  const SizedBox(height: 2),
                  Text(
                    'Vị trí: ${formatSelectedWorkLocationsFromRequest(req)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (requestedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${requestedAt.day}/${requestedAt.month}/${requestedAt.year}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA)),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => _approveDeviceChange(req, true),
            icon: const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 24),
            tooltip: 'Duyệt đổi máy',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            onPressed: () => _approveDeviceChange(req, false),
            icon: const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 24),
            tooltip: 'Từ chối',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Future<void> _approveDeviceChange(Map<String, dynamic> req, bool approve) async {
    String? rejectionReason;
    if (!approve) {
      rejectionReason = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final controller = TextEditingController();
          return ScrollableAlertDialog(
            title: const Text('Từ chối đổi máy'),
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
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                child: const Text('Từ chối'),
              ),
            ],
          );
        },
      );
      if (rejectionReason == null || !mounted) return;
    }

    try {
      final requestId = req['id']?.toString() ?? '';
      final response = await _apiService.approveDeviceChange(
        requestId: requestId,
        approved: approve,
        rejectionReason: rejectionReason,
      );

      if (mounted) {
        if (response['isSuccess'] == true) {
          appNotification.showSuccess(
            title: 'Thành công',
            message: approve
                ? 'Đã duyệt đổi máy cho ${req['employeeName']}'
                : 'Đã từ chối đổi máy cho ${req['employeeName']}',
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

  Future<void> _approveDevice(AuthorizedDevice device, bool approve) async {
    if (!approve) {
      // Ask for rejection reason
      final reason = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final controller = TextEditingController();
          return ScrollableAlertDialog(
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
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
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
    bool photoProofOn = device.requirePhotoProof;
    for (final d in _authorizedDevices) {
      if (d.id == device.id) {
        photoProofOn = d.requirePhotoProof;
        break;
      }
    }
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          AuthorizedDevice current = device;
          for (final d in _authorizedDevices) {
            if (d.id == device.id) {
              current = d;
              break;
            }
          }
          return Dialog(
        insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: isMobile ? const RoundedRectangleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: HrmPageChrome.primaryNavy,
            foregroundColor: Colors.white,
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_deviceEmployeeLabel(current), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  '${current.deviceName} · ${current.deviceModel}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
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
                _buildDetailRow('Nhân viên', _deviceEmployeeLabel(device)),
                if (device.employeeId != null && device.employeeId!.isNotEmpty)
                  _buildDetailRow('Mã nhân viên', device.employeeId!),
                _buildDetailRow('Tên thiết bị', device.deviceName),
                _buildDetailRow('Model', device.deviceModel),
                _buildDetailRow('Hệ điều hành', device.osVersion ?? 'N/A'),
                _buildDetailRow('Mã thiết bị', device.deviceId),
                _buildDetailRow('Face ID', device.canUseFaceId ? 'Cho phép' : 'Không'),
                _buildDetailRow('GPS', device.canUseGps ? 'Cho phép' : 'Không'),
                _buildDetailRow('Chấm công ngoài CT', device.allowOutsideCheckIn ? 'Cho phép' : 'Không'),
                _buildPhotoProofStatusBanner(
                  current.copyWith(requirePhotoProof: photoProofOn),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Chụp ảnh hiện trường sau chấm',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF18181B),
                    ),
                  ),
                  subtitle: Text(
                    !_settings.requirePhotoProof
                        ? 'Bật «Ảnh hiện trường (cửa hàng)» ở tab Cài đặt chung trước'
                        : (photoProofOn
                            ? 'ĐANG BẬT trên thiết bị này'
                            : 'ĐANG TẮT trên thiết bị này'),
                    style: TextStyle(
                      fontSize: 13,
                      color: !_settings.requirePhotoProof
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF71717A),
                    ),
                  ),
                  value: photoProofOn,
                  onChanged: !_settings.requirePhotoProof
                      ? null
                      : (v) async {
                          if (v == photoProofOn) return;
                          setDialogState(() => photoProofOn = v);
                          final ok = await _toggleDeviceRequirePhotoProof(
                            current,
                            targetValue: v,
                          );
                          if (!mounted) return;
                          if (!ok) {
                            setDialogState(() => photoProofOn = !v);
                            return;
                          }
                          setDialogState(() => photoProofOn = v);
                        },
                  activeThumbColor: const Color(0xFF059669),
                ),
                _buildDetailRow('MAC WiFi (BSSID)', device.wifiBssid ?? 'Chưa có'),
                _buildDetailRow(
                  'Vị trí chấm công',
                  device.selectedWorkLocationsLabel,
                ),
                _buildDetailRow('Trạng thái', isPending ? 'Chờ duyệt' : (device.isAuthorized ? 'Đã cấp quyền' : 'Đã thu hồi')),
                if (device.authorizedAt != null)
                  _buildDetailRow('Ngày đăng ký', '${device.authorizedAt!.day}/${device.authorizedAt!.month}/${device.authorizedAt!.year}'),

                const SizedBox(height: 16),
                Text(
                  device.faceImages.isNotEmpty
                      ? 'Khuôn mặt của ${_deviceEmployeeLabel(device)} trên thiết bị'
                      : 'Khuôn mặt trên thiết bị',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF18181B)),
                ),
                const SizedBox(height: 4),
                Text(
                  device.faceImages.isNotEmpty
                      ? '${device.faceImages.length} ảnh đồng bộ từ đăng ký khuôn mặt của nhân viên'
                      : (device.employeeId != null && device.employeeId!.isNotEmpty
                          ? 'Nhân viên chưa có ảnh khuôn mặt — đăng ký khi cấp thiết bị hoặc quét trên máy nhân viên'
                          : 'Gán nhân viên cho thiết bị để xem ảnh khuôn mặt'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                ),
                if (device.faceImages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildStoredFaceImagesGrid(
                    imagePaths: device.faceImages,
                    previewName: _deviceEmployeeLabel(device),
                    isMobile: isMobile,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.face_retouching_off, color: Color(0xFF71717A)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Chưa có ảnh khuôn mặt gắn với thiết bị này',
                            style: TextStyle(fontSize: 13, color: Color(0xFF71717A)),
                          ),
                        ),
                      ],
                    ),
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
                  if (_perm.canDelete('MobileAttendance'))
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _deleteDevice(device);
                      },
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Color(0xFFEF4444)),
                      label: const Text('Xóa',
                          style: TextStyle(color: Color(0xFFEF4444))),
                    ),
                  if (_perm.canEdit('MobileAttendance'))
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
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _approveDevice(device, false);
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Từ chối'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _approveDevice(device, true);
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Duyệt'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
          );
        },
      ),
    );
  }

  Widget _buildPhotoProofStatusBanner(AuthorizedDevice device) {
    final storeOn = _settings.requirePhotoProof;
    final deviceOn = device.requirePhotoProof;
    final effective = storeOn && deviceOn;
    final Color bg;
    final Color border;
    final Color text;
    final String label;
    final IconData icon;
    if (effective) {
      bg = const Color(0xFFECFDF5);
      border = const Color(0xFF6EE7B7);
      text = const Color(0xFF047857);
      label = 'Ảnh hiện trường: ĐANG BẬT (sau mỗi lần chấm sẽ mở camera)';
      icon = Icons.photo_camera;
    } else if (!storeOn) {
      bg = const Color(0xFFFFF7ED);
      border = const Color(0xFFFDBA74);
      text = const Color(0xFFC2410C);
      label = 'Ảnh hiện trường: TẮT — chưa bật ở cấp cửa hàng';
      icon = Icons.storefront_outlined;
    } else if (deviceOn) {
      bg = const Color(0xFFEFF6FF);
      border = const Color(0xFF93C5FD);
      text = const Color(0xFF1D4ED8);
      label =
          'Thiết bị: ĐANG BẬT · Cửa hàng: TẮT (chưa có hiệu lực khi chấm công)';
      icon = Icons.info_outline;
    } else {
      bg = const Color(0xFFF4F4F5);
      border = const Color(0xFFE4E4E7);
      text = const Color(0xFF52525B);
      label = 'Ảnh hiện trường: TẮT trên thiết bị này';
      icon = Icons.photo_camera_outlined;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: text),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ),
        ],
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

/// Dialog gán nhân viên cho vị trí — tải dữ liệu trong initState (không gọi API trong build).
class _LocationEmployeesAssignDialog extends StatefulWidget {
  final WorkLocation location;
  final ApiService apiService;

  const _LocationEmployeesAssignDialog({
    required this.location,
    required this.apiService,
  });

  @override
  State<_LocationEmployeesAssignDialog> createState() =>
      _LocationEmployeesAssignDialogState();
}

class _LocationEmployeesAssignDialogState
    extends State<_LocationEmployeesAssignDialog> {
  bool _loading = true;
  bool _saving = false;
  String _loadError = '';
  String _searchQuery = '';
  List<dynamic> _allEmployees = [];
  final Set<String> _selectedIds = {};
  final Map<String, String> _nameById = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        widget.apiService.getEmployees(page: 1, pageSize: 500),
        widget.apiService.getLocationEmployees(widget.location.id),
      ]);
      if (!mounted) return;

      final empList = results[0];
      final assigned = results[1] as Map<String, dynamic>;

      if (assigned['isSuccess'] == true && assigned['data'] is List) {
        for (final row in assigned['data'] as List) {
          final id = row['employeeId']?.toString() ?? '';
          if (id.isEmpty) continue;
          _selectedIds.add(id);
          final n = row['employeeName']?.toString().trim();
          if (n != null && n.isNotEmpty) _nameById[id] = n;
        }
      }

      if (empList is List) {
        _allEmployees = empList;
        for (final emp in empList) {
          final id = emp['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final name =
              '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
          final code = emp['employeeCode']?.toString() ?? '';
          final label = code.isNotEmpty ? '$name ($code)' : name;
          if (label.isNotEmpty) _nameById[id] = label;
        }
      } else {
        _loadError = 'Không tải được danh sách nhân viên';
      }
    } catch (e) {
      _loadError = 'Lỗi tải dữ liệu: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = _selectedIds
          .map((id) => {
                'employeeId': id,
                'employeeName': _nameById[id] ?? id,
              })
          .toList();
      final response = await widget.apiService.setLocationEmployees(
        locationId: widget.location.id,
        employees: payload,
      );
      if (!mounted) return;
      if (response['isSuccess'] == true) {
        Navigator.pop(context, _selectedIds.length);
        NotificationOverlayManager().showSuccess(
          title: 'Đã lưu',
          message:
              'Đã gán ${_selectedIds.length} nhân viên cho «${widget.location.name}»',
        );
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: response['message']?.toString() ?? 'Không thể lưu gán NV',
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: 'Không thể lưu: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<dynamic> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _allEmployees;
    final q = _searchQuery.toLowerCase();
    return _allEmployees.where((emp) {
      final name =
          '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.toLowerCase();
      final code = (emp['employeeCode'] ?? '').toString().toLowerCase();
      final dept = (emp['departmentName'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q) || dept.contains(q);
    }).toList();
  }

  Widget _buildBody() {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError.isNotEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(_loadError,
              style: const TextStyle(color: Color(0xFFEF4444))),
        ),
      );
    }
    if (_allEmployees.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('Chưa có nhân viên trong hệ thống',
              style: TextStyle(color: Color(0xFF71717A))),
        ),
      );
    }
    final filtered = _filteredEmployees;
    final isMobile = Responsive.isCompactViewport(context);
    return SizedBox(
      height: isMobile ? 360 : 420,
      child: ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (_, index) {
          final emp = filtered[index];
          final id = emp['id']?.toString() ?? '';
          if (id.isEmpty) return const SizedBox.shrink();
          final name =
              '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
          final code = emp['employeeCode']?.toString() ?? '';
          final dept = emp['departmentName']?.toString() ?? '';
          final subtitle = [
            if (code.isNotEmpty) code,
            if (dept.isNotEmpty) dept,
          ].join(' · ');
          return CheckboxListTile(
            value: _selectedIds.contains(id),
            onChanged: _saving
                ? null
                : (v) {
                    setState(() {
                      if (v == true) {
                        _selectedIds.add(id);
                      } else {
                        _selectedIds.remove(id);
                      }
                    });
                  },
            title: Text(
              name.isNotEmpty ? name : id,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: subtitle.isNotEmpty
                ? Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF71717A)))
                : null,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F4F5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Chọn nhân viên được phép chấm tại vị trí này. '
            'NV chưa được gán vị trí nào → chấm được mọi vị trí. '
            'NV đã gán ít nhất 1 vị trí → chỉ chấm các vị trí đã gán.',
            style: TextStyle(fontSize: 12, color: Color(0xFF52525B), height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            hintText: 'Tìm theo tên, mã, phòng ban…',
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
            ),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _searchQuery = v.trim()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Đã chọn: ${_selectedIds.length}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF71717A)),
            ),
            const Spacer(),
            TextButton(
              onPressed: _saving || _allEmployees.isEmpty
                  ? null
                  : () => setState(() {
                        for (final emp in _allEmployees) {
                          final id = emp['id']?.toString() ?? '';
                          if (id.isNotEmpty) _selectedIds.add(id);
                        }
                      }),
              child: const Text('Chọn tất cả'),
            ),
            TextButton(
              onPressed: _saving ? null : () => setState(_selectedIds.clear),
              child: const Text('Bỏ chọn'),
            ),
          ],
        ),
        _buildBody(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isCompactViewport(context);
    final canSave = !_loading && !_saving && _loadError.isEmpty;

    if (isMobile) {
      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.group_add,
                        color: HrmPageChrome.primaryNavy),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Gán NV — ${widget.location.name}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _buildContent(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Hủy'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: canSave ? _save : null,
                      style: FilledButton.styleFrom(
                          backgroundColor: HrmPageChrome.primaryNavy),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Lưu gán'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ScrollableAlertDialog(
      title: Row(
        children: [
          const Icon(Icons.group_add, color: HrmPageChrome.primaryNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Gán nhân viên — ${widget.location.name}',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(width: 520, child: _buildContent()),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: canSave ? _save : null,
          style: FilledButton.styleFrom(
              backgroundColor: HrmPageChrome.primaryNavy),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Lưu gán'),
        ),
      ],
    );
  }
}
