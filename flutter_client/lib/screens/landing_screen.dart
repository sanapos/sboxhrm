import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/landing_product_image.dart';
import '../widgets/landing_youtube_player.dart';

/// Landing/Marketing page for SBOX HRM.
/// Nội dung (tiêu đề, mô tả, liên hệ...) load từ /api/publicsettings để
/// SuperAdmin có thể chỉnh sửa trong tab "Trang Landing".
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _heroKey = GlobalKey();
  final GlobalKey _featuresKey = GlobalKey();
  final GlobalKey _pricingKey = GlobalKey();
  final GlobalKey _videoKey = GlobalKey();
  final GlobalKey _guideKey = GlobalKey();
  final GlobalKey _devicesKey = GlobalKey();
  final GlobalKey _downloadKey = GlobalKey();
  final GlobalKey _contactKey = GlobalKey();

  bool _isScrolled = false;
  bool _mobileMenuOpen = false;

  // Dynamic content loaded from API
  String _heroTitle = 'Quản lý nhân sự\nthông minh với SBOX HRM';
  String _heroSubtext =
      'Chấm công ZKTeco, quản lý lương, ca làm, phép năm, KPI và hơn 30 tính năng HR – tất cả trong một nền tảng duy nhất.';
  String _phoneNumber = '0973 024 042';
  String _zaloNumber = '0973024042';
  String _contactEmail = 'support@sboxhrm.com';
  String _address = '184 Nam Cao, Hòa Khánh, Đà Nẵng';
  String _videoIntroUrl =
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ'; // replaced by API
  String _videoGuideUrl =
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ'; // replaced by API
  String _videoIntroTitle = 'Video giới thiệu';
  String _videoIntroSubtitle =
      'Tổng quan SBOX HRM – chấm công, lương, ca làm, báo cáo';
  String _videoIntroBadge = 'Xem ngay';
  String _videoIntroDuration = '3:45';
  String _videoGuideTitle = 'Video hướng dẫn';
  String _videoGuideSubtitle =
      'Thiết lập từ A–Z: kết nối máy, thêm nhân viên, cài ca';
  String _videoGuideBadge = 'Học ngay';
  String _videoGuideDuration = '12:00';

  // Dynamic JSON content from API (null = use hardcoded defaults)
  List<({String title, String desc})>? _dynamicFeatures;
  List<
      ({
        String name,
        String price,
        String unit,
        String desc,
        bool highlight,
        bool contactOnly,
        List<String> features
      })>? _dynamicPricing;
  List<_ProductData>? _dynamicProducts;
  List<_DownloadItemData>? _dynamicDownloads;

  // Brand colors – Blue theme matching LoginScreen
  static const Color kBlue = Color(0xFF0C56D0);
  static const Color kDark = Color(0xFF111827);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final scrolled = _scrollController.offset > 60;
      if (scrolled != _isScrolled) setState(() => _isScrolled = scrolled);
      if (_mobileMenuOpen) setState(() => _mobileMenuOpen = false);
    });
    _loadPublicSettings();
  }

  Future<void> _loadPublicSettings() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/publicsettings'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final body = json.decode(res.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null || !mounted) return;
      String pick(String key, String fallback) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        return fallback;
      }

      setState(() {
        // Map API property names (camelCase) to state fields
        _heroTitle = pick('landingHeroTitle', _heroTitle);
        _heroSubtext = pick('landingHeroSubtext', _heroSubtext);
        _phoneNumber = pick(
            'technicalSupportPhone',
            pick('technicalSupportphone',
                pick('salesPhone', pick('salesphone', _phoneNumber))));
        _zaloNumber = pick('zaloUrl', _zaloNumber)
            .replaceAll('https://zalo.me/', '')
            .replaceAll(' ', '');
        _contactEmail =
            pick('technicalSupportEmail', pick('salesEmail', _contactEmail));
        _address = pick('companyAddress', _address);

        // Parse video JSON (may be plain URL for backward compat)
        void parseVideo(
            String key,
            void Function(String url, String title, String subtitle,
                    String badge, String duration)
                apply) {
          final raw = data[key];
          if (raw is! String || raw.trim().isEmpty) return;
          try {
            final m = json.decode(raw) as Map<String, dynamic>;
            apply(
              m['url']?.toString() ?? '',
              m['title']?.toString() ?? '',
              m['subtitle']?.toString() ?? '',
              m['badge']?.toString() ?? '',
              m['duration']?.toString() ?? '',
            );
          } catch (_) {
            // old format: plain URL
            if (raw.startsWith('http')) apply(raw, '', '', '', '');
          }
        }

        parseVideo('landingVideoIntro',
            (url, title, subtitle, badge, duration) {
          if (url.isNotEmpty) _videoIntroUrl = url;
          if (title.isNotEmpty) _videoIntroTitle = title;
          if (subtitle.isNotEmpty) _videoIntroSubtitle = subtitle;
          if (badge.isNotEmpty) _videoIntroBadge = badge;
          if (duration.isNotEmpty) _videoIntroDuration = duration;
        });
        parseVideo('landingVideoGuide',
            (url, title, subtitle, badge, duration) {
          if (url.isNotEmpty) _videoGuideUrl = url;
          if (title.isNotEmpty) _videoGuideTitle = title;
          if (subtitle.isNotEmpty) _videoGuideSubtitle = subtitle;
          if (badge.isNotEmpty) _videoGuideBadge = badge;
          if (duration.isNotEmpty) _videoGuideDuration = duration;
        });

        // Parse JSON arrays for features and pricing
        try {
          final featuresRaw = data['landingFeaturesJson'];
          if (featuresRaw is String && featuresRaw.trim().isNotEmpty) {
            final arr = json.decode(featuresRaw) as List;
            _dynamicFeatures = arr
                .whereType<Map>()
                .map((e) => (
                      title: e['title']?.toString() ?? '',
                      desc: e['desc']?.toString() ?? ''
                    ))
                .where((e) => e.title.isNotEmpty)
                .toList();
          }
        } catch (_) {}

        try {
          final pricingRaw = data['landingPricingJson'];
          if (pricingRaw is String && pricingRaw.trim().isNotEmpty) {
            final arr = json.decode(pricingRaw) as List;
            _dynamicPricing = arr
                .whereType<Map>()
                .map((e) => (
                      name: e['name']?.toString() ?? '',
                      price: e['price']?.toString() ?? '0',
                      unit: e['unit']?.toString() ?? 'đ/năm',
                      desc: e['desc']?.toString() ?? '',
                      highlight: e['highlight'] == true,
                      contactOnly: e['contactOnly'] == true,
                      features: (e['features'] as List? ?? [])
                          .map((f) => f.toString())
                          .toList(),
                    ))
                .where((e) => e.name.isNotEmpty)
                .toList();
          }
        } catch (_) {}

        try {
          final productsRaw = data['landingProducts'];
          if (productsRaw is String && productsRaw.trim().isNotEmpty) {
            final arr = json.decode(productsRaw) as List;
            final parsed = arr
                .whereType<Map>()
                .map((e) => (
                      name: e['name']?.toString() ?? '',
                      sub: e['sub']?.toString() ?? '',
                      price: e['price']?.toString() ?? '',
                      oldPrice: e['oldPrice']?.toString() ?? '',
                      badge: e['badge']?.toString() ?? '',
                      specs: e['specs']?.toString() ?? '',
                      specsDetail: e['specsDetail']?.toString() ?? '',
                      imageUrl:
                          _normalizePublicUrl(e['imageUrl']?.toString() ?? ''),
                      link: _normalizePublicUrl(e['link']?.toString() ?? ''),
                      brand: e['brand']?.toString() ?? '',
                    ))
                .where((e) => e.name.isNotEmpty)
                .toList();
            if (parsed.isNotEmpty) _dynamicProducts = parsed;
          }
        } catch (_) {}

        try {
          final downloadsRaw = data['landingDownloadsJson'];
          if (downloadsRaw is String && downloadsRaw.trim().isNotEmpty) {
            final arr = json.decode(downloadsRaw) as List;
            final parsed = arr
                .whereType<Map>()
                .map((e) => (
                      title: e['title']?.toString() ?? '',
                      desc: e['desc']?.toString() ?? '',
                      version: e['version']?.toString() ?? '',
                      badge: e['badge']?.toString() ?? '',
                      platform: e['platform']?.toString() ?? '',
                      url: _normalizePublicUrl(e['url']?.toString() ?? ''),
                    ))
                .where((e) => e.title.isNotEmpty && e.url.isNotEmpty)
                .toList();
            if (parsed.isNotEmpty) _dynamicDownloads = parsed;
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
  }

  void _goToLogin() => Navigator.of(context).pushNamed('/login-app');
  void _goToRegister([String? packageName]) => Navigator.of(context).pushNamed(
        '/register',
        arguments: packageName == null || packageName.trim().isEmpty
            ? null
            : {'packageName': packageName.trim()},
      );

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _callPhone() => _openUrl('tel:${_phoneNumber.replaceAll(' ', '')}');
  void _openZalo() => _openUrl('https://zalo.me/$_zaloNumber');
  void _openEmail() => _openUrl('mailto:$_contactEmail');

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 900;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 0,
                backgroundColor: _isScrolled
                    ? Colors.white.withValues(alpha: 0.97)
                    : Colors.transparent,
                elevation: _isScrolled ? 2 : 0,
                automaticallyImplyLeading: false,
                title: Row(
                  children: [
                    Image.asset('assets/logo.png',
                        height: 38, filterQuality: FilterQuality.high),
                    const SizedBox(width: 8),
                    Text('SBOX',
                        style: TextStyle(
                            color: _isScrolled ? kBlue : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 0.5,
                            shadows: _isScrolled
                                ? null
                                : [
                                    const Shadow(
                                        color: Color(0x88000000),
                                        blurRadius: 4,
                                        offset: Offset(0, 1))
                                  ])),
                    Text(' HRM',
                        style: TextStyle(
                            color: _isScrolled ? kDark : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            shadows: _isScrolled
                                ? null
                                : [
                                    const Shadow(
                                        color: Color(0x88000000),
                                        blurRadius: 4,
                                        offset: Offset(0, 1))
                                  ])),
                  ],
                ),
                actions: isMobile
                    ? [
                        IconButton(
                          onPressed: () => setState(
                              () => _mobileMenuOpen = !_mobileMenuOpen),
                          icon: Icon(
                            _mobileMenuOpen
                                ? Icons.close_rounded
                                : Icons.menu_rounded,
                            color: _isScrolled ? kDark : Colors.white,
                          ),
                        ),
                      ]
                    : [
                        _NavLink('Tính năng',
                            onTap: () => _scrollTo(_featuresKey),
                            dark: _isScrolled),
                        _NavLink('Bảng giá',
                            onTap: () => _scrollTo(_pricingKey),
                            dark: _isScrolled),
                        _NavLink('Hướng dẫn',
                            onTap: () => _scrollTo(_guideKey),
                            dark: _isScrolled),
                        _NavLink('Thiết bị',
                            onTap: () => _scrollTo(_devicesKey),
                            dark: _isScrolled),
                        _NavLink('Liên hệ',
                            onTap: () => _scrollTo(_contactKey),
                            dark: _isScrolled),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: FilledButton(
                            onPressed: _goToLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                            ),
                            child: const Text('Đăng nhập',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  _HeroSection(
                    key: _heroKey,
                    isMobile: isMobile,
                    heroTitle: _heroTitle,
                    heroSubtext: _heroSubtext,
                    onGetStarted: () => _goToRegister(),
                    onLogin: _goToLogin,
                    onRegister: () => _goToRegister(),
                  ),
                  _FeaturesSection(
                      key: _featuresKey,
                      isMobile: isMobile,
                      dynamicFeatures: _dynamicFeatures),
                  _VideoSection(
                      key: _videoKey,
                      isMobile: isMobile,
                      videoIntroUrl: _videoIntroUrl,
                      videoIntroTitle: _videoIntroTitle,
                      videoIntroSubtitle: _videoIntroSubtitle,
                      videoIntroBadge: _videoIntroBadge,
                      videoIntroDuration: _videoIntroDuration,
                      videoGuideUrl: _videoGuideUrl,
                      videoGuideTitle: _videoGuideTitle,
                      videoGuideSubtitle: _videoGuideSubtitle,
                      videoGuideBadge: _videoGuideBadge,
                      videoGuideDuration: _videoGuideDuration),
                  _PricingSection(
                      key: _pricingKey,
                      isMobile: isMobile,
                      dynamicPlans: _dynamicPricing,
                      onContact: () => _scrollTo(_contactKey),
                      onRegister: _goToRegister),
                  _GuideSection(key: _guideKey, isMobile: isMobile),
                  _DevicesSection(
                      key: _devicesKey,
                      isMobile: isMobile,
                      onContact: () => _scrollTo(_contactKey),
                      dynamicProducts: _dynamicProducts),
                  _DownloadSection(
                      key: _downloadKey,
                      isMobile: isMobile,
                      dynamicDownloads: _dynamicDownloads),
                  _ContactSection(
                    key: _contactKey,
                    isMobile: isMobile,
                    phone: _phoneNumber,
                    zaloNumber: _zaloNumber,
                    email: _contactEmail,
                    onCallPhone: _callPhone,
                    onOpenZalo: _openZalo,
                    onOpenEmail: _openEmail,
                  ),
                  _Footer(
                    isMobile: isMobile,
                    onFeatures: () => _scrollTo(_featuresKey),
                    onPricing: () => _scrollTo(_pricingKey),
                    onGuide: () => _scrollTo(_guideKey),
                    onDevices: () => _scrollTo(_devicesKey),
                    onContact: () => _scrollTo(_contactKey),
                    onLogin: _goToLogin,
                  ),
                ]),
              ),
            ],
          ),
          if (isMobile && _mobileMenuOpen)
            _MobileMenuOverlay(
              onDismiss: () => setState(() => _mobileMenuOpen = false),
              onFeatures: () {
                setState(() => _mobileMenuOpen = false);
                _scrollTo(_featuresKey);
              },
              onPricing: () {
                setState(() => _mobileMenuOpen = false);
                _scrollTo(_pricingKey);
              },
              onGuide: () {
                setState(() => _mobileMenuOpen = false);
                _scrollTo(_guideKey);
              },
              onDevices: () {
                setState(() => _mobileMenuOpen = false);
                _scrollTo(_devicesKey);
              },
              onContact: () {
                setState(() => _mobileMenuOpen = false);
                _scrollTo(_contactKey);
              },
              onLogin: () {
                setState(() => _mobileMenuOpen = false);
                _goToLogin();
              },
              onRegister: () {
                setState(() => _mobileMenuOpen = false);
                _goToRegister();
              },
            ),
        ],
      ),
    );
  }
}

