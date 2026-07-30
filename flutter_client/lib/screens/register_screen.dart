import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/vietnam_provinces.dart';
import '../utils/web_route_parser.dart';
import '../utils/agent_referral_prefs.dart';
import '../utils/permission_navigation.dart';
import '../services/api_service.dart';
import '../utils/web_marketing_gate_stub.dart'
    if (dart.library.html) '../utils/web_marketing_gate_web.dart' as web_home;
import '../widgets/store_agent_support_card.dart';
import 'store_success_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../widgets/pos/pos_theme.dart';
String _sanitizeStoreLoginNameInput(String input) {
  var code = input.toLowerCase();
  code = _removeVietnameseAccentsForLoginName(code);
  code = code.replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (code.length > 20) code = code.substring(0, 20);
  return code;
}

String _removeVietnameseAccentsForLoginName(String text) {
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

class _StoreLoginNameInputFormatter extends TextInputFormatter {
  const _StoreLoginNameInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = _sanitizeStoreLoginNameInput(newValue.text);
    if (text == newValue.text) return newValue;
    final offset = newValue.selection.baseOffset.clamp(0, text.length);
    return TextEditingValue(
      text: tr(text),
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.initialAgentCode, this.initialPackageName});

  final String? initialAgentCode;
  final String? initialPackageName;

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
  String? _selectedProvince;
  String? _agentCode; // Mã đại lý nếu vào từ link giới thiệu
  String? _agentName;
  String? _agentPhone;
  String? _agentEmail;
  String? _agentAddress;
  String? _agentZaloUrl;
  List<_PublicServicePackage> _servicePackages = const [];
  String? _selectedServicePackageId;
  String? _initialPackageName;
  bool _loadedRouteArgs = false;
  bool _isLoading = false;
  bool _isLoadingPackages = false;
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
    _loadAgentCode();
    _loadServicePackages();
    _storeNameController.addListener(_onStoreNameChanged);
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedRouteArgs) return;
    _loadedRouteArgs = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final packageName = args['packageName']?.toString().trim();
      if (packageName != null && packageName.isNotEmpty) {
        _initialPackageName = packageName;
        _applyInitialPackageSelection();
      }
      final routeAgent = args['agentCode']?.toString().trim();
      if (routeAgent != null && routeAgent.isNotEmpty) {
        _applyAgentCode(routeAgent);
      }
    }
    if (_initialPackageName == null &&
        widget.initialPackageName != null &&
        widget.initialPackageName!.trim().isNotEmpty) {
      _initialPackageName = widget.initialPackageName!.trim();
      _applyInitialPackageSelection();
    }
  }

  Future<void> _loadAgentCode() async {
    try {
      var code = widget.initialAgentCode?.trim();
      if (code == null || code.isEmpty) {
        final params = parseWebRouteQueryParams();
        code = params['agentCode'] ?? params['agent'] ?? params['ref'];
        code ??= InitialWebRoute.agentCode;
      }
      code ??= await AgentReferralPrefs.load();
      if (code != null && code.trim().isNotEmpty) {
        _applyAgentCode(code);
      }
    } catch (_) {}
  }

  void _applyAgentCode(String code) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return;
    if (_agentCode == normalized) return;
    _agentCode = normalized;
    AgentReferralPrefs.save(normalized);
    _resolveAgentName();
    if (mounted) setState(() {});
  }

  Future<void> _resolveAgentName() async {
    if (_agentCode == null) return;
    try {
      final api = ApiService();
      final res = await api.lookupAgentByCode(_agentCode!);
      if (mounted && res['isSuccess'] == true) {
        final data = res['data'] as Map<String, dynamic>?;
        if (data == null) return;
        setState(() {
          _agentName = data['name']?.toString();
          _agentPhone = data['phone']?.toString();
          _agentEmail = data['email']?.toString();
          _agentAddress = data['address']?.toString();
          _agentZaloUrl = data['zaloUrl']?.toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadServicePackages() async {
    setState(() => _isLoadingPackages = true);
    try {
      final api = ApiService();
      final result = await api.getPublicServicePackages();
      if (!mounted) return;
      final rawItems = (result['data'] as List?) ?? const [];
      final packages = rawItems
          .whereType<Map>()
          .map((item) =>
              _PublicServicePackage.fromMap(Map<String, dynamic>.from(item)))
          .toList();
      setState(() {
        _servicePackages = packages;
        if (packages.isNotEmpty && _selectedServicePackageId == null) {
          _selectedServicePackageId = packages.first.id;
        }
      });
      _applyInitialPackageSelection();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _servicePackages = const [];
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingPackages = false);
      }
    }
  }

  void _applyInitialPackageSelection() {
    if (_initialPackageName == null || _servicePackages.isEmpty) return;
    final normalizedTarget = _normalizePackageName(_initialPackageName!);
    final matched = _servicePackages
        .where((package) =>
            _normalizePackageName(package.name) == normalizedTarget)
        .firstOrNull;
    if (matched == null) return;
    if (mounted) {
      setState(() => _selectedServicePackageId = matched.id);
    } else {
      _selectedServicePackageId = matched.id;
    }
  }

  static String _normalizePackageName(String value) {
    return value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _onStoreNameChanged() {
    if (!_loginNameManuallyEdited) {
      _loginNameController.text = _generateLoginName(_storeNameController.text);
    }
  }

  static String _generateLoginName(String storeName) =>
      _sanitizeStoreLoginNameInput(storeName);

  static String _registerErrorMessage(dynamic raw) {
    if (raw is List) {
      final parts = raw.map((e) => e.toString()).where((s) => s.isNotEmpty);
      if (parts.isNotEmpty) return parts.join('\n');
    }
    final msg = raw?.toString().trim() ?? '';
    if (msg.isEmpty) return 'Đăng ký thất bại';
    final lower = msg.toLowerCase();
    if (lower.contains('province') && lower.contains('required')) {
      return 'Vui lòng chọn tỉnh / thành phố';
    }
    if (lower.contains('phonenumber') && lower.contains('required')) {
      return 'Vui lòng nhập số điện thoại';
    }
    if (lower.contains('duplicate') &&
        (lower.contains('email') || lower.contains('username'))) {
      return 'Email này đã được sử dụng';
    }
    if (lower.contains('phone') &&
        (lower.contains('duplicate') || lower.contains('already'))) {
      return 'Số điện thoại này đã được sử dụng';
    }
    if (msg.contains('đã được sử dụng') ||
        msg.contains('đã tồn tại') ||
        msg.contains('Không thể hoàn tất')) {
      return msg;
    }
    return msg;
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
        phoneNumber: _phoneController.text.trim(),
        province: _selectedProvince!.trim(),
        storeCode: _loginNameController.text.trim(),
        agentCode: _agentCode,
        servicePackageId: _selectedServicePackageId,
      );

      if (result['isSuccess'] == true) {
        await AgentReferralPrefs.clear();
        final message = result['data'] as String? ?? 'Đăng ký thành công!';
        final codeMatch =
            RegExp(r'Mã cửa hàng của bạn là:\s*(\S+)').firstMatch(message);
        final storeCode = codeMatch?.group(1)?.replaceAll('.', '') ??
            _loginNameController.text.trim();
        if (mounted) {
          _navigateToSuccessScreen(storeCode);
        }
      } else {
        final errors = result['errors'];
        final message = result['message'];
        setState(() {
          _errorMessage = _registerErrorMessage(
            (errors is List && errors.isNotEmpty) ? errors : message,
          );
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tr('SBOX HRM'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(tr('Bắt đầu hành trình\nquản lý nhân sự'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(tr('Đăng ký doanh nghiệp để sử dụng hệ thống\nquản lý nhân sự thông minh.'),
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
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                        child: const Icon(Icons.rocket_launch_rounded,
                            color: Color(0xFF0C56D0), size: 20),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('THIẾT LẬP NHANH'),
                            style: TextStyle(
                                color: Color(0xFF586064),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5),
                          ),
                          SizedBox(height: 2),
                          Text(tr('CHỈ 2 PHÚT'),
                            style: TextStyle(
                                color: Color(0xFF0C56D0),
                                fontSize: 20,
                                fontWeight: FontWeight.w800),
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
                    alignment:
                        isDesktop ? Alignment.centerLeft : Alignment.center,
                    child: Text(tr('Đăng ký doanh nghiệp'),
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
                    alignment:
                        isDesktop ? Alignment.centerLeft : Alignment.center,
                    child: Text(tr('Tạo tài khoản doanh nghiệp mới để bắt đầu.'),
                      style: TextStyle(color: Color(0xFF586064), fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Banner: đăng ký qua link đại lý
                  if (_agentCode != null) ...[
                    if (_agentName != null || _agentPhone != null)
                      StoreAgentSupportCard(
                        agentName: _agentName ?? _agentCode!,
                        agentCode: _agentCode,
                        phone: _agentPhone,
                        email: _agentEmail,
                        address: _agentAddress,
                        zaloUrl: _agentZaloUrl,
                        compact: true,
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7E6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFD591)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.handshake_rounded,
                                color: Color(0xFFD46B08)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(tr('Bạn đang đăng ký qua mã đại lý: $_agentCode'),
                                style: const TextStyle(
                                  color: Color(0xFFAD4E00),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],

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
                            if (v == null || v.isEmpty) {
                              return 'Vui lòng nhập tên doanh nghiệp';
                            }
                            if (v.length < 2) {
                              return 'Tên doanh nghiệp phải có ít nhất 2 ký tự';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Login name (auto-generated)
                        _buildLabel('TÊN ĐĂNG NHẬP (MÃ DOANH NGHIỆP)'),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _loginNameController,
                          hint: 'Ví dụ: sanapos — chỉ chữ và số, không dấu',
                          icon: Icons.badge_rounded,
                          inputFormatters: const [_StoreLoginNameInputFormatter()],
                          maxLength: 20,
                          onChanged: (_) {
                            if (!_loginNameManuallyEdited) {
                              setState(() => _loginNameManuallyEdited = true);
                            }
                          },
                          suffixIcon: _loginNameManuallyEdited
                              ? IconButton(
                                  icon: const Icon(Icons.refresh_rounded,
                                      color: Color(0xFF0C56D0), size: 20),
                                  tooltip: tr('Tạo lại từ tên doanh nghiệp'),
                                  onPressed: () {
                                    setState(() {
                                      _loginNameManuallyEdited = false;
                                      _loginNameController.text =
                                          _generateLoginName(
                                              _storeNameController.text);
                                    });
                                  },
                                )
                              : null,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Vui lòng nhập tên đăng nhập';
                            }
                            if (v.length < 2) {
                              return 'Tên đăng nhập phải có ít nhất 2 ký tự';
                            }
                            if (!RegExp(r'^[a-z0-9]+$').hasMatch(v)) {
                              return 'Chỉ nhập liền không dấu, không khoảng trắng (a-z, 0-9)';
                            }
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
                            if (v == null || v.isEmpty) {
                              return 'Vui lòng nhập email';
                            }
                            if (!RegExp(r'^[\w\.\-]+@[\w\.\-]+\.\w+$')
                                .hasMatch(v.trim())) {
                              return 'Email không hợp lệ';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        _buildLabel('TỈNH / THÀNH PHỐ'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedProvince,
                          isExpanded: true,
                          decoration: InputDecoration(
                            hintText: tr('Chọn tỉnh / thành phố'),
                            prefixIcon: const Icon(Icons.location_city_outlined,
                                color: Color(0xFF586064), size: 20),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 18),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFD9E0E3)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFD9E0E3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0C56D0), width: 1.4),
                            ),
                          ),
                          items: kVietnamProvinces
                              .map(
                                (p) => DropdownMenuItem<String>(
                                  value: p,
                                  child: Text(
                                    tr(p),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedProvince = value),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Vui lòng chọn tỉnh / thành phố';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // phone
                        _buildLabel('SỐ ĐIỆN THOẠI'),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _phoneController,
                          hint: 'Nhập số điện thoại liên hệ',
                          icon: Icons.phone_rounded,
                          keyboardType: TextInputType.phone,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Vui lòng nhập số điện thoại';
                            }
                            if (!RegExp(r'^\+?[0-9]{9,15}$').hasMatch(v.trim())) {
                              return 'Số điện thoại không hợp lệ';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        _buildLabel('GÓI DÙNG THỬ'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedServicePackageId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            hintText: tr(_isLoadingPackages
                                ? 'Đang tải gói dịch vụ...'
                                : 'Chọn gói dùng thử'),
                            prefixIcon: const Icon(Icons.inventory_2_outlined,
                                color: Color(0xFF586064), size: 20),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 18),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFD9E0E3)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFD9E0E3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0C56D0), width: 1.4),
                            ),
                          ),
                          items: _servicePackages
                              .map(
                                (package) => DropdownMenuItem<String>(
                                  value: package.id,
                                  child: Text(
                                    tr(package.displayLabel),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged:
                              _isLoadingPackages || _servicePackages.isEmpty
                                  ? null
                                  : (value) => setState(
                                      () => _selectedServicePackageId = value),
                          validator: (_) {
                            if (_servicePackages.isNotEmpty &&
                                (_selectedServicePackageId == null ||
                                    _selectedServicePackageId!.isEmpty)) {
                              return 'Vui lòng chọn gói dùng thử';
                            }
                            return null;
                          },
                        ),
                        if (_servicePackages.isNotEmpty &&
                            _selectedServicePackageId != null)
                          _buildSelectedPackageInfo(),
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
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFFABB3B7),
                              size: 20,
                            ),
                            onPressed: () => setState(() =>
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Vui lòng xác nhận mật khẩu';
                            }
                            if (v != _passwordController.text) {
                              return 'Mật khẩu không khớp';
                            }
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
                                  color: const Color(0xFF0C56D0)
                                      .withValues(alpha: 0.25),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: FilledButton(
                              onPressed: _isLoading ? null : _handleRegister,
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
                                        Text(tr('Đăng ký doanh nghiệp'),
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700)),
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
                      Text(tr('Đã có tài khoản?'),
                          style: TextStyle(
                              color: Color(0xFF586064), fontSize: 14)),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF0C56D0)),
                        child: Text(tr('Đăng nhập'),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
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
                        Text(tr('@2026 SBOX HRM HỆ THỐNG QUẢN TRỊ NHÂN SỰ'),
                          style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5),
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
                        Text(tr('@2026 SBOX HRM HỆ THỐNG QUẢN TRỊ NHÂN SỰ'),
                          style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5),
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
      mainAxisAlignment:
          isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bubble_chart, color: Color(0xFF0C56D0), size: 44),
        SizedBox(width: 14),
        Text(
          tr('SBOX HRM'),
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

  _PublicServicePackage? get _selectedPackage {
    final id = _selectedServicePackageId;
    if (id == null) return null;
    for (final package in _servicePackages) {
      if (package.id == id) return package;
    }
    return null;
  }

  Widget _buildSelectedPackageInfo() {
    final package = _selectedPackage;
    if (package == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD6E4FF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    tr(package.name),
                    style: const TextStyle(
                      color: PosTheme.kiotBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
                Material(
                  color: Colors.white,
                  shape: const CircleBorder(
                    side: BorderSide(color: Color(0xFF0C56D0), width: 1.2),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _showPackageModulesDialog(package),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 18,
                        color: Color(0xFF0C56D0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr(package.descriptionText),
              style: const TextStyle(
                color: Color(0xFF586064),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(package.limitsLine),
              style: const TextStyle(
                color: Color(0xFF7A8790),
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _openLandingPricing,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_new_rounded,
                        size: 15, color: Color(0xFF0C56D0)),
                    SizedBox(width: 6),
                    Text(tr('Xem bảng giá các gói dịch vụ trên trang chủ'),
                      style: TextStyle(
                        color: Color(0xFF0C56D0),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF0C56D0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPackageModulesDialog(_PublicServicePackage package) {
    final modules = package.allowedModules;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Expanded(
              child: Text(tr('Chức năng gói ${package.name}'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(ctx).pop(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: modules.isEmpty
              ? Text(tr('Gói này bao gồm các chức năng cơ bản của SBOX HRM.'),
                  style: TextStyle(fontSize: 14, height: 1.5),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final code in modules)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 18, color: Color(0xFF16A34A)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tr(PermissionNavigation.label(code)),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    color: Color(0xFF2B3437),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openLandingPricing();
            },
            child: Text(tr('Xem bảng giá trang chủ')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('Đóng')),
          ),
        ],
      ),
    );
  }

  void _openLandingPricing() {
    if (kIsWeb) {
      web_home.redirectToStaticHome(section: 'pricing');
      return;
    }
    final base = ApiService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
    final uri = Uri.parse('$base/?section=pricing');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Widget _buildLabel(String text) {
    return Text(
      tr(text),
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
        tr(text),
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
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(message),
              style: TextStyle(
                color:
                    isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
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
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      buildCounter: maxLength == null
          ? null
          : (_, {required currentLength, required isFocused, maxLength}) =>
              null,
      style: const TextStyle(color: Color(0xFF2B3437), fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        hintText: tr(hint),
        hintStyle: const TextStyle(color: Color(0xFFABB3B7), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFFABB3B7), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: const Color(0xFFABB3B7).withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: const Color(0xFFABB3B7).withValues(alpha: 0.15)),
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

class _PublicServicePackage {
  const _PublicServicePackage({
    required this.id,
    required this.name,
    required this.description,
    required this.defaultDurationDays,
    required this.maxUsers,
    required this.maxDevices,
    required this.allowedModules,
  });

  final String id;
  final String name;
  final String description;
  final int defaultDurationDays;
  final int maxUsers;
  final int maxDevices;
  final List<String> allowedModules;

  String get displayLabel => '$name - $defaultDurationDays ngày';

  String get moduleSummary {
    if (allowedModules.isEmpty) return 'Chức năng cơ bản';
    final labels = allowedModules
        .take(8)
        .map((c) => PermissionNavigation.label(c))
        .toList();
    final extra = allowedModules.length > 8
        ? ' +${allowedModules.length - 8} chức năng'
        : '';
    return '${labels.join(', ')}$extra';
  }

  String get limitsLine {
    final limitUsers =
        maxUsers > 0 ? '$maxUsers người dùng' : 'không giới hạn người dùng';
    final limitDevices =
        maxDevices > 0 ? '$maxDevices thiết bị' : 'không giới hạn thiết bị';
    return 'Dùng thử $defaultDurationDays ngày · $limitUsers · $limitDevices';
  }

  String get descriptionText {
    final desc = description.trim();
    if (desc.isNotEmpty) return desc;
    return 'Gói dùng thử $name phù hợp để trải nghiệm SBOX HRM trước khi nâng cấp.';
  }

  String get summary {
    final desc = description.trim();
    final limitUsers =
        maxUsers > 0 ? '$maxUsers người dùng' : 'không giới hạn người dùng';
    final limitDevices =
        maxDevices > 0 ? '$maxDevices thiết bị' : 'không giới hạn thiết bị';
    final modules = 'Chức năng: $moduleSummary';
    if (desc.isEmpty) {
      return 'Dùng thử $defaultDurationDays ngày, $limitUsers, $limitDevices. $modules';
    }
    return '$desc. Dùng thử $defaultDurationDays ngày, $limitUsers, $limitDevices. $modules';
  }

  factory _PublicServicePackage.fromMap(Map<String, dynamic> map) {
    final rawModules = map['allowedModules'];
    final modules = rawModules is List
        ? rawModules.map((e) => e.toString()).toList()
        : <String>[];
    return _PublicServicePackage(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      defaultDurationDays: _toInt(map['defaultDurationDays']),
      maxUsers: _toInt(map['maxUsers']),
      maxDevices: _toInt(map['maxDevices']),
      allowedModules: modules,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
