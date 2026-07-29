import 'dart:convert';
import '../design_system/design_system.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../utils/landing_guide_url.dart';
import '../utils/landing_public_url.dart';
import '../utils/landing_usage_guide.dart';
import '../utils/web_marketing_gate_stub.dart'
    if (dart.library.html) '../utils/web_marketing_gate_web.dart' as web_gate;
import '../widgets/landing_product_image.dart';
import '../widgets/landing_youtube_player.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Trang hướng dẫn sử dụng — mở từ thanh công cụ landing, không nhúng trong trang chủ.
class LandingGuideScreen extends StatefulWidget {
  const LandingGuideScreen({
    super.key,
    this.guideData,
    this.initialLink,
  });

  final LandingGuideData? guideData;
  final GuideDeepLink? initialLink;

  @override
  State<LandingGuideScreen> createState() => _LandingGuideScreenState();
}

class _LandingGuideScreenState extends State<LandingGuideScreen> {
  LandingGuideData _guideData = LandingGuideData.defaults;
  GuideDeepLink? _initialLink;
  late bool _loading;

  @override
  void initState() {
    super.initState();
    _loading = widget.guideData == null;
    _initialLink = widget.initialLink ?? LandingGuideUrl.parseCurrent();
    if (widget.guideData != null) {
      _guideData = widget.guideData!;
    } else {
      _loadGuideData();
    }
  }