// ─── MOBILE MENU OVERLAY ──────────────────────────────────────────────────────
class _MobileMenuOverlay extends StatelessWidget {
  const _MobileMenuOverlay({
    required this.onDismiss,
    required this.onFeatures,
    required this.onPricing,
    required this.onGuide,
    required this.onDevices,
    required this.onContact,
    required this.onLogin,
    required this.onRegister,
  });
  final VoidCallback onDismiss;
  final VoidCallback onFeatures;
  final VoidCallback onPricing;
  final VoidCallback onGuide;
  final VoidCallback onDevices;
  final VoidCallback onContact;
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  static const Color _kBlue = Color(0xFF0C56D0);
  static const Color _kDark = Color(0xFF111827);
  static const Color _kGrey = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final topPad = kToolbarHeight + MediaQuery.of(context).padding.top;
    return Positioned.fill(
      top: topPad,
      child: GestureDetector(
        onTap: onDismiss,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () {},
            child: Material(
              elevation: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _item(Icons.star_outline_rounded, 'Tính năng', onFeatures),
                  _divider(),
                  _item(Icons.local_offer_outlined, 'Bảng giá', onPricing),
                  _divider(),
                  _item(Icons.menu_book_outlined, 'Hướng dẫn', onGuide),
                  _divider(),
                  _item(Icons.devices_rounded, 'Thiết bị', onDevices),
                  _divider(),
                  _item(Icons.phone_outlined, 'Liên hệ', onContact),
                  const Divider(height: 1, thickness: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onLogin,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kBlue,
                              side: const BorderSide(color: _kBlue),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Đăng nhập',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: onRegister,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Dùng miễn phí',
                                style: TextStyle(fontWeight: FontWeight.bold)),
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
    );
  }

  Widget _item(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: _kGrey, size: 20),
            const SizedBox(width: 14),
            Text(label,
                style: const TextStyle(
                    color: _kDark, fontSize: 16, fontWeight: FontWeight.w500)),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: _kGrey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, thickness: 1, indent: 54);
}

// ─── NAV LINK ─────────────────────────────────────────────────────────────────
class _NavLink extends StatelessWidget {
  const _NavLink(this.label, {required this.onTap, required this.dark});
  final String label;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(label,
          style: TextStyle(
              color: dark ? const Color(0xFF374151) : Colors.white,
              fontWeight: FontWeight.w500)),
    );
  }
}

