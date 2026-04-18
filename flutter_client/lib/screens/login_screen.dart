import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../widgets/notification_overlay.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _storeCodeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const String _prefRememberMe = 'remember_me';
  static const String _prefStoreCode = 'saved_store_code';
  static const String _prefEmail = 'saved_email';

  @override
  void initState() {
    super.initState();
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
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool(_prefRememberMe) ?? false;
      if (rememberMe) {
        setState(() {
          _rememberMe = rememberMe;
          _storeCodeController.text = prefs.getString(_prefStoreCode) ?? '';
          _emailController.text = prefs.getString(_prefEmail) ?? '';
        });
      }
      // Clean up any previously saved password
      await prefs.remove('saved_password');
    } catch (e) {
      debugPrint('Error loading saved credentials: $e');
    }
  }

  Future<void> _saveCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool(_prefRememberMe, true);
        await prefs.setString(_prefStoreCode, _storeCodeController.text.trim());
        await prefs.setString(_prefEmail, _emailController.text.trim());
      } else {
        await prefs.remove(_prefRememberMe);
        await prefs.remove(_prefStoreCode);
        await prefs.remove(_prefEmail);
      }
      // Always clean up any previously saved password
      await prefs.remove('saved_password');
    } catch (e) {
      debugPrint('Error saving credentials: $e');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    _storeCodeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.login(
        _storeCodeController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (success && mounted) {
        await _saveCredentials();
      } else if (!success && mounted) {
        final errMsg = authProvider.error ?? 'Đăng nhập thất bại';
        setState(() => _errorMessage = errMsg);
        NotificationOverlayManager().showError(title: 'Đăng nhập thất bại', message: errMsg);
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Không thể kết nối đến server');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 900;

    return Scaffold(
      body: isDesktop ? _buildDesktopLayout(size) : _buildMobileLayout(size),
    );
  }

  // ====== DESKTOP: Split layout (left hero 7/12 + right form 5/12) ======
  Widget _buildDesktopLayout(Size size) {
    return Row(
      children: [
        // ===== LEFT PANEL: Hero (7/12) =====
        Expanded(
          flex: 7,
          child: _buildHeroPanel(),
        ),
        // ===== RIGHT PANEL: Form (5/12) =====
        Expanded(
          flex: 5,
          child: _buildFormPanel(isDesktop: true),
        ),
      ],
    );
  }

  // ====== MOBILE: Form only ======
  Widget _buildMobileLayout(Size size) {
    return _buildFormPanel(isDesktop: false);
  }

  // ===== Hero Panel (Left side) - ảnh nền + gradient overlay =====
  Widget _buildHeroPanel() {
    const imageUrl =
        'https://lh3.googleusercontent.com/aida-public/AB6AXuD6gKf5JQatbloDEXQAJyi7OUPnQiNzZORiDKYsBmYfd5RGNvPEOgNyL1K1NW3zrx3NMlwn7vfdnRQpjFl4njRzguVyN7-OTnFC3uKzO2NZxboaxRf0he8vwScXzAANWuVj-B3bWWox3NkiwL3EkbqgZsCF4UvY0S92s_ryURmITms5q7pfRNqenj848647ByfIGa-yEIcjh6nJXtHIPjZSgoX4keaiY1mtAA6DV5k-naedu6M8dnZQTEshrBgVY6JQ7G3-wOdyCsoG';

    return Container(
      color: const Color(0xFFDAE2FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image - AI face recognition photo
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            opacity: const AlwaysStoppedAnimation(0.9),
            errorBuilder: (context, error, stackTrace) {
              // Fallback: gradient + icon if image fails to load
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
                    Icons.face_retouching_natural,
                    size: 180,
                    color: const Color(0xFF0C56D0).withValues(alpha: 0.2),
                  ),
                ),
              );
            },
          ),
          // Gradient overlay: from-primary/60 via-primary/20 to-transparent (top-right direction)
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
          // Content overlay at bottom - justify-end p-20
          Positioned(
            left: 56,
            right: 56,
            bottom: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badge - rounded-full bg-white/20 backdrop-blur
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Title - font-headline text-5xl font-extrabold
                const Text(
                  'Quản lý nhân sự\nthời gian thực',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 16),
                // Description - text-white/80 text-lg
                Text(
                  'Hệ thống quản lý và vận hành nhân sự công nghệ mới,\nChấm công nhanh và Tính lương chuẩn.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 15,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 40),
                // Glass stat card - glass-card with backdrop blur effect
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
                        child: const Icon(Icons.trending_up_rounded, color: Color(0xFF0C56D0), size: 20),
                      ),
                      const SizedBox(width: 16),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HIỆU QUẢ CÔNG VIỆC',
                            style: TextStyle(color: Color(0xFF586064), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'TĂNG 100%',
                            style: TextStyle(color: Color(0xFF0C56D0), fontSize: 18, fontWeight: FontWeight.w800),
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
                          // Welcome text
                          Align(
                            alignment: isDesktop ? Alignment.centerLeft : Alignment.center,
                            child: const Text(
                              'Chào mừng trở lại',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2B3437),
                                letterSpacing: -0.3,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: isDesktop ? Alignment.centerLeft : Alignment.center,
                            child: const Text(
                              'Nhập thông tin để truy cập hệ thống quản trị.',
                              style: TextStyle(color: Color(0xFF586064), fontSize: 14, height: 1.5),
                            ),
                          ),
                          const SizedBox(height: 32),

                      // Form
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_errorMessage != null) ...[
                              _buildErrorBanner(_errorMessage!),
                              const SizedBox(height: 20),
                            ],

                            // Store Code
                            _buildLabel('TÊN CỬA HÀNG'),
                            const SizedBox(height: 8),
                            _buildField(
                              controller: _storeCodeController,
                              hint: 'Ví dụ: SBOX-HQ',
                              icon: Icons.storefront_rounded,
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Vui lòng nhập mã cửa hàng' : null,
                            ),
                            const SizedBox(height: 20),

                            // Email
                            _buildLabel('EMAIL / SĐT'),
                            const SizedBox(height: 8),
                            _buildField(
                              controller: _emailController,
                              hint: 'Email hoặc số điện thoại',
                              icon: Icons.person_outline_rounded,
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Vui lòng nhập email hoặc số điện thoại' : null,
                            ),
                            const SizedBox(height: 20),

                            // Password
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildLabel('MẬT KHẨU'),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pushNamed('/forgot-password'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF0C56D0),
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('Quên mật khẩu?',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
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
                                if (v.length < 6) return 'Mật khẩu phải có ít nhất 6 ký tự';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Remember me
                            GestureDetector(
                              onTap: () => setState(() => _rememberMe = !_rememberMe),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 20, height: 20,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                      side: BorderSide(color: const Color(0xFFABB3B7).withValues(alpha: 0.3)),
                                      checkColor: Colors.white,
                                      fillColor: WidgetStateProperty.resolveWith(
                                        (s) => s.contains(WidgetState.selected)
                                            ? const Color(0xFF3B82F6)
                                            : Colors.transparent,
                                      ),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text('Ghi nhớ đăng nhập',
                                      style: TextStyle(color: Color(0xFF586064), fontSize: 14)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Login button - gradient from primary to primary-dim
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
                                  onPressed: _isLoading ? null : _handleLogin,
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
                                            Text('Đăng nhập',
                                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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

                      // Register link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Chưa có tài khoản?',
                              style: TextStyle(color: Color(0xFF586064), fontSize: 14, height: 1.5)),
                          TextButton(
                            onPressed: () => Navigator.of(context).pushNamed('/register'),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFF0C56D0)),
                            child: const Text('Đăng ký ngay',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Color(0xFF0C56D0),
                                )),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),

                      // Platform icons
                      Opacity(
                        opacity: 0.5,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildPlatformIcon(Icons.language, 'WEB'),
                            const SizedBox(width: 32),
                            _buildPlatformIcon(Icons.apple, 'IOS'),
                            const SizedBox(width: 32),
                            _buildPlatformIcon(Icons.android, 'ANDROID'),
                          ],
                        ),
                      ),
                      // Spacing for footer
                      const SizedBox(height: 80),
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
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.3),
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
          : Stack(
              children: [
                scrollContent,
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 20,
                  child: IgnorePointer(
                    ignoring: MediaQuery.of(context).viewInsets.bottom > 0,
                    child: AnimatedOpacity(
                      opacity: MediaQuery.of(context).viewInsets.bottom > 0 ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
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
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildLogo({bool isDesktop = false}) {
    return Row(
      mainAxisAlignment: isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset('assets/logo.png', width: 44, height: 44),
        ),
        const SizedBox(width: 14),
        const Text(
          'SBOX HRM',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0C56D0),
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildFooterLink(String text) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF586064),
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildPlatformIcon(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF0F2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF586064), size: 24),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Color(0xFF586064), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, height: 1.4)),
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
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(color: Color(0xFF2B3437), fontSize: 15, height: 1.5),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFABB3B7), fontSize: 14, height: 1.5),
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
