import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'notification_overlay.dart';

class CameraFaceCaptureResult {
  final List<String> base64Images;
  CameraFaceCaptureResult({required this.base64Images});
}

class CameraFaceCapture extends StatefulWidget {
  final String? employeeName;
  final int requiredPhotos;

  const CameraFaceCapture({
    super.key,
    this.employeeName,
    this.requiredPhotos = 3,
  });

  static Future<CameraFaceCaptureResult?> show(
    BuildContext context, {
    String? employeeName,
    int requiredPhotos = 3,
  }) {
    return Navigator.of(context).push<CameraFaceCaptureResult>(
      MaterialPageRoute(
        builder: (_) => CameraFaceCapture(
          employeeName: employeeName,
          requiredPhotos: requiredPhotos,
        ),
      ),
    );
  }

  @override
  State<CameraFaceCapture> createState() => _CameraFaceCaptureState();
}

class _CameraFaceCaptureState extends State<CameraFaceCapture> {
  final List<String> _capturedImages = [];
  bool _isCapturing = false;
  final ImagePicker _picker = ImagePicker();

  final List<_CaptureStep> _steps = const [
    _CaptureStep(instruction: 'Nhìn thẳng vào camera', icon: Icons.face),
    _CaptureStep(instruction: 'Nghiêng mặt sang TRÁI', icon: Icons.arrow_back),
    _CaptureStep(instruction: 'Nghiêng mặt sang PHẢI', icon: Icons.arrow_forward),
  ];

  int get _currentStep => _capturedImages.length;
  bool get _allCaptured => _capturedImages.length >= widget.requiredPhotos;

  Future<void> _capturePhoto() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 640,
        maxHeight: 480,
      );

      if (photo != null && mounted) {
        final bytes = await File(photo.path).readAsBytes();
        final base64 = base64Encode(bytes);
        setState(() => _capturedImages.add(base64));
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể chụp ảnh: $e');
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _retakePhoto(int index) {
    setState(() => _capturedImages.removeAt(index));
  }

  void _resetAll() {
    setState(() => _capturedImages.clear());
  }

  void _confirmAndReturn() {
    Navigator.pop(
      context,
      CameraFaceCaptureResult(base64Images: List.from(_capturedImages)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildContent()),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 24),
            ),
          ),
          const Spacer(),
          if (widget.employeeName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(widget.employeeName!,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Ảnh ${_capturedImages.length}/${widget.requiredPhotos}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_allCaptured) return _buildCompletionView();

    final step = _currentStep < _steps.length ? _steps[_currentStep] : null;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, color: Colors.white.withValues(alpha: 0.3), size: 120),
          const SizedBox(height: 24),
          if (step != null) ...[
            Icon(step.icon, color: Colors.white70, size: 32),
            const SizedBox(height: 8),
            Text(step.instruction,
                style: const TextStyle(color: Colors.white, fontSize: 18)),
          ],
          const SizedBox(height: 32),
          if (_capturedImages.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _capturedImages
                  .asMap()
                  .entries
                  .map((e) => _buildThumbnail(e.key, e.value))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildCompletionView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              color: Color(0xFF1E3A5F),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 60),
          ),
          const SizedBox(height: 24),
          const Text('Chụp ảnh hoàn tất!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${_capturedImages.length} ảnh đã được chụp thành công',
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _capturedImages
                .asMap()
                .entries
                .map((e) => _buildThumbnail(e.key, e.value))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(int index, String base64) {
    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E3A5F), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(base64Decode(base64), fit: BoxFit.cover),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => _retakePhoto(index),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: _allCaptured ? _buildCompletionButtons() : _buildCaptureControls(),
    );
  }

  Widget _buildCaptureControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_steps.length, (index) {
            final isCompleted = index < _capturedImages.length;
            final isCurrent = index == _currentStep;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isCurrent ? 24 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: isCompleted
                    ? const Color(0xFF1E3A5F)
                    : isCurrent
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(5),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _isCapturing ? null : _capturePhoto,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isCapturing ? Colors.red : Colors.white,
              ),
              child: _isCapturing
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.camera, color: Color(0xFF18181B), size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isCapturing ? 'Đang chụp...' : 'Nhấn để chụp',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildCompletionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _resetAll,
            icon: const Icon(Icons.refresh, color: Colors.white70),
            label: const Text('Chụp lại',
                style: TextStyle(color: Colors.white70)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _confirmAndReturn,
            icon: const Icon(Icons.check),
            label: const Text('Xác nhận & Đăng ký'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

class _CaptureStep {
  final String instruction;
  final IconData icon;
  const _CaptureStep({required this.instruction, required this.icon});
}
