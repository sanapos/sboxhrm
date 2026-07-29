import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/app_permission_service.dart';
import '../utils/site_photo_watermark.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Chụp ảnh hiện trường bằng camera sau; trả về base64 JPEG (có watermark).
class SitePhotoCaptureScreen extends StatefulWidget {
  const SitePhotoCaptureScreen({
    super.key,
    this.latitude,
    this.longitude,
    this.locationLabel,
    this.mandatory = false,
  });

  final double? latitude;
  final double? longitude;
  final String? locationLabel;
  /// true = bắt buộc chụp, không cho đóng/bỏ qua (sau xác thực chấm công).
  final bool mandatory;

  @override
  State<SitePhotoCaptureScreen> createState() => _SitePhotoCaptureScreenState();
}

class _SitePhotoCaptureScreenState extends State<SitePhotoCaptureScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;
  bool _capturing = false;
  String? _error;
  bool _permissionPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (kIsWeb) {
      setState(() {
        _error = 'Chụp ảnh hiện trường chỉ hỗ trợ trên điện thoại.';
        _initializing = false;
      });
      return;
    }

    final camStatus = await AppPermissionService.ensureCameraPermission();
    final allowed = camStatus.isGranted ||
        camStatus.isLimited ||
        await AppPermissionService.hasCameraAccess();
    if (!allowed) {
      setState(() {
        _permissionPermanentlyDenied = camStatus.isPermanentlyDenied;
        _error = camStatus.isPermanentlyDenied
            ? 'Cần bật Camera trong Cài đặt > SBOX HRM > Quyền.'
            : 'Cần quyền camera để chụp ảnh hiện trường.';
        _initializing = false;
      });
      return;
    }

    try {
      _cameras = await availableCameras();
      CameraDescription camera;
      try {
        camera = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
      } catch (_) {
        camera = _cameras.first;
      }

      final ctrl = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _initializing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Không mở được camera: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _retryCamera() async {
    await _controller?.dispose();
    _controller = null;
    if (!mounted) return;
    setState(() {
      _error = null;
      _permissionPermanentlyDenied = false;
      _initializing = true;
    });
    await _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;

    setState(() => _capturing = true);
    try {
      final file = await ctrl.takePicture();
      final raw = await file.readAsBytes();
      final stamped = applySitePhotoWatermark(
        raw,
        capturedAt: DateTime.now(),
        latitude: widget.latitude,
        longitude: widget.longitude,
        locationLabel: widget.locationLabel,
      );
      if (!mounted) return;
      Navigator.pop(context, base64Encode(stamped));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Chụp ảnh thất bại: $e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.mandatory,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: HrmPageChrome.primaryNavy,
          foregroundColor: Colors.white,
          title: Text(tr(widget.mandatory
              ? 'Ảnh hiện trường (bắt buộc)'
              : 'Ảnh hiện trường')),
          automaticallyImplyLeading: !widget.mandatory,
          leading: widget.mandatory
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_camera_outlined,
                size: 48,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                tr(_error!),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _retryCamera,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('Thử lại mở camera')),
                  style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy,
                  ),
                ),
              ),
              if (_permissionPermanentlyDenied) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: openAppSettings,
                  child: Text(tr('Mở Cài đặt quyền'),
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return Center(
        child: Text(tr('Camera chưa sẵn sàng'),
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(ctrl),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tr(_overlayHint()),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _capturing ? null : _capture,
                icon: _capturing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(tr(_capturing ? 'Đang chụp…' : 'Chụp ảnh hiện trường')),
                style: FilledButton.styleFrom(
                  backgroundColor: HrmPageChrome.primaryNavy,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _overlayHint() {
    final parts = <String>[
      if (widget.mandatory)
        'Bắt buộc chụp ảnh hiện trường để hoàn tất chấm công.',
      'Thời gian và GPS sẽ được gắn lên ảnh sau khi chụp.',
    ];
    if (widget.latitude != null && widget.longitude != null) {
      parts.add(
        'Vị trí: ${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}',
      );
    }
    if (widget.locationLabel != null && widget.locationLabel!.isNotEmpty) {
      parts.add(widget.locationLabel!);
    }
    return parts.join('\n');
  }
}
