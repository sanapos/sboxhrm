import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart' as file_saver;
import '../widgets/notification_overlay.dart';

class StoreSuccessScreen extends StatefulWidget {
  final String storeName;
  final String storeCode;
  final String email;
  final String phone;
  final String? password;

  const StoreSuccessScreen({
    super.key,
    required this.storeName,
    required this.storeCode,
    required this.email,
    required this.phone,
    this.password,
  });

  @override
  State<StoreSuccessScreen> createState() => _StoreSuccessScreenState();
}

class _StoreSuccessScreenState extends State<StoreSuccessScreen>
    with TickerProviderStateMixin {
  final GlobalKey _cardKey = GlobalKey();
  bool _isDownloading = false;
  bool _isSeeding = false;
  bool _seedDone = false;
  String? _seedError;

  late AnimationController _checkController;
  late AnimationController _cardController;
  late AnimationController _confettiController;
  late Animation<double> _checkScale;
  late Animation<double> _checkOpacity;
  late Animation<double> _cardSlide;
  late Animation<double> _cardOpacity;
  late Animation<double> _buttonsOpacity;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.elasticOut),
    );
    _checkOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _checkController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _cardSlide = Tween<double>(begin: 60.0, end: 0.0).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOutCubic),
    );
    _cardOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _buttonsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    _checkController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _cardController.forward();
    });
    _confettiController.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
    _cardController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _downloadPng() async {
    setState(() => _isDownloading = true);
    try {
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final Uint8List pngBytes = byteData.buffer.asUint8List();
      await file_saver.saveFileBytes(
        pngBytes,
        'cua-hang-${widget.storeCode}.png',
        'image/png',
      );
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể tải ảnh: $e');
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _seedSampleData() async {
    setState(() {
      _isSeeding = true;
      _seedError = null;
    });
    try {
      final result = await ApiService().seedSampleData(widget.storeCode);
      if (mounted) {
        if (result['isSuccess'] == true) {
          setState(() {
            _seedDone = true;
            _isSeeding = false;
          });
          NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã cài dữ liệu mẫu thành công!');
        } else {
          setState(() {
            _seedError = result['message'] ?? 'Lỗi không xác định';
            _isSeeding = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _seedError = e.toString();
          _isSeeding = false;
        });
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    NotificationOverlayManager().showSuccess(title: 'Sao chép', message: 'Đã sao chép $label');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F23),
      body: Stack(
        children: [
          // Background gradient orbs
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.blue.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.green.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Confetti particles
          AnimatedBuilder(
            animation: _confettiController,
            builder: (context, child) {
              return CustomPaint(
                size: MediaQuery.of(context).size,
                painter: _ConfettiPainter(_confettiController.value),
              );
            },
          ),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    children: [
                      // Animated checkmark
                      AnimatedBuilder(
                        animation: _checkController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _checkOpacity.value,
                            child: Transform.scale(
                              scale: _checkScale.value,
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF00C853),
                                Color(0xFF2E7D32),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00C853).withValues(alpha: 0.4),
                                blurRadius: 30,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      AnimatedBuilder(
                        animation: _checkController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _checkOpacity.value,
                            child: child,
                          );
                        },
                        child: Column(
                          children: [
                            const Text(
                              'Đăng ký thành công!',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Lưu thông tin bên dưới để đăng nhập hệ thống',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Info card with animation
                      AnimatedBuilder(
                        animation: _cardController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _cardOpacity.value,
                            child: Transform.translate(
                              offset: Offset(0, _cardSlide.value),
                              child: child,
                            ),
                          );
                        },
                        child: RepaintBoundary(
                          key: _cardKey,
                          child: _StoreInfoCard(
                            storeName: widget.storeName,
                            storeCode: widget.storeCode,
                            email: widget.email,
                            phone: widget.phone,
                            password: widget.password,
                            onCopy: _copyToClipboard,
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Animated buttons
                      AnimatedBuilder(
                        animation: _cardController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _buttonsOpacity.value,
                            child: child,
                          );
                        },
                        child: Column(
                          children: [
                            // Sample data - đặt lên trên để dễ thấy
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: _seedDone
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.check_circle_rounded,
                                              color: Color(0xFF4CAF50), size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            'Đã cài dữ liệu mẫu',
                                            style: TextStyle(
                                              color: Color(0xFF4CAF50),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : OutlinedButton.icon(
                                      icon: _isSeeding
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFFFFB74D),
                                              ),
                                            )
                                          : const Icon(Icons.dataset_rounded,
                                              size: 20),
                                      label: Text(
                                        _isSeeding
                                            ? 'Đang cài dữ liệu mẫu...'
                                            : 'Cài dữ liệu mẫu (10 NV, 15 ngày)',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFFFB74D),
                                        side: BorderSide(
                                          color: const Color(0xFFFF9800)
                                              .withValues(alpha: 0.3),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                      ),
                                      onPressed:
                                          _isSeeding ? null : _seedSampleData,
                                    ),
                            ),
                            if (_seedError != null) ...[                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  _seedError!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            // Download PNG
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: OutlinedButton.icon(
                                icon: _isDownloading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white70,
                                        ),
                                      )
                                    : const Icon(Icons.download_rounded,
                                        size: 20),
                                label: const Text(
                                  'Tải ảnh thông tin (PNG)',
                                  style: TextStyle(fontSize: 14),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.15),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: _isDownloading ? null : _downloadPng,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Đăng nhập ngay - đặt cuối cùng
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: FilledButton.icon(
                                icon: const Icon(Icons.login_rounded, size: 20),
                                label: const Text(
                                  'Đăng nhập ngay',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1565C0),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  Navigator.of(context)
                                      .popUntil((route) => route.isFirst);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Store Info Card ─────────────────────────────────────────────

class _StoreInfoCard extends StatefulWidget {
  final String storeName;
  final String storeCode;
  final String email;
  final String phone;
  final String? password;
  final void Function(String text, String label)? onCopy;

  const _StoreInfoCard({
    required this.storeName,
    required this.storeCode,
    required this.email,
    required this.phone,
    this.password,
    this.onCopy,
  });

  @override
  State<_StoreInfoCard> createState() => _StoreInfoCardState();
}

class _StoreInfoCardState extends State<_StoreInfoCard> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1B3A), Color(0xFF162447)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header with gradient ──
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
              ),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(23),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.store_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SBOX HRM',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.storeName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Body ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              children: [
                // Store code highlight
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1565C0).withValues(alpha: 0.2),
                        const Color(0xFF0D47A1).withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.key_rounded,
                              size: 14,
                              color: Colors.blue.shade300),
                          const SizedBox(width: 6),
                          Text(
                            'MÃ CỬA HÀNG',
                            style: TextStyle(
                              color: Colors.blue.shade300,
                              fontSize: 11,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.storeCode,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _CopyButton(
                            onTap: () => widget.onCopy
                                ?.call(widget.storeCode, 'mã cửa hàng'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Info items
                _InfoTile(
                  icon: Icons.email_outlined,
                  label: 'Email đăng nhập',
                  value: widget.email,
                  onCopy: () =>
                      widget.onCopy?.call(widget.email, 'email'),
                ),

                if (widget.password != null &&
                    widget.password!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _InfoTile(
                    icon: Icons.lock_outline_rounded,
                    label: 'Mật khẩu',
                    value:
                        _showPassword ? widget.password! : '••••••••',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => setState(
                              () => _showPassword = !_showPassword),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              _showPassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              key: ValueKey(_showPassword),
                              size: 18,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _CopyButton(
                          onTap: () => widget.onCopy
                              ?.call(widget.password!, 'mật khẩu'),
                        ),
                      ],
                    ),
                  ),
                ],

                if (widget.phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _InfoTile(
                    icon: Icons.phone_outlined,
                    label: 'Số điện thoại',
                    value: widget.phone,
                  ),
                ],

                const SizedBox(height: 2),
                _InfoTile(
                  icon: Icons.calendar_today_rounded,
                  label: 'Ngày đăng ký',
                  value: dateStr,
                ),

                const SizedBox(height: 20),

                // Warning banner
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 1),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFFF9800).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.info_outline_rounded,
                            color: Color(0xFFFFB74D), size: 14),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Bạn cần nhập MÃ CỬA HÀNG mỗi lần đăng nhập.\nHãy chụp ảnh hoặc tải PNG để lưu lại!',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFFFB74D),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Footer ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(23)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_rounded,
                    size: 13, color: Colors.blue.shade400),
                const SizedBox(width: 6),
                Text(
                  'SBOX HRM  •  Quản lý nhân sự thời gian thực',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info Tile ───────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onCopy;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.grey[400]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (onCopy != null && trailing == null)
            _CopyButton(onTap: onCopy!),
        ],
      ),
    );
  }
}

