import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/app_permission_service.dart';
import '../services/pos_app_update_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_form_keyboard.dart';
import '../widgets/pos_app_update_dialog.dart';
import '../widgets/store_agent_support_card.dart';
import '../utils/web_marketing_gate_stub.dart'
    if (dart.library.html) '../utils/web_marketing_gate_web.dart' as web_home;
import 'package:sbox_pos/l10n/app_tr.dart';
import 'forgot_password_screen.dart';

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
  static const String _prefAdminEmail = 'admin_saved_email';

  // Footer link URLs (loaded from /api/publicsettings, with safe defaults)
  String? _learnMoreUrl;
  String? _contactUrl;
  String? _supportUrl;
  String? _websiteUrl;
  String _phoneNumber = '0973 024 042';
  String _zaloNumber = '0973024042';
  Map<String, dynamic>? _storeAgentContact;
  Timer? _agentLookupDebounce;
  String _appVersionLabel = '';

  String get _siteOrigin {
    var origin = ApiService.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    if (!origin.startsWith('http')) origin = 'https://$origin';
    return origin.replaceAll(RegExp(r'/+$'), '');
  }

  String get _phoneDigits => _phoneNumber.replaceAll(RegExp(r'\s+'), '');

  String get _zaloDigits {
    final agentZalo = _storeAgentContact?['zaloUrl']?.toString();
    if (agentZalo != null && agentZalo.isNotEmpty) {
      return agentZalo
          .replaceAll('https://zalo.me/', '')
          .replaceAll(RegExp(r'\s+'), '');
    }
    return _zaloNumber
        .replaceAll('https://zalo.me/', '')
        .replaceAll(RegExp(r'\s+'), '');
  }

  String get _supportPhoneDisplay {
    final agentPhone = _storeAgentContact?['phone']?.toString();
    if (agentPhone != null && agentPhone.isNotEmpty) return agentPhone;
    return _phoneNumber;
  }

  String get _supportPhoneDigits =>
      _supportPhoneDisplay.replaceAll(RegExp(r'\s+'), '');

  bool _isLicenseExpiredMessage(String message) =>
      message.toLowerCase().contains('hết hạn sử dụng');

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
    ).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
    _loadSavedCredentials();
    _loadPublicSettings();
    _loadAppVersion();
    _storeCodeController.addListener(_onStoreCodeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppPermissionService.promptEssentialPermissionsIfNeeded(context);
      final authError = context.read<AuthProvider>().error;
      if (authError != null && authError.isNotEmpty) {
        setState(() => _errorMessage = authError);
      }
      // QA: adb push file → one-shot login (file tự xóa).
      unawaited(_tryAdbAutologinHook());
    });
  }

  /// One-shot QA login via adb:
  /// `adb push autologin.json /sdcard/sbox_pos_autologin.json`
  /// JSON: `{"storeCode":"demopos","userName":"demopos@gmail.com","password":"123456"}`
  Future<void> _tryAdbAutologinHook() async {
    if (kIsWeb || !Platform.isAndroid) return;
    const paths = <String>[
      '/sdcard/sbox_pos_autologin.json',
      '/storage/emulated/0/sbox_pos_autologin.json',
      '/sdcard/Android/data/sbox.sana.vn.pos.flutter/files/sbox_pos_autologin.json',
    ];
    for (final path in paths) {
      try {
        final f = File(path);
        if (!await f.exists()) continue;
        final raw = await f.readAsString();
        try {
          await f.delete();
        } catch (_) {}
        final map = jsonDecode(raw);
        if (map is! Map) return;
        final store = '${map['storeCode'] ?? ''}'.trim();
        final user = '${map['userName'] ?? map['email'] ?? ''}'.trim();
        final pass = '${map['password'] ?? ''}'.trim();
        if (store.isEmpty || user.isEmpty || pass.isEmpty) return;
        if (!mounted) return;
        setState(() {
          _storeCodeController.text = store;
          _emailController.text = user;
          _passwordController.text = pass;
          _rememberMe = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted || _isLoading) return;
        await _handleLogin();
        return;
      } catch (_) {
        // thử path tiếp theo
      }
    }
  }

  void _onStoreCodeChanged() {
    _agentLookupDebounce?.cancel();
    _agentLookupDebounce = Timer(const Duration(milliseconds: 500), () {
      _loadStoreAgentContact(_storeCodeController.text.trim());
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersionLabel = 'v${info.version} (${info.buildNumber})';
      });
    } catch (_) {}
  }

  Future<void> _loadStoreAgentContact(String storeCode) async {
    if (storeCode.isEmpty) {
      if (mounted) setState(() => _storeAgentContact = null);
      return;
    }
    try {
      final res =
          await ApiService().getStoreAgentContactByStoreCode(storeCode);
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] != null) {
        setState(() =>
            _storeAgentContact = Map<String, dynamic>.from(res['data'] as Map));
      } else {
        setState(() => _storeAgentContact = null);
      }
    } catch (_) {
      if (mounted) setState(() => _storeAgentContact = null);
    }
  }

  Future<void> _loadPublicSettings() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/publicsettings'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final body = json.decode(res.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return;
      String? pickNullable(String key) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        return null;
      }

      if (!mounted) return;
      setState(() {
        _learnMoreUrl = pickNullable('learnMoreUrl');
        _contactUrl = pickNullable('contactUrl');
        _supportUrl = pickNullable('supportUrl');
        _websiteUrl = pickNullable('websiteUrl');
        _phoneNumber = pickNullable('technicalSupportPhone') ??
            pickNullable('salesPhone') ??
            _phoneNumber;
        final zaloRaw = pickNullable('zaloUrl');
        if (zaloRaw != null) {
          _zaloNumber = zaloRaw
              .replaceAll('https://zalo.me/', '')
              .replaceAll(RegExp(r'\s+'), '');
        }
      });
    } catch (e) {
      debugPrint('LoginScreen public settings load failed: $e');
    }
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool(_prefRememberMe) ?? false;
      // Always pre-fill saved store code + email (even if rememberMe is false)
      // so users don't need to re-enter them after logout.
      final savedStore = prefs.getString(_prefStoreCode) ?? '';
      final savedEmail = prefs.getString(_prefEmail) ?? '';
      final adminEmail = prefs.getString(_prefAdminEmail) ?? '';
      final isAdminPortalEmail = adminEmail.isNotEmpty &&
          savedEmail.isNotEmpty &&
          savedEmail.toLowerCase() == adminEmail.toLowerCase();
      if (savedStore.isNotEmpty || savedEmail.isNotEmpty || rememberMe) {
        setState(() {
          _rememberMe = rememberMe;
          // Tránh đăng nhập SuperAdmin nhầm qua mã cửa hàng đã lưu trước đó.
          _storeCodeController.text = isAdminPortalEmail ? '' : savedStore;
          _emailController.text = savedEmail;
        });
        if (!isAdminPortalEmail && savedStore.isNotEmpty) {
          _loadStoreAgentContact(savedStore);
        }
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
      // Always remember the last-used store code + email so logout preserves identity.
      await prefs.setString(_prefStoreCode, _storeCodeController.text.trim());
      await prefs.setString(_prefEmail, _emailController.text.trim());
      // rememberMe flag only controls whether to keep the session / auto-login feel.
      if (_rememberMe) {
        await prefs.setBool(_prefRememberMe, true);
      } else {
        await prefs.remove(_prefRememberMe);
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
    _agentLookupDebounce?.cancel();
    _storeCodeController.removeListener(_onStoreCodeChanged);
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
      final email = _emailController.text.trim();
      final prefs = await SharedPreferences.getInstance();
      final adminEmail = prefs.getString(_prefAdminEmail) ?? '';
      var storeCode = _storeCodeController.text.trim();
      if (adminEmail.isNotEmpty &&
          email.toLowerCase() == adminEmail.toLowerCase()) {
        storeCode = '';
      }
      final success = await authProvider.login(
        storeCode,
        email,
        _passwordController.text,
      );

      if (success && mounted) {
        await _saveCredentials();
        final role = authProvider.userRole;
        if (!mounted) return;
        if (role == 'SuperAdmin' || role == 'Agent') {
          await authProvider.logout();
          if (!mounted) return;
          NotificationOverlayManager().showError(
            title: 'Admin',
            message: 'Dùng app SBOX HRM để vào cổng quản trị.',
          );
        }
        // else: stay — Consumer flips to hub
      } else if (!success && mounted) {
        final errMsg = authProvider.error ?? 'Đăng nhập thất bại';
        setState(() => _errorMessage = errMsg);
        NotificationOverlayManager()
            .showError(title: 'Đăng nhập thất bại', message: errMsg);
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
      backgroundColor:
          isDesktop ? null : const Color(0xFFF8F9FA),
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
                      const Color(0xFF0C56D0).withOpacity(0.3),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.face_retouching_natural,
                    size: 180,
                    color: const Color(0xFF0C56D0).withOpacity(0.2),
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
                    const Color(0xFF0C56D0).withOpacity(0.60),
                    const Color(0xFF0C56D0).withOpacity(0.20),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tr('SBOX POS'),
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
                Text(tr('Bán hàng POS\nthời gian thực'),
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
                Text(tr('Bán hàng, kho và máy in trên một app POS.\nĐồng bộ hoá đơn nhanh — vận hành cửa hàng chuẩn.'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
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
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
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
                          color: const Color(0xFF0C56D0).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.trending_up_rounded,
                            color: Color(0xFF0C56D0), size: 20),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('TỐC ĐỘ BÁN HÀNG'),
                              style: TextStyle(
                                  color: Color(0xFF586064),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2),
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 2),
                            Text(tr('TĂNG 100%'),
                              style: TextStyle(
                                  color: Color(0xFF0C56D0),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
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
    final viewInsetsBottom = posImeBottomPad(context);
    final isCompactMobile = !isDesktop &&
        math.min(MediaQuery.sizeOf(context).width,
                MediaQuery.sizeOf(context).height) <
            600;
    final hPad = isDesktop ? 60.0 : 24.0;
    final vPad = isCompactMobile ? 16.0 : 32.0;
    final scrollContent = LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            hPad,
            vPad,
            hPad,
            vPad + viewInsetsBottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(
                0,
                constraints.maxHeight - vPad * 2 - viewInsetsBottom,
              ),
            ),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Align(
                  alignment: isCompactMobile && viewInsetsBottom > 0
                      ? Alignment.topCenter
                      : Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                  // Back to home
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        if (kIsWeb) {
                          web_home.redirectToStaticHome();
                          return;
                        }
                        // On mobile: open the web homepage in browser
                        final webUrl = ApiService.baseUrl
                            .replaceFirst(RegExp(r'/api$'), '');
                        final uri = Uri.parse(webUrl.endsWith('/')
                            ? webUrl
                            : '$webUrl/');
                        final ok = await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                        if (!ok && mounted) {
                          NotificationOverlayManager().showError(
                            title: 'Không mở được',
                            message: uri.toString(),
                          );
                        }
                      },
                      icon: const Icon(
                          kIsWeb
                              ? Icons.arrow_back_rounded
                              : Icons.open_in_browser_rounded,
                          size: 16,
                          color: Color(0xFF6B7280)),
                      label: Text(tr('Trang chủ')),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  SizedBox(height: isCompactMobile ? 4 : 8),
                  // Logo
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _buildLogo(isDesktop: isDesktop)),
                  SizedBox(height: isCompactMobile ? 16 : 36),
                  // Welcome text
                  Align(
                    alignment:
                        isDesktop ? Alignment.centerLeft : Alignment.center,
                    child: Text(tr('Chào mừng trở lại'),
                      style: TextStyle(
                        fontSize: isCompactMobile ? 22 : 26,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2B3437),
                        letterSpacing: -0.3,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment:
                        isDesktop ? Alignment.centerLeft : Alignment.center,
                    child: Text(tr('Nhập thông tin để vào SBOX POS.'),
                      style: TextStyle(
                          color: Color(0xFF586064), fontSize: 14, height: 1.5),
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
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Vui lòng nhập mã cửa hàng'
                              : null,
                        ),
                        if (_storeAgentContact != null) ...[
                          const SizedBox(height: 12),
                          StoreAgentSupportCard.fromMap(
                            _storeAgentContact!,
                            compact: true,
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Email
                        _buildLabel('EMAIL / SĐT'),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _emailController,
                          hint: 'Email hoặc số điện thoại',
                          icon: Icons.person_outline_rounded,
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Vui lòng nhập email hoặc số điện thoại'
                              : null,
                        ),
                        const SizedBox(height: 20),

                        // Password
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildLabel('MẬT KHẨU'),
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ForgotPasswordScreen(
                                    initialStoreCode:
                                        _storeCodeController.text.trim(),
                                    initialEmail:
                                        _emailController.text.trim(),
                                  ),
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF0C56D0),
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(tr('Quên mật khẩu?'),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
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
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFFABB3B7),
                              size: 20,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Vui lòng nhập mật khẩu';
                            }
                            if (v.length < 6) {
                              return 'Mật khẩu phải có ít nhất 6 ký tự';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Remember me
                        GestureDetector(
                          onTap: () =>
                              setState(() => _rememberMe = !_rememberMe),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: _rememberMe,
                                  onChanged: (v) =>
                                      setState(() => _rememberMe = v ?? false),
                                  side: BorderSide(
                                      color: const Color(0xFFABB3B7)
                                          .withOpacity(0.3)),
                                  checkColor: Colors.white,
                                  fillColor: WidgetStateProperty.resolveWith(
                                    (s) => s.contains(WidgetState.selected)
                                        ? const Color(0xFF3B82F6)
                                        : Colors.transparent,
                                  ),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(tr('Ghi nhớ đăng nhập'),
                                  style: TextStyle(
                                      color: Color(0xFF586064), fontSize: 14)),
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
                                  color: const Color(0xFF0C56D0)
                                      .withOpacity(0.25),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: FilledButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              onLongPress: _isLoading
                                  ? null
                                  : () =>
                                      () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(tr('Đăng nhập'),
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600)),
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

                  // Register link — web only (hidden on iOS/Android per App Store guideline 3.1.1)
                  if (kIsWeb)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(tr('Chưa có tài khoản?'),
                              style: TextStyle(
                                  color: Color(0xFF586064),
                                  fontSize: 14,
                                  height: 1.5)),
                          TextButton(
                            onPressed: () =>
                                () {},
                            style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF0C56D0)),
                            child: Text(tr('Đăng ký ngay'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Color(0xFF0C56D0),
                                )),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 40),

                  // Platform icons — hide Android icon on iOS (Apple guideline 2.3.10)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Opacity(
                      opacity: 0.5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildPlatformIcon(Icons.language, 'WEB'),
                          const SizedBox(width: 32),
                          _buildPlatformIcon(Icons.apple, 'IOS'),
                          if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) ...[
                            const SizedBox(width: 32),
                            _buildPlatformIcon(Icons.android, 'ANDROID'),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (kIsWeb) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(
                          '${const String.fromEnvironment("API_BASE", defaultValue: "https://sboxhrm.com")}/downloads/sbox-pos.apk',
                        );
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.android, size: 18),
                      label: Text(tr('Tải APK SBOX POS (Android 6+)')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0C56D0),
                        side: const BorderSide(color: Color(0xFF0C56D0)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('Cài thủ công — máy Android cũ không dùng được CH Play'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ] else if (!kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.android) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final release =
                            await PosAppUpdateService.checkForUpdate();
                        if (!context.mounted) return;
                        final info =
                            await PosAppUpdateService.currentPackage();
                        if (!context.mounted) return;
                        if (release == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                tr(
                                  'Đang dùng bản mới nhất ${info.version} (${info.buildNumber}).',
                                ),
                              ),
                            ),
                          );
                          return;
                        }
                        await showPosAppUpdateDialog(
                          context,
                          release: release,
                          currentVersion:
                              '${info.version} (${info.buildNumber})',
                        );
                      },
                      icon: const Icon(Icons.system_update_alt, size: 18),
                      label: Text(tr('Kiểm tra cập nhật')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0C56D0),
                        side: const BorderSide(color: Color(0xFF0C56D0)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                  _buildLoginFooter(isDesktop: isDesktop),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return Container(
      color: const Color(0xFFF8F9FA),
      child: SafeArea(child: scrollContent),
    );
  }

  /// Footer nằm trong panel đăng nhập (cuộn theo form), không cố định viewport.
  Widget _buildLoginFooter({required bool isDesktop}) {
    const copyright = '@2026 SBOX POS — BÁN HÀNG & KHO';
    final copyrightStyle = TextStyle(
      color: Colors.grey.shade400,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
    );
    final versionStyle = TextStyle(
      color: Colors.grey.shade500,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );
    final versionText = _appVersionLabel.isEmpty
        ? null
        : Text(_appVersionLabel, style: versionStyle, textAlign: TextAlign.center);
    final links = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFooterLink('TÌM HIỂU THÊM'),
        const SizedBox(width: 16),
        _buildFooterLink('LIÊN HỆ'),
        const SizedBox(width: 16),
        _buildFooterLink('HỖ TRỢ'),
      ],
    );

    if (isDesktop) {
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(copyright), style: copyrightStyle),
                  if (versionText != null) ...[
                    const SizedBox(height: 4),
                    versionText,
                  ],
                ],
              ),
            ),
            links,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: links),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              tr(copyright),
              style: copyrightStyle,
              textAlign: TextAlign.center,
            ),
          ),
          if (versionText != null) ...[
            const SizedBox(height: 4),
            versionText,
          ],
        ],
      ),
    );
  }

  Widget _buildLogo({bool isDesktop = false}) {
    return Row(
      mainAxisAlignment:
          isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset('assets/logo.png', width: 44, height: 44),
        ),
        const SizedBox(width: 14),
        Text(
          tr('SBOX POS'),
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
    return InkWell(
      onTap: () => _handleFooterLinkTap(text),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          tr(text),
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Future<void> _handleFooterLinkTap(String label) async {
    final raw = _footerUrlFor(label);
    if (raw.isEmpty) return;
    Uri? uri = Uri.tryParse(raw.trim());
    if (uri == null || (!uri.hasScheme)) {
      uri = Uri.tryParse('https://${raw.trim()}');
    }
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        NotificationOverlayManager().showError(
          title: 'Không mở được liên kết',
          message: uri.toString(),
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Lỗi mở liên kết',
          message: e.toString(),
        );
      }
    }
  }

  /// URL thực tế cho chip footer — ưu tiên cấu hình SuperAdmin, fallback liên hệ thật.
  String _footerUrlFor(String label) {
    switch (label) {
      case 'TÌM HIỂU THÊM':
        return _learnMoreUrl ??
            _websiteUrl ??
            '$_siteOrigin/';
      case 'LIÊN HỆ':
        if (_contactUrl != null) return _contactUrl!;
        if (kIsWeb) {
          return '$_siteOrigin/?section=contact';
        }
        return 'tel:+84${_phoneDigits.startsWith('0') ? _phoneDigits.substring(1) : _phoneDigits}';
      case 'HỖ TRỢ':
        if (_storeAgentContact?['zaloUrl'] != null) {
          return _storeAgentContact!['zaloUrl'].toString();
        }
        if (_supportUrl != null) return _supportUrl!;
        return 'https://zalo.me/$_zaloDigits';
    }
    return '';
  }

  Future<void> _launchTel(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse(
      'tel:+84${digits.startsWith('0') ? digits.substring(1) : digits}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchZalo(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('https://zalo.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Widget _buildLabel(String text) {
    return Text(
      tr(text),
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
        Text(tr(label),
            style: const TextStyle(
                color: Color(0xFF586064),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    final isLicenseExpired = _isLicenseExpiredMessage(message);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFDC2626), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(tr(message),
                    style: const TextStyle(
                        color: Color(0xFFDC2626), fontSize: 13, height: 1.4)),
              ),
            ],
          ),
          if (isLicenseExpired) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF0891B2).withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Liên hệ gia hạn ngay'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF0C4A6E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _launchTel(_supportPhoneDigits),
                        icon: const Icon(Icons.phone_rounded, size: 16),
                        label: Text(tr('Gọi $_supportPhoneDisplay')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0C4A6E),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _launchZalo(_zaloDigits),
                        icon: const Icon(Icons.chat_rounded, size: 16),
                        label: Text(
                            tr(_storeAgentContact != null
                                ? 'Zalo đại lý'
                                : 'Zalo $_phoneNumber')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0C4A6E),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
      style:
          const TextStyle(color: Color(0xFF2B3437), fontSize: 15, height: 1.5),
      validator: validator,
      decoration: InputDecoration(
        hintText: tr(hint),
        hintStyle: const TextStyle(
            color: Color(0xFFABB3B7), fontSize: 14, height: 1.5),
        prefixIcon: Icon(icon, color: const Color(0xFFABB3B7), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: const Color(0xFFABB3B7).withOpacity(0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: const Color(0xFFABB3B7).withOpacity(0.15)),
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