// ─── HERO ─────────────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  const _HeroSection({
    super.key,
    required this.isMobile,
    required this.heroTitle,
    required this.heroSubtext,
    required this.onGetStarted,
    required this.onLogin,
    required this.onRegister,
  });
  final bool isMobile;
  final String heroTitle;
  final String heroSubtext;
  final VoidCallback onGetStarted;
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  static const String _bgImage =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuD6gKf5JQatbloDEXQAJyi7OUPnQiNzZORiDKYsBmYfd5RGNvPEOgNyL1K1NW3zrx3NMlwn7vfdnRQpjFl4njRzguVyN7-OTnFC3uKzO2NZxboaxRf0he8vwScXzAANWuVj-B3bWWox3NkiwL3EkbqgZsCF4UvY0S92s_ryURmITms5q7pfRNqenj848647ByfIGa-yEIcjh6nJXtHIPjZSgoX4keaiY1mtAA6DV5k-naedu6M8dnZQTEshrBgVY6JQ7G3-wOdyCsoG';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFDAE2FF),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // Background
          SizedBox(
            height: isMobile ? 520 : 680,
            child: Image.network(
              _bgImage,
              fit: BoxFit.cover,
              width: double.infinity,
              opacity: const AlwaysStoppedAnimation(0.9),
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFDAE2FF), Color(0xFF0C56D0)],
                  ),
                ),
              ),
            ),
          ),
          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    const Color(0xFF0C56D0).withValues(alpha: 0.85),
                    const Color(0xFF0C56D0).withValues(alpha: 0.40),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 24 : 80,
                isMobile ? 60 : 80,
                isMobile ? 24 : 80,
                isMobile ? 48 : 80,
              ),
              child: isMobile ? _buildMobile() : _buildDesktop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _badge(),
        const SizedBox(height: 20),
        Text(
          heroTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.2,
              letterSpacing: -0.5),
        ),
        const SizedBox(height: 16),
        Text(
          heroSubtext,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88), fontSize: 15, height: 1.6),
        ),
        const SizedBox(height: 32),
        _buttons(true),
        const SizedBox(height: 40),
        _statsRow(true),
      ],
    );
  }

  Widget _buildDesktop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _badge(),
              const SizedBox(height: 24),
              Text(
                heroTitle,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                    letterSpacing: -1),
              ),
              const SizedBox(height: 20),
              Text(
                heroSubtext,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 17,
                    height: 1.6),
              ),
              const SizedBox(height: 40),
              _buttons(false),
              const SizedBox(height: 48),
              _statsRow(false),
            ],
          ),
        ),
        const SizedBox(width: 60),
        Expanded(flex: 4, child: _glassCard()),
      ],
    );
  }

  Widget _badge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, color: Color(0xFF93C5FD), size: 15),
          SizedBox(width: 6),
          Text('Phần mềm HRM hàng đầu Việt Nam',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buttons(bool center) {
    return Wrap(
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: onGetStarted,
          icon: const Icon(Icons.rocket_launch_rounded, size: 17),
          label: const Text('Bắt đầu miễn phí',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0C56D0),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
        OutlinedButton.icon(
          onPressed: onLogin,
          icon: const Icon(Icons.login_rounded, size: 17, color: Colors.white),
          label: const Text('Đăng nhập',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _statsRow(bool center) {
    return Wrap(
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      spacing: 32,
      runSpacing: 16,
      children: [
        _stat('500+', 'Doanh nghiệp'),
        _stat('10.000+', 'Nhân viên'),
        _stat('99.9%', 'Uptime'),
      ],
    );
  }

  Widget _stat(String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
        ],
      );

  Widget _glassCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Chấm công hôm nay',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(height: 16),
          ...([
            (
              'Nguyễn Văn A',
              'Vân tay',
              Icons.fingerprint_rounded,
              '07:32',
              true
            ),
            (
              'Trần Thị B',
              'Khuôn mặt',
              Icons.face_retouching_natural_rounded,
              '07:45',
              true
            ),
            ('Lê Văn C', 'Mobile', Icons.smartphone_rounded, '08:01', true),
            ('Phạm Thị D', 'Thủ công', Icons.edit_rounded, '08:15', false),
          ]).map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    child: const Icon(Icons.person,
                        size: 14, color: Colors.white)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(e.$1,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13))),
                Row(children: [
                  Icon(e.$3, size: 11, color: Colors.white54),
                  const SizedBox(width: 3),
                  Text(e.$2,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: e.$5
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.orange.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(e.$4,
                      style: TextStyle(
                          color: e.$5
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFFFDE68A),
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [
              Icon(Icons.trending_up_rounded,
                  color: Color(0xFF93C5FD), size: 20),
              SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hiệu quả công việc',
                    style: TextStyle(color: Colors.white60, fontSize: 11)),
                Text('TĂNG 100%',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── FEATURES ─────────────────────────────────────────────────────────────────
class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection(
      {super.key, required this.isMobile, this.dynamicFeatures});
  final bool isMobile;
  final List<({String title, String desc})>? dynamicFeatures;

  static const features = [
    (
      Icons.fingerprint_rounded,
      '0C56D0',
      'Chấm công ZKTeco',
      'Tích hợp máy chấm công ZKTeco tự động, dữ liệu đồng bộ real-time qua giao thức ADMS/PUSH.'
    ),
    (
      Icons.phone_android_rounded,
      '0D47A1',
      'Chấm công Mobile',
      'Check-in/out qua App bằng GPS, WiFi điểm chấm, nhận diện khuôn mặt (Face ID) hoặc quét mã QR – không cần máy phần cứng.'
    ),
    (
      Icons.schedule_rounded,
      '1565C0',
      'Quản lý ca làm việc',
      'Tạo ca linh hoạt, xoay ca, tăng ca, nghỉ bù. Hỗ trợ ca qua đêm và lịch làm việc phức tạp.'
    ),
    (
      Icons.payments_rounded,
      '1976D2',
      'Tính lương tự động',
      'Tự động tính lương theo ngày công, phụ cấp, thưởng, khấu trừ BHXH/thuế TNCN.'
    ),
    (
      Icons.beach_access_rounded,
      '1E88E5',
      'Quản lý nghỉ phép',
      'Theo dõi ngày phép, xét duyệt trực tuyến, tổng hợp báo cáo nghỉ phép theo tháng/năm.'
    ),
    (
      Icons.location_on_rounded,
      '2196F3',
      'Chấm công hiện trường',
      'GPS check-in/check-out có ảnh xác thực khuôn mặt, hỗ trợ nhân viên field sales và giao hàng.'
    ),
    (
      Icons.inventory_2_rounded,
      '00897B',
      'Quản lý tài sản',
      'Theo dõi tài sản cấp phát cho nhân viên, lịch sử bàn giao, mã QR tra cứu nhanh, cảnh báo hết hạn bảo trì.'
    ),
    (
      Icons.campaign_rounded,
      '6D4C41',
      'Truyền thông nội bộ',
      'Đăng thông báo, tin tức công ty, nội quy lao động, tài liệu đào tạo – nhân viên nhận thông qua App tức thì.'
    ),
    (
      Icons.rate_review_rounded,
      '558B2F',
      'Ph\u1ea3n \u00e1nh & \u00dd ki\u1ebfn',
      'K\u00eanh ph\u1ea3n \u00e1nh \u1ea9n danh ho\u1eb7c c\u00f4ng khai, ban l\u00e3nh \u0111\u1ea1o theo d\u00f5i v\u00e0 ph\u1ea3n h\u1ed3i tr\u1ef1c ti\u1ebfp tr\u00ean h\u1ec7 th\u1ed1ng.'
    ),
    (
      Icons.assessment_rounded,
      '42A5F5',
      'Báo cáo & Phân tích',
      'Dashboard trực quan, báo cáo chuyên cần, tổng hợp lương, xuất Excel tức thì.'
    ),
    (
      Icons.restaurant_rounded,
      '0C56D0',
      'Quản lý bữa ăn',
      'Đăng ký xuất ăn, theo dõi khẩu phần thực tế, báo cáo chi phí bữa ăn hàng ngày.'
    ),
    (
      Icons.task_alt_rounded,
      '1565C0',
      'Quản lý công việc',
      'Giao việc, theo dõi tiến độ, KPI cá nhân và phòng ban theo thời gian thực.'
    ),
    (
      Icons.school_rounded,
      '6A1B9A',
      'Đào tạo & Phát triển',
      'Tạo khóa học nội bộ, giao bài kiểm tra, theo dõi tiến độ học tập và kết quả đào tạo của từng nhân viên.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF9FAFB),
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 24 : 80, vertical: 80),
      child: Column(
        children: [
          const _SectionBadge('Tính năng'),
          const SizedBox(height: 12),
          const _SectionTitle('Tất cả những gì bạn cần\nđể quản lý nhân sự'),
          const SizedBox(height: 8),
          const _SectionSubtext(
              '13 nhóm tính năng HR toàn diện, thiết kế riêng cho doanh nghiệp Việt Nam'),
          const SizedBox(height: 48),
          _buildGrid(),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    // If admin has set dynamic features via API, show those (text-only cards)
    if (dynamicFeatures != null && dynamicFeatures!.isNotEmpty) {
      final colors = [
        const Color(0xFF0C56D0),
        const Color(0xFF1565C0),
        const Color(0xFF1976D2),
        const Color(0xFF1E88E5),
        const Color(0xFF00897B),
        const Color(0xFF6A1B9A)
      ];
      final icons = [
        Icons.fingerprint_rounded,
        Icons.schedule_rounded,
        Icons.payments_rounded,
        Icons.beach_access_rounded,
        Icons.location_on_rounded,
        Icons.assessment_rounded,
        Icons.restaurant_rounded,
        Icons.task_alt_rounded,
        Icons.phone_android_rounded
      ];
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isMobile ? 1 : 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          mainAxisExtent: isMobile ? 110 : 170,
        ),
        itemCount: dynamicFeatures!.length,
        itemBuilder: (_, i) {
          final f = dynamicFeatures![i];
          final color = colors[i % colors.length];
          final icon = icons[i % icons.length];
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(f.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF111827))),
                      const SizedBox(height: 4),
                      Text(f.desc,
                          style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                              height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    // Fallback: hardcoded features with icons
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 1 : 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: isMobile ? 110 : 170,
      ),
      itemCount: features.length,
      itemBuilder: (_, i) {
        final f = features[i];
        final color = Color(int.parse('FF${f.$2}', radix: 16));
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(f.$1, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(f.$3,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 4),
                    Text(f.$4,
                        style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                            height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── PRICING ──────────────────────────────────────────────────────────────────
class _PricingSection extends StatelessWidget {
  const _PricingSection(
      {super.key,
      required this.isMobile,
      required this.onContact,
      required this.onRegister,
      this.dynamicPlans});
  final bool isMobile;
  final List<
      ({
        String name,
        String price,
        String unit,
        String desc,
        bool highlight,
        bool contactOnly,
        List<String> features
      })>? dynamicPlans;
  final VoidCallback onContact;
  final ValueChanged<String?> onRegister;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 24 : 80, vertical: 80),
      child: Column(
        children: [
          const _SectionBadge('Bảng giá'),
          const SizedBox(height: 12),
          const _SectionTitle('Gói dịch vụ phù hợp\nvới mọi quy mô'),
          const SizedBox(height: 8),
          const _SectionSubtext(
              'Thanh toán theo năm • Đã bao gồm VAT • Không phí cài đặt • Hủy bất kỳ lúc nào'),
          const SizedBox(height: 48),
          isMobile ? _buildMobileCards(context) : _buildDesktopCards(context),
          const SizedBox(height: 24),
          Text('* Giá chưa bao gồm VAT. Liên hệ để được tư vấn gói phù hợp.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  static const plans = [
    _Plan(
      name: 'Miễn phí',
      price: '0',
      unit: '/tháng',
      tag: '',
      color: 0xFF757575,
      highlight: false,
      contactOnly: false,
      desc: 'Trải nghiệm đầy đủ tính năng cơ bản',
      features: [
        'Tối đa 10 nhân viên',
        '1 thiết bị ZKTeco',
        'Chấm công & báo cáo cơ bản',
        'App mobile',
        'Hỗ trợ qua email'
      ],
    ),
    _Plan(
      name: 'Hộ kinh doanh',
      price: '900.000',
      unit: 'đ/năm',
      tag: 'Phổ biến',
      color: 0xFF0C56D0,
      highlight: true,
      contactOnly: false,
      desc: 'Dành cho hộ kinh doanh & cửa hàng nhỏ',
      features: [
        'Tối đa 30 nhân viên',
        '2 thiết bị ZKTeco',
        'Chấm công & ca làm việc',
        'Tính lương tự động',
        'Quản lý nghỉ phép',
        'Báo cáo chi tiết',
        'Hỗ trợ Zalo 24/7'
      ],
    ),
    _Plan(
      name: 'Doanh nghiệp',
      price: '1.450.000',
      unit: 'đ/năm',
      tag: '',
      color: 0xFF1565C0,
      highlight: false,
      contactOnly: false,
      desc: 'Cho doanh nghiệp vừa và lớn',
      features: [
        'Không giới hạn nhân viên',
        '5 thiết bị ZKTeco',
        'Đầy đủ tính năng HRM',
        'Chấm công ngoài hiện trường',
        'KPI & công việc',
        'Quản lý bữa ăn',
        'Google Sheets sync',
        'Hỗ trợ ưu tiên 24/7'
      ],
    ),
    _Plan(
      name: 'Nhà máy SX',
      price: 'Từ 1.950.000',
      unit: 'đ/năm',
      tag: 'Chuyên biệt',
      color: 0xFF0D47A1,
      highlight: false,
      contactOnly: true,
      desc: 'Tối ưu cho nhà máy sản xuất',
      features: [
        'Không giới hạn nhân viên',
        'Không giới hạn thiết bị',
        'Chấm công nhiều ca / dây chuyền',
        'Sản lượng & KPI sản xuất',
        'Tích hợp ERP/Odoo',
        'Báo cáo nhà máy chuyên sâu',
        'Triển khai tại chỗ (on-premise)',
        'Hỗ trợ kỹ thuật riêng'
      ],
    ),
  ];

  Widget _buildMobileCards(BuildContext context) {
    final displayPlans = dynamicPlans != null && dynamicPlans!.isNotEmpty
        ? dynamicPlans!.map((d) => _planFromDynamic(d)).toList()
        : plans;
    return Column(
      children: displayPlans
          .map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _PricingCard(
                    plan: p,
                    isMobile: true,
                    onContact: onContact,
                    onRegister: onRegister),
              ))
          .toList(),
    );
  }

  Widget _buildDesktopCards(BuildContext context) {
    final displayPlans = dynamicPlans != null && dynamicPlans!.isNotEmpty
        ? dynamicPlans!.map((d) => _planFromDynamic(d)).toList()
        : plans;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: displayPlans
          .map((p) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _PricingCard(
                      plan: p,
                      isMobile: false,
                      onContact: onContact,
                      onRegister: onRegister),
                ),
              ))
          .toList(),
    );
  }

  static _Plan _planFromDynamic(
      ({
        String name,
        String price,
        String unit,
        String desc,
        bool highlight,
        bool contactOnly,
        List<String> features
      }) d) {
    return _Plan(
      name: d.name,
      price: d.price,
      unit: d.unit,
      tag: d.highlight ? 'Phổ biến' : (d.contactOnly ? 'Chuyên biệt' : ''),
      color:
          d.highlight ? 0xFF0C56D0 : (d.contactOnly ? 0xFF0D47A1 : 0xFF757575),
      highlight: d.highlight,
      contactOnly: d.contactOnly,
      desc: d.desc,
      features: d.features,
    );
  }
}

class _Plan {
  const _Plan(
      {required this.name,
      required this.price,
      required this.unit,
      required this.tag,
      required this.color,
      required this.highlight,
      required this.contactOnly,
      required this.desc,
      required this.features});
  final String name, price, unit, tag, desc;
  final int color;
  final bool highlight;
  final bool contactOnly;
  final List<String> features;
}

class _PricingCard extends StatelessWidget {
  const _PricingCard(
      {required this.plan,
      required this.isMobile,
      required this.onContact,
      required this.onRegister});
  final _Plan plan;
  final bool isMobile;
  final VoidCallback onContact;
  final ValueChanged<String?> onRegister;

  @override
  Widget build(BuildContext context) {
    final color = Color(plan.color);
    return Container(
      decoration: BoxDecoration(
        color: plan.highlight ? color : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: plan.highlight ? color : const Color(0xFFE5E7EB),
            width: plan.highlight ? 0 : 1),
        boxShadow: plan.highlight
            ? [
                BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8))
              ]
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(plan.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: plan.highlight
                              ? Colors.white
                              : const Color(0xFF111827))),
                  if (plan.tag.isNotEmpty) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: plan.highlight
                            ? Colors.white.withValues(alpha: 0.2)
                            : color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(plan.tag,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: plan.highlight ? Colors.white : color)),
                    ),
                  ],
                ]),
                const SizedBox(height: 6),
                Text(plan.desc,
                    style: TextStyle(
                        fontSize: 12,
                        color: plan.highlight
                            ? Colors.white70
                            : const Color(0xFF6B7280))),
                const SizedBox(height: 16),
                RichText(
                    text: TextSpan(children: [
                  TextSpan(
                      text: plan.price,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: plan.highlight
                              ? Colors.white
                              : const Color(0xFF111827))),
                  TextSpan(
                      text: ' ${plan.unit}',
                      style: TextStyle(
                          fontSize: 13,
                          color: plan.highlight
                              ? Colors.white70
                              : const Color(0xFF6B7280))),
                ])),
              ],
            ),
          ),
          // Divider
          Divider(
              height: 1,
              color: plan.highlight
                  ? Colors.white.withValues(alpha: 0.2)
                  : const Color(0xFFE5E7EB)),
          // Features
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                ...plan.features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16,
                            color: plan.highlight ? Colors.white : color),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(f,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: plan.highlight
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : const Color(0xFF374151)))),
                      ]),
                    )),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: plan.price == '0'
                        ? () => onRegister(plan.name)
                        : (plan.contactOnly
                            ? onContact
                            : () => onRegister(plan.name)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: plan.highlight ? Colors.white : color,
                      foregroundColor: plan.highlight ? color : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: Text(
                      plan.price == '0'
                          ? 'Dùng miễn phí'
                          : (plan.contactOnly
                              ? 'Liên hệ ngay'
                              : 'Đăng ký ngay'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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

// ─── VIDEO ────────────────────────────────────────────────────────────────────
class _VideoSection extends StatelessWidget {
  const _VideoSection({
    super.key,
    required this.isMobile,
    required this.videoIntroUrl,
    required this.videoIntroTitle,
    required this.videoIntroSubtitle,
    required this.videoIntroBadge,
    required this.videoIntroDuration,
    required this.videoGuideUrl,
    required this.videoGuideTitle,
    required this.videoGuideSubtitle,
    required this.videoGuideBadge,
    required this.videoGuideDuration,
  });
  final bool isMobile;
  final String videoIntroUrl,
      videoIntroTitle,
      videoIntroSubtitle,
      videoIntroBadge,
      videoIntroDuration;
  final String videoGuideUrl,
      videoGuideTitle,
      videoGuideSubtitle,
      videoGuideBadge,
      videoGuideDuration;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFF),
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 24 : 80, vertical: 72),
      child: Column(
        children: [
          const _SectionBadge('Video'),
          const SizedBox(height: 12),
          const _SectionTitle('Xem SBOX HRM\nhoạt động thực tế'),
          const SizedBox(height: 8),
          const _SectionSubtext(
              'Không cần đăng ký – xem ngay video giới thiệu và hướng dẫn sử dụng'),
          const SizedBox(height: 48),
          isMobile
              ? Column(children: [
                  _VideoCard(
                    title: videoIntroTitle,
                    subtitle: videoIntroSubtitle,
                    icon: Icons.play_circle_filled_rounded,
                    color: const Color(0xFF0C56D0),
                    badge: videoIntroBadge,
                    url: videoIntroUrl,
                    duration: videoIntroDuration,
                  ),
                  const SizedBox(height: 16),
                  _VideoCard(
                    title: videoGuideTitle,
                    subtitle: videoGuideSubtitle,
                    icon: Icons.school_rounded,
                    color: const Color(0xFF1565C0),
                    badge: videoGuideBadge,
                    url: videoGuideUrl,
                    duration: videoGuideDuration,
                  ),
                ])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _VideoCard(
                        title: videoIntroTitle,
                        subtitle: videoIntroSubtitle,
                        icon: Icons.play_circle_filled_rounded,
                        color: const Color(0xFF0C56D0),
                        badge: videoIntroBadge,
                        url: videoIntroUrl,
                        duration: videoIntroDuration,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _VideoCard(
                        title: videoGuideTitle,
                        subtitle: videoGuideSubtitle,
                        icon: Icons.school_rounded,
                        color: const Color(0xFF1565C0),
                        badge: videoGuideBadge,
                        url: videoGuideUrl,
                        duration: videoGuideDuration,
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}

class _VideoCard extends StatefulWidget {
  const _VideoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.badge,
    required this.url,
    required this.duration,
  });
  final String title, subtitle, badge, url, duration;
  final IconData icon;
  final Color color;

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  bool _hovered = false;

  Future<void> _openYoutube() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openPlayer() async {
    final videoId = _extractYouTubeId(widget.url);
    if (videoId == null || videoId.isEmpty) {
      await _openYoutube();
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _LandingVideoPlayerDialog(
        videoId: videoId,
        title: widget.title,
        subtitle: widget.subtitle,
        url: widget.url,
        onOpenYoutube: _openYoutube,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoId = _extractYouTubeId(widget.url);
    final thumbUrl = videoId != null
        ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg'
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _openPlayer,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? widget.color.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.18),
                blurRadius: _hovered ? 32 : 12,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Thumbnail background ──────────────────────────────
                  if (thumbUrl != null)
                    Image.network(
                      thumbUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: widget.color.withValues(alpha: 0.15)),
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : Container(color: widget.color.withValues(alpha: 0.12)),
                    )
                  else
                    Container(color: widget.color.withValues(alpha: 0.12)),

                  // ── Gradient overlay: bottom-heavy for text legibility ─
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.38, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.08),
                          Colors.black.withValues(alpha: 0.20),
                          Colors.black.withValues(alpha: 0.82),
                        ],
                      ),
                    ),
                  ),

                  // ── Play button (centre) ──────────────────────────────
                  Align(
                    alignment: const Alignment(0, -0.18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: _hovered ? 72 : 62,
                      height: _hovered ? 72 : 62,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: _hovered ? 1.0 : 0.88),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: widget.color.withValues(alpha: 0.55),
                              blurRadius: 28,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 34),
                    ),
                  ),

                  // ── Duration badge (top-right) ────────────────────────
                  Positioned(
                    top: 12,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.70),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(widget.duration,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),

                  // ── Text content overlaid at bottom ───────────────────
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Title row
                          Row(children: [
                            Icon(widget.icon, color: Colors.white, size: 15),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Colors.white),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          // Subtitle
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.82)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          // Badge button
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: widget.color,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(widget.badge,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _extractYouTubeId(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    if (uri.host.contains('youtube.com')) {
      if (uri.pathSegments.contains('embed') ||
          uri.pathSegments.contains('shorts')) {
        return uri.pathSegments.last;
      }
      return uri.queryParameters['v'];
    }
  } catch (_) {}
  return null;
}

