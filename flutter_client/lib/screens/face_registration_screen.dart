import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/circle_face_capture_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';
class FaceRegistrationScreen extends StatefulWidget {
  final String? employeeId;
  final String? employeeName;
  
  const FaceRegistrationScreen({
    super.key,
    this.employeeId,
    this.employeeName,
  });

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  bool _isLoading = false;
  final List<String> _capturedImages = [];
  final int _requiredImages = 5;
  
  final List<String> _captureLabels = [
    'Thẳng',
    'Trái',
    'Phải',
    'Trên',
    'Dưới',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(tr('Đăng ký khuôn mặt'),
          style: TextStyle(
            color: SboxColors.slate900,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildProgressIndicator(),
          Expanded(
            child: _capturedImages.length >= _requiredImages
                ? _buildCompletionView()
                : _buildCaptureView(),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        children: [
          if (widget.employeeName != null) ...[
            Row(
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
                        tr(widget.employeeName!),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: SboxColors.slate900,
                        ),
                      ),
                      if (widget.employeeId != null)
                        Text(tr('Mã NV: ${widget.employeeId}'),
                          style: const TextStyle(
                            color: SboxColors.slate500,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          Row(
            children: List.generate(_requiredImages, (index) {
              final isCompleted = index < _capturedImages.length;
              final isCurrent = index == _capturedImages.length && !isCompleted;
              
              return Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? HrmPageChrome.primaryNavy
                            : isCurrent
                                ? HrmPageChrome.primaryNavy
                                : SboxColors.slate200,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, color: Colors.white, size: 20)
                            : Text(
                                tr('${index + 1}'),
                                style: TextStyle(
                                  color: isCurrent ? Colors.white : SboxColors.slate500,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    if (index < _requiredImages - 1)
                      Expanded(
                        child: Container(
                          height: 3,
                          color: isCompleted
                              ? HrmPageChrome.primaryNavy
                              : SboxColors.slate200,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            tr(_capturedImages.length >= _requiredImages
                ? 'Hoàn tất - Đã chụp $_requiredImages ảnh'
                : 'Chưa chụp - Nhấn "Bắt đầu chụp" để bắt đầu'),
            style: const TextStyle(
              color: SboxColors.slate500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.face_retouching_natural,
                size: 80,
                color: HrmPageChrome.primaryNavy,
              ),
            ),
            const SizedBox(height: 32),
            Text(tr('Đăng ký khuôn mặt'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: SboxColors.slate900,
              ),
            ),
            const SizedBox(height: 12),
            Text(tr('Hệ thống sẽ chụp 5 góc khuôn mặt:\nThẳng, Trái, Phải, Trên, Dưới'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SboxColors.slate500,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openFaceCapture,
                icon: const Icon(Icons.camera_alt),
                label: Text(tr('Bắt đầu chụp'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HrmPageChrome.primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFaceCapture() async {
    final images = await CircleFaceCaptureWidget.show(context);
    if (!mounted || images == null) return;
    if (images.length < _requiredImages) {
      NotificationOverlayManager().showError(
        title: 'Chưa đủ ảnh',
        message: tr('Cần đủ $_requiredImages ảnh khuôn mặt (hiện có ${images.length}). Vui lòng chụp lại.'),
      );
      return;
    }
    setState(() {
      _capturedImages.clear();
      _capturedImages.addAll(images);
    });
  }

  Widget _buildCompletionView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: HrmPageChrome.primaryNavy,
              size: 80,
            ),
          ),
          const SizedBox(height: 24),
          Text(tr('Đã chụp đủ ảnh!'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: SboxColors.slate900,
            ),
          ),
          const SizedBox(height: 8),
          Text(tr('Nhấn "Đăng ký" để hoàn tất quá trình'),
            style: TextStyle(
              color: SboxColors.slate500,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _capturedImages.asMap().entries.map((entry) {
              final label = entry.key < _captureLabels.length 
                  ? _captureLabels[entry.key] 
                  : 'Ảnh ${entry.key + 1}';
              return Container(
                width: 60,
                height: 72,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: HrmPageChrome.primaryNavy, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: SboxColors.success,
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(label),
                      style: const TextStyle(
                        fontSize: 10,
                        color: SboxColors.slate500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 48),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetCapture,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('Chụp lại')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SboxColors.slate500,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: SboxColors.slate200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _submitRegistration,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(tr(_isLoading ? 'Đang xử lý...' : 'Đăng ký')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _resetCapture() {
    setState(() {
      _capturedImages.clear();
    });
  }

  Future<void> _submitRegistration() async {
    setState(() => _isLoading = true);
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      final employeeId = widget.employeeId ?? user?.id ?? '';
      final employeeName = widget.employeeName ?? user?.fullName ?? '';

      if (employeeId.isEmpty) {
        _showError('Không xác định được nhân viên. Vui lòng đăng nhập lại.');
        return;
      }

      final apiService = ApiService();
      final response = await apiService.registerFace(
        employeeId: employeeId,
        employeeName: employeeName,
        faceImages: _capturedImages,
      );

      if (!mounted) return;

      if (response['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: tr('Đăng ký khuôn mặt thành công! Chờ quản lý duyệt.'));
        setState(() {
          _capturedImages.clear();
        });
      } else {
        _showError(response['message'] ?? 'Đăng ký thất bại');
      }
    } catch (e) {
      if (mounted) _showError('Lỗi kết nối: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    NotificationOverlayManager().showError(title: 'Lỗi', message: msg);
  }
}
