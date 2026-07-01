import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/mobile_attendance.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/global_location_reporter.dart';
import '../services/face_storage_service.dart';
import '../services/face_embedding_service_stub.dart'
    if (dart.library.io) '../services/face_embedding_service.dart';
import '../utils/platform_geolocation.dart';
import '../utils/mobile_device_id.dart';
import '../utils/device_site_photo_prefs.dart';
import '../widgets/face_verification_camera.dart';
import '../widgets/site_photo_capture_screen.dart';
import '../utils/app_error_utils.dart';
import '../utils/travel_hours_calculator.dart';
import '../widgets/mobile_attendance_record_detail_sheet.dart';
import '../widgets/notification_overlay.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import 'mobile_attendance_history_screen.dart';

class MobileAttendanceScreen extends StatefulWidget {
  const MobileAttendanceScreen({super.key});

  @override
  State<MobileAttendanceScreen> createState() => _MobileAttendanceScreenState();
}

class _MobileAttendanceScreenState extends State<MobileAttendanceScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final ApiService _apiService = ApiService();

  bool _isLocationVerified = false;
  bool _isGettingLocation = false;
  bool _isWifiVerified = false;
  bool _isCheckingWifi = false;
  String? _connectedWifiSsid;
  String? _wifiLocationName;
  String? _detectedBssid;
  double? _currentLatitude;
  double? _currentLongitude;
  double? _distanceFromOffice;
  String? _nearestLocationName;

  // Employee data from auth
  String _employeeName = '';
  String _department = '';
  String _employeeId = '';

  // Work locations from API
  List<WorkLocation> _workLocations = [];

  // Today's attendance records from API
  List<MobileAttendanceRecord> _todayRecords = [];

  // Device registration state
  bool _isDeviceRegistered = false;
  bool _isDeviceApproved = false;
  String? _currentDeviceId;
  bool _registeredOnOtherDevice = false;
  String? _otherDeviceName;

  // Device outside check-in permission
  bool _allowOutsideCheckIn = false;
  bool _allowTravelCheckIn = false;
  /// Loại chấm đang xử lý (null = chấm vào/ra thường).
  int? _punchContextType;
  /// Cửa hàng + thiết bị đều bật → mở camera sau chấm (từ API requirePhotoProof).
  bool _deviceRequirePhotoProof = false;
  bool _devicePhotoProofFlag = false;
  bool _storePhotoProofFlag = false;
  bool _localDevicePhotoProof = false;
  bool _localStorePhotoProof = false;

  // Face verification state
  bool _isFaceVerified = false;
  double? _faceMatchScore;
  String? _faceImageBase64;
  bool _livenessPassed = false;
  String? _clientFaceEngine;
  List<String> _cachedFacePaths = []; // On-device face registration images

  // Settings for verification requirements
  MobileAttendanceSettings? _settings;

  // Continuous monitoring timer
  Timer? _monitorTimer;
  int _monitorFailCount = 0; // for backoff

  // Auto-submit state
  bool _isAutoSubmitting = false;

  /// Đồng hồ — một Timer duy nhất, tránh tạo Stream mới mỗi lần build (gây Stack Overflow).
  DateTime _clockNow = DateTime.now();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadEmployeeData();
    _initVerification();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _clockNow = DateTime.now());
    });
  }

  /// Optimized startup: request permission once, then parallelize everything
  Future<void> _initVerification() async {
    // 1. Request location permission once (needed by both GPS + WiFi BSSID)
    if (!kIsWeb) {
      final granted = await ensureLocationPermission();
      if (!mounted) return;
      // Also set permission_handler status for WiFi
      if (granted) {
        _wifiPermissionsRequested = true;
      }
    }

    // 2. Instant GPS from OS cache (< 50ms)
    final lastPos = await getLastKnownPosition();
    if (lastPos != null && mounted) {
      setState(() {
        _currentLatitude = lastPos.latitude;
        _currentLongitude = lastPos.longitude;
      });
    }

    _currentDeviceId = await MobileDeviceId.resolve();

    // 3. Parallelize ALL network calls + fresh GPS + WiFi scan
    await Future.wait([
      _loadWorkLocations(),
      _loadDeviceStatus(),
      _loadSettings(),
      _loadTodayRecords(),
      _getCurrentLocation(),
      _checkWifiConnection(requestPermissions: true),
    ]);

    // 4. Recalculate with both workLocations + GPS ready
    if (mounted) _calculateNearestLocation();

    // 5. Start monitoring with backoff
    _startMonitoring();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDeviceStatus();
      _loadSettings();
      GlobalLocationReporter.instance.startIfEligible(
        employeeId: _employeeId.isNotEmpty ? _employeeId : null,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _monitorTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _loadEmployeeData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user != null) {
      setState(() {
        _employeeName = user.fullName;
        _employeeId = user.employeeId ?? user.id;
        _department = user.department ?? '';
      });
      unawaited(_loadCachedFacesFromDevice());
    }
  }

  Future<void> _loadCachedFacesFromDevice() async {
    if (_employeeId.isEmpty) return;
    try {
      final storageService = FaceStorageService(baseUrl: ApiService.baseUrl);
      final cachedPaths = await storageService.getCachedFacePaths(_employeeId);
      if (!mounted || cachedPaths.isEmpty) return;

      setState(() => _cachedFacePaths = cachedPaths);
      debugPrint(
          'Loaded cached faces from device: ${cachedPaths.length} files');
      FaceEmbeddingService.clearCache();
      await FaceEmbeddingService.initialize();
    } catch (e) {
      debugPrint('Error loading cached faces from device: $e');
    }
  }

  static bool _parseApiBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' || s == '1';
  }

  Future<void> _loadDeviceStatus() async {
    final storageService = FaceStorageService(baseUrl: ApiService.baseUrl);
    try {
      _localStorePhotoProof = await DeviceSitePhotoPrefs.getStoreEnabled();
      if (_currentDeviceId == null || _currentDeviceId!.isEmpty) {
        _currentDeviceId = await MobileDeviceId.resolve();
      }
      final localPhoto = _currentDeviceId != null && _currentDeviceId!.isNotEmpty
          ? await DeviceSitePhotoPrefs.getDeviceEnabled(_currentDeviceId!)
          : false;
      final response = await _apiService.getMyDeviceStatus(
        employeeId: _employeeId.isNotEmpty ? _employeeId : null,
        currentDeviceId: _currentDeviceId,
      );
      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        if (mounted) {
          setState(() {
            _isDeviceRegistered = _parseApiBool(data['registered']);
            _isDeviceApproved = _parseApiBool(data['approved']);
            _registeredOnOtherDevice =
                _parseApiBool(data['registeredOnOtherDevice']);
            _otherDeviceName = data['deviceName'] as String?;
            _allowOutsideCheckIn = _parseApiBool(data['allowOutsideCheckIn']) &&
                _isDeviceRegistered &&
                _isDeviceApproved;
            _allowTravelCheckIn = _parseApiBool(data['allowTravelCheckIn']) &&
                _isDeviceRegistered &&
                _isDeviceApproved;
            _storePhotoProofFlag = _localStorePhotoProof ||
                (data.containsKey('requirePhotoProofStore')
                    ? _parseApiBool(data['requirePhotoProofStore'])
                    : (_settings?.requirePhotoProof ?? false));
            if (data.containsKey('requirePhotoProofDevice')) {
              _devicePhotoProofFlag =
                  _parseApiBool(data['requirePhotoProofDevice']);
              _deviceRequirePhotoProof =
                  _parseApiBool(data['requirePhotoProof']) &&
                      _isDeviceRegistered &&
                      _isDeviceApproved;
            } else {
              _devicePhotoProofFlag =
                  _parseApiBool(data['requirePhotoProof']);
              _deviceRequirePhotoProof =
                  _devicePhotoProofFlag &&
                      _storePhotoProofFlag &&
                      _isDeviceRegistered &&
                      _isDeviceApproved;
            }
            _localDevicePhotoProof = localPhoto;
            if (localPhoto) _devicePhotoProofFlag = true;
            if (_devicePhotoProofFlag && _currentDeviceId != null) {
              DeviceSitePhotoPrefs.setDeviceEnabledForRecord(
                _currentDeviceId!,
                true,
              );
            }
          });
          if (_allowOutsideCheckIn && _isDeviceApproved) {
            GlobalLocationReporter.instance.startIfEligible(
        employeeId: _employeeId.isNotEmpty ? _employeeId : null,
      );
          }
        }

        final faceImages = data['faceImages'];
        if (faceImages != null &&
            faceImages is List &&
            faceImages.isNotEmpty &&
            _employeeId.isNotEmpty) {
          final imageUrls = List<String>.from(faceImages);
          final paths = await storageService.downloadAndCacheFaces(
              _employeeId, imageUrls);
          if (mounted && paths.isNotEmpty) {
            setState(() => _cachedFacePaths = paths);
            debugPrint(
                'Face images refreshed from server: ${paths.length} files');
            FaceEmbeddingService.clearCache();
            await FaceEmbeddingService.initialize();
          }
        } else {
          await _loadCachedFacesFromDevice();
        }
      } else {
        if (mounted && localPhoto) {
          setState(() {
            _localDevicePhotoProof = true;
            _devicePhotoProofFlag = true;
          });
        }
        await _loadCachedFacesFromDevice();
      }
    } catch (e) {
      debugPrint('Error loading device status: $e');
      await _loadCachedFacesFromDevice();
    }
  }

  Future<void> _loadSettings() async {
    try {
      _localStorePhotoProof = await DeviceSitePhotoPrefs.getStoreEnabled();
      final response = await _apiService.getMyMobileSettings();
      if (response['isSuccess'] == true && response['data'] != null) {
        if (mounted) {
          setState(() {
            var s = MobileAttendanceSettings.fromJson(
                response['data'] as Map<String, dynamic>);
            if (_localStorePhotoProof || s.requirePhotoProof) {
              s = s.copyWith(requirePhotoProof: true);
              _storePhotoProofFlag = true;
              _localStorePhotoProof = true;
              DeviceSitePhotoPrefs.setStoreEnabled(true);
            }
            _settings = s;
          });
        }
      } else if (mounted && _localStorePhotoProof) {
        setState(() {
          _storePhotoProofFlag = true;
          _settings = (_settings ?? MobileAttendanceSettings())
              .copyWith(requirePhotoProof: true);
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  /// Đang ở công ty (GPS trong vùng hoặc WiFi công ty đã xác thực).
  bool get _isAtCompanyLocation =>
      _isLocationVerified || _isWifiVerified;

  bool get _sitePhotoFeatureEnabled {
    final storeOn = _localStorePhotoProof ||
        _settings?.requirePhotoProof == true ||
        _storePhotoProofFlag;
    if (storeOn) return true;
    return _localDevicePhotoProof ||
        _devicePhotoProofFlag ||
        _deviceRequirePhotoProof;
  }

  bool get _shouldCaptureSitePhoto => _serverWouldRequireSitePhoto;

  Future<void> _explainSkippedSitePhoto() async {
    if (!mounted) return;
    final storePref = await DeviceSitePhotoPrefs.getStoreEnabled();
    final storeOn = storePref ||
        _localStorePhotoProof ||
        _settings?.requirePhotoProof == true ||
        _storePhotoProofFlag;
    final devicePref =
        await DeviceSitePhotoPrefs.isDeviceEnabledOnPhone(_currentDeviceId);
    final deviceOn = devicePref ||
        _localDevicePhotoProof ||
        _devicePhotoProofFlag ||
        _deviceRequirePhotoProof;
    if (!storeOn && !deviceOn) return;
    if (!storeOn) {
      _showWarning(
        'Chưa chụp ảnh hiện trường',
        'Vào Cài đặt mobile → Cài đặt chung → bật «Ảnh hiện trường (cửa hàng)» rồi Lưu. '
            'Sau đó tab Thiết bị → bật cho máy này.',
      );
      return;
    }
    if (!deviceOn) {
      _showWarning(
        'Chưa chụp ảnh hiện trường',
        'Vào Cài đặt mobile → Thiết bị → bật «Chụp ảnh hiện trường sau chấm» cho máy đang dùng.',
      );
    }
  }

  String? _extractPunchRecordId(Map<String, dynamic> response) {
    dynamic data = response['data'] ?? response['Data'];
    if (data is Map && (data['data'] != null || data['Data'] != null)) {
      data = data['data'] ?? data['Data'];
    }
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);
    final id = map['id'] ?? map['Id'] ?? map['recordId'] ?? map['RecordId'];
    final s = id?.toString().trim();
    if (s == null || s.isEmpty) return null;
    final normalized = ApiService.normalizeMobileRecordIdForUpload(s);
    return normalized ?? s;
  }

  /// GPS/WiFi cuối cùng trước quyết định ảnh hiện trường (tránh cờ cũ / GPS nhanh sai).
  Future<void> _finalizeLocationBeforeSitePhotoCheck() async {
    try {
      final isIOS =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      final position = await getCurrentPosition(
        enableHighAccuracy: true,
        timeout: isIOS ? 12000 : 6000,
      );
      if (!mounted) return;
      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
      });
      _calculateNearestLocation();
    } catch (e) {
      debugPrint('finalizeLocationBeforeSitePhoto: $e');
    }
    await _checkWifiConnection(forceRefresh: true);
  }

  /// Khớp server: (RequirePhotoProof cửa hàng HOẶC thiết bị) && ngoài công ty.
  bool get _serverWouldRequireSitePhoto =>
      _sitePhotoFeatureEnabled && !_isAtCompanyLocation;

  bool _isMissingSitePhotoError(String message) {
    final m = message.toLowerCase();
    return m.contains('ảnh hiện trường') ||
        m.contains('anh hien truong') ||
        m.contains('site photo');
  }

  Future<bool> _needSitePhotoForPunch() async {
    await _finalizeLocationBeforeSitePhotoCheck();
    if (!mounted) return false;
    if (_isAtCompanyLocation) return false;
    if (_sitePhotoFeatureEnabled) return true;
    return DeviceSitePhotoPrefs.shouldCaptureAfterPunch(
      serverStoreFlag: _settings?.requirePhotoProof == true ||
          _storePhotoProofFlag ||
          _localStorePhotoProof,
      serverDeviceFlag: _devicePhotoProofFlag ||
          _localDevicePhotoProof ||
          _deviceRequirePhotoProof,
      hardwareDeviceId: _currentDeviceId,
    );
  }

  /// Chụp ảnh hiện trường bắt buộc sau xác thực — không cho bỏ qua.
  Future<String?> _captureMandatorySitePhoto() async {
    // Face camera vừa đóng — chờ giải phóng camera trước khi mở camera sau.
    if (!kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return null;
    final locationLabel = _wifiLocationName ?? _nearestLocationName;
    while (mounted) {
      final photoBase64 = await Navigator.of(context, rootNavigator: true)
          .push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SitePhotoCaptureScreen(
            latitude: _currentLatitude,
            longitude: _currentLongitude,
            locationLabel: locationLabel,
            mandatory: true,
          ),
        ),
      );
      if (!mounted) return null;
      if (photoBase64 != null && photoBase64.trim().length > 100) {
        return photoBase64.trim();
      }
      _showWarning(
        'Bắt buộc chụp ảnh hiện trường',
        'Vui lòng chụp ảnh công trình để hoàn tất chấm công.',
      );
    }
    return null;
  }

  void _pauseLocationMonitor() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  void _resumeLocationMonitor() {
    if (_monitorTimer != null) return;
    _startMonitoring();
  }

  /// Đã lấy được tọa độ GPS (dịch vụ vị trí bật), không yêu cầu trong vùng công ty.
  bool get _hasGpsPosition =>
      _currentLatitude != null &&
      _currentLongitude != null &&
      (_currentLatitude!.abs() > 1e-5 || _currentLongitude!.abs() > 1e-5);

  bool _outsideLikeFor(int punchType) =>
      isTravelPunchType(punchType) ? _allowTravelCheckIn : _allowOutsideCheckIn;

  bool get _effectiveOutsideLike {
    if (_punchContextType != null) {
      return _outsideLikeFor(_punchContextType!);
    }
    return _allowOutsideCheckIn;
  }

  bool _gpsMetForPunch(int punchType) {
    final s = _settings;
    if (s == null || !s.enableGps) return true;
    if (_outsideLikeFor(punchType)) return _hasGpsPosition;
    return _isLocationVerified;
  }

  bool _nonFaceMetForPunch(int punchType) {
    final settings = _settings;
    if (settings == null) return _gpsMetForPunch(punchType);
    int enabledNonFace = 0;
    int passedNonFace = 0;
    if (settings.enableGps) {
      enabledNonFace++;
      if (_gpsMetForPunch(punchType)) passedNonFace++;
    }
    if (settings.enableWifi && !_outsideLikeFor(punchType)) {
      enabledNonFace++;
      if (_isWifiVerified) passedNonFace++;
    }
    if (enabledNonFace == 0) return true;
    return settings.verificationMode == 'any'
        ? passedNonFace >= 1
        : passedNonFace >= enabledNonFace;
  }

  /// GPS đạt: trong vùng (thường) hoặc chỉ cần có tọa độ (chấm ngoài / đi đường).
  bool get _gpsRequirementMet {
    final s = _settings;
    if (s == null || !s.enableGps) return true;
    if (_effectiveOutsideLike) return _hasGpsPosition;
    return _isLocationVerified;
  }

  /// GPS + WiFi only (face handled separately at punch time).
  bool get _nonFaceConditionsMet {
    final settings = _settings;
    if (settings == null) return false;
    int enabledNonFace = 0;
    int passedNonFace = 0;
    if (settings.enableGps) {
      enabledNonFace++;
      if (_gpsRequirementMet) passedNonFace++;
    }
    if (settings.enableWifi && !_effectiveOutsideLike) {
      enabledNonFace++;
      if (_isWifiVerified) passedNonFace++;
    }
    if (enabledNonFace == 0) return true;
    return settings.verificationMode == 'any'
        ? passedNonFace >= 1
        : passedNonFace >= enabledNonFace;
  }

  /// Same rules as [_conditionsMet]; used after face scan with optional face flag.
  bool _evaluateVerificationConditions({required bool includeFace}) {
    if (_registeredOnOtherDevice) return false;
    if (!_isDeviceRegistered || !_isDeviceApproved) return false;

    final settings = _settings;
    if (settings == null) return false;

    final mode = settings.verificationMode;
    int enabledCount = 0;
    int passedCount = 0;

    if (settings.enableFaceId && includeFace) {
      enabledCount++;
      if (_isFaceVerified) passedCount++;
    }
    if (settings.enableGps) {
      enabledCount++;
      if (_gpsRequirementMet) passedCount++;
    }
    if (settings.enableWifi && !_effectiveOutsideLike) {
      enabledCount++;
      if (_isWifiVerified) passedCount++;
    }

    if (enabledCount == 0) return true;
    if (mode == 'any') return passedCount >= 1;
    return passedCount >= enabledCount;
  }

  void _startMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final gpsRequired = _settings?.enableGps ?? true;
      final needGps = gpsRequired &&
          (_allowOutsideCheckIn ? !_hasGpsPosition : !_isLocationVerified);
      final needWifi =
          !_allowOutsideCheckIn && (_settings?.enableWifi ?? false) && !_isWifiVerified;
      if (!needGps && !needWifi) {
        // Both verified - no need to poll
        _monitorFailCount = 0;
        return;
      }
      // Exponential backoff: skip more cycles as failures accumulate (max gap ~60s)
      _monitorFailCount++;
      final skipCycles = (_monitorFailCount ~/ 3).clamp(0, 4);
      if (_monitorFailCount % (skipCycles + 1) != 0) return;

      if (needGps) _getCurrentLocation();
      if (needWifi) _checkWifiConnection();
    });
  }

  /// Check if all required conditions are met for attendance
  bool get _conditionsMet {
    if (_registeredOnOtherDevice) return false;
    // Must have registered & approved device on THIS phone
    if (!_isDeviceRegistered || !_isDeviceApproved) return false;

    final settings = _settings;
    if (settings == null) return false;

    // Count enabled & passed methods
    final mode = settings.verificationMode; // "any" or "all"
    int enabledCount = 0;
    int passedCount = 0;

    if (settings.enableFaceId) {
      enabledCount++;
      if (_isFaceVerified) passedCount++;
    }
    if (settings.enableGps) {
      enabledCount++;
      if (_gpsRequirementMet) passedCount++;
    }
    if (settings.enableWifi && !_effectiveOutsideLike) {
      enabledCount++;
      if (_isWifiVerified) passedCount++;
    }

    if (enabledCount == 0) return true; // No method enabled = allow

    if (mode == 'any') {
      return passedCount >= 1; // At least 1 method passed
    } else {
      // "all" mode
      return passedCount >= enabledCount; // All must pass
    }
  }

  /// Whether the punch button should be tappable.
  /// Face is interactive (opens camera on tap), so we allow tapping
  /// when all non-face conditions are met, or in "any" mode with at least 1 pass.
  /// Returns a human-readable explanation of which conditions are still unmet.
  String _buildConditionDetail({bool includeFaceInMessage = true}) {
    final s = _settings;
    if (s == null) return '';
    final reasons = <String>[];
    if (s.enableGps && !_gpsRequirementMet) {
      if (_isGettingLocation) {
        reasons.add('GPS đang định vị');
      } else if (_allowOutsideCheckIn) {
        reasons.add('Vui lòng bật GPS / quyền vị trí');
      } else if (_distanceFromOffice != null) {
        reasons.add('GPS ngoài phạm vi (${formatMobileAttendanceDistance(_distanceFromOffice)})');
      } else {
        reasons.add('GPS chưa xác định vị trí');
      }
    }
    if (!_allowOutsideCheckIn && s.enableWifi && !_isWifiVerified) {
      if (_isCheckingWifi) {
        reasons.add('WiFi đang kiểm tra');
      } else if (_connectedWifiSsid != null) {
        reasons.add('WiFi "${_connectedWifiSsid!}" không khớp');
      } else {
        reasons.add('WiFi chưa kết nối đúng mạng');
      }
    }
    if (includeFaceInMessage && s.enableFaceId && !_isFaceVerified) {
      reasons.add('Khuôn mặt chưa xác thực');
    }
    return reasons.isEmpty ? '' : reasons.join(' • ');
  }

  bool get _canTapPunch {
    if (_registeredOnOtherDevice) return false;
    if (!_isDeviceRegistered || !_isDeviceApproved) return false;
    if (_settings == null) return false;

    final settings = _settings!;
    if (!settings.enableFaceId) return _nonFaceConditionsMet;

    // Luôn bấm để quét mặt mới — không dùng _isFaceVerified cũ trên màn hình.
    if (settings.verificationMode == 'any') {
      return true;
    }
    return _nonFaceConditionsMet;
  }

  /// Có bật Face ID và cần quét mặt khi bấm chấm công (mỗi lần một lượt).
  bool get _needsFaceScanOnPunch {
    final s = _settings;
    return s?.enableFaceId ?? false;
  }

  /// Chip khuôn mặt: xanh chỉ trong lúc đang gửi sau khi vừa quét (không giữ xanh lâu).
  bool get _faceChipShowsVerified =>
      _isFaceVerified && _isAutoSubmitting;

  /// Vàng = sẵn sàng bấm để quét (GPS/WiFi đã đạt nếu chế độ "all").
  bool get _faceChipPendingScan {
    if (!_needsFaceScanOnPunch) return false;
    if (_faceChipShowsVerified) return false;
    if (_allowOutsideCheckIn) return _gpsRequirementMet;
    final s = _settings!;
    if (s.verificationMode == 'any') return true;
    return _nonFaceConditionsMet;
  }

  bool _canTapTravelPunch(int punchType) {
    if (!_allowTravelCheckIn || !isTravelPunchType(punchType)) return false;
    if (_registeredOnOtherDevice) return false;
    if (!_isDeviceRegistered || !_isDeviceApproved) return false;
    final settings = _settings;
    if (settings == null) return _gpsMetForPunch(punchType);
    if (!settings.enableFaceId) return _nonFaceMetForPunch(punchType);
    if (settings.verificationMode == 'any') return true;
    return _nonFaceMetForPunch(punchType);
  }

  /// Chỉ bật một nút: Bắt đầu đi HOẶC Đến điểm làm (theo cặp trong ngày).
  bool _canTapTravelPunchInSequence(int punchType) {
    if (!_canTapTravelPunch(punchType)) return false;
    final openStart = openTravelStartTime(_todayRecords);
    if (punchType == mobilePunchTravelStart) {
      return openStart == null;
    }
    if (punchType == mobilePunchTravelArrive) {
      return openStart != null;
    }
    return false;
  }

  DateTime? get _openTravelStartAt => openTravelStartTime(_todayRecords);

  String _punchSuccessTitle(int punchType) {
    switch (punchType) {
      case mobilePunchTravelStart:
        return 'Bắt đầu đi thành công!';
      case mobilePunchTravelArrive:
        return 'Đến điểm làm thành công!';
      case mobilePunchCheckIn:
        return 'Chấm công VÀO thành công!';
      default:
        return 'Chấm công RA thành công!';
    }
  }

  /// Auto-determine next punch type from today's records
  int _getNextPunchType() {
    if (_todayRecords.isEmpty) return 0; // check-in
    final sorted = List.of(_todayRecords)
      ..sort((a, b) => b.punchTime.compareTo(a.punchTime));
    return sorted.first.punchType == 0 ? 1 : 0; // toggle
  }

  Future<void> _autoSubmitAttendance({int? punchType}) async {
    if (_isAutoSubmitting) return;
    setState(() => _isAutoSubmitting = true);
    _punchContextType = punchType ?? _getNextPunchType();

    try {
      await _autoSubmitAttendanceImpl();
    } finally {
      _punchContextType = null;
      if (mounted) setState(() => _isAutoSubmitting = false);
    }
  }

  Future<void> _autoSubmitAttendanceImpl() async {
    // iOS: timer GPS/WiFi chạy nền trong lúc quét mặt (30–60s) có thể reset cờ → báo lỗi sau khi mặt OK.
    _pauseLocationMonitor();
    try {
      await _autoSubmitAttendanceImplBody();
    } finally {
      _resumeLocationMonitor();
    }
  }

  Future<void> _autoSubmitAttendanceImplBody() async {
    // Pre-check device status
    if (_registeredOnOtherDevice) {
      _showError(_otherDeviceName != null && _otherDeviceName!.isNotEmpty
          ? 'Tài khoản đã đăng ký trên thiết bị "$_otherDeviceName". Vui lòng đổi thiết bị hoặc chấm công trên máy đã đăng ký.'
          : 'Tài khoản đã đăng ký trên thiết bị khác. Vui lòng đổi thiết bị trước khi chấm công.');
      return;
    }
    if (!_isDeviceRegistered) {
      _showError(
          'Thiết bị chưa được đăng ký. Vui lòng đăng ký thiết bị trước.');
      return;
    }
    if (!_isDeviceApproved) {
      _showError(
          'Thiết bị chưa được duyệt hoặc đã bị thu hồi. Vui lòng liên hệ quản lý.');
      return;
    }
    if (_currentDeviceId == null || _currentDeviceId!.isEmpty) {
      _showError('Không xác định được mã thiết bị. Vui lòng khởi động lại ứng dụng.');
      return;
    }

    await _loadDeviceStatus();
    if (!mounted) return;

    // ---------------------------------------------------------------------
    // LIVE RE-VALIDATION at tap time.
    // Bug: employee opened the screen at the office (wifi/gps passed), went
    // home, then tapped submit. The cached `_isLocationVerified` / `_isWifiVerified`
    // flags were still true so the punch was accepted with home coordinates.
    // Fix: refresh GPS and WiFi BSSID right before we proceed (and before
    // opening the face camera, so the user does not waste a face scan).
    // ---------------------------------------------------------------------
    try {
      await _refreshVerificationBeforePunch();
    } catch (_) {
      // individual helpers already log; continue to condition check below
    }
    if (!mounted) return;

    final settings = _settings;
    if (settings == null && !_effectiveOutsideLike) {
      _showError(
          'Chưa tải được cấu hình xác thực. Vui lòng thoát màn hình và mở lại.');
      return;
    }

    if (!_nonFaceConditionsMet && !_effectiveOutsideLike) {
      final detail = _buildConditionDetail(includeFaceInMessage: false);
      if (mounted) setState(() {});
      _showError(detail.isNotEmpty
          ? 'Chưa đạt đủ điều kiện xác thực: $detail'
          : 'Chưa đạt đủ điều kiện xác thực. Vui lòng kiểm tra lại khi bạn ở khu vực cho phép.');
      return;
    }

    // Luôn mở camera khi bật Face ID (kể cả chấm ngoài công ty — server vẫn cần ảnh mặt).
    if (settings != null && settings.enableFaceId) {
      setState(() {
        _isFaceVerified = false;
        _faceMatchScore = null;
        _faceImageBase64 = null;
        _livenessPassed = false;
        _clientFaceEngine = null;
      });
      // Block if employee has no face registration
      if (_cachedFacePaths.isEmpty) {
        await _loadCachedFacesFromDevice();
        if (_cachedFacePaths.isEmpty) {
          await _loadDeviceStatus();
        }
      }
      if (!mounted) return;
      if (_cachedFacePaths.isEmpty) {
        _showError(
            'Chưa có ảnh đăng ký Face ID trên máy. Vui lòng đồng bộ lại hoặc liên hệ quản lý.');
        return;
      }

      final result = await FaceVerificationCamera.show(
        context,
        registeredFacePaths: _cachedFacePaths,
        minMatchScore: settings.minFaceMatchScore,
      );
      if (result == null) return; // User cancelled

      // Backend expects faceImageUrl for audit and face verification checks.
      if ((result.faceImageBase64 ?? '').trim().isEmpty) {
        setState(() {
          _isFaceVerified = false;
          _faceMatchScore = null;
          _faceImageBase64 = null;
          _clientFaceEngine = null;
        });
        _showError(
            'Không chụp được ảnh khuôn mặt để gửi xác thực. Vui lòng thử lại.');
        return;
      }

      final serverFaceVerificationPending = result.matchScore <= 0;

      setState(() {
        _isFaceVerified = true;
        _faceMatchScore =
            serverFaceVerificationPending ? -1 : result.matchScore;
        _faceImageBase64 = result.faceImageBase64;
        _livenessPassed = result.livenessPassed;
        _clientFaceEngine = result.clientFaceEngine;
      });

      if (serverFaceVerificationPending) {
        _showWarning('Đang dùng xác thực server',
            'Thiết bị sẽ gửi ảnh lên server để xác thực khuôn mặt.');
      }

      // Sau quét mặt: làm mới GPS/WiFi (tránh cờ cũ bị timer hoặc iOS đổi trạng thái).
      try {
        await _refreshVerificationBeforePunch();
      } catch (_) {}
      if (!mounted) return;

      if (!_evaluateVerificationConditions(includeFace: true)) {
        final detail =
            _buildConditionDetail(includeFaceInMessage: false);
        if (mounted) setState(() {});
        _showError(detail.isNotEmpty
            ? 'Khuôn mặt đã xác thực, nhưng chưa đủ điều kiện khác: $detail'
            : 'Khuôn mặt đã xác thực. Vui lòng kiểm tra GPS/WiFi hoặc đứng trong vùng cho phép.');
        return;
      }
    }

    if (settings != null &&
        settings.enableFaceId &&
        (_faceImageBase64 == null || _faceImageBase64!.trim().isEmpty)) {
      _showError(
          'Chưa quét khuôn mặt. Vui lòng bấm lại và hoàn tất bước quét mặt.');
      return;
    }

    if ((_settings?.enableGps ?? true) && !_hasGpsPosition) {
      _showError(
          'Vui lòng bật GPS và cho phép quyền vị trí trước khi chấm công.');
      return;
    }

    await Future.wait([_loadSettings(), _loadDeviceStatus()]);
    if (!mounted) return;

    final needSitePhoto = await _needSitePhotoForPunch();
    if (!mounted) return;
    String? sitePhotoBase64;
    if (needSitePhoto) {
      sitePhotoBase64 = await _captureMandatorySitePhoto();
      if (!mounted) return;
      if (sitePhotoBase64 == null) return;
    }

    try {
      final punchType = _punchContextType ?? _getNextPunchType();
      final onDeviceFaceOk =
          _faceMatchScore != null && (_faceMatchScore ?? 0) > 0;
      final response = await _apiService.submitMobileAttendance(
        employeeId: _employeeId,
        employeeName: _employeeName,
        punchType: punchType,
        latitude: _currentLatitude!,
        longitude: _currentLongitude!,
        faceImage: _faceImageBase64 ?? '',
        distanceFromLocation: _distanceFromOffice,
        faceMatchScore: _faceMatchScore,
        deviceId: _currentDeviceId,
        wifiSsid: _connectedWifiSsid,
        wifiBssid: _detectedBssid,
        livenessPassed: _livenessPassed,
        clientFaceEngine: onDeviceFaceOk ? (_clientFaceEngine ?? 'tflite') : null,
        sitePhotoBase64: sitePhotoBase64,
      );

      if (!mounted) return;

      if (response['isSuccess'] == true) {
        final data = response['data'];
        final status = data is Map ? (data['status']?.toString() ?? '') : '';
        final syncedRaw = data is Map && data['syncedToAttendanceLog'] == true;
        String subtitle;
        if (isTravelPunchType(punchType)) {
          subtitle = status == 'pending'
              ? 'Đã lưu. Chờ duyệt để tính giờ đi đường vào lương.'
              : 'Đã ghi nhận giờ đi đường.';
        } else if (status == 'pending') {
          subtitle =
              'Đã lưu trên app. Vào Duyệt chấm công → Mobile để duyệt; sau đó mới có trên Chấm công thô.';
        } else if (syncedRaw) {
          subtitle = _isWifiVerified
              ? 'Đã ghi dữ liệu thô (WiFi: ${_connectedWifiSsid ?? ''})'
              : _isLocationVerified
                  ? 'Đã ghi dữ liệu thô (GPS ${formatMobileAttendanceDistance(_distanceFromOffice)})'
                  : 'Đã ghi dữ liệu thô — xem thiết bị «Chấm công Mobile»';
        } else {
          subtitle = 'Đã lưu mobile; kiểm tra Chấm công thô hoặc liên hệ quản trị.';
        }
        if (!needSitePhoto && !isTravelPunchType(punchType)) {
          await _explainSkippedSitePhoto();
        }

        _showSuccess(
          _punchSuccessTitle(punchType),
          subtitle,
        );

        _loadTodayRecords();
        ScreenRefreshNotifier.refreshDashboardScreen();
        ScreenRefreshNotifier.refreshAttendanceSummaryScreen();
        ScreenRefreshNotifier.refreshAttendanceScreen();
        // Reset face verification for next punch
        setState(() {
          _isFaceVerified = false;
          _faceMatchScore = null;
          _faceImageBase64 = null;
          _clientFaceEngine = null;
        });
      } else {
        final message =
            (response['message'] ?? 'Không thể chấm công').toString();

        // Server yêu cầu ảnh hiện trường nhưng client chưa mở camera — chụp và thử lại.
        if (_isMissingSitePhotoError(message)) {
          final retryPhoto = await _captureMandatorySitePhoto();
          if (!mounted) return;
          if (retryPhoto != null && retryPhoto.trim().length > 100) {
            final retryResponse = await _apiService.submitMobileAttendance(
              employeeId: _employeeId,
              employeeName: _employeeName,
              punchType: punchType,
              latitude: _currentLatitude!,
              longitude: _currentLongitude!,
              faceImage: _faceImageBase64 ?? '',
              distanceFromLocation: _distanceFromOffice,
              faceMatchScore: _faceMatchScore,
              deviceId: _currentDeviceId,
              wifiSsid: _connectedWifiSsid,
              wifiBssid: _detectedBssid,
              livenessPassed: _livenessPassed,
              clientFaceEngine:
                  onDeviceFaceOk ? (_clientFaceEngine ?? 'tflite') : null,
              sitePhotoBase64: retryPhoto,
            );
            if (!mounted) return;
            if (retryResponse['isSuccess'] == true) {
              final data = retryResponse['data'];
              final status =
                  data is Map ? (data['status']?.toString() ?? '') : '';
              final syncedRaw =
                  data is Map && data['syncedToAttendanceLog'] == true;
              String subtitle;
              if (isTravelPunchType(punchType)) {
                subtitle = status == 'pending'
                    ? 'Đã lưu. Chờ duyệt để tính giờ đi đường vào lương.'
                    : 'Đã ghi nhận giờ đi đường.';
              } else if (status == 'pending') {
                subtitle =
                    'Đã lưu trên app. Vào Duyệt chấm công → Mobile để duyệt; sau đó mới có trên Chấm công thô.';
              } else if (syncedRaw) {
                subtitle = _isWifiVerified
                    ? 'Đã ghi dữ liệu thô (WiFi: ${_connectedWifiSsid ?? ''})'
                    : _isLocationVerified
                        ? 'Đã ghi dữ liệu thô (GPS ${formatMobileAttendanceDistance(_distanceFromOffice)})'
                        : 'Đã ghi dữ liệu thô — xem thiết bị «Chấm công Mobile»';
              } else {
                subtitle =
                    'Đã lưu mobile; kiểm tra Chấm công thô hoặc liên hệ quản trị.';
              }
              _showSuccess(
                _punchSuccessTitle(punchType),
                subtitle,
              );
              _loadTodayRecords();
              ScreenRefreshNotifier.refreshDashboardScreen();
              ScreenRefreshNotifier.refreshAttendanceSummaryScreen();
              ScreenRefreshNotifier.refreshAttendanceScreen();
              setState(() {
                _isFaceVerified = false;
                _faceMatchScore = null;
                _faceImageBase64 = null;
                _clientFaceEngine = null;
              });
              return;
            }
            final retryMsg =
                (retryResponse['message'] ?? message).toString();
            setState(() {
              _isFaceVerified = false;
              _faceMatchScore = null;
              _faceImageBase64 = null;
              _clientFaceEngine = null;
            });
            _showError(retryMsg);
            return;
          }
        }

        // Any failed submit must clear face state so retry always re-opens camera.
        setState(() {
          _isFaceVerified = false;
          _faceMatchScore = null;
          _faceImageBase64 = null;
          _clientFaceEngine = null;
        });

        _showError(message);
      }
    } catch (e) {
      _showError(AppErrorUtils.userMessage(e));
    }
  }

  Future<void> _loadWorkLocations() async {
    try {
      final response = await _apiService.getPunchWorkLocations(
        employeeId: _employeeId.isNotEmpty ? _employeeId : null,
      );
      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        final list = data is Map ? data['locations'] : data;
        if (list is List) {
          setState(() {
            _workLocations = list
                .map((e) => WorkLocation.fromJson(e as Map<String, dynamic>))
                .toList();
          });
          // Recalculate distance if we already have GPS
          if (_currentLatitude != null && _currentLongitude != null) {
            _calculateNearestLocation();
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading work locations: $e');
    }
  }

  /// Chờ lần định vị đang chạy (timer nền) xong — tránh bỏ qua kiểm tra lúc bấm chấm công.
  Future<void> _waitForLocationCheckToFinish() async {
    final deadline = DateTime.now().add(const Duration(seconds: 18));
    while (_isGettingLocation && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
    }
  }

  Future<void> _waitForWifiCheckToFinish() async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (_isCheckingWifi && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
    }
  }

  /// Làm mới GPS/WiFi ngay trước khi chấm — không dùng cờ cache khi timer đang chạy.
  Future<void> _refreshVerificationBeforePunch() async {
    await Future.wait<void>([
      _getCurrentLocation(forceRefresh: true),
      _checkWifiConnection(requestPermissions: false, forceRefresh: true),
    ]);
  }

  Future<void> _getCurrentLocation({bool forceRefresh = false}) async {
    if (_isGettingLocation) {
      if (!forceRefresh) return;
      await _waitForLocationCheckToFinish();
      if (_isGettingLocation) return;
    }
    setState(() => _isGettingLocation = true);
    try {
      // Try last known position first (instant, <50ms)
      if (_currentLatitude == null) {
        final cached = await getLastKnownPosition();
        if (cached != null && mounted) {
          setState(() {
            _currentLatitude = cached.latitude;
            _currentLongitude = cached.longitude;
          });
          _calculateNearestLocation();
          if (_isLocationVerified) {
            setState(() => _isGettingLocation = false);
            _refineLocationInBackground();
            return;
          }
        }
      }

      // iOS cold-start GPS thường mất 10-30s; Android nhanh hơn nhiều.
      // Dùng timeout riêng cho từng platform để tránh fallback sớm về vị trí cũ.
      final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      final fastTimeout = isIOS ? 5000 : 2000;
      final highAccTimeout = isIOS ? 12000 : 6000;

      // Fast low accuracy
      final fastPosition = await getCurrentPosition(
        enableHighAccuracy: false,
        timeout: fastTimeout,
      );
      if (!mounted) return;
      setState(() {
        _currentLatitude = fastPosition.latitude;
        _currentLongitude = fastPosition.longitude;
      });
      _calculateNearestLocation();

      // If already in range, stop early
      if (_isLocationVerified) {
        setState(() => _isGettingLocation = false);
        _monitorFailCount = 0; // reset backoff
        _refineLocationInBackground();
        return;
      }

      // Not in range → high accuracy
      final position = await getCurrentPosition(
        enableHighAccuracy: true,
        timeout: highAccTimeout,
      );
      if (!mounted) return;
      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
        _isGettingLocation = false;
      });
      _calculateNearestLocation();
      if (_isLocationVerified) _monitorFailCount = 0;
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        setState(() => _isGettingLocation = false);
      }
    }
  }

  /// Quietly update location with high accuracy in background
  Future<void> _refineLocationInBackground() async {
    try {
      final position = await getCurrentPosition(
        enableHighAccuracy: true,
        timeout: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
            ? 15000
            : 8000,
      );
      if (!mounted) return;
      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
      });
      _calculateNearestLocation();
    } catch (_) {}
  }

  void _calculateNearestLocation() {
    if (_currentLatitude == null ||
        _currentLongitude == null ||
        _workLocations.isEmpty) {
      return;
    }

    double? nearestDist;
    String? nearestName;
    int nearestRadius = 100;

    final defaultRadius = _settings?.gpsRadiusMeters ?? 100;
    for (final loc in _workLocations) {
      if (!loc.isActive) continue;
      final d = _haversineDistance(
          _currentLatitude!, _currentLongitude!, loc.latitude, loc.longitude);
      if (nearestDist == null || d < nearestDist) {
        nearestDist = d;
        nearestName = loc.name;
        nearestRadius = loc.radius > 0 ? loc.radius : defaultRadius;
      }
    }

    setState(() {
      _distanceFromOffice = nearestDist;
      _nearestLocationName = nearestName;
      _isLocationVerified = nearestDist != null && nearestDist <= nearestRadius;
    });
  }

  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  Future<void> _loadTodayRecords() async {
    try {
      final now = DateTime.now();
      debugPrint(
          '📋 _loadTodayRecords: employeeId=$_employeeId, from=${DateTime(now.year, now.month, now.day)}, to=${DateTime(now.year, now.month, now.day, 23, 59, 59)}');
      final response = await _apiService.getMobileAttendanceHistory(
        employeeId: _employeeId.isNotEmpty ? _employeeId : null,
        fromDate: DateTime(now.year, now.month, now.day),
        toDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );

      if (!mounted) return;
      debugPrint(
          '📋 _loadTodayRecords response: isSuccess=${response['isSuccess']}, data type=${response['data']?.runtimeType}, data=${response['data']}');
      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        debugPrint(
            '📋 _loadTodayRecords: data is List=${data is List}, length=${data is List ? data.length : 'N/A'}');
        if (data is List) {
          setState(() {
            _todayRecords = data
                .map((e) =>
                    MobileAttendanceRecord.fromJson(e as Map<String, dynamic>))
                .toList();
          });
          debugPrint(
              '📋 _loadTodayRecords: parsed ${_todayRecords.length} records');
        }
      }
    } catch (e, st) {
      debugPrint('Error loading today records: $e\n$st');
    }
  }

  bool _wifiPermissionsRequested = false; // only request permissions once

  Future<void> _checkWifiConnection({
    bool requestPermissions = false,
    bool forceRefresh = false,
  }) async {
    if (_isCheckingWifi) {
      if (!forceRefresh) return;
      await _waitForWifiCheckToFinish();
      if (_isCheckingWifi) return;
    }

    // Only show loading indicator on manual/first check, not periodic
    if (requestPermissions || !_wifiPermissionsRequested) {
      setState(() {
        _isCheckingWifi = true;
      });
    } else {
      _isCheckingWifi = true; // set flag without triggering full UI rebuild
    }

    final debugLines = <String>[];
    try {
      // Try to detect BSSID (router MAC address) on supported platforms
      String? bssid;
      String? ssid;
      if (!kIsWeb) {
        try {
          // Check location permission status
          var locationStatus = await Permission.locationWhenInUse.status;
          debugLines.add('LocationWhenInUse: $locationStatus');

          // Only request permissions on first call or manual refresh
          if (!locationStatus.isGranted &&
              (requestPermissions || !_wifiPermissionsRequested)) {
            locationStatus = await Permission.locationWhenInUse.request();
            debugLines.add('Requested → $locationStatus');
          }

          // Mark that we've attempted permission requests
          _wifiPermissionsRequested = true;

          if (!locationStatus.isGranted) {
            debugPrint('Location permission denied - BSSID unavailable');
            _detectedBssid = null;
            debugLines.add('⚠ Quyền vị trí bị từ chối');
            final response = await _apiService.checkWifi(bssid: null).timeout(
                const Duration(seconds: 5),
                onTimeout: () => <String, dynamic>{
                      'isSuccess': false,
                      'message': 'Timeout'
                    });
            debugLines.add('API(bssid=null): ${response['isSuccess']}');
            if (!mounted) {
              _isCheckingWifi = false;
              return;
            }
            if (response['isSuccess'] == true && response['data'] != null) {
              final data = response['data'] as Map<String, dynamic>;
              debugLines.add(
                  'Verified: ${data['isWifiVerified']}, locs: ${data['locationsChecked']}');
              setState(() {
                _isWifiVerified = data['isWifiVerified'] == true;
                _wifiLocationName = data['locationName'] as String?;
                _connectedWifiSsid = data['wifiSsid'] as String?;
                if (!_isWifiVerified) {
                  _connectedWifiSsid = 'Chưa cấp quyền vị trí';
                }
                _isCheckingWifi = false;
              });
            } else {
              setState(() {
                _connectedWifiSsid = 'Chưa cấp quyền vị trí';
                _isCheckingWifi = false;
              });
            }
            return;
          }

          final networkInfo = NetworkInfo();
          // Fetch BSSID and SSID in parallel (saves ~3s)
          final wifiResults = await Future.wait([
            networkInfo
                .getWifiBSSID()
                .timeout(const Duration(seconds: 3), onTimeout: () => null),
            networkInfo
                .getWifiName()
                .timeout(const Duration(seconds: 3), onTimeout: () => null),
          ]);
          bssid = wifiResults[0];
          ssid = wifiResults[1];
          // Remove quotes from SSID if present
          if (ssid != null) {
            ssid = ssid.replaceAll('"', '');
          }
          debugLines.add('Raw BSSID: $bssid');
          debugLines.add('Raw SSID: $ssid');
          debugPrint('WiFi BSSID detected: $bssid, SSID: $ssid');
          if (bssid != null &&
              bssid.isNotEmpty &&
              bssid != '02:00:00:00:00:00') {
            _detectedBssid = bssid.toLowerCase().trim();
            debugLines.add('✓ BSSID OK: $_detectedBssid');
          } else {
            debugPrint('BSSID unavailable or placeholder: $bssid');
            _detectedBssid = null;
            if (bssid == '02:00:00:00:00:00') {
              debugLines.add('⚠ BSSID=02:00:... → GPS tắt?');
            } else {
              debugLines.add('⚠ BSSID null/empty → không có WiFi?');
            }
          }
        } catch (e) {
          debugPrint('BSSID detection error: $e');
          debugLines.add('⚠ Lỗi: $e');
        }
      }

      debugLines.add('Gọi API bssid=${_detectedBssid ?? "null"}');
      final response = await _apiService
          .checkWifi(bssid: _detectedBssid)
          .timeout(const Duration(seconds: 5),
              onTimeout: () =>
                  <String, dynamic>{'isSuccess': false, 'message': 'Timeout'});
      debugPrint('WiFi check response: $response');
      if (!mounted) {
        _isCheckingWifi = false;
        return;
      }
      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'] as Map<String, dynamic>;
        final isVerified = data['isWifiVerified'] == true;
        debugLines.add('Verified: $isVerified, type: ${data['verifyType']}');
        debugLines.add('Location: ${data['locationName'] ?? "-"}');
        debugLines.add('Locs checked: ${data['locationsChecked'] ?? "-"}');
        debugLines.add('UserStoreId: ${data['userStoreId'] ?? "-"}');
        if (data['receivedBssid'] != null) {
          debugLines.add('Server got: ${data['receivedBssid']}');
        }
        if (data['message'] != null && !isVerified) {
          debugLines.add('Msg: ${data['message']}');
        }
        setState(() {
          _isWifiVerified = isVerified;
          _wifiLocationName = data['locationName'] as String?;
          _connectedWifiSsid = ssid ?? (data['wifiSsid'] as String?);

          _isCheckingWifi = false;
        });
        if (isVerified) _monitorFailCount = 0;
      } else {
        debugLines.add('API error: ${response['message'] ?? "unknown"}');
        setState(() {
          _connectedWifiSsid = ssid;
          _isCheckingWifi = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking wifi: $e');
      debugLines.add('Exception: $e');
      if (mounted) {
        setState(() {
          _isCheckingWifi = false;
        });
      } else {
        _isCheckingWifi = false;
      }
    }
  }

  void _showSuccess(String title, String message) {
    NotificationOverlayManager().showSuccess(title: title, message: message);
  }

  String _normalizeViText(String input) {
    if (!(input.contains('Ã') || input.contains('Â') || input.contains('â'))) {
      return input;
    }
    try {
      const cp1252Extra = {
        '\u20ac': 0x80,
        '\u201a': 0x82,
        '\u0192': 0x83,
        '\u201e': 0x84,
        '\u2026': 0x85,
        '\u2020': 0x86,
        '\u2021': 0x87,
        '\u02c6': 0x88,
        '\u2030': 0x89,
        '\u0160': 0x8a,
        '\u2039': 0x8b,
        '\u0152': 0x8c,
        '\u017d': 0x8e,
        '\u2018': 0x91,
        '\u2019': 0x92,
        '\u201c': 0x93,
        '\u201d': 0x94,
        '\u2022': 0x95,
        '\u2013': 0x96,
        '\u2014': 0x97,
        '\u02dc': 0x98,
        '\u2122': 0x99,
        '\u0161': 0x9a,
        '\u203a': 0x9b,
        '\u0153': 0x9c,
        '\u017e': 0x9e,
        '\u0178': 0x9f,
      };
      final bytes = <int>[];
      for (final ch in input.runes) {
        final c = String.fromCharCode(ch);
        if (cp1252Extra.containsKey(c)) {
          bytes.add(cp1252Extra[c]!);
        } else if (ch <= 0xFF) {
          bytes.add(ch);
        } else {
          return input;
        }
      }
      return utf8.decode(bytes);
    } catch (_) {
      return input;
    }
  }

  void _showError(String message) {
    NotificationOverlayManager()
        .showError(title: 'Lỗi', message: _normalizeViText(message));
  }

  void _showWarning(String title, String message) {
    NotificationOverlayManager().showWarning(title: title, message: message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background gradient orbs
          Positioned(
              top: -80,
              right: -60,
              child: _bgOrb(200, const Color(0xFF3B82F6), 0.15)),
          Positioned(
              bottom: 100,
              left: -40,
              child: _bgOrb(160, const Color(0xFF8B5CF6), 0.1)),
          Positioned(
              top: 300,
              right: -30,
              child: _bgOrb(120, const Color(0xFF06B6D4), 0.08)),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 8),
                  _buildClockAndPunchButton(),
                  const SizedBox(height: 16),
                  _buildVerificationCards(),
                  const SizedBox(height: 16),
                  _buildTodayRecords(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bgOrb(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
            colors: [color.withValues(alpha: opacity), Colors.transparent]),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
            ),
            child: Center(
              child: Text(
                _employeeName.isNotEmpty ? _employeeName[0].toUpperCase() : 'U',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _employeeName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _department,
                  style:
                      const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _glassIconButton(
            Icons.history_rounded,
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const MobileAttendanceHistoryScreen())),
          ),
        ],
      ),
    );
  }

  Widget _glassIconButton(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, color: const Color(0xFF94A3B8), size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildClockAndPunchButton() {
    final isEnabled = _canTapPunch && !_isAutoSubmitting;
    final nextPunchType = _getNextPunchType();
    final isCheckIn = nextPunchType == 0;
    final needsFaceScan = _needsFaceScanOnPunch;
    final now = _clockNow;
    final weekdays = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];

    final List<Color> activeGradient = isCheckIn
        ? [const Color(0xFF3B82F6), const Color(0xFF2563EB)]
        : [const Color(0xFFEF4444), const Color(0xFFDC2626)];
    final List<Color> disabledGradient = [
      const Color(0xFF334155),
      const Color(0xFF1E293B)
    ];
    final ctaLabel = isEnabled
        ? (needsFaceScan ? 'QUÉT MẶT' : (isCheckIn ? 'CHẤM VÀO' : 'CHẤM RA'))
        : 'TẠM KHÓA';
    final ctaHint = isEnabled
        ? (needsFaceScan
            ? (isCheckIn
                ? 'Bước tiếp theo: Quét khuôn mặt để chấm vào'
                : 'Bước tiếp theo: Quét khuôn mặt để chấm ra')
            : (isCheckIn ? 'Sẵn sàng chấm công vào' : 'Sẵn sàng chấm công ra') +
                (_shouldCaptureSitePhoto
                    ? ' · Ngoài công ty: bắt buộc chụp ảnh công trình'
                    : (_sitePhotoFeatureEnabled && _isAtCompanyLocation
                        ? ' · Tại công ty: không cần ảnh công trình'
                        : '')))
        : (_registeredOnOtherDevice
            ? (_otherDeviceName != null && _otherDeviceName!.isNotEmpty
                ? 'Đã đăng ký trên $_otherDeviceName — cần đổi thiết bị'
                : 'Đã đăng ký trên thiết bị khác — cần đổi thiết bị')
            : (!_isDeviceRegistered
                ? 'Cần đăng ký thiết bị trước khi chấm công'
                : (!_isDeviceApproved
                    ? 'Thiết bị đang chờ duyệt từ quản lý'
                    : () {
                        final d = _buildConditionDetail();
                        return d.isNotEmpty
                            ? 'Chưa đạt: $d'
                            : 'Đang kiểm tra điều kiện...';
                      }())));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _glassCard(
        child: Column(
          children: [
            // Clock (cập nhật qua Timer — không dùng Stream trong build)
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF60A5FA), Color(0xFFA78BFA)],
              ).createShader(bounds),
              child: Text(
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w200,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: 4,
                  height: 1.1,
                ),
              ),
            ),
            Text(
              ':${now.second.toString().padLeft(2, '0')}',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                  color: Color(0xFF64748B),
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
            const SizedBox(height: 4),
            Text(
              '${weekdays[now.weekday % 7]}, ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF64748B), letterSpacing: 0.5),
            ),
            const SizedBox(height: 14),
            _buildNextActionBar(
                isEnabled: isEnabled,
                hint: ctaHint,
                needsFaceScan: needsFaceScan),
            const SizedBox(height: 28),
            // Punch button with outer ring
            GestureDetector(
              onTap: isEnabled ? _autoSubmitAttendance : null,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final scale = isEnabled ? _pulseAnimation.value : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 148,
                      height: 148,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isEnabled
                              ? activeGradient[0].withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.05),
                          width: 3,
                        ),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors:
                                isEnabled ? activeGradient : disabledGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: isEnabled
                              ? [
                                  BoxShadow(
                                      color: activeGradient[0]
                                          .withValues(alpha: 0.4),
                                      blurRadius: 28,
                                      spreadRadius: 0,
                                      offset: const Offset(0, 8)),
                                ]
                              : [],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isEnabled
                                  ? needsFaceScan
                                      ? Icons.face_rounded
                                      : (isCheckIn
                                          ? Icons.fingerprint_rounded
                                          : Icons.logout_rounded)
                                  : Icons.lock_outline_rounded,
                              color: Colors.white
                                  .withValues(alpha: isEnabled ? 1.0 : 0.4),
                              size: 42,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              ctaLabel,
                              style: TextStyle(
                                color: Colors.white
                                    .withValues(alpha: isEnabled ? 0.95 : 0.3),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_allowTravelCheckIn) _buildTravelPunchSection(),
            if (_allowTravelCheckIn) const SizedBox(height: 8),
            if (_isAutoSubmitting)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: activeGradient[0])),
                  const SizedBox(width: 8),
                  const Text('Đang xử lý...',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                ],
              )
            else
              Text(
                isEnabled
                    ? needsFaceScan
                        ? (isCheckIn
                            ? 'Nhấn để quét mặt và chấm vào'
                            : 'Nhấn để quét mặt và chấm ra')
                        : (isCheckIn
                            ? 'Nhấn để chấm công vào'
                            : 'Nhấn để chấm công ra')
                    : _registeredOnOtherDevice
                        ? 'Thiết bị khác đã đăng ký'
                        : !_isDeviceRegistered
                            ? 'Thiết bị chưa đăng ký'
                            : !_isDeviceApproved
                                ? 'Thiết bị chưa được duyệt'
                                : 'Đang kiểm tra...',
                style: TextStyle(
                    fontSize: 12,
                    color: isEnabled
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF475569)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextActionBar(
      {required bool isEnabled,
      required String hint,
      required bool needsFaceScan}) {
    final barColor = isEnabled
        ? (needsFaceScan ? const Color(0xFF0EA5E9) : const Color(0xFF22C55E))
        : const Color(0xFFF59E0B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: barColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            isEnabled
                ? (needsFaceScan
                    ? Icons.face_retouching_natural_rounded
                    : Icons.verified_rounded)
                : Icons.info_outline_rounded,
            size: 16,
            color: barColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: barColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard(
      {required Widget child, EdgeInsets? padding, EdgeInsets? margin}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: padding ??
              const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          margin: margin,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildVerificationCards() {
    final settings = _settings;
    final faceRequired = settings?.enableFaceId ?? true;
    final gpsRequired = settings?.enableGps ?? true;
    final wifiRequired = settings?.enableWifi ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Status bar
          _buildStatusBar(faceRequired, gpsRequired, wifiRequired),
          const SizedBox(height: 10),
          if (_allowOutsideCheckIn) ...[
            if (gpsRequired) _buildGpsCard(),
            const SizedBox(height: 8),
            _buildOutsideChip(),
          ] else
            Row(
              children: [
                if (gpsRequired) Expanded(child: _buildGpsCard()),
                if (gpsRequired && wifiRequired) const SizedBox(width: 10),
                if (wifiRequired) Expanded(child: _buildWifiCard()),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(
      bool faceRequired, bool gpsRequired, bool wifiRequired) {
    final mode = _settings?.verificationMode ?? 'all';
    final ready = _canTapPunch;
    final bool deviceReady = _isDeviceRegistered && _isDeviceApproved;
    final String modeText =
        mode == 'any' ? 'Cần 1 điều kiện bất kỳ' : 'Cần tất cả điều kiện';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: ready
                ? const Color(0xFF16A34A).withValues(alpha: 0.1)
                : const Color(0xFFF59E0B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: ready
                    ? const Color(0xFF16A34A).withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      ready ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                  boxShadow: [
                    BoxShadow(
                        color: (ready
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFF59E0B))
                            .withValues(alpha: 0.4),
                        blurRadius: 6)
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modeText,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildMiniChip('1. Thiết bị', deviceReady,
                            pending: !deviceReady),
                        if (faceRequired)
                          _buildMiniChip(
                            _faceChipPendingScan
                                ? '2. Khuôn mặt (bấm quét)'
                                : '2. Khuôn mặt',
                            _faceChipShowsVerified,
                            pending: _faceChipPendingScan,
                          ),
                        if (gpsRequired && !_allowOutsideCheckIn)
                          _buildMiniChip('3. GPS', _isLocationVerified,
                              pending:
                                  _isGettingLocation && !_isLocationVerified),
                        if (wifiRequired && !_allowOutsideCheckIn)
                          _buildMiniChip('4. WiFi', _isWifiVerified,
                              pending: _isCheckingWifi && !_isWifiVerified),
                        if (_allowOutsideCheckIn)
                          _buildMiniChip('Ngoài công ty', true),
                      ],
                    ),
                  ],
                ),
              ),
              if (mode == 'any' && !_allowOutsideCheckIn)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('ANY',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                          letterSpacing: 1)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChip(String label, bool ok, {bool pending = false}) {
    final chipColor = ok
        ? const Color(0xFF22C55E)
        : (pending ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chipColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: chipColor,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            pending ? '$label (đang chờ)' : label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: ok
                  ? const Color(0xFF4ADE80)
                  : (pending
                      ? const Color(0xFFFCD34D)
                      : const Color(0xFFFCA5A5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTravelPunchSection() {
    final openStart = _openTravelStartAt;
    final startEnabled = _canTapTravelPunchInSequence(mobilePunchTravelStart) &&
        !_isAutoSubmitting;
    final arriveEnabled = _canTapTravelPunchInSequence(mobilePunchTravelArrive) &&
        !_isAutoSubmitting;
    final todayTravelHours =
        computeTravelHoursFromMobileRecords(_todayRecords);

    return Column(
      children: [
        Text(
          'Chấm đi đường',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.55),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildTravelPunchButton(
                label: 'Bắt đầu đi',
                icon: Icons.directions_car_rounded,
                color: const Color(0xFF0EA5E9),
                enabled: startEnabled,
                onTap: () => _autoSubmitAttendance(
                  punchType: mobilePunchTravelStart,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTravelPunchButton(
                label: 'Đến điểm làm',
                icon: Icons.place_rounded,
                color: const Color(0xFF14B8A6),
                enabled: arriveEnabled,
                onTap: () => _autoSubmitAttendance(
                  punchType: mobilePunchTravelArrive,
                ),
              ),
            ),
          ],
        ),
        if (openStart != null) ...[
          const SizedBox(height: 8),
          Text(
            'Đang di chuyển từ ${openStart.hour.toString().padLeft(2, '0')}:${openStart.minute.toString().padLeft(2, '0')} — bấm Đến điểm làm khi tới công trình',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: const Color(0xFF0EA5E9).withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          todayTravelHours > 0
              ? 'Hôm nay: ${todayTravelHours.toStringAsFixed(1)} giờ đi đường (đã duyệt) · tính lương 1×'
              : 'Giờ đi đường tính lương 1× (không tăng ca)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }

  Widget _buildTravelPunchButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: enabled
                ? color.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: enabled
                  ? color.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: enabled ? color : Colors.white.withValues(alpha: 0.25),
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? Colors.white.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGpsCard() {
    final gpsOk = _gpsRequirementMet;
    final statusColor = gpsOk
        ? const Color(0xFF22C55E)
        : _isGettingLocation
            ? const Color(0xFFF59E0B)
            : const Color(0xFF64748B);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: statusColor.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      gpsOk
                          ? Icons.location_on_rounded
                          : Icons.gps_not_fixed_rounded,
                      size: 16,
                      color: statusColor,
                    ),
                  ),
                  const Spacer(),
                  if (_isGettingLocation)
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: statusColor))
                  else
                    GestureDetector(
                      onTap: _getCurrentLocation,
                      child: Icon(Icons.refresh_rounded,
                          size: 18, color: Colors.white.withValues(alpha: 0.3)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _isGettingLocation
                    ? 'Định vị...'
                    : gpsOk
                        ? (_allowOutsideCheckIn
                            ? 'GPS đã bật'
                            : 'Trong phạm vi')
                        : (_allowOutsideCheckIn
                            ? 'Chưa có GPS'
                            : 'Ngoài phạm vi'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: statusColor),
              ),
              if (_nearestLocationName != null) ...[
                const SizedBox(height: 3),
                Text(
                  _nearestLocationName!,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (_distanceFromOffice != null) ...[
                const SizedBox(height: 2),
                Text(formatMobileAttendanceDistance(_distanceFromOffice, compact: true),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: statusColor)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWifiCard() {
    final statusColor = _isWifiVerified
        ? const Color(0xFF22C55E)
        : _isCheckingWifi
            ? const Color(0xFFF59E0B)
            : const Color(0xFF64748B);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: statusColor.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      _isWifiVerified
                          ? Icons.wifi_rounded
                          : Icons.wifi_find_rounded,
                      size: 16,
                      color: statusColor,
                    ),
                  ),
                  const Spacer(),
                  if (_isCheckingWifi)
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: statusColor))
                  else
                    GestureDetector(
                      onTap: () =>
                          _checkWifiConnection(requestPermissions: true),
                      child: Icon(Icons.refresh_rounded,
                          size: 18, color: Colors.white.withValues(alpha: 0.3)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _isCheckingWifi
                    ? 'Kiểm tra...'
                    : _isWifiVerified
                        ? 'Đã xác thực'
                        : 'Chưa xác thực',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: statusColor),
              ),
              if (_wifiLocationName != null) ...[
                const SizedBox(height: 3),
                Text(
                  _wifiLocationName!,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (_connectedWifiSsid != null) ...[
                const SizedBox(height: 2),
                Text(
                  _connectedWifiSsid!,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: statusColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutsideChip() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Color(0xFF22C55E)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Chấm ngoài công ty — cần bật GPS, không cần trong vùng',
                style: TextStyle(fontSize: 12, color: Color(0xFF4ADE80))),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayRecords() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _glassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  ),
                  child: const Icon(Icons.timeline_rounded,
                      size: 16, color: Color(0xFF60A5FA)),
                ),
                const SizedBox(width: 10),
                const Text('Hôm nay',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('${_todayRecords.length}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B))),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_todayRecords.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.event_note_rounded,
                          size: 32, color: Colors.white.withValues(alpha: 0.1)),
                      const SizedBox(height: 8),
                      const Text('Chưa có lượt chấm công',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF475569))),
                    ],
                  ),
                ),
              )
            else
              ...(_todayRecords.map((record) => _buildRecordItem(record))),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordItem(MobileAttendanceRecord record) {
    final isCheckIn = record.punchType == mobilePunchCheckIn;
    final isTravel = record.isTravelPunch;
    final approved =
        record.status == 'auto_approved' || record.status == 'approved';
    final Color color;
    IconData icon;
    if (isTravel) {
      color = record.punchType == mobilePunchTravelStart
          ? const Color(0xFF0EA5E9)
          : const Color(0xFF14B8A6);
      icon = record.punchType == mobilePunchTravelStart
          ? Icons.directions_car_rounded
          : Icons.place_rounded;
    } else {
      color = isCheckIn ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);
      icon = isCheckIn ? Icons.south_west_rounded : Icons.north_east_rounded;
    }

    return InkWell(
      onTap: () => showMobileAttendanceRecordDetailSheet(context, record: record),
      borderRadius: BorderRadius.circular(12),
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${record.punchTime.hour.toString().padLeft(2, '0')}:${record.punchTime.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Text(
                    record.punchTypeLabel,
                    style: TextStyle(
                        fontSize: 11, color: color.withValues(alpha: 0.8)),
                  ),
                  if (record.distanceFromLocation != null) ...[
                    Text(' · ',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.2))),
                    Text(record.formattedDistanceFromLocation,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ],
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: approved
                  ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: (approved
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFF59E0B))
                      .withValues(alpha: 0.15)),
            ),
            child: Text(
              approved ? 'Duyệt' : 'Chờ',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: approved
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFFCD34D)),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
