import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'store_success_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _storeNameController = TextEditingController();
  final _loginNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _loginNameManuallyEdited = false;
  String? _errorMessage;
  String? _successMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _storeNameController.addListener(_onStoreNameChanged);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  void _onStoreNameChanged() {
    if (!_loginNameManuallyEdited) {
      _loginNameController.text = _generateLoginName(_storeNameController.text);
    }
  }

  static String _generateLoginName(String storeName) {
    var code = storeName.toLowerCase().trim();
    code = _removeVietnameseAccents(code);
    code = code.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (code.length > 20) code = code.substring(0, 20);
    return code;
  }

  static String _removeVietnameseAccents(String text) {
    const vietnamese = [
      'aàảãáạăằẳẵắặâầẩẫấậ',
      'dđ',
      'eèẻẽéẹêềểễếệ',
      'iìỉĩíị',
      'oòỏõóọôồổỗốộơờởỡớợ',
      'uùủũúụưừửữứự',
      'yỳỷỹýỵ',
    ];
    for (final chars in vietnamese) {
      for (int i = 1; i < chars.length; i++) {
        text = text.replaceAll(chars[i], chars[0]);
      }
    }
    return text;
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    _storeNameController.removeListener(_onStoreNameChanged);
    _storeNameController.dispose();
    _loginNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _navigateToSuccessScreen(String storeCode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoreSuccessScreen(
          storeName: _storeNameController.text.trim(),
          storeCode: storeCode,
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          password: _passwordController.text,
        ),
      ),
    );
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final apiService = ApiService();
      final result = await apiService.register(
        _storeNameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
        phoneNumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        storeCode: _loginNameController.text.trim(),
      );

      if (result['isSuccess'] == true) {
        final message = result['data'] as String? ?? 'Đăng ký thành công!';
        final codeMatch = RegExp(r'Mã cửa hàng của bạn là:\s*(\S+)').firstMatch(message);
        final storeCode = codeMatch?.group(1)?.replaceAll('.', '') ?? _loginNameController.text.trim();
        if (mounted) {
          _navigateToSuccessScreen(storeCode);
        }
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Đăng ký thất bại';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Không thể kết nối đến server';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 900;

    return Scaffold(
      body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

  // ====== DESKTOP: Split layout (left hero 7/12 + right form 5/12) ======
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Expanded(
          flex: 7,
          child: _buildHeroPanel(),
        ),
        Expanded(
          flex: 5,
          child: _buildFormPanel(isDesktop: true),
        ),
      ],
    );
  }

  // ====== MOBILE: Form only ======
  Widget _buildMobileLayout() {
    return _buildFormPanel(isDesktop: false);
  }

  // ===== Hero Panel (Left side) =====
  Widget _buildHeroPanel() {
    const imageUrl =
        'https://lh3.googleusercontent.com/aida-public/AB6AXuD6gKf5JQatbloDEXQAJyi7OUPnQiNzZORiDKYsBmYfd5RGNvPEOgNyL1K1NW3zrx3NMlwn7vfdnRQpjFl4njRzguVyN7-OTnFC3uKzO2NZxboaxRf0he8vwScXzAANWuVj-B3bWWox3NkiwL3EkbqgZsCF4UvY0S92s_ryURmITms5q7pfRNqenj848647ByfIGa-yEIcjh6nJXtHIPjZSgoX4keaiY1mtAA6DV5k-naedu6M8dnZQTEshrBgVY6JQ7G3-wOdyCsoG';

    return Container(
      color: const Color(0xFFDAE2FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            opacity: const AlwaysStoppedAnimation(0.9),
            errorBuilder: (context, error, stackTrace) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFDAE2FF),
                      const Color(0xFF0C56D0).withValues(alpha: 0.3),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.store_rounded,
                    size: 180,
                    color: const Color(0xFF0C56D0).withValues(alpha: 0.2),
                  ),
                ),
              );
            },
          ),
          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    const Color(0xFF0C56D0).withValues(alpha: 0.60),
                    const Color(0xFF0C56D0).withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // Content overlay at bottom
          Positioned(
            left: 56,
            right: 56,
            bottom: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'SBOX HRM',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Bắt đầu hành trình\nquản lý nhân sự',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Đăng ký doanh nghiệp để sử dụng hệ thống\nquản lý nhân sự thông minh.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 17,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 40),
                // Glass stat card
                Container(
                  padding: const EdgeInsets.all(22),
                  constraints: const BoxConstraints(maxWidth: 280),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 40,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C56D0).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF0C56D0), size: 20),
                      ),
                      const SizedBox(width: 16),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'THIẾT LẬP NHANH',
                            style: TextStyle(color: Color(0xFF586064), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'CHỈ 2 PHÚT',
                            style: TextStyle(color: Color(0xFF0C56D0), fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== Form Panel (Right side / Mobile) =====
  Widget _buildFormPanel({required bool isDesktop}) {
    final scrollContent = Center(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 60 : 24,
                  vertical: 32,
                ),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo
                          _buildLogo(isDesktop: isDesktop),
                          const SizedBox(height: 36),
                          // Title
                          Align(
                            alignment: isDesktop ? Alignment.centerLeft : Alignment.center,
                            child: const Text(
                              'Đăng ký doanh nghiệp',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2B3437),
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: isDesktop ? Alignment.centerLeft : Alignment.center,
                            child: const Text(
                              'Tạo tài khoản doanh nghiệp mới để bắt đầu.',
                              style: TextStyle(color: Color(0xFF586064), fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Form
                          Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Success message
                                if (_successMessage != null) ...[
                                  _buildBanner(_successMessage!, isError: false),
                                  const SizedBox(height: 20),
                                ],
                                // Error message
                                if (_errorMessage != null) ...[
                                  _buildBanner(_errorMessage!, isError: true),
                                  const SizedBox(height: 20),
                                ],

                                // Store name
                                _buildLabel('TÊN DOANH NGHIỆP'),
                                const SizedBox(height: 8),
                                _buildField(
                                  controller: _storeNameController,
                                  hint: 'Nhập tên doanh nghiệp của bạn',
                                  icon: Icons.store_rounded,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Vui lòng nhập tên doanh nghiệp';
                                    if (v.length < 2) return 'Tên doanh nghiệp phải có ít nhất 2 ký tự';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Login name (auto-generated)
                                _buildLabel('TÊN ĐĂNG NHẬP (MÃ DOANH NGHIỆP)'),
                                const SizedBox(height: 8),
                                _buildField(
                                  controller: _loginNameController,
                                  hint: 'Tự động tạo từ tên doanh nghiệp',
                                  icon: Icons.badge_rounded,
                                  onChanged: (value) {
                                    if (!_loginNameManuallyEdited) {
                                      setState(() => _loginNameManuallyEdited = true);
                                    }
                                  },
                                  suffixIcon: _loginNameManuallyEdited
                                      ? IconButton(
                                          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF0C56D0), size: 20),
                                          tooltip: 'Tạo lại từ tên doanh nghiệp',
                                          onPressed: () {
                                            setState(() {
                                              _loginNameManuallyEdited = false;
                                              _loginNameController.text = _generateLoginName(_storeNameController.text);
                                            });
                                          },
                                        )
                                      : null,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Vui lòng nhập tên đăng nhập';
                                    if (v.length < 2) return 'Tên đăng nhập phải có ít nhất 2 ký tự';
                                    if (!RegExp(r'^[a-z0-9]+$').hasMatch(v)) return 'Chỉ chấp nhận chữ thường và số, không dấu';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Email
                                _buildLabel('EMAIL'),
                                const SizedBox(height: 8),
                                _buildField(
                                  controller: _emailController,
                                  hint: 'Nhập email đăng nhập',
                                  icon: Icons.email_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Vui lòng nhập email';
                                    if (!RegExp(r'^[\w\.\-]+@[\w\.\-]+\.\w+$').hasMatch(v.trim())) return 'Email không hợp lệ';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Phone
                                _buildLabel('SỐ ĐIỆN THOẠI (TÙY CHỌN)'),
                                const SizedBox(height: 8),
                                _buildField(
                                  controller: _phoneController,
                                  hint: 'Nhập số điện thoại',
                                  icon: Icons.phone_rounded,
                                  keyboardType: TextInputType.phone,
                                  validator: (v) {
                                    if (v != null && v.isNotEmpty) {
                                      if (!RegExp(r'^\+?[0-9]{9,15}$').hasMatch(v)) return 'Số điện thoại không hợp lệ';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Password
                                _buildLabel('MẬT KHẨU'),
                                const SizedBox(height: 8),
                                _buildField(
                                  controller: _passwordController,
                                  hint: 'Nhập mật khẩu',
                                  icon: Icons.lock_outline_rounded,
                                  obscure: _obscurePassword,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      color: const Color(0xFFABB3B7), size: 20,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu';
                                    if (v.length < 8) return 'Mật khẩu phải có ít nhất 8 ký tự';
                                    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Phải có ít nhất 1 chữ hoa';
                                    if (!RegExp(r'[a-z]').hasMatch(v)) return 'Phải có ít nhất 1 chữ thường';
                                    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Phải có ít nhất 1 chữ số';
                                    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(v)) return 'Phải có ít nhất 1 ký tự đặc biệt';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Confirm password
                                _buildLabel('XÁC NHẬN MẬT KHẨU'),
                                const SizedBox(height: 8),
                                _buildField(
                                  controller: _confirmPasswordController,
                                  hint: 'Nhập lại mật khẩu',
                                  icon: Icons.lock_outline_rounded,
                                  obscure: _obscureConfirmPassword,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      color: const Color(0xFFABB3B7), size: 20,
                                    ),
                                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Vui lòng xác nhận mật khẩu';
                                    if (v != _passwordController.text) return 'Mật khẩu không khớp';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 28),

                                // Register button
                                SizedBox(
                                  height: 54,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [Color(0xFF0C56D0), Color(0xFF004ABA)],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF0C56D0).withValues(alpha: 0.25),
                                          blurRadius: 16,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _handleRegister,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 22, height: 22,
                                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                            )
                                          : const Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text('Đăng ký doanh nghiệp',
                                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                                SizedBox(width: 8),
                                                Icon(Icons.arrow_forward, size: 18),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Login link
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Đã có tài khoản?',
                                  style: TextStyle(color: Color(0xFF586064), fontSize: 14)),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: TextButton.styleFrom(foregroundColor: const Color(0xFF0C56D0)),
                                child: const Text('Đăng nhập',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 14,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Color(0xFF0C56D0),
                                    )),
                              ),
                            ],
                          ),
                          // Spacing for footer (desktop only)
                          if (isDesktop) const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
    );

    return Container(
      color: const Color(0xFFF8F9FA),
      child: SafeArea(
        child: isDesktop
          ? Stack(
              children: [
                scrollContent,
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '@2026 SBOX HRM HỆ THỐNG QUẢN TRỊ NHÂN SỰ',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFooterLink('TÌM HIỂU THÊM'),
                          const SizedBox(width: 16),
                          _buildFooterLink('LIÊN HỆ'),
                          const SizedBox(width: 16),
                          _buildFooterLink('HỖ TRỢ'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(child: scrollContent),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildFooterLink('TÌM HIỂU THÊM'),
                          const SizedBox(width: 16),
                          _buildFooterLink('LIÊN HỆ'),
                          const SizedBox(width: 16),
                          _buildFooterLink('HỖ TRỢ'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '@2026 SBOX HRM HỆ THỐNG QUẢN TRỊ NHÂN SỰ',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  // ===== Reusable widgets matching login screen =====

  Widget _buildLogo({bool isDesktop = false}) {
    return Row(
      mainAxisAlignment: isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.bubble_chart, color: Color(0xFF0C56D0), size: 44),
        SizedBox(width: 14),
        Text(
          'SBOX HRM',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0C56D0),
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  static Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF586064),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildFooterLink(String text) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildBanner(String message, {required bool isError}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      onChanged: onChanged,
      style: const TextStyle(color: Color(0xFF2B3437), fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFABB3B7), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFFABB3B7), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: const Color(0xFFABB3B7).withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: const Color(0xFFABB3B7).withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF0C56D0), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFF87171), width: 2),
        ),
        errorStyle: const TextStyle(color: Color(0xFFEF4444)),
      ),
    );
  }
}
