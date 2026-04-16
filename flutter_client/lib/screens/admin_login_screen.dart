import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberMe = false;
  bool _isSetupMode = false;
  String? _errorMessage;
  String? _successMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const String _prefAdminRememberMe = 'admin_remember_me';
  static const String _prefAdminEmail = 'admin_saved_email';

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
      final rememberMe = prefs.getBool(_prefAdminRememberMe) ?? false;
      if (rememberMe) {
        setState(() {
          _rememberMe = rememberMe;
          _emailController.text = prefs.getString(_prefAdminEmail) ?? '';
        });
      }
      // Clean up any previously saved password
      await prefs.remove('admin_saved_password');
    } catch (e) {
      debugPrint('Error loading admin credentials: $e');
    }
  }

  Future<void> _saveCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool(_prefAdminRememberMe, true);
        await prefs.setString(_prefAdminEmail, _emailController.text.trim());
      } else {
        await prefs.remove(_prefAdminRememberMe);
        await prefs.remove(_prefAdminEmail);
      }
      // Always clean up any previously saved password
      await prefs.remove('admin_saved_password');
    } catch (e) {
      debugPrint('Error saving admin credentials: $e');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
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
        '',
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (success && mounted) {
        await _saveCredentials();
        final role = authProvider.userRole;
        if (role != 'SuperAdmin' && role != 'Agent') {
          await authProvider.logout();
          setState(() {
            _errorMessage = 'Tài khoản không có quyền truy cập quản trị hệ thống';
          });
        }
      } else if (!success && mounted) {
        setState(() {
          _errorMessage = authProvider.error ?? 'Đăng nhập thất bại';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Không thể kết nối đến server');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final result = await ApiService().setupSuperAdmin(
        _emailController.text.trim(),
        _passwordController.text,
        _fullNameController.text.trim().isEmpty
            ? null
            : _fullNameController.text.trim(),
      );

      if (mounted) {
        if (result['isSuccess'] == true) {
          setState(() {
            _successMessage = result['data'] ?? 'Tạo SuperAdmin thành công! Hãy đăng nhập.';
            _isSetupMode = false;
            _confirmPasswordController.clear();
            _fullNameController.clear();
          });
        } else {
          setState(() {
            _errorMessage = result['message'] ?? 'Không thể tạo SuperAdmin';
          });
        }
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

    return Scaffold(
      body: Stack(
        children: [
          // Dark gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0C0C1D), Color(0xFF1A1035), Color(0xFF0C0C1D)],
              ),
            ),
          ),

          // Decorative orbs
          Positioned(
            top: -size.height * 0.1,
            left: -size.width * 0.15,
            child: Container(
              width: size.width * 0.6,
              height: size.width * 0.6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF7C3AED).withValues(alpha: 0.12), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -size.height * 0.08,
            right: -size.width * 0.1,
            child: Container(
              width: size.width * 0.45,
              height: size.width * 0.45,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF6366F1).withValues(alpha: 0.10), Colors.transparent],
                ),
              ),
            ),
          ),

          // Floating dots
          ...List.generate(6, (i) {
            final r = math.Random(i * 13);
            return Positioned(
              top: r.nextDouble() * size.height,
              left: r.nextDouble() * size.width,
              child: Container(
                width: 3 + r.nextDouble() * 3,
                height: 3 + r.nextDouble() * 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06 + r.nextDouble() * 0.08),
                ),
              ),
            );
          }),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Brand header
                          _buildBrandHeader(),
                          const SizedBox(height: 36),

                          // Glass card
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 40,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Admin badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.2)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _isSetupMode ? Icons.rocket_launch_rounded : Icons.shield_rounded,
                                            color: const Color(0xFFA78BFA), size: 18,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _isSetupMode
                                                  ? 'Khởi tạo tài khoản SuperAdmin đầu tiên cho hệ thống'
                                                  : 'Khu vực quản trị dành cho SuperAdmin và Agent',
                                              style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    if (_successMessage != null) ...[
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF86EFAC), size: 20),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(_successMessage!,
                                                  style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 13)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                    ],

                                    if (_errorMessage != null) ...[
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.error_outline_rounded, color: Color(0xFFFCA5A5), size: 20),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(_errorMessage!,
                                                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                    ],

                                    // Full name (setup mode only)
                                    if (_isSetupMode) ...[
                                      _buildGlassField(
                                        controller: _fullNameController,
                                        label: 'Họ và tên',
                                        hint: 'Nhập họ tên SuperAdmin',
                                        icon: Icons.person_rounded,
                                      ),
                                      const SizedBox(height: 18),
                                    ],

                                    // Email
                                    _buildGlassField(
                                      controller: _emailController,
                                      label: 'Email',
                                      hint: _isSetupMode ? 'Nhập email SuperAdmin' : 'Nhập email quản trị',
                                      icon: Icons.email_rounded,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (v) => (v == null || v.isEmpty) ? 'Vui lòng nhập email' : null,
                                    ),
                                    const SizedBox(height: 18),

                                    // Password
                                    _buildGlassField(
                                      controller: _passwordController,
                                      label: 'Mật khẩu',
                                      hint: 'Nhập mật khẩu',
                                      icon: Icons.lock_rounded,
                                      obscure: _obscurePassword,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                          color: Colors.white38, size: 20,
                                        ),
                                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu';
                                        if (v.length < 6) return 'Mật khẩu phải có ít nhất 6 ký tự';
                                        return null;
                                      },
                                    ),

                                    // Confirm password (setup mode only)
                                    if (_isSetupMode) ...[
                                      const SizedBox(height: 18),
                                      _buildGlassField(
                                        controller: _confirmPasswordController,
                                        label: 'Xác nhận mật khẩu',
                                        hint: 'Nhập lại mật khẩu',
                                        icon: Icons.lock_outline_rounded,
                                        obscure: _obscureConfirmPassword,
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscureConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                            color: Colors.white38, size: 20,
                                          ),
                                          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                        ),
                                        validator: (v) {
                                          if (v == null || v.isEmpty) return 'Vui lòng xác nhận mật khẩu';
                                          if (v != _passwordController.text) return 'Mật khẩu không khớp';
                                          return null;
                                        },
                                      ),
                                    ],

                                    // Remember me (login mode only)
                                    if (!_isSetupMode) ...[
                                      const SizedBox(height: 12),
                                      GestureDetector(
                                        onTap: () => setState(() => _rememberMe = !_rememberMe),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 20, height: 20,
                                              child: Checkbox(
                                                value: _rememberMe,
                                                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                                side: const BorderSide(color: Colors.white24),
                                                checkColor: Colors.white,
                                                fillColor: WidgetStateProperty.resolveWith(
                                                  (s) => s.contains(WidgetState.selected)
                                                      ? const Color(0xFF7C3AED)
                                                      : Colors.transparent,
                                                ),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text('Nhớ đăng nhập',
                                                style: TextStyle(color: Colors.white38, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 24),

                                    // Action button
                                    SizedBox(
                                      height: 52,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: _isSetupMode
                                                ? [const Color(0xFF16A34A), const Color(0xFF15803D)]
                                                : [const Color(0xFF7C3AED), const Color(0xFF6D28D9)],
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (_isSetupMode
                                                      ? const Color(0xFF16A34A)
                                                      : const Color(0xFF7C3AED))
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 18,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton(
                                          onPressed: _isLoading
                                              ? null
                                              : (_isSetupMode ? _handleSetup : _handleLogin),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 24, height: 24,
                                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                                )
                                              : Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      _isSetupMode
                                                          ? Icons.rocket_launch_rounded
                                                          : Icons.admin_panel_settings_rounded,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _isSetupMode
                                                          ? 'Khởi tạo SuperAdmin'
                                                          : 'Đăng nhập quản trị',
                                                      style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.w600,
                                                          letterSpacing: 0.5),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Toggle setup/login mode
                                    Center(
                                      child: TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _isSetupMode = !_isSetupMode;
                                            _errorMessage = null;
                                            _successMessage = null;
                                            _formKey.currentState?.reset();
                                          });
                                        },
                                        style: TextButton.styleFrom(foregroundColor: Colors.white54),
                                        child: Text(
                                          _isSetupMode
                                              ? '← Quay lại đăng nhập'
                                              : 'Chưa có SuperAdmin? Khởi tạo tài khoản',
                                          style: const TextStyle(fontSize: 13, decoration: TextDecoration.underline, decorationColor: Colors.white38),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Link back
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Đăng nhập cửa hàng?',
                                  style: TextStyle(color: Colors.white38, fontSize: 14)),
                              TextButton(
                                onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false),
                                style: TextButton.styleFrom(foregroundColor: Colors.white),
                                child: const Text('Về trang chủ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 14,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Colors.white54,
                                    )),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.admin_panel_settings_rounded, size: 44, color: Colors.white),
        ),
        const SizedBox(height: 20),
        const Text(
          'SBOX HRM',
          style: TextStyle(
            fontSize: 34, fontWeight: FontWeight.w800,
            color: Colors.white, letterSpacing: 2.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Quản trị hệ thống',
          style: TextStyle(
            color: Colors.white54, fontSize: 15, fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  static Widget _buildGlassField({
    required TextEditingController controller,
    required String label,
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
      style: const TextStyle(color: Colors.white, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 14),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.18), fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.white24, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFA78BFA), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFCA5A5)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFCA5A5), width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFCA5A5)),
      ),
    );
  }
}