class _LandingVideoPlayerDialog extends StatelessWidget {
  const _LandingVideoPlayerDialog({
    required this.videoId,
    required this.title,
    required this.subtitle,
    required this.url,
    required this.onOpenYoutube,
  });

  final String videoId;
  final String title;
  final String subtitle;
  final String url;
  final Future<void> Function() onOpenYoutube;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final dialogWidth =
        width > 1280 ? 1100.0 : (width > 900 ? width * 0.82 : width - 24);
    return Dialog(
      backgroundColor: const Color(0xFF020617),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 13,
                              height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: LandingYoutubePlayer(videoId: videoId, autoplay: true),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () async => onOpenYoutube(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Xem trên YouTube'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF475569)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.fullscreen_exit_rounded, size: 18),
                    label: const Text('Thu nhỏ / Đóng'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Bạn có thể dùng nút fullscreen ngay trong trình phát để phóng to toàn màn hình.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── GUIDE ────────────────────────────────────────────────────────────────────
/// Mỗi step gồm: tiêu đề, mô tả, danh sách điểm nổi bật, tip, màu accent,
/// icon đại diện và một màu gradient để vẽ mock-screen minh hoạ.
class _GuideStep {
  const _GuideStep({
    required this.icon,
    required this.title,
    required this.desc,
    required this.bullets,
    required this.tip,
    required this.accent,
    required this.screenGradient,
    required this.screenItems,
  });
  final IconData icon;
  final String title, desc, tip;
  final List<String> bullets;
  final Color accent;
  final List<Color> screenGradient;

  /// Fake UI elements shown on the mock screen
  final List<(IconData, String)> screenItems;
}

class _GuideSection extends StatefulWidget {
  const _GuideSection({super.key, required this.isMobile});
  final bool isMobile;

  static final steps = <_GuideStep>[
    const _GuideStep(
      icon: Icons.app_registration_rounded,
      title: 'Đăng ký tài khoản',
      desc:
          'Truy cập sboxhrm.com, điền thông tin cửa hàng/công ty, số điện thoại và mật khẩu. Hệ thống tự tạo mã cửa hàng và tài khoản quản trị trong vòng 5 phút – hoàn toàn miễn phí.',
      bullets: [
        'Không cần thẻ tín dụng, không cam kết dài hạn',
        'Nhận ngay mã Store ID để cấu hình thiết bị',
        'Tài khoản Admin mặc định được tạo tự động',
        'Có thể thêm Sub-admin phân quyền theo bộ phận',
      ],
      tip: 'Dùng số điện thoại thật – OTP kích hoạt gửi về SMS trong 60 giây.',
      accent: Color(0xFF0C56D0),
      screenGradient: [Color(0xFF0C56D0), Color(0xFF1976D2)],
      screenItems: [
        (Icons.storefront_rounded, 'Tên cửa hàng / công ty'),
        (Icons.phone_rounded, 'Số điện thoại quản trị'),
        (Icons.lock_rounded, 'Mật khẩu (≥ 8 ký tự)'),
        (Icons.badge_rounded, 'Store ID: SBOX-00123'),
      ],
    ),
    const _GuideStep(
      icon: Icons.settings_input_component_rounded,
      title: 'Kết nối máy chấm công',
      desc:
          'Trên máy ZKTeco, vào Thiết lập liên kết → Máy chủ đám mây, nhập Địa chỉ máy chủ: 103.133.224.176 và Port: 7070. Hệ thống tự nhận dữ liệu qua ADMS – không cần cài phần mềm thêm.',
      bullets: [
        'Menu máy: Thiết lập liên kết → Máy chủ đám mây',
        'Địa chỉ máy chủ: 103.133.224.176',
        'Port: 7070',
        'Kiểm tra kết nối real-time ngay trên dashboard',
      ],
      tip:
          'Chưa biết cách cấu hình? Đội kỹ thuật hỗ trợ từ xa qua Zalo trong 30 phút.',
      accent: Color(0xFF1565C0),
      screenGradient: [Color(0xFF1565C0), Color(0xFF0D47A1)],
      screenItems: [
        (Icons.link_rounded, 'Thiết lập liên kết → Máy chủ đám mây'),
        (Icons.router_rounded, 'Địa chỉ máy chủ: 103.133.224.176'),
        (Icons.cable_rounded, 'Port: 7070'),
        (Icons.sync_rounded, 'Đồng bộ lần cuối: 2 phút trước'),
      ],
    ),
    const _GuideStep(
      icon: Icons.group_add_rounded,
      title: 'Thêm nhân viên & sinh trắc học',
      desc:
          'Import danh sách nhân viên qua file Excel mẫu hoặc nhập thủ công. Đăng ký vân tay / khuôn mặt trực tiếp trên máy ZKTeco – dữ liệu đồng bộ lên hệ thống tức thì.',
      bullets: [
        'Import Excel hàng loạt – cập nhật hàng trăm nhân viên/lần',
        'Vân tay & khuôn mặt tự đẩy từ máy vào profile nhân viên',
        'Phân công phòng ban, chức vụ, mức lương cơ bản',
        'Tự động tạo tài khoản App mobile cho từng nhân viên',
      ],
      tip: 'File Excel mẫu tải tại Nhân viên → Nhập dữ liệu → Tải mẫu.',
      accent: Color(0xFF00897B),
      screenGradient: [Color(0xFF00897B), Color(0xFF00695C)],
      screenItems: [
        (Icons.upload_file_rounded, 'Import Excel – 45 nhân viên'),
        (Icons.person_add_rounded, 'Nguyễn Văn A · KD-001'),
        (Icons.fingerprint_rounded, 'Vân tay: 2 ngón đã đăng ký'),
        (Icons.face_retouching_natural_rounded, 'Face ID: Đã kích hoạt ✓'),
      ],
    ),
    const _GuideStep(
      icon: Icons.tune_rounded,
      title: 'Thiết lập ca làm việc',
      desc:
          'Tạo ca linh hoạt theo giờ vào/ra, thời gian trễ cho phép và quy tắc tăng ca. Phân ca cho từng nhân viên hoặc cả phòng ban. Hỗ trợ ca qua đêm và lịch xoay ca tự động.',
      bullets: [
        'Ca cố định, ca xoay tuần, ca qua đêm đều hỗ trợ',
        'Cài thời gian làm thêm giờ và hệ số lương OT',
        'Phân ca theo phòng ban hoặc từng cá nhân',
        'Lịch làm việc tự động tính ngày nghỉ bù và phép năm',
      ],
      tip:
          'Dùng tính năng "Nhân bản ca" để tạo nhanh ca tương tự mà không cần nhập lại.',
      accent: Color(0xFF6A1B9A),
      screenGradient: [Color(0xFF6A1B9A), Color(0xFF4A148C)],
      screenItems: [
        (Icons.schedule_rounded, 'Ca Sáng: 07:30 – 16:30'),
        (Icons.nights_stay_rounded, 'Ca Đêm: 22:00 – 06:00'),
        (Icons.repeat_rounded, 'Xoay ca: Tuần A / Tuần B'),
        (Icons.people_rounded, 'Phân ca: Bộ phận Kho (12 NV)'),
      ],
    ),
    const _GuideStep(
      icon: Icons.bar_chart_rounded,
      title: 'Theo dõi & xuất báo cáo',
      desc:
          'Dashboard real-time hiển thị chấm công, đi muộn, vắng mặt ngay trong ngày. Lương và nghỉ phép tính tự động cuối tháng. Xuất Excel / PDF một cú nhấp.',
      bullets: [
        'Dashboard: tổng hợp toàn công ty theo ngày/tuần/tháng',
        'Báo cáo lương tự động: ngày công × đơn giá + phụ cấp',
        'Xuất Excel chi tiết gửi kế toán, xuất PDF gửi nhân viên',
        'Cảnh báo tự động qua App khi nhân viên đi muộn hoặc quên chấm',
      ],
      tip:
          'Bật thông báo push trên App để nhận cảnh báo đi muộn ngay khi xảy ra.',
      accent: Color(0xFF1976D2),
      screenGradient: [Color(0xFF1976D2), Color(0xFF0D47A1)],
      screenItems: [
        (Icons.check_circle_rounded, 'Đúng giờ: 38 / 45 NV'),
        (Icons.watch_later_rounded, 'Đi muộn: 4 NV · Trung bình 12\''),
        (Icons.money_rounded, 'Lương tháng: 285.500.000 đ'),
        (Icons.picture_as_pdf_rounded, 'Xuất PDF · Xuất Excel'),
      ],
    ),
  ];

  @override
  State<_GuideSection> createState() => _GuideSectionState();
}

class _GuideSectionState extends State<_GuideSection> {
  int _active = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0F1E),
      padding: EdgeInsets.symmetric(
        horizontal: widget.isMobile ? 20 : 80,
        vertical: 80,
      ),
      child: Column(
        children: [
          const _SectionBadge('Hướng dẫn sử dụng', dark: true),
          const SizedBox(height: 12),
          const _SectionTitle('Bắt đầu trong\n5 bước đơn giản', dark: true),
          const SizedBox(height: 8),
          const _SectionSubtext(
            'Không cần kỹ năng IT · Hỗ trợ cài đặt tận nơi hoặc từ xa · Vận hành trong 2–4 giờ',
            dark: true,
          ),
          const SizedBox(height: 48),
          widget.isMobile ? _buildMobile() : _buildDesktop(),
        ],
      ),
    );
  }

  // ── DESKTOP: step tabs on left, content+screen on right ──────────────────
  Widget _buildDesktop() {
    final step = _GuideSection.steps[_active];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step tab list
        SizedBox(
          width: 260,
          child: Column(
            children: _GuideSection.steps.asMap().entries.map((e) {
              final i = e.key;
              final s = e.value;
              final active = i == _active;
              return GestureDetector(
                onTap: () => setState(() => _active = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: active
                        ? s.accent.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? s.accent.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color:
                            active ? s.accent : Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${i + 1}',
                            style: TextStyle(
                              color: active ? Colors.white : Colors.white54,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            )),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.title,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.white60,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (active)
                      Icon(Icons.arrow_forward_ios_rounded,
                          color: s.accent, size: 12),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 40),
        // Detail + mock screen
        Expanded(child: _buildDetail(step, false)),
      ],
    );
  }

  // ── MOBILE: accordion steps ───────────────────────────────────────────────
  Widget _buildMobile() {
    return Column(
      children: _GuideSection.steps.asMap().entries.map((e) {
        final i = e.key;
        final s = e.value;
        final open = i == _active;
        return GestureDetector(
          onTap: () => setState(() => _active = open ? -1 : i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: open
                  ? s.accent.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: open
                    ? s.accent.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: open ? s.accent : Colors.white12,
                          shape: BoxShape.circle),
                      child: Center(
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(s.title,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight:
                                    open ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 14))),
                    Icon(
                        open
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.white54),
                  ]),
                ),
                if (open) ...[
                  const Divider(color: Colors.white12, height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    child: _buildDetail(s, true),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Shared detail panel ───────────────────────────────────────────────────
  Widget _buildDetail(_GuideStep step, bool mobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mock screen UI
        _MockScreen(step: step, isMobile: mobile),
        const SizedBox(height: 28),
        // Description
        Text(step.desc,
            style: const TextStyle(
                color: Colors.white70, fontSize: 14, height: 1.65)),
        const SizedBox(height: 20),
        // Bullet points
        ...step.bullets.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: step.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(b,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.5))),
              ]),
            )),
        const SizedBox(height: 16),
        // Tip box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: step.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: step.accent.withValues(alpha: 0.35)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.tips_and_updates_rounded, color: step.accent, size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Text(step.tip,
                    style: TextStyle(
                        color: step.accent, fontSize: 12.5, height: 1.5))),
          ]),
        ),
      ],
    );
  }
}