  Future<void> _loadGuideData() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/publicsettings'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null && mounted) {
          setState(() {
            _guideData = LandingGuideData.fromApiJson(data['landingGuideJson']);
            _initialLink ??= LandingGuideUrl.parseCurrent();
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) LandingGuideUrl.clearFromBrowser();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0F1E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0F1E),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(tr('Hướng dẫn sử dụng'),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              LandingGuideUrl.clearFromBrowser();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                // Deep-link entry (/guide) has no prior Flutter route — go home.
                web_gate.redirectToStaticHome();
              }
            },
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Desktop: Row+Expanded cần chiều cao giới hạn — tránh Stack Overflow
                  // khi đặt Expanded trong SingleChildScrollView (viewport không giới hạn).
                  if (isMobile) {
                    return SingleChildScrollView(
                      child: LandingGuidePanel(
                        isMobile: true,
                        guideData: _guideData,
                        initialLink: _initialLink,
                      ),
                    );
                  }
                  final panelHeight = (constraints.maxHeight - 32)
                      .clamp(480.0, 900.0);
                  return SingleChildScrollView(
                    child: LandingGuidePanel(
                      isMobile: false,
                      guideData: _guideData,
                      initialLink: _initialLink,
                      desktopBodyHeight: panelHeight,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class LandingGuidePanel extends StatefulWidget {
  const LandingGuidePanel({
    super.key,
    required this.isMobile,
    required this.guideData,
    this.initialLink,
    this.desktopBodyHeight,
  });

  final bool isMobile;
  final LandingGuideData guideData;
  final GuideDeepLink? initialLink;
  /// Chiều cao cố định cho layout 2 cột desktop — tránh Expanded trong scroll vô hạn.
  final double? desktopBodyHeight;

  @override
  State<LandingGuidePanel> createState() => _LandingGuidePanelState();
}

class _LandingGuidePanelState extends State<LandingGuidePanel> {
  int _section = 0;
  int _active = -1;

  List<LandingUsageGuideStep> get _steps =>
      _section == 0 ? widget.guideData.basic : widget.guideData.advanced;

  String get _sectionKey => _section == 0 ? 'basic' : 'advanced';

  @override
  void initState() {
    super.initState();
    _applyDeepLink(widget.initialLink, notify: false);
  }

  @override
  void didUpdateWidget(covariant LandingGuidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialLink != null && _active < 0) {
      _applyDeepLink(widget.initialLink, notify: true);
    }
  }

  bool _applyDeepLink(GuideDeepLink? link, {required bool notify}) {
    if (link == null) return false;
    final steps =
        link.sectionIndex == 0 ? widget.guideData.basic : widget.guideData.advanced;
    final idx = steps.indexWhere((s) => s.id == link.stepId);
    if (idx < 0) return false;
    if (_section == link.sectionIndex && _active == idx) return true;
    if (notify) {
      setState(() {
        _section = link.sectionIndex;
        _active = idx;
      });
    } else {
      _section = link.sectionIndex;
      _active = idx;
    }
    return true;
  }

  void _openStep(int index) {
    setState(() => _active = index);
    LandingGuideUrl.syncToBrowser(
      section: _sectionKey,
      stepId: _steps[index].id,
    );
  }

  void _closeStep() => setState(() => _active = -1);

  @override
  Widget build(BuildContext context) {
    final isBasic = _section == 0;
    final stepCount = _steps.length;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isMobile ? 20 : 80,
        vertical: widget.isMobile ? 24 : 48,
      ),
      child: Column(
        children: [
          const _GuideSectionBadge('Hướng dẫn sử dụng'),
          const SizedBox(height: 12),
          _GuideSectionTitle(
            isBasic
                ? 'Quy trình triển khai\n$stepCount bước thực tế'
                : 'Hướng dẫn nâng cao\n$stepCount tính năng',
          ),
          const SizedBox(height: 8),
          _GuideSectionSubtext(
            isBasic
                ? 'Theo đúng menu phần mềm SBOX HRM · Từ đăng ký đến báo cáo · Hỗ trợ cài đặt từ xa'
                : 'Vận hành sau triển khai: lịch ca, KPI, phép, tài sản, truyền thông và hơn thế nữa',
          ),
          const SizedBox(height: 28),
          _buildSectionTabs(),
          const SizedBox(height: 32),
          widget.isMobile ? _buildMobile() : _buildDesktop(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTabs() {
    final basicCount = widget.guideData.basicCount;
    final advancedCount = widget.guideData.advancedCount;
    Widget tab(String label, int index) {
      final selected = _section == index;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _section = index;
            _active = -1;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Text(
              tr(label),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: widget.isMobile ? 12 : 13,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('Triển khai ($basicCount)', 0),
        const SizedBox(width: 10),
        tab('Nâng cao ($advancedCount)', 1),
      ],
    );
  }

  Widget _buildDesktop() {
    final bodyHeight = widget.desktopBodyHeight ?? 520;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 260,
          height: bodyHeight,
          child: SingleChildScrollView(
              child: Column(
                children: _steps.asMap().entries.map((e) {
                  final i = e.key;
                  final s = e.value;
                  final active = i == _active;
                  return GestureDetector(
                    onTap: () => _openStep(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
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
                            color: active
                                ? s.accent
                                : Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              tr('${i + 1}'),
                              style: TextStyle(
                                color: active ? Colors.white : Colors.white54,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr(s.title),
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
        ),
        const SizedBox(width: 40),
        Expanded(
          child: SizedBox(
            height: bodyHeight,
            child: SingleChildScrollView(
              child: _buildDetailPanel(false),
            ),
          ),
        ),
      ],
    );
    return SizedBox(height: bodyHeight, child: row);
  }

  Widget _buildDetailPanel(bool mobile) {
    if (_active < 0) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app_rounded,
                size: 40, color: Colors.white.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(tr('${tr('Chọn một bước bên ')}${mobile ? 'trên' : 'trái'} để xem hướng dẫn chi tiết'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }
    return _GuideStepDetail(
      key: ValueKey('$_section-$_active'),
      step: _steps[_active],
      sectionKey: _sectionKey,
      mobile: mobile,
    );
  }

  Widget _buildMobile() {
    return Column(
      children: _steps.asMap().entries.map((e) {
        final i = e.key;
        final s = e.value;
        final open = i == _active;
        return GestureDetector(
          onTap: () => open ? _closeStep() : _openStep(i),
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
                          child: Text(tr('${i + 1}'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(tr(s.title),
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
                    child: _GuideStepDetail(
                      key: ValueKey('m-$_section-$i'),
                      step: s,
                      sectionKey: _sectionKey,
                      mobile: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _GuideStepDetail extends StatelessWidget {
  const _GuideStepDetail({
    super.key,
    required this.step,
    required this.sectionKey,
    required this.mobile,
  });

  final LandingUsageGuideStep step;
  final String sectionKey;
  final bool mobile;

  Future<void> _copyShareLink(BuildContext context) async {
    final link = LandingGuideUrl.buildLink(
      section: sectionKey,
      stepId: step.id,
    );
    await Clipboard.setData(ClipboardData(text: tr(link)));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Đã copy link hướng dẫn — gửi cho khách hàng')),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openVideo(BuildContext context) async {
    final url = step.videoUrl.trim();
    if (url.isEmpty) return;
    final videoId = LandingGuideUrl.extractYouTubeVideoId(url);
    if (videoId != null && videoId.isNotEmpty) {
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _GuideVideoPlayerDialog(
          videoId: videoId,
          title: step.title,
          url: url,
        ),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shareLink = LandingGuideUrl.buildLink(
      section: sectionKey,
      stepId: step.id,
    );
    final videoId = LandingGuideUrl.extractYouTubeVideoId(step.videoUrl);
    final videoThumb = videoId != null
        ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Icon(Icons.link_rounded,
                  size: 16, color: step.accent.withValues(alpha: 0.9)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(shareLink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _copyShareLink(context),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(tr('Copy link')),
                style: TextButton.styleFrom(
                  foregroundColor: step.accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(tr(step.desc),
            style: const TextStyle(
                color: Colors.white70, fontSize: 14, height: 1.65)),
        if (step.imageUrls.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: step.imageUrls.map((raw) {
              final url = normalizeLandingPublicUrl(raw);
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: mobile ? double.infinity : 220,
                  height: mobile ? 180 : 140,
                  child: LandingProductImage(imageUrl: url, fit: BoxFit.cover),
                ),
              );
            }).toList(),
          ),
        ],
        if (step.videoUrl.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => _openVideo(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: videoThumb != null
                        ? Image.network(
                            videoThumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.white12,
                              child: const Icon(Icons.videocam_rounded,
                                  color: Colors.white38, size: 48),
                            ),
                          )
                        : Container(
                            color: Colors.white12,
                            child: const Icon(Icons.videocam_rounded,
                                color: Colors.white38, size: 48),
                          ),
                  ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: step.accent.withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 32),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
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
                    child: Text(tr(b),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.5))),
              ]),
            )),
        if (step.tip.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: step.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: step.accent.withValues(alpha: 0.35)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.tips_and_updates_rounded,
                  color: step.accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(tr(step.tip),
                      style: TextStyle(
                          color: step.accent, fontSize: 12.5, height: 1.5))),
            ]),
          ),
        ],
      ],
    );
  }
}

class _GuideVideoPlayerDialog extends StatelessWidget {
  const _GuideVideoPlayerDialog({
    required this.videoId,
    required this.title,
    required this.url,
  });

  final String videoId;
  final String title;
  final String url;

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
                children: [
                  Expanded(
                    child: Text(tr(title),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
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
              FilledButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(tr('Xem trên YouTube')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideSectionBadge extends StatelessWidget {
  const _GuideSectionBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(tr(label),
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5)),
    );
  }
}

class _GuideSectionTitle extends StatelessWidget {
  const _GuideSectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(tr(text),
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.2));
  }
}

class _GuideSectionSubtext extends StatelessWidget {
  const _GuideSectionSubtext(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(tr(text),
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white54, fontSize: 15, height: 1.5));
  }
}
