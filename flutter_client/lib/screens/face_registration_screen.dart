import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/circle_face_capture_widget.dart';
import '../widgets/notification_overlay.dart';

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
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Đăng ký khuôn mặt',
          style: TextStyle(
            color: Color(0xFF18181B),
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
                  backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                  child: const Icon(Icons.person, color: Color(0xFF1E3A5F)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.employeeName!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF18181B),
                        ),
                      ),
                      if (widget.employeeId != null)
                        Text(
                          'Mã NV: ${widget.employeeId}',
                          style: const TextStyle(
                            color: Color(0xFF71717A),
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
                            ? const Color(0xFF1E3A5F)
                            : isCurrent
                                ? const Color(0xFF1E3A5F)
                                : const Color(0xFFE4E4E7),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, color: Colors.white, size: 20)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: isCurrent ? Colors.white : const Color(0xFF71717A),
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
                              ? const Color(0xFF1E3A5F)
                              : const Color(0xFFE4E4E7),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            _capturedImages.length >= _requiredImages
                ? 'Hoàn tất - Đã chụp $_requiredImages ảnh'
                : 'Chưa chụp - Nhấn "Bắt đầu chụp" để bắt đầu',
            style: const TextStyle(
              color: Color(0xFF71717A),
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
                color: const Color(0xFF1E3A5F).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.face_retouching_natural,
                size: 80,
                color: Color(0xFF1E3A5F),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Đăng ký khuôn mặt',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Hệ thống sẽ chụp 5 góc khuôn mặt:\nThẳng, Trái, Phải, Trên, Dưới',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF71717A),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openFaceCapture,
                icon: const Icon(Icons.camera_alt),
                label: const Text(
                  'Bắt đầu chụp',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
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
    if (images != null && images.isNotEmpty && mounted) {
      setState(() {
        _capturedImages.clear();
        _capturedImages.addAll(images);
      });
    }
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
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: Color(0xFF1E3A5F),
              size: 80,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Đã chụp đủ ảnh!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF18181B),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nhấn "Đăng ký" để hoàn tất quá trình',
            style: TextStyle(
              color: Color(0xFF71717A),
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
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E3A5F), width: 2),
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
                      color: Color(0xFF22C55E),
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF71717A),
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
                  label: const Text('Chụp lại'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF71717A),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Color(0xFFE4E4E7)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
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
                  label: Text(_isLoading ? 'Đang xử lý...' : 'Đăng ký'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đăng ký khuôn mặt thành công! Chờ quản lý duyệt.');
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