// ── Mock screen widget (drawn UI, no real images) ─────────────────────────────
class _MockScreen extends StatelessWidget {
  const _MockScreen({required this.step, required this.isMobile});
  final _GuideStep step;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: step.accent.withValues(alpha: 0.3),
              blurRadius: 32,
              offset: const Offset(0, 8))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: const Color(0xFF111827),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: step.screenGradient),
                ),
                child: Row(children: [
                  Icon(step.icon, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(step.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                  // Fake window controls
                  Row(children: [
                    _dot(Colors.white30),
                    const SizedBox(width: 5),
                    _dot(Colors.white30),
                    const SizedBox(width: 5),
                    _dot(Colors.white30),
                  ]),
                ]),
              ),
              // Content rows
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: step.screenItems.asMap().entries.map((e) {
                    final i = e.key;
                    final item = e.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: i == 0
                            ? step.accent.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: i == 0
                              ? step.accent.withValues(alpha: 0.45)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(children: [
                        Icon(item.$1,
                            size: 16,
                            color: i == 0 ? step.accent : Colors.white38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(item.$2,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: i == 0 ? Colors.white : Colors.white60,
                                fontWeight:
                                    i == 0 ? FontWeight.w600 : FontWeight.w400,
                              )),
                        ),
                        if (i == 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: step.accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('MỚI',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800)),
                          ),
                      ]),
                    );
                  }).toList(),
                ),
              ),
              // Bottom status bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.white.withValues(alpha: 0.04),
                child: Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFF22C55E), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  const Text('Kết nối thành công · SBOX HRM',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 11)),
                  const Spacer(),
                  const Text('v3.2.1',
                      style:
                          TextStyle(color: Colors.white24, fontSize: 10)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

// ─── CONTACT ──────────────────────────────────────────────────────────────────
class _ContactSection extends StatelessWidget {
  const _ContactSection({
    super.key,
    required this.isMobile,
    required this.phone,
    required this.zaloNumber,
    required this.email,
    required this.onCallPhone,
    required this.onOpenZalo,
    required this.onOpenEmail,
  });
  final bool isMobile;
  final String phone;
  final String zaloNumber;
  final String email;
  final VoidCallback onCallPhone;
  final VoidCallback onOpenZalo;
  final VoidCallback onOpenEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A3880), Color(0xFF0C56D0), Color(0xFF1976D2)],
        ),
      ),
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 24 : 80, vertical: 80),
      child: isMobile ? _buildMobile(context) : _buildDesktop(context),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: _leftContent()),
        const SizedBox(width: 60),
        Expanded(
            flex: 5,
            child: _RegisterForm(zaloNumber: zaloNumber, supportEmail: email)),
      ],
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Column(children: [
      _leftContent(),
      const SizedBox(height: 40),
      _RegisterForm(zaloNumber: zaloNumber, supportEmail: email),
    ]);
  }

  Widget _leftContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('LIÊN HỆ & HỖ TRỢ',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        const SizedBox(height: 12),
        const Text('Sẵn sàng nâng cấp\nquản lý nhân sự?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1.2)),
        const SizedBox(height: 16),
        Text(
            'Đội ngũ tư vấn sẵn sàng hỗ trợ bạn chọn gói phù hợp, cài đặt thiết bị và đào tạo sử dụng — tất cả trong vòng 24 giờ làm việc.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 15,
                height: 1.6)),
        const SizedBox(height: 28),
        // Quick action buttons
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _quickBtn(Icons.phone_rounded, 'Gọi ngay', onCallPhone),
            _quickBtn(Icons.chat_rounded, 'Nhắn Zalo', onOpenZalo),
          ],
        ),
        const SizedBox(height: 28),
        _contactItem(
            Icons.phone_rounded, 'Hotline hỗ trợ kỹ thuật', phone, onCallPhone),
        const SizedBox(height: 14),
        _contactItem(
            Icons.chat_rounded, 'Zalo hỗ trợ kỹ thuật', _formatZaloPhone, onOpenZalo),
        const SizedBox(height: 14),
        _contactItem(Icons.email_rounded, 'Email', email, onOpenEmail),
        const SizedBox(height: 14),
        _contactItem(Icons.location_on_rounded, 'Địa chỉ',
            'Việt Nam — Hỗ trợ toàn quốc', null),
        const SizedBox(height: 14),
        _contactItem(Icons.access_time_rounded, 'Giờ hỗ trợ',
            'Thứ 2 – Thứ 7: 8:00 – 22:00 | Chủ nhật: 9:00 – 17:00', null),
      ],
    );
  }

  String get _formatZaloPhone {
    final digits = zaloNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '${digits.substring(0, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}';
    }
    return zaloNumber;
  }

  Widget _quickBtn(IconData icon, String label, VoidCallback onTap) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0C56D0),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }

  Widget _contactItem(
      IconData icon, String label, String value, VoidCallback? onTap) {
    final row = Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
      const SizedBox(width: 14),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style:
                TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
      ])),
      if (onTap != null)
        const Icon(Icons.arrow_forward_ios_rounded,
            color: Colors.white38, size: 14),
    ]);
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4), child: row),
      );
    }
    return row;
  }
}

