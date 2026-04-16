import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;

/// Widget for Face ID capture with animated overlay
class FaceIdCaptureWidget extends StatefulWidget {
  final VoidCallback? onCapture;
  final void Function(double matchScore)? onVerified;
  final void Function(String error)? onError;
  final bool showLivenessPrompt;
  
  const FaceIdCaptureWidget({
    super.key,
    this.onCapture,
    this.onVerified,
    this.onError,
    this.showLivenessPrompt = true,
  });

  @override
  State<FaceIdCaptureWidget> createState() => _FaceIdCaptureWidgetState();
}

class _FaceIdCaptureWidgetState extends State<FaceIdCaptureWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scanController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scanAnimation;
  
  bool _isCapturing = false;
  bool _isVerified = false;
  bool _showLivenessAction = false;
  String _livenessAction = '';
  int _livenessStep = 0;
  double? _matchScore;
  String _statusText = 'Hướng mặt vào camera';

  final List<String> _livenessActions = [
    'Quay đầu sang trái',
    'Quay đầu sang phải',
    'Nháy mắt',
    'Mỉm cười',
  ];

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _scanController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );
    
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  Future<void> startCapture() async {
    if (_isCapturing) return;
    
    setState(() {
      _isCapturing = true;
      _statusText = 'Đang phân tích khuôn mặt...';
    });
    
    _scanController.repeat();
    widget.onCapture?.call();
    
    // Simulate face detection delay
    await Future.delayed(const Duration(seconds: 1));
    
    if (widget.showLivenessPrompt) {
      await _performLivenessCheck();
    } else {
      await _verifyFace();
    }
  }

  Future<void> _performLivenessCheck() async {
    setState(() {
      _showLivenessAction = true;
      _livenessStep = 0;
    });
    
    for (int i = 0; i < 2; i++) {
      final randomAction = _livenessActions[math.Random().nextInt(_livenessActions.length)];
      setState(() {
        _livenessAction = randomAction;
        _statusText = randomAction;
      });
      
      // Wait for user to perform action (simulated)
      await Future.delayed(const Duration(seconds: 2));
      setState(() => _livenessStep++);
    }
    
    setState(() {
      _showLivenessAction = false;
    });
    
    await _verifyFace();
  }

  Future<void> _verifyFace() async {
    setState(() {
      _statusText = 'Đang xác thực...';
    });
    
    // Simulate verification
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Mock result - in real app, this would come from face recognition API
    final success = math.Random().nextDouble() > 0.1; // 90% success rate for demo
    
    _scanController.stop();
    
    if (success) {
      final score = 85.0 + math.Random().nextDouble() * 15; // 85-100
      setState(() {
        _isVerified = true;
        _matchScore = score;
        _statusText = 'Xác thực thành công!';
        _isCapturing = false;
      });
      widget.onVerified?.call(score);
    } else {
      setState(() {
        _statusText = 'Không nhận diện được. Thử lại.';
        _isCapturing = false;
      });
      widget.onError?.call('Face not recognized');
    }
  }

  void reset() {
    setState(() {
      _isCapturing = false;
      _isVerified = false;
      _matchScore = null;
      _showLivenessAction = false;
      _livenessStep = 0;
      _statusText = 'Hướng mặt vào camera';
    });
    _scanController.reset();
    _pulseController.repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCameraPreview(),
          _buildStatusSection(),
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Container(
      height: 280,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Simulated camera preview (placeholder)
          Center(
            child: Icon(
              Icons.person,
              size: 120,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          
          // Face oval guide
          Center(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isCapturing ? 1.0 : _pulseAnimation.value,
                  child: CustomPaint(
                    size: const Size(180, 220),
                    painter: FaceOvalPainter(
                      color: _isVerified
                          ? const Color(0xFF1E3A5F)
                          : _isCapturing
                              ? const Color(0xFF1E3A5F)
                              : const Color(0xFF0F2340),
                      strokeWidth: 3,
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Scanning animation
          if (_isCapturing && !_isVerified)
            AnimatedBuilder(
              animation: _scanAnimation,
              builder: (context, child) {
                return Positioned(
                  left: 0,
                  right: 0,
                  top: 30 + (_scanAnimation.value * 200),
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 50),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFF1E3A5F).withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              },
            ),
          
          // Verified checkmark
          if (_isVerified)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E3A5F).withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          
          // Liveness action prompt
          if (_showLivenessAction)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2340),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _livenessAction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Corner guides
          _buildCornerGuide(Alignment.topLeft),
          _buildCornerGuide(Alignment.topRight),
          _buildCornerGuide(Alignment.bottomLeft),
          _buildCornerGuide(Alignment.bottomRight),
        ],
      ),
    );
  }

  Widget _buildCornerGuide(Alignment alignment) {
    final isTop = alignment == Alignment.topLeft || alignment == Alignment.topRight;
    final isLeft = alignment == Alignment.topLeft || alignment == Alignment.bottomLeft;
    
    return Positioned(
      top: isTop ? 20 : null,
      bottom: isTop ? null : 20,
      left: isLeft ? 20 : null,
      right: isLeft ? null : 20,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border(
            top: isTop
                ? BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 3)
                : BorderSide.none,
            bottom: !isTop
                ? BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 3)
                : BorderSide.none,
            left: isLeft
                ? BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 3)
                : BorderSide.none,
            right: !isLeft
                ? BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 3)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            _statusText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _isVerified
                  ? const Color(0xFF1E3A5F)
                  : _isCapturing
                      ? const Color(0xFF1E3A5F)
                      : const Color(0xFF18181B),
            ),
          ),
          if (_matchScore != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF1E3A5F), size: 18),
                const SizedBox(width: 6),
                Text(
                  'Độ khớp: ${_matchScore!.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Color(0xFF1E3A5F),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          if (_showLivenessAction) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                2,
                (index) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: index < _livenessStep
                        ? const Color(0xFF1E3A5F)
                        : const Color(0xFFE4E4E7),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isCapturing
              ? null
              : _isVerified
                  ? reset
                  : startCapture,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isVerified
                ? const Color(0xFF1E3A5F)
                : const Color(0xFF0F2340),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isCapturing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              else
                Icon(
                  _isVerified ? Icons.refresh : Icons.face,
                  size: 20,
                ),
              const SizedBox(width: 8),
              Text(
                _isCapturing
                    ? 'Đang xử lý...'
                    : _isVerified
                        ? 'Chụp lại'
                        : 'Bắt đầu xác thực',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for face oval guide
class FaceOvalPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  FaceOvalPainter({
    required this.color,
    this.strokeWidth = 2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawOval(rect, paint);
    
    // Draw dashed effect
    final dashPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2;
    
    canvas.drawOval(rect.inflate(8), dashPaint);
  }

  @override
  bool shouldRepaint(FaceOvalPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Full screen face capture dialog
class FaceIdCaptureDialog extends StatelessWidget {
  final void Function(double matchScore)? onVerified;
  
  const FaceIdCaptureDialog({super.key, this.onVerified});
  
  static Future<double?> show(BuildContext context) async {
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FaceIdCaptureDialog(
        onVerified: (score) => Navigator.of(context).pop(score),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Color(0xFF71717A)),
                  ),
                ),
              ],
            ),
            FaceIdCaptureWidget(
              onVerified: onVerified,
            ),
          ],
        ),
      ),
    );
  }
}