// ─── Copy Button ─────────────────────────────────────────────────

class _CopyButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CopyButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.copy_rounded,
              size: 15, color: Colors.blue.shade300),
        ),
      ),
    );
  }
}

// ─── Confetti Painter ────────────────────────────────────────────

class _ConfettiPainter extends CustomPainter {
  final double progress;
  static final List<_Particle> _particles = _generateParticles();

  _ConfettiPainter(this.progress);

  static List<_Particle> _generateParticles() {
    final rng = Random(42);
    return List.generate(40, (i) {
      return _Particle(
        x: rng.nextDouble(),
        startY: -0.1 - rng.nextDouble() * 0.3,
        speed: 0.5 + rng.nextDouble() * 0.7,
        size: 3 + rng.nextDouble() * 5,
        color: [
          const Color(0xFF42A5F5),
          const Color(0xFF66BB6A),
          const Color(0xFFFFCA28),
          const Color(0xFFEF5350),
          const Color(0xFFAB47BC),
          const Color(0xFF26C6DA),
        ][i % 6],
        rotation: rng.nextDouble() * 3.14,
        drift: (rng.nextDouble() - 0.5) * 0.3,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1.0) return;
    final opacity = (1.0 - progress).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    for (final p in _particles) {
      final y = p.startY + p.speed * progress;
      if (y > 1.1) continue;
      final x = p.x + p.drift * progress;

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity * 0.8)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(p.rotation + progress * 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _Particle {
  final double x, startY, speed, size, rotation, drift;
  final Color color;
  const _Particle({
    required this.x,
    required this.startY,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotation,
    required this.drift,
  });
}