class _RegisterForm extends StatefulWidget {
  const _RegisterForm({required this.zaloNumber, required this.supportEmail});

  final String zaloNumber;
  final String supportEmail;

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  String _selectedPlan = 'Hộ kinh doanh';
  bool _isSubmitting = false;
  bool _isDone = false;

  static const plans = [
    'Miễn phí',
    'Hộ kinh doanh',
    'Doanh nghiệp',
    'Nhà máy Sản xuất'
  ];

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final phone = _phoneCtrl.text.trim();
      final name = _nameCtrl.text.trim();
      final company = _companyCtrl.text.trim();
      final province = _provinceCtrl.text.trim();
      final result = await _api.submitLandingConsultation(
        name: name,
        phone: phone,
        company: company.isEmpty ? null : company,
        province: province.isEmpty ? null : province,
        interestedPlan: _selectedPlan,
      );

      if (result['isSuccess'] != true) {
        if (!mounted) return;
        final msg = (result['message']?.toString().isNotEmpty == true)
            ? result['message'].toString()
            : ((result['errors'] is List &&
                    (result['errors'] as List).isNotEmpty)
                ? (result['errors'] as List).join(', ')
                : 'Không thể gửi yêu cầu tư vấn');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      final zaloValue = widget.zaloNumber
          .trim()
          .replaceAll('https://zalo.me/', '')
          .replaceAll(' ', '');
      final zaloUri = Uri.parse('https://zalo.me/$zaloValue');
      if (zaloValue.isNotEmpty && await canLaunchUrl(zaloUri)) {
        await launchUrl(zaloUri, mode: LaunchMode.externalApplication);
      } else {
        final subject =
            Uri.encodeComponent('Yêu cầu tư vấn SBOX HRM - $_selectedPlan');
        final body = Uri.encodeComponent(
          'Xin chào SBOX HRM!\n\n'
          'Họ tên: $name\n'
          'SĐT: $phone\n'
          'Công ty / cửa hàng: ${company.isEmpty ? "(chưa điền)" : company}\n'
          'Tỉnh / thành: ${province.isEmpty ? "(chưa điền)" : province}\n'
          'Gói quan tâm: $_selectedPlan\n\n'
          'Tôi đã gửi form tư vấn trên landing page, vui lòng liên hệ giúp tôi.',
        );
        final mailUri = Uri.parse(
            'mailto:${widget.supportEmail}?subject=$subject&body=$body');
        if (await canLaunchUrl(mailUri)) {
          await launchUrl(mailUri);
        }
      }
    } catch (_) {}
    setState(() {
      _isSubmitting = false;
      _isDone = true;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _companyCtrl.dispose();
    _provinceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10))
        ],
      ),
      child: _isDone ? _successContent() : _formContent(),
    );
  }

  Widget _successContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              color: Color(0xFFEBF2FF), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded,
              color: Color(0xFF0C56D0), size: 48),
        ),
        const SizedBox(height: 20),
        const Text('Yêu cầu đã được gửi!',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Color(0xFF111827))),
        const SizedBox(height: 8),
        const Text(
            'Yêu cầu đã được lưu vào hệ thống. Zalo hoặc email hỗ trợ sẽ được mở để tư vấn viên hỗ trợ bạn ngay.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6B7280), height: 1.5)),
      ],
    );
  }

  Widget _formContent() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Đăng ký tư vấn miễn phí',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF111827))),
          const SizedBox(height: 4),
          const Text(
              'Điền thông tin bên dưới — Zalo tư vấn viên sẽ được mở tự động',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
          const SizedBox(height: 20),
          _field(_nameCtrl, 'Họ và tên', Icons.person_outline,
              validator: (v) => v!.isEmpty ? 'Vui lòng nhập tên' : null),
          const SizedBox(height: 12),
          _field(_phoneCtrl, 'Số điện thoại', Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  v!.length < 9 ? 'Số điện thoại không hợp lệ' : null),
          const SizedBox(height: 12),
          _field(
              _companyCtrl, 'Tên công ty / cửa hàng', Icons.business_outlined),
          const SizedBox(height: 12),
          _field(_provinceCtrl, 'Tỉnh / thành', Icons.location_on_outlined),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedPlan,
            decoration: InputDecoration(
              labelText: 'Gói quan tâm',
              prefixIcon: const Icon(Icons.inventory_2_outlined, size: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            ),
            items: plans
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => setState(() => _selectedPlan = v!),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C56D0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Nhắn Zalo tư vấn ngay',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }
}

// ─── FOOTER ───────────────────────────────────────────────────────────────────
class _FooterLink {
  const _FooterLink(this.label, this.onTap);
  final String label;
  final VoidCallback? onTap;
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.isMobile,
    required this.onFeatures,
    required this.onPricing,
    required this.onGuide,
    required this.onDevices,
    required this.onContact,
    required this.onLogin,
  });
  final bool isMobile;
  final VoidCallback onFeatures;
  final VoidCallback onPricing;
  final VoidCallback onGuide;
  final VoidCallback onDevices;
  final VoidCallback onContact;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 24 : 80, vertical: 48),
      child: Column(
        children: [
          isMobile ? _buildMobile() : _buildDesktop(),
          const SizedBox(height: 32),
          const Divider(color: Color(0xFF374151)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('© 2024–2026 SBOX HRM. Bảo lưu mọi quyền.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              Row(children: [
                Text('Privacy',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(width: 16),
                Text('Terms',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _brand()),
        const SizedBox(width: 48),
        Expanded(
            child: _links('Sản phẩm', [
          _FooterLink('Tính năng', onFeatures),
          _FooterLink('Bảng giá', onPricing),
          _FooterLink('Thiết bị chấm công', onDevices),
          const _FooterLink('Cập nhật mới', null),
        ])),
        Expanded(
            child: _links('Hỗ trợ', [
          _FooterLink('Hướng dẫn sử dụng', onGuide),
          const _FooterLink('FAQ', null),
          _FooterLink('Liên hệ', onContact),
        ])),
        Expanded(
            child: _links('Tài khoản', [
          _FooterLink('Đăng nhập', onLogin),
          _FooterLink('Đăng ký dùng thử', onContact),
        ])),
      ],
    );
  }

  Widget _buildMobile() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _brand(),
      const SizedBox(height: 32),
      _links('Sản phẩm', [
        _FooterLink('Tính năng', onFeatures),
        _FooterLink('Bảng giá', onPricing),
        _FooterLink('Thiết bị', onDevices),
      ]),
      const SizedBox(height: 20),
      _links('Hỗ trợ', [
        _FooterLink('Hướng dẫn', onGuide),
        _FooterLink('Liên hệ', onContact),
        _FooterLink('Đăng nhập', onLogin),
      ]),
    ]);
  }

  Widget _brand() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Image.asset('assets/logo.png',
            height: 42, filterQuality: FilterQuality.high),
        const SizedBox(width: 10),
        const Text('SBOX',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 0.5)),
        const Text(' HRM',
            style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
      ]),
      const SizedBox(height: 12),
      Text('Phần mềm quản lý nhân sự\nthế hệ mới cho doanh nghiệp Việt Nam.',
          style: TextStyle(
              color: Colors.grey.shade500, fontSize: 13, height: 1.6)),
    ]);
  }

  Widget _links(String title, List<_FooterLink> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13)),
        const SizedBox(height: 12),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: item.onTap != null
                  ? InkWell(
                      onTap: item.onTap,
                      child: Text(item.label,
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13)),
                    )
                  : Text(item.label,
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            )),
      ],
    );
  }
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────
class _SectionBadge extends StatelessWidget {
  const _SectionBadge(this.label, {this.dark = false});
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFEBF2FF),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label,
          style: TextStyle(
              color: dark ? Colors.white70 : const Color(0xFF0C56D0),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.dark = false});
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: dark ? Colors.white : const Color(0xFF111827),
            height: 1.2));
  }
}

