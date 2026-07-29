import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/circle_face_capture_widget.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import '../services/signalr_service.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class MobileDeviceRegistrationScreen extends StatefulWidget {
  const MobileDeviceRegistrationScreen({super.key});

  @override
  State<MobileDeviceRegistrationScreen> createState() =>
      _MobileDeviceRegistrationScreenState();
}

enum _RegStatus { loading, notRegistered, pending, approved, alreadyRegisteredOnOtherDevice, pendingDeviceChange, error }

const _faceCaptureStepLabels = ['Thẳng', 'Trái', 'Phải', 'Trên', 'Dưới'];

class _MobileDeviceRegistrationScreenState
    extends State<MobileDeviceRegistrationScreen> {
  final ApiService _apiService = ApiService();
  _RegStatus _status = _RegStatus.loading;
  String? _errorMessage;
  bool _isSubmitting = false;

  // Device info
  String _deviceId = '';
  String _deviceName = '';
  String _deviceModel = '';
  String _osVersion = '';
  String? _wifiBssid;

  // Face images
  final List<String> _capturedImages = [];

  // Registration result
  String? _registeredDeviceName;
  DateTime? _registeredAt;

  // Already registered device info (different device)
  String? _existingDeviceName;
  String? _existingDeviceModel;

  // Device change request
  String? _changeRequestReason;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  // Work locations for registration / device change
  List<Map<String, dynamic>> _registrationLocations = [];
  final Set<String> _selectedLocationIds = {};
  bool _loadingLocations = false;
  String? _locationsError;

  @override
  void initState() {
    super.initState();
    _initScreen();
    ScreenRefreshNotifier.mobileDeviceRegistration.addListener(_onExternalRefresh);
    _notificationSubscription =
        SignalRService().onNewNotification.listen(_onRegistrationNotification);
  }

  Future<void> _initScreen() async {
    await _loadDeviceInfo();
    await _loadRegistrationLocations();
    await _checkRegistrationStatus();
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    _checkRegistrationStatus();
  }

  void _onRegistrationNotification(Map<String, dynamic> data) {
    final entityType = (data['relatedEntityType'] as String?)?.toLowerCase();
    if (entityType != 'authorizedmobiledevice' &&
        entityType != 'devicechangerequest') {
      return;
    }
    if (!mounted) return;
    final title = (data['title'] as String?)?.trim();
    final message = (data['message'] as String?)?.trim();
    if ((title != null && title.isNotEmpty) ||
        (message != null && message.isNotEmpty)) {
      NotificationOverlayManager().showInfo(
        title: title?.isNotEmpty == true ? title! : 'Thông báo',
        message: message?.isNotEmpty == true ? message! : '',
      );
    }
    _checkRegistrationStatus();
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.mobileDeviceRegistration.removeListener(_onExternalRefresh);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  /// Generate a stable, persistent device ID.
  /// - Android: use androidInfo.id (already stable across reinstalls on most devices).
  /// - iOS: identifierForVendor resets when the last app from the vendor is uninstalled,
  ///   so we persist it via SharedPreferences so it survives app updates and future
  ///   identifierForVendor regenerations. (Note: iOS still clears NSUserDefaults on
  ///   full uninstall, so re-registration is expected in that case.)
  Future<String> _getPersistentDeviceId(String rawId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'sbox_persistent_device_id';
      final cached = prefs.getString(key);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      // First launch (or cache cleared): derive a stable ID seeded from the
      // platform raw ID plus a random suffix so two devices with the same raw
      // ID (extremely rare but possible on rooted/cloned devices) won't collide.
      final rand = math.Random.secure();
      final suffix = List<int>.generate(6, (_) => rand.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final generated = rawId.isNotEmpty ? '${rawId}_$suffix' : 'dev_$suffix';
      await prefs.setString(key, generated);
      return generated;
    } catch (e) {
      debugPrint('Persistent device ID error: $e');
      return rawId.isNotEmpty ? rawId : 'dev_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<void> _loadDeviceInfo() async {
    String rawId = '';
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        rawId = 'web_${webInfo.userAgent?.hashCode ?? DateTime.now().millisecondsSinceEpoch}';
        _deviceName = webInfo.browserName.name;
        _deviceModel = 'Web Browser';
        _osVersion = webInfo.platform ?? 'Unknown';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        rawId = androidInfo.id;
        _deviceName = '${androidInfo.brand} ${androidInfo.model}';
        _deviceModel = androidInfo.model;
        _osVersion = 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        rawId = iosInfo.identifierForVendor ?? '';
        _deviceName = iosInfo.name;
        _deviceModel = iosInfo.model;
        _osVersion = '${iosInfo.systemName} ${iosInfo.systemVersion}';
      }
      _deviceId = await _getPersistentDeviceId(rawId);
    } catch (e) {
      debugPrint('Error getting device info: $e');
      _deviceId = await _getPersistentDeviceId(rawId);
      if (_deviceName.isEmpty) _deviceName = 'Unknown Device';
      if (_deviceModel.isEmpty) _deviceModel = 'Unknown';
      if (_osVersion.isEmpty) _osVersion = 'Unknown';
    }

    // Detect WiFi BSSID
    await _detectBssid();
  }

  Future<void> _loadRegistrationLocations({List<String>? preselectIds}) async {
    setState(() {
      _loadingLocations = true;
      _locationsError = null;
    });
    try {
      final response = await _apiService.getLocationsForRegistration();
      if (!mounted) return;
      if (response['isSuccess'] == true && response['data'] is List) {
        final list = (response['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final preselect = <String>{};
        if (preselectIds != null) {
          preselect.addAll(preselectIds.where((e) => e.isNotEmpty));
        }
        setState(() {
          _registrationLocations = list;
          _selectedLocationIds
            ..clear()
            ..addAll(preselect);
          _loadingLocations = false;
        });
      } else {
        setState(() {
          _registrationLocations = [];
          _loadingLocations = false;
          _locationsError =
              response['message']?.toString() ?? 'Không tải được danh sách vị trí';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _registrationLocations = [];
        _loadingLocations = false;
        _locationsError = 'Lỗi tải vị trí: $e';
      });
    }
  }

  void _toggleLocationSelection(String locationId) {
    setState(() {
      if (_selectedLocationIds.contains(locationId)) {
        _selectedLocationIds.remove(locationId);
      } else {
        _selectedLocationIds.add(locationId);
      }
    });
  }

  List<String> get _selectedLocationIdList =>
      _selectedLocationIds.where((e) => e.isNotEmpty).toList();

  bool get _hasValidLocationSelection => _selectedLocationIdList.isNotEmpty;

  Widget _buildLocationPicker({required int step}) {
    return _buildStepCard(
      step: step,
      title: 'Vị trí chấm công',
      subtitle: _selectedLocationIds.isEmpty
          ? 'Chọn ít nhất 1 vị trí'
          : 'Đã chọn ${_selectedLocationIds.length} vị trí',
      icon: Icons.location_on_outlined,
      isCompleted: _hasValidLocationSelection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Chọn các chi nhánh/vị trí bạn sẽ chấm công. '
            'Sau khi được duyệt, hệ thống tự gán bạn vào các vị trí này.'),
            style: TextStyle(
              color: Color(0xFF71717A),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingLocations)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_locationsError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(_locationsError!),
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _loadRegistrationLocations(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(tr('Tải lại')),
                ),
              ],
            )
          else if (_registrationLocations.isEmpty)
            Text(tr('Chưa có vị trí chấm công active. Liên hệ quản trị thiết lập tab Vị trí.'),
              style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13),
            )
          else
            ..._registrationLocations.map((loc) {
              final id = loc['id']?.toString() ?? '';
              final name = loc['name']?.toString() ?? 'Vị trí';
              final address = loc['address']?.toString();
              final selected = _selectedLocationIds.contains(id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected
                      ? HrmPageChrome.primaryNavy.withValues(alpha: 0.06)
                      : const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: id.isEmpty ? null : () => _toggleLocationSelection(id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: selected
                                ? HrmPageChrome.primaryNavy
                                : const Color(0xFFA1A1AA),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(name),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF18181B),
                                  ),
                                ),
                                if (address != null && address.isNotEmpty)
                                  Text(
                                    tr(address),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF71717A),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
      ),
    );
  }

  Future<void> _detectBssid() async {
    try {
      if (!kIsWeb) {
        final locStatus = await Permission.location.request();
        if (!locStatus.isGranted) {
          debugPrint('Location permission not granted for BSSID detection');
          return;
        }
      }
      final info = NetworkInfo();
      final bssid = await info.getWifiBSSID();
      if (bssid != null && bssid.isNotEmpty && bssid != '02:00:00:00:00:00') {
        if (mounted) setState(() => _wifiBssid = bssid);
      }
    } catch (e) {
      debugPrint('BSSID detection error: $e');
    }
  }

  static bool _parseApiBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' || s == '1';
  }

  Future<void> _checkRegistrationStatus() async {
    if (_deviceId.isEmpty) {
      await _loadDeviceInfo();
    }
    setState(() => _status = _RegStatus.loading);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      final employeeId = user?.employeeId ?? user?.id ?? '';

      final response = await _apiService.getMyDeviceStatus(
        employeeId: employeeId,
        currentDeviceId: _deviceId.isNotEmpty ? _deviceId : null,
      );

      if (!mounted) return;

      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        final registered = _parseApiBool(data['registered']);
        final approved = _parseApiBool(data['approved']);
        final registeredOnOther = _parseApiBool(data['registeredOnOtherDevice']);

        if (registeredOnOther) {
          final changeReqResponse =
              await _apiService.getMyDeviceChangeRequest(employeeId: employeeId);
          bool hasPendingChange = false;
          if (changeReqResponse['isSuccess'] == true &&
              changeReqResponse['data'] != null) {
            hasPendingChange =
                changeReqResponse['data']['hasPendingRequest'] == true;
          }
          if (hasPendingChange) {
            setState(() {
              _status = _RegStatus.pendingDeviceChange;
              _existingDeviceName = data['deviceName'];
              _registeredDeviceName =
                  changeReqResponse['data']?['newDeviceName'];
            });
          } else {
            final preselect = <String>[];
            final swl = data['selectedWorkLocations'];
            if (swl is Map<String, dynamic>) {
              final ids = swl['ids'];
              if (ids is List) {
                preselect.addAll(ids.map((e) => e.toString()));
              }
            }
            if (preselect.isEmpty) {
              final raw = data['selectedWorkLocationIds']?.toString();
              if (raw != null && raw.isNotEmpty) {
                try {
                  final decoded = jsonDecode(raw);
                  if (decoded is List) {
                    preselect.addAll(decoded.map((e) => e.toString()));
                  }
                } catch (_) {}
              }
            }
            if (preselect.isNotEmpty) {
              _loadRegistrationLocations(preselectIds: preselect);
            }
            setState(() {
              _status = _RegStatus.alreadyRegisteredOnOtherDevice;
              _existingDeviceName = data['deviceName'];
              _existingDeviceModel = data['deviceModel'];
              _registeredAt = data['registeredAt'] != null
                  ? DateTime.parse(data['registeredAt'])
                  : null;
            });
          }
        } else if (!registered) {
          final changeReqResponse =
              await _apiService.getMyDeviceChangeRequest(employeeId: employeeId);
          if (changeReqResponse['isSuccess'] == true &&
              changeReqResponse['data'] != null) {
            final crData = changeReqResponse['data'];
            if (crData['hasPendingRequest'] == true) {
              setState(() {
                _status = _RegStatus.pendingDeviceChange;
                _existingDeviceName = crData['oldDeviceName'];
                _registeredDeviceName = crData['newDeviceName'];
              });
              return;
            }
          }
          setState(() => _status = _RegStatus.notRegistered);
        } else if (approved) {
          setState(() {
            _status = _RegStatus.approved;
            _registeredDeviceName = data['deviceName'];
            _registeredAt = data['registeredAt'] != null
                ? DateTime.parse(data['registeredAt'])
                : null;
          });
        } else {
          setState(() {
            _status = _RegStatus.pending;
            _registeredDeviceName = data['deviceName'];
            _registeredAt = data['registeredAt'] != null
                ? DateTime.parse(data['registeredAt'])
                : null;
          });
        }
      } else {
        final code = response['statusCode'];
        var msg = response['message']?.toString() ?? 'Không thể kiểm tra trạng thái';
        if (code == 403) {
          msg =
              'Tài khoản chưa có quyền đăng ký chấm công mobile. Liên hệ quản trị bật quyền «Đăng ký CC Mobile» hoặc «Chấm công mobile».';
        }
        setState(() {
          _status = _RegStatus.error;
          _errorMessage = msg;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _RegStatus.error;
          _errorMessage = 'Lỗi kết nối: $e';
        });
      }
    }
  }

  Future<void> _openFaceCapture() async {
    final images = await CircleFaceCaptureWidget.show(context);
    if (!mounted || images == null) return;
    if (images.length < 5) {
      _showSnackBar(
        'Cần đủ 5 ảnh khuôn mặt (hiện có ${images.length}). Vui lòng chụp lại.',
        isError: true,
      );
      return;
    }
    setState(() {
      _capturedImages.clear();
      _capturedImages.addAll(images);
    });
  }

  Widget _buildFacePreviewBeforeSubmit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Xem trước ${_capturedImages.length}/5 ảnh trước khi gửi'),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF18181B),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_capturedImages.length, (index) {
                Uint8List? bytes;
                try {
                  bytes = base64Decode(_capturedImages[index]);
                } catch (_) {
                  return const SizedBox.shrink();
                }
                final label = index < _faceCaptureStepLabels.length
                    ? _faceCaptureStepLabels[index]
                    : 'Ảnh ${index + 1}';
                return Padding(
                  padding: EdgeInsets.only(
                      right: index < _capturedImages.length - 1 ? 10 : 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          bytes,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(label),
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF71717A)),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitRegistration() async {
    if (!_hasValidLocationSelection) {
      _showSnackBar('Chọn ít nhất một vị trí chấm công', isError: true);
      return;
    }
    if (_capturedImages.length < 5) {
      _showSnackBar('Cần đủ 5 ảnh khuôn mặt hợp lệ trước khi gửi', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      final employeeId = user?.employeeId ?? user?.id ?? '';
      final employeeName = user?.fullName ?? '';

      if (employeeId.isEmpty) {
        _showSnackBar('Không xác định được nhân viên', isError: true);
        return;
      }

      final response = await _apiService.registerMobileDevice(
        deviceId: _deviceId,
        deviceName: _deviceName,
        deviceModel: _deviceModel,
        osVersion: _osVersion,
        employeeId: employeeId,
        employeeName: employeeName,
        faceImages: _capturedImages,
        selectedWorkLocationIds: _selectedLocationIdList,
        wifiBssid: _wifiBssid,
      );

      if (!mounted) return;

      if (response['isSuccess'] == true) {
        _showSnackBar('Đăng ký thành công! Chờ quản lý duyệt.');
        setState(() {
          _status = _RegStatus.pending;
          _registeredDeviceName = _deviceName;
          _registeredAt = DateTime.now();
          _capturedImages.clear();
        });
      } else if (response['alreadyRegistered'] == true) {
        final data = response['data'] as Map<String, dynamic>?;
        final existingId = data?['existingDeviceId']?.toString() ?? '';
        final isSameDevice = existingId.isNotEmpty &&
            existingId.toLowerCase() == _deviceId.toLowerCase();
        if (isSameDevice) {
          final approved = data?['isAuthorized'] == true;
          setState(() {
            _status = approved ? _RegStatus.approved : _RegStatus.pending;
            _registeredDeviceName =
                data?['existingDeviceName']?.toString() ?? _deviceName;
            _registeredAt = data?['registeredAt'] != null
                ? DateTime.tryParse(data!['registeredAt'].toString())
                : null;
            _capturedImages.clear();
          });
          _showSnackBar(
            approved
                ? 'Thiết bị này đã được đăng ký và duyệt.'
                : 'Thiết bị này đã đăng ký, đang chờ quản lý duyệt.',
          );
        } else {
          setState(() {
            _status = _RegStatus.alreadyRegisteredOnOtherDevice;
            _existingDeviceName = data?['existingDeviceName'] ?? 'Không rõ';
            _existingDeviceModel = data?['existingDeviceModel'] ?? '';
            _capturedImages.clear();
          });
          _showSnackBar(
            'Tài khoản đã đăng ký trên thiết bị khác. Vui lòng dùng yêu cầu đổi thiết bị.',
            isError: true,
          );
        }
      } else {
        final code = response['statusCode'];
        var msg = _sanitizeApiMessage(
          response['message']?.toString(),
          fallback: 'Đăng ký thất bại',
        );
        if (code == 403) {
          msg =
              'Không có quyền gửi đăng ký. Cần quyền chấm công mobile trên tài khoản của bạn.';
        }
        _showSnackBar(msg, isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Lỗi kết nối: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _sanitizeApiMessage(String? raw, {required String fallback}) {
    final m = raw?.trim() ?? '';
    if (m.isEmpty) return fallback;
    // Chuỗi lỗi encoding từ API cũ (Thi?t b?, Kh?ng...)
    if (m.contains('?') &&
        RegExp(r'Thi\?t|Kh\?ng|nh\?n vi\?n|d\?').hasMatch(m)) {
      return fallback;
    }
    return m;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final text = _sanitizeApiMessage(message, fallback: message);
    if (isError) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: text);
    } else {
      NotificationOverlayManager().showSuccess(
          title: 'Thành công', message: text);
    }
  }

  Future<void> _submitDeviceChangeRequest() async {
    if (!_hasValidLocationSelection) {
      _showSnackBar('Chọn ít nhất một vị trí chấm công', isError: true);
      return;
    }
    if (_capturedImages.length < 5) {
      _showSnackBar('Cần đủ 5 ảnh khuôn mặt hợp lệ trước khi gửi', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      final employeeId = user?.employeeId ?? user?.id ?? '';
      final employeeName = user?.fullName ?? '';

      if (employeeId.isEmpty) {
        _showSnackBar('Không xác định được nhân viên', isError: true);
        return;
      }

      final response = await _apiService.requestDeviceChange(
        employeeId: employeeId,
        employeeName: employeeName,
        newDeviceId: _deviceId,
        newDeviceName: _deviceName,
        newDeviceModel: _deviceModel,
        newOsVersion: _osVersion,
        newWifiBssid: _wifiBssid,
        faceImages: _capturedImages,
        selectedWorkLocationIds: _selectedLocationIdList,
        reason: _changeRequestReason,
      );

      if (!mounted) return;

      if (response['isSuccess'] == true) {
        _showSnackBar('Yêu cầu đổi máy đã được gửi. Chờ quản lý duyệt.');
        setState(() {
          _status = _RegStatus.pendingDeviceChange;
          _registeredDeviceName = _deviceName;
          _capturedImages.clear();
          _changeRequestReason = null;
        });
      } else {
        _showSnackBar(response['message'] ?? 'Gửi yêu cầu thất bại', isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Lỗi kết nối: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
        title: Text(tr('Đăng ký chấm công Mobile'),
          style: TextStyle(
            color: Color(0xFF18181B),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _RegStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case _RegStatus.notRegistered:
        return _buildRegistrationForm();

      case _RegStatus.pending:
        return _buildPendingView();

      case _RegStatus.approved:
        return _buildApprovedView();

      case _RegStatus.alreadyRegisteredOnOtherDevice:
        return _buildAlreadyRegisteredView();

      case _RegStatus.pendingDeviceChange:
        return _buildPendingDeviceChangeView();

      case _RegStatus.error:
        return _buildErrorView();
    }
  }

  Widget _buildRegistrationForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  HrmPageChrome.primaryNavy,
                  HrmPageChrome.primaryNavy.withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.phone_android, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(tr('Đăng ký thiết bị'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  tr('Đăng ký điện thoại và khuôn mặt để sử dụng chấm công mobile. '
                  'Mỗi tài khoản chỉ được đăng ký 1 thiết bị.'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Step 1: Device info (auto-detected)
          _buildStepCard(
            step: 1,
            title: 'Thông tin thiết bị',
            subtitle: 'Tự động nhận diện',
            icon: Icons.smartphone,
            isCompleted: _deviceId.isNotEmpty,
            child: Column(
              children: [
                _buildInfoRow(Icons.badge, 'Tên thiết bị', _deviceName),
                _buildInfoRow(Icons.phone_android, 'Model', _deviceModel),
                _buildInfoRow(Icons.system_update, 'Hệ điều hành', _osVersion),
                _buildInfoRow(Icons.fingerprint, 'Mã thiết bị',
                    _deviceId.length > 20 ? '${_deviceId.substring(0, 20)}...' : _deviceId),
                _buildInfoRow(Icons.router, 'MAC WiFi (BSSID)',
                    _wifiBssid ?? 'Không phát hiện được'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _buildLocationPicker(step: 2),
          const SizedBox(height: 16),

          // Step 3: Face capture
          _buildStepCard(
            step: 3,
            title: 'Chụp khuôn mặt',
            subtitle: _capturedImages.isEmpty
                ? 'Chưa chụp'
                : '${_capturedImages.length} ảnh đã chụp',
            icon: Icons.face_retouching_natural,
            isCompleted: _capturedImages.isNotEmpty,
            child: Column(
              children: [
                if (_capturedImages.isEmpty) ...[
                  Text(tr('Hệ thống sẽ chụp 5 góc khuôn mặt: Thẳng, Trái, Phải, Trên, Dưới'),
                    style: TextStyle(
                      color: Color(0xFF71717A),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Color(0xFF22C55E), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr('Đã chụp ${_capturedImages.length} ảnh khuôn mặt'),
                          style: const TextStyle(
                            color: Color(0xFF22C55E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildFacePreviewBeforeSubmit(),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openFaceCapture,
                    icon: Icon(_capturedImages.isEmpty
                        ? Icons.camera_alt
                        : Icons.refresh),
                    label: Text(
                        tr(_capturedImages.isEmpty ? 'Bắt đầu chụp' : 'Chụp lại')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HrmPageChrome.primaryNavy,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: HrmPageChrome.primaryNavy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_hasValidLocationSelection &&
                      _capturedImages.length >= 5 &&
                      !_isSubmitting)
                  ? _submitRegistration
                  : null,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(
                tr(_isSubmitting ? 'Đang gửi...' : 'Gửi yêu cầu đăng ký'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: HrmPageChrome.primaryNavy,
                disabledBackgroundColor: const Color(0xFFD4D4D8),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Note
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Sau khi gửi yêu cầu, quản lý sẽ duyệt đăng ký. '
                    'Khi được duyệt, chức năng chấm công mobile sẽ hiển thị.'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF92400E),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({
    required int step,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isCompleted,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCompleted
              ? const Color(0xFF22C55E).withValues(alpha: 0.3)
              : const Color(0xFFE4E4E7),
        ),
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
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? const Color(0xFF22C55E)
                      : HrmPageChrome.primaryNavy,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : Text(
                          tr('$step'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(title),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF18181B),
                      ),
                    ),
                    Text(
                      tr(subtitle),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF71717A),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(icon,
                  color: isCompleted
                      ? const Color(0xFF22C55E)
                      : HrmPageChrome.primaryNavy,
                  size: 24),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF71717A)),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(tr(label),
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF71717A))),
          ),
          Expanded(
            child: Text(
              tr(value),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF18181B)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.hourglass_empty,
                  size: 64, color: Color(0xFFF59E0B)),
            ),
            const SizedBox(height: 32),
            Text(tr('Đang chờ duyệt'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr('${tr('Thiết bị "')}${_registeredDeviceName ?? ''}" đã được đăng ký.\n'
              'Vui lòng chờ quản lý duyệt yêu cầu.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF71717A),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (_registeredAt != null) ...[
              const SizedBox(height: 8),
              Text(tr('Đăng ký lúc: ${_registeredAt!.day}/${_registeredAt!.month}/${_registeredAt!.year}'),
                style: const TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _checkRegistrationStatus,
              icon: const Icon(Icons.refresh),
              label: Text(tr('Kiểm tra lại')),
              style: OutlinedButton.styleFrom(
                foregroundColor: HrmPageChrome.primaryNavy,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.check_circle,
                  size: 64, color: Color(0xFF22C55E)),
            ),
            const SizedBox(height: 32),
            Text(tr('Đã được duyệt!'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF22C55E),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr('${tr('Thiết bị "')}${_registeredDeviceName ?? ''}" đã được duyệt.\n'
              'Bạn có thể sử dụng chấm công mobile.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF71717A),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            const Icon(Icons.phone_android,
                size: 28, color: HrmPageChrome.primaryNavy),
            const SizedBox(height: 8),
            Text(tr('Mở "Chấm công Mobile" trong menu để bắt đầu'),
              style: TextStyle(
                color: HrmPageChrome.primaryNavy,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlreadyRegisteredView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Warning header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB45309), Color(0xFFF59E0B)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(tr('Đã đăng ký trên thiết bị khác'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(tr('Tài khoản của bạn đã đăng ký chấm công trên thiết bị:'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.smartphone, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tr(_existingDeviceName ?? 'Không rõ'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_existingDeviceModel != null && _existingDeviceModel!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 28),
                          child: Text(
                            tr(_existingDeviceModel!),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      if (_registeredAt != null) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 28),
                          child: Text(tr('Đăng ký: ${_registeredAt!.day}/${_registeredAt!.month}/${_registeredAt!.year}'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Device change request form
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
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
                Row(
                  children: [
                    Icon(Icons.swap_horiz, color: Color(0xFF2563EB), size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(tr('Yêu cầu đổi sang thiết bị này'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF18181B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Gửi yêu cầu đổi máy để chuyển chấm công sang thiết bị hiện tại. '
                  'Sau khi được duyệt, thiết bị cũ và khuôn mặt cũ sẽ bị xóa.'),
                  style: TextStyle(
                    color: Color(0xFF71717A),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),

                // New device info
                _buildInfoRow(Icons.badge, 'Thiết bị mới', _deviceName),
                _buildInfoRow(Icons.phone_android, 'Model', _deviceModel),
                _buildInfoRow(Icons.system_update, 'Hệ điều hành', _osVersion),
                const SizedBox(height: 16),

                _buildLocationPicker(step: 1),
                const SizedBox(height: 16),

                // Reason input
                TextField(
                  decoration: InputDecoration(
                    labelText: tr('Lý do đổi máy (tùy chọn)'),
                    hintText: tr('VD: Máy cũ bị hỏng, đổi máy mới...'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  maxLines: 2,
                  onChanged: (v) => _changeRequestReason = v.isEmpty ? null : v,
                ),
                const SizedBox(height: 16),

                // Face capture
                if (_capturedImages.isEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openFaceCapture,
                      icon: const Icon(Icons.camera_alt),
                      label: Text(tr('Chụp khuôn mặt mới')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HrmPageChrome.primaryNavy,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: HrmPageChrome.primaryNavy),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr('Đã chụp ${_capturedImages.length} ảnh khuôn mặt'),
                          style: const TextStyle(
                            color: Color(0xFF22C55E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _openFaceCapture,
                        child: Text(tr('Chụp lại')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildFacePreviewBeforeSubmit(),
                ],
                const SizedBox(height: 16),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_hasValidLocationSelection &&
                            _capturedImages.length >= 5 &&
                            !_isSubmitting)
                        ? _submitDeviceChangeRequest
                        : null,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      tr(_isSubmitting ? 'Đang gửi...' : 'Gửi yêu cầu đổi máy'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: HrmPageChrome.primaryNavy,
                      disabledBackgroundColor: const Color(0xFFD4D4D8),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Info note
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Sau khi gửi yêu cầu, quản lý sẽ duyệt và thiết bị cũ + khuôn mặt cũ sẽ bị xóa. '
                    'Thiết bị mới sẽ được tự động kích hoạt.'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF92400E),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingDeviceChangeView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFDBEAFE),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.swap_horiz,
                  size: 64, color: Color(0xFF2563EB)),
            ),
            const SizedBox(height: 32),
            Text(tr('Đang chờ duyệt đổi máy'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr('${tr('Yêu cầu đổi sang "')}${_registeredDeviceName ?? 'thiết bị mới'}" đang chờ quản lý duyệt.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF71717A),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (_existingDeviceName != null) ...[
              const SizedBox(height: 8),
              Text(tr('Thiết bị hiện tại: $_existingDeviceName'),
                style: const TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _checkRegistrationStatus,
              icon: const Icon(Icons.refresh),
              label: Text(tr('Kiểm tra lại')),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text(
              tr(_errorMessage ?? 'Đã xảy ra lỗi'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF71717A),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _checkRegistrationStatus,
              icon: const Icon(Icons.refresh),
              label: Text(tr('Thử lại')),
              style: FilledButton.styleFrom(
                backgroundColor: HrmPageChrome.primaryNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
