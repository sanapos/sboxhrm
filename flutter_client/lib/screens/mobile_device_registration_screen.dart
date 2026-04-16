import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/circle_face_capture_widget.dart';
import '../widgets/notification_overlay.dart';

class MobileDeviceRegistrationScreen extends StatefulWidget {
  const MobileDeviceRegistrationScreen({super.key});

  @override
  State<MobileDeviceRegistrationScreen> createState() =>
      _MobileDeviceRegistrationScreenState();
}

enum _RegStatus { loading, notRegistered, pending, approved, error }

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

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _checkRegistrationStatus();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        _deviceId = 'web_${webInfo.userAgent?.hashCode ?? DateTime.now().millisecondsSinceEpoch}';
        _deviceName = webInfo.browserName.name;
        _deviceModel = 'Web Browser';
        _osVersion = webInfo.platform ?? 'Unknown';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id;
        _deviceName = '${androidInfo.brand} ${androidInfo.model}';
        _deviceModel = androidInfo.model;
        _osVersion = 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor ?? 'ios_unknown';
        _deviceName = iosInfo.name;
        _deviceModel = iosInfo.model;
        _osVersion = '${iosInfo.systemName} ${iosInfo.systemVersion}';
      }
    } catch (e) {
      debugPrint('Error getting device info: $e');
      _deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      _deviceName = 'Unknown Device';
      _deviceModel = 'Unknown';
      _osVersion = 'Unknown';
    }

    // Detect WiFi BSSID
    await _detectBssid();
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

  Future<void> _checkRegistrationStatus() async {
    setState(() => _status = _RegStatus.loading);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      final employeeId = user?.id ?? '';

      final response =
          await _apiService.getMyDeviceStatus(employeeId: employeeId);

      if (!mounted) return;

      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        final registered = data['registered'] == true;
        final approved = data['approved'] == true;

        if (!registered) {
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
        setState(() {
          _status = _RegStatus.error;
          _errorMessage = response['message'] ?? 'Không thể kiểm tra trạng thái';
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
    if (images != null && images.isNotEmpty && mounted) {
      setState(() {
        _capturedImages.clear();
        _capturedImages.addAll(images);
      });
    }
  }

  Future<void> _submitRegistration() async {
    if (_capturedImages.isEmpty) {
      _showSnackBar('Vui lòng chụp ảnh khuôn mặt trước', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      final employeeId = user?.id ?? '';
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
      } else {
        _showSnackBar(response['message'] ?? 'Đăng ký thất bại', isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Lỗi kết nối: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (isError) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: message);
    } else {
      NotificationOverlayManager().showSuccess(title: 'Thành công', message: message);
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
        title: const Text(
          'Đăng ký chấm công Mobile',
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
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A5F), Color(0xFF2563EB)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.phone_android, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Đăng ký thiết bị',
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
                  'Đăng ký điện thoại và khuôn mặt để sử dụng chấm công mobile. '
                  'Mỗi tài khoản chỉ được đăng ký 1 thiết bị.',
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

          // Step 2: Face capture
          _buildStepCard(
            step: 2,
            title: 'Chụp khuôn mặt',
            subtitle: _capturedImages.isEmpty
                ? 'Chưa chụp'
                : '${_capturedImages.length} ảnh đã chụp',
            icon: Icons.face_retouching_natural,
            isCompleted: _capturedImages.isNotEmpty,
            child: Column(
              children: [
                if (_capturedImages.isEmpty) ...[
                  const Text(
                    'Hệ thống sẽ chụp 5 góc khuôn mặt: Thẳng, Trái, Phải, Trên, Dưới',
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
                      Text(
                        'Đã chụp ${_capturedImages.length} ảnh khuôn mặt',
                        style: const TextStyle(
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      _capturedImages.length,
                      (i) => Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF1E3A5F), width: 2),
                        ),
                        child: const Icon(Icons.check,
                            color: Color(0xFF1E3A5F), size: 24),
                      ),
                    ),
                  ),
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
                        _capturedImages.isEmpty ? 'Bắt đầu chụp' : 'Chụp lại'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E3A5F),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFF1E3A5F)),
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
            child: ElevatedButton.icon(
              onPressed:
                  (_capturedImages.isNotEmpty && !_isSubmitting) ? _submitRegistration : null,
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
                _isSubmitting ? 'Đang gửi...' : 'Gửi yêu cầu đăng ký',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFD4D4D8),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
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
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sau khi gửi yêu cầu, quản lý sẽ duyệt đăng ký. '
                    'Khi được duyệt, chức năng chấm công mobile sẽ hiển thị.',
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
                      : const Color(0xFF1E3A5F),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : Text(
                          '$step',
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
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF18181B),
                      ),
                    ),
                    Text(
                      subtitle,
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
                      : const Color(0xFF1E3A5F),
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
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF71717A))),
          ),
          Expanded(
            child: Text(
              value,
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
            const Text(
              'Đang chờ duyệt',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Thiết bị "${_registeredDeviceName ?? ''}" đã được đăng ký.\n'
              'Vui lòng chờ quản lý duyệt yêu cầu.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF71717A),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (_registeredAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Đăng ký lúc: ${_registeredAt!.day}/${_registeredAt!.month}/${_registeredAt!.year}',
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
              label: const Text('Kiểm tra lại'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1E3A5F),
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
            const Text(
              'Đã được duyệt!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF22C55E),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Thiết bị "${_registeredDeviceName ?? ''}" đã được duyệt.\n'
              'Bạn có thể sử dụng chấm công mobile.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF71717A),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            const Icon(Icons.phone_android,
                size: 28, color: Color(0xFF1E3A5F)),
            const SizedBox(height: 8),
            const Text(
              'Mở "Chấm công Mobile" trong menu để bắt đầu',
              style: TextStyle(
                color: Color(0xFF1E3A5F),
                fontWeight: FontWeight.w600,
                fontSize: 14,
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
              _errorMessage ?? 'Đã xảy ra lỗi',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF71717A),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _checkRegistrationStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