class _SectionSubtext extends StatelessWidget {
  const _SectionSubtext(this.text, {this.dark = false});
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(
            color: dark ? Colors.white54 : const Color(0xFF6B7280),
            fontSize: 15,
            height: 1.5));
  }
}

// ─── DEVICES SECTION ──────────────────────────────────────────────────────────
class _DevicesSection extends StatelessWidget {
  const _DevicesSection(
      {super.key,
      required this.isMobile,
      required this.onContact,
      this.dynamicProducts});
  final bool isMobile;
  final VoidCallback onContact;
  final List<_ProductData>? dynamicProducts;

  static const _defaultProducts = [
    (
      name: 'ZKTeco LX35',
      sub: 'Máy chấm công vân tay WiFi',
      price: '1.500.000 đ',
      oldPrice: '1.700.000 đ',
      badge: 'Giảm 12%',
      specs: 'Vân tay • WiFi • 500 users',
      specsDetail: '',
      imageUrl:
          'https://maychamcong24h.vn/wp-content/uploads/2024/12/May-cham-cong-Wifi-LX35.jpg',
      link: 'https://maychamcong24h.vn/may-cham-cong-van-tay-wifi-zkteco-lx35/',
      brand: 'ZKTeco',
    ),
    (
      name: 'ZKTeco SenseFace 2A',
      sub: 'Nhận diện khuôn mặt',
      price: '2.530.000 đ',
      oldPrice: '',
      badge: '',
      specs: 'Khuôn mặt • Vân tay • Thẻ • WiFi',
      specsDetail: '',
      imageUrl:
          'https://maychamcong24h.vn/wp-content/uploads/2024/11/may-cham-cong-khuon-mat-zkteco-senseface-2a-10.jpg',
      link:
          'https://maychamcong24h.vn/may-cham-cong-khuon-mat-zkteco-senseface-2a/',
      brand: 'ZKTeco',
    ),
    (
      name: 'Ronald Jack 8300Pro',
      sub: 'Máy chấm công vân tay ADMS',
      price: '2.300.000 đ',
      oldPrice: '2.500.000 đ',
      badge: 'Giảm 8%',
      specs: 'Vân tay • Thẻ • TCP/IP • ADMS',
      specsDetail: '',
      imageUrl:
          'https://maychamcong24h.vn/wp-content/uploads/2024/10/36628_ronald_jack_ua300_ha1.jpg',
      link:
          'https://maychamcong24h.vn/may-cham-cong-van-tay-ronald-jack-8300pro/',
      brand: 'Ronald Jack',
    ),
    (
      name: 'ZKTeco MB10VL',
      sub: 'Nhận diện khuôn mặt ADMS',
      price: '2.100.000 đ',
      oldPrice: '2.500.000 đ',
      badge: 'Giảm 16%',
      specs: 'Khuôn mặt • Vân tay • Thẻ • ADMS',
      specsDetail: '',
      imageUrl:
          'https://maychamcong24h.vn/wp-content/uploads/2024/11/May-cham-cong-khuon-mat-Zkteco-MB10VL.jpg',
      link: 'https://maychamcong24h.vn/may-cham-cong-khuon-mat-zkteco-mb10vl/',
      brand: 'ZKTeco',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFF),
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 20 : 80, vertical: 72),
      child: Column(
        children: [
          const _SectionBadge('THIẾT BỊ CHẤM CÔNG'),
          const SizedBox(height: 16),
          const _SectionTitle('Máy chấm công tương thích'),
          const SizedBox(height: 12),
          const _SectionSubtext(
              'SBOX HRM tích hợp trực tiếp với các máy ZKTeco và Ronald Jack qua giao thức ADMS – cắm vào là dùng ngay.'),
          const SizedBox(height: 48),
          isMobile
              ? _buildMobileGrid(dynamicProducts ?? _defaultProducts)
              : _buildDesktopGrid(dynamicProducts ?? _defaultProducts),
          const SizedBox(height: 36),
          OutlinedButton.icon(
            onPressed: onContact,
            icon: const Icon(Icons.support_agent_rounded, size: 18),
            label: const Text('Tư vấn chọn thiết bị phù hợp'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0C56D0),
              side: const BorderSide(color: Color(0xFF0C56D0)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopGrid(List<_ProductData> products) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: products
          .map((p) => Expanded(
                  child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _ProductCard(product: p),
              )))
          .toList(),
    );
  }

  Widget _buildMobileGrid(List<_ProductData> products) {
    final half = (products.length / 2).ceil();
    final first = products.take(half).toList();
    final second = products.skip(half).toList();
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: first
              .map((p) => Expanded(
                      child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _ProductCard(product: p),
                  )))
              .toList(),
        ),
        if (second.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: second
                .map((p) => Expanded(
                        child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _ProductCard(product: p),
                    )))
                .toList(),
          ),
        ],
      ],
    );
  }
}

typedef _ProductData = ({
  String name,
  String sub,
  String price,
  String oldPrice,
  String badge,
  String specs,
  String specsDetail,
  String imageUrl,
  String link,
  String brand
});

String _normalizePublicUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  if (kIsWeb && value.startsWith('http://')) {
    return 'https://${value.substring(7)}';
  }
  return value;
}

String _deltaJsonToPlainText(String raw) {
  if (raw.isEmpty) return '';
  try {
    final list = jsonDecode(raw) as List;
    final buffer = StringBuffer();
    for (final op in list) {
      if (op is Map && op['insert'] is String) {
        buffer.write(op['insert'] as String);
      }
    }
    return buffer.toString().trim();
  } catch (_) {
    return raw.trim();
  }
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({required this.product});
  final _ProductData product;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hovered = false;

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ProductDetailDialog(product: widget.product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showDetail(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? const Color(0x330C56D0)
                    : const Color(0x18000000),
                blurRadius: _hovered ? 20 : 8,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: _hovered ? const Color(0xFF0C56D0) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: AspectRatio(
                  aspectRatio: 1.1,
                  child: LandingProductImage(
                    imageUrl: _normalizePublicUrl(p.imageUrl),
                    fit: BoxFit.cover,
                    errorIconSize: 48,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEBF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(p.brand,
                          style: const TextStyle(
                              color: Color(0xFF0C56D0),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                    ),
                    const SizedBox(height: 6),
                    Text(p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 2),
                    Text(p.sub,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF6B7280))),
                    const SizedBox(height: 8),
                    // Price row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(p.price,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0C56D0))),
                        if (p.badge.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(p.badge,
                                style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF16A34A))),
                          ),
                        ],
                      ],
                    ),
                    if (p.oldPrice.isNotEmpty)
                      Text(p.oldPrice,
                          style: const TextStyle(
                              fontSize: 11,
                              decoration: TextDecoration.lineThrough,
                              color: Color(0xFF9CA3AF))),
                    const SizedBox(height: 6),
                    Text(p.specs,
                        style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6B7280),
                            height: 1.4)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Spacer(),
                        Text('Xem chi tiết',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _hovered
                                    ? const Color(0xFF0C56D0)
                                    : const Color(0xFF6B7280))),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_forward_rounded,
                            size: 12,
                            color: _hovered
                                ? const Color(0xFF0C56D0)
                                : const Color(0xFF9CA3AF)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductDetailDialog extends StatefulWidget {
  const _ProductDetailDialog({required this.product});
  final _ProductData product;

  @override
  State<_ProductDetailDialog> createState() => _ProductDetailDialogState();
}

class _ProductDetailDialogState extends State<_ProductDetailDialog> {
  quill.QuillController? _quillCtrl;
  late final String _specsDetailText;
  final _focusNode = FocusNode();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final raw = widget.product.specsDetail;
    _specsDetailText = _deltaJsonToPlainText(raw);
    if (raw.isNotEmpty) {
      try {
        if (!kIsWeb) {
          final list = jsonDecode(raw) as List;
          _quillCtrl = quill.QuillController(
            document: quill.Document.fromJson(list),
            selection: const TextSelection.collapsed(offset: 0),
            readOnly: true,
          );
        }
      } catch (_) {
        _quillCtrl = null;
      }
    }
  }

  @override
  void dispose() {
    _quillCtrl?.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final isWide = MediaQuery.of(context).size.width > 600;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 480 : double.infinity),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image
              AspectRatio(
                aspectRatio: isWide ? 16 / 9 : 4 / 3,
                child: LandingProductImage(
                  imageUrl: _normalizePublicUrl(p.imageUrl),
                  fit: BoxFit.cover,
                  errorIconSize: 64,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: const Color(0xFFEBF2FF),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(p.brand,
                          style: const TextStyle(
                              color: Color(0xFF0C56D0),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                    ),
                    const SizedBox(height: 10),
                    Text(p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 4),
                    Text(p.sub,
                        style: const TextStyle(
                            fontSize: 14, color: Color(0xFF6B7280))),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(p.price,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0C56D0))),
                        if (p.badge.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(p.badge,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF16A34A))),
                          ),
                        ],
                      ],
                    ),
                    if (p.oldPrice.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(p.oldPrice,
                          style: const TextStyle(
                              fontSize: 13,
                              decoration: TextDecoration.lineThrough,
                              color: Color(0xFF9CA3AF))),
                    ],
                    const SizedBox(height: 16),
                    // Specs section: rich if available, else plain text summary
                    if (_specsDetailText.isNotEmpty) ...[
                      const Text('Thông số kỹ thuật',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280))),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 320),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFF),
                            borderRadius: BorderRadius.circular(10)),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _specsDetailText,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF374151),
                                height: 1.6),
                          ),
                        ),
                      ),
                    ] else if (_quillCtrl != null) ...[
                      const Text('Thông số kỹ thuật',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280))),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 320),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFF),
                            borderRadius: BorderRadius.circular(10)),
                        child: quill.QuillEditor(
                          controller: _quillCtrl!,
                          scrollController: _scrollCtrl,
                          focusNode: _focusNode,
                          config: const quill.QuillEditorConfig(
                            showCursor: false,
                            padding: EdgeInsets.zero,
                            autoFocus: false,
                            expands: false,
                            scrollable: true,
                          ),
                        ),
                      ),
                    ] else if (p.specs.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFF),
                            borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.memory_rounded,
                                size: 16, color: Color(0xFF0C56D0)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(p.specs,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF374151),
                                        height: 1.5))),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF6B7280),
                              side: const BorderSide(color: Color(0xFFD1D5DB)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Đóng'),
                          ),
                        ),
                        if (p.link.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                final uri =
                                    Uri.parse(_normalizePublicUrl(p.link));
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0C56D0),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Mua ngay'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── DOWNLOAD SECTION ─────────────────────────────────────────────────────────
class _DownloadSection extends StatelessWidget {
  const _DownloadSection(
      {super.key, required this.isMobile, this.dynamicDownloads});
  final bool isMobile;
  final List<_DownloadItemData>? dynamicDownloads;

  static const _defaultDownloads = [
    (
      title: 'APK Android mới nhất',
      desc: 'Cài thủ công cho thiết bị Android nội bộ',
      version: 'v1.0',
      badge: 'APK',
      platform: 'android',
      url: 'https://sbox.sana.vn/#/register'
    ),
    (
      title: 'Driver USB ZKTeco',
      desc: 'Driver kết nối máy chấm công với máy tính Windows',
      version: 'Windows',
      badge: 'Driver',
      platform: 'windows',
      url: 'https://sbox.sana.vn/#/contact'
    ),
    (
      title: 'Bộ cài công cụ đồng bộ',
      desc: 'Tiện ích hỗ trợ cấu hình và kiểm tra kết nối thiết bị',
      version: 'v2.1',
      badge: 'Tool',
      platform: 'desktop',
      url: 'https://sbox.sana.vn/#/contact'
    ),
    (
      title: 'Bản phát hành iOS/TestFlight',
      desc: 'Link cài đặt dành cho đội triển khai và kiểm thử',
      version: 'iOS',
      badge: 'Beta',
      platform: 'ios',
      url: 'https://sbox.sana.vn/#/contact'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final downloads = dynamicDownloads != null && dynamicDownloads!.isNotEmpty
        ? dynamicDownloads!
        : _defaultDownloads;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A3880), Color(0xFF0C56D0)],
        ),
      ),
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 24 : 80, vertical: 64),
      child: Column(
        children: [
          const _SectionBadge('TẢI PHẦN MỀM BỔ SUNG', dark: true),
          const SizedBox(height: 16),
          const _SectionTitle('Tải driver, APK và công cụ hỗ trợ', dark: true),
          const SizedBox(height: 12),
          Text(
            'SuperAdmin có thể cấu hình trực tiếp danh sách driver, APK và các gói cài đặt bổ sung hiển thị trên landing page.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 15,
                height: 1.6),
          ),
          const SizedBox(height: 44),
          isMobile
              ? Column(
                  children: downloads
                      .map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _DownloadBadge(data: item),
                          ))
                      .toList(),
                )
              : Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 18,
                  runSpacing: 18,
                  children: downloads
                      .map((item) => SizedBox(
                          width: 260, child: _DownloadBadge(data: item)))
                      .toList(),
                ),
        ],
      ),
    );
  }
}

typedef _DownloadItemData = ({
  String title,
  String desc,
  String version,
  String badge,
  String platform,
  String url
});

class _DownloadBadge extends StatefulWidget {
  const _DownloadBadge({required this.data});
  final _DownloadItemData data;
  @override
  State<_DownloadBadge> createState() => _DownloadBadgeState();
}

class _DownloadBadgeState extends State<_DownloadBadge> {
  bool _hovered = false;

  IconData _iconForPlatform(String platform) {
    switch (platform.trim().toLowerCase()) {
      case 'android':
        return Icons.android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'windows':
        return Icons.laptop_windows_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      case 'driver':
        return Icons.usb_rounded;
      case 'desktop':
        return Icons.install_desktop_rounded;
      default:
        return Icons.download_rounded;
    }
  }

  Future<void> _open() async {
    final uri = Uri.parse(_normalizePublicUrl(widget.data.url));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30), width: 1),
          ),
          child: Column(
            children: [
              Icon(_iconForPlatform(d.platform), color: Colors.white, size: 32),
              const SizedBox(height: 10),
              Text(d.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
              const SizedBox(height: 4),
              Text(d.desc,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 11,
                      height: 1.4)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                  d.badge.isNotEmpty
                      ? '${d.badge}${d.version.isNotEmpty ? ' • ${d.version}' : ''}'
                      : (d.version.isNotEmpty ? d.version : d.platform),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_rounded, size: 15, color: Colors.white),
                  SizedBox(width: 6),
                  Text('Tải xuống',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
