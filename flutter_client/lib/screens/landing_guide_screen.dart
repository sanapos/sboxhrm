import 'dart:convert';

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

/// Tông màu khớp trang chủ sboxhrm.com (nền sáng, xanh #1565C0).
abstract final class _GuideUi {
  static const brand = Color(0xFF1565C0);
  static const brandDeep = Color(0xFF0C56D0);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const body = Color(0xFF475569);
  static const page = Color(0xFFF4F7FC);
  static const card = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF8FAFF);
  static const line = Color(0xFFE2E8F0);
  static const lineSoft = Color(0xFFE8EEF8);
  static const chip = Color(0xFFE3F2FD);
  static const shadow = Color(0x140F2864);

  static List<BoxShadow> get cardShadow => const [
        BoxShadow(color: shadow, blurRadius: 28, offset: Offset(0, 8)),
      ];
}

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
        backgroundColor: _GuideUi.page,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _GuideUi.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: _GuideUi.lineSoft),
          ),
          title: Text(
            tr('Hướng dẫn sử dụng'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: _GuideUi.ink,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: _GuideUi.brand),
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
                child: CircularProgressIndicator(color: _GuideUi.brand),
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
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  bool _showSuggestions = false;

  List<LandingUsageGuideStep> get _steps =>
      widget.guideData.stepsAt(_section);

  String get _sectionKey => LandingGuideData.keyForIndex(_section);

  List<LandingGuideSearchHit> get _searchHits =>
      widget.guideData.search(_query);

  List<String> get _visibleSuggestionChips {
    final q = _query.trim();
    final all = LandingGuideData.suggestionKeywords;
    if (q.isEmpty) return all.take(10).toList();
    final foldQ = q.toLowerCase();
    return all
        .where((k) => k.toLowerCase().contains(foldQ) || foldQ.contains(k.toLowerCase()))
        .take(10)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _applyDeepLink(widget.initialLink, notify: false);
    _searchCtrl.addListener(() {
      final next = _searchCtrl.text;
      if (next == _query) return;
      setState(() {
        _query = next;
        _showSuggestions = true;
      });
    });
    _searchFocus.addListener(() {
      setState(() => _showSuggestions = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
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
    final steps = widget.guideData.stepsAt(link.sectionIndex);
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

  void _openHit(LandingGuideSearchHit hit) {
    setState(() {
      _section = hit.sectionIndex;
      _active = hit.stepIndex;
      _showSuggestions = false;
      _searchCtrl.text = hit.step.title;
      _query = hit.step.title;
    });
    _searchFocus.unfocus();
    final sectionKey = LandingGuideData.keyForIndex(hit.sectionIndex);
    LandingGuideUrl.syncToBrowser(
      section: sectionKey,
      stepId: hit.step.id,
    );
  }

  void _applyKeyword(String keyword) {
    _searchCtrl.text = keyword;
    _searchCtrl.selection = TextSelection.collapsed(offset: keyword.length);
    setState(() {
      _query = keyword;
      _showSuggestions = true;
    });
    final hits = widget.guideData.search(keyword);
    if (hits.length == 1) {
      _openHit(hits.first);
    }
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _showSuggestions = _searchFocus.hasFocus;
    });
  }

  void _closeStep() => setState(() => _active = -1);

  void _goAdjacent(int delta) {
    if (_active < 0) return;
    final next = _active + delta;
    if (next < 0 || next >= _steps.length) return;
    _openStep(next);
  }

  @override
  Widget build(BuildContext context) {
    final stepCount = _steps.length;
    final title = switch (_section) {
      1 => 'Hướng dẫn nâng cao\n$stepCount tính năng HRM',
      2 => 'Hướng dẫn POS\n$stepCount bước bán hàng & in',
      _ => 'Quy trình triển khai\n$stepCount bước thực tế',
    };
    final sub = switch (_section) {
      1 =>
        'Sau triển khai: lịch ca, KPI, phép, tài sản, hiện trường — POS xem tab POS',
      2 =>
        'A6 app POS · A7/web bán trong HRM · Máy in, bếp, kho, báo cáo doanh thu',
      _ =>
        'Làm theo từng bước · SBOX HRM - SBOX POS · Hỗ trợ cài đặt từ xa',
    };
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isMobile ? 20 : 80,
        vertical: widget.isMobile ? 24 : 48,
      ),
      child: Column(
        children: [
          const _GuideSectionBadge('Hướng dẫn sử dụng'),
          const SizedBox(height: 12),
          _GuideSectionTitle(title),
          const SizedBox(height: 8),
          _GuideSectionSubtext(sub),
          const SizedBox(height: 20),
          _buildSearchBar(),
          const SizedBox(height: 20),
          _buildSectionTabs(),
          const SizedBox(height: 28),
          widget.isMobile ? _buildMobile() : _buildDesktop(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final hits = _searchHits;
    final chips = _visibleSuggestionChips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          style: const TextStyle(color: _GuideUi.ink, fontSize: 14),
          cursorColor: _GuideUi.brand,
          decoration: InputDecoration(
            hintText: tr('Tìm hướng dẫn: máy chấm công, lương, nghỉ phép…'),
            hintStyle: const TextStyle(
              color: _GuideUi.muted,
              fontSize: 13.5,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: _GuideUi.brand,
            ),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: tr('Xóa'),
                    onPressed: _clearSearch,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _GuideUi.muted,
                    ),
                  ),
            filled: true,
            fillColor: _GuideUi.card,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _GuideUi.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _GuideUi.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _GuideUi.brandDeep, width: 1.4),
            ),
          ),
          onSubmitted: (_) {
            if (hits.isNotEmpty) _openHit(hits.first);
          },
        ),
        if (_showSuggestions) ...[
          const SizedBox(height: 10),
          if (chips.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  tr('Gợi ý: '),
                  style: const TextStyle(
                    color: _GuideUi.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ...chips.map(
                  (k) => ActionChip(
                    label: Text(tr(k), style: const TextStyle(fontSize: 12)),
                    backgroundColor: _GuideUi.chip,
                    side: const BorderSide(color: Color(0xFFBBDEFB)),
                    labelStyle: const TextStyle(color: _GuideUi.brand),
                    onPressed: () => _applyKeyword(k),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          if (_query.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                color: _GuideUi.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _GuideUi.line),
                boxShadow: _GuideUi.cardShadow,
              ),
              child: hits.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        tr('Không tìm thấy mục phù hợp. Thử từ khóa khác hoặc chọn gợi ý bên trên.'),
                        style: const TextStyle(
                          color: _GuideUi.muted,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: hits.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: _GuideUi.lineSoft,
                      ),
                      itemBuilder: (context, i) {
                        final hit = hits[i];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: _GuideUi.chip,
                            child: Icon(hit.step.icon,
                                size: 16, color: _GuideUi.brand),
                          ),
                          title: Text(
                            tr(hit.step.title),
                            style: const TextStyle(
                              color: _GuideUi.ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: Text(
                            tr('${hit.sectionLabel} · ${hit.matchedIn}'),
                            style: const TextStyle(
                              color: _GuideUi.muted,
                              fontSize: 11.5,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 12,
                            color: _GuideUi.muted,
                          ),
                          onTap: () => _openHit(hit),
                        );
                      },
                    ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSectionTabs() {
    final basicCount = widget.guideData.basicCount;
    final advancedCount = widget.guideData.advancedCount;
    final posCount = widget.guideData.posCount;
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
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? _GuideUi.brand : _GuideUi.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? _GuideUi.brand : _GuideUi.line,
              ),
              boxShadow: selected ? _GuideUi.cardShadow : null,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                tr(label),
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? Colors.white : _GuideUi.body,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: widget.isMobile ? 11 : 13,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('Triển khai ($basicCount)', 0),
        const SizedBox(width: 8),
        tab('Nâng cao ($advancedCount)', 1),
        const SizedBox(width: 8),
        tab('POS ($posCount)', 2),
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
                        color: active ? _GuideUi.chip : _GuideUi.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active ? _GuideUi.brand : _GuideUi.line,
                        ),
                        boxShadow: active ? _GuideUi.cardShadow : null,
                      ),
                      child: Row(children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: active ? _GuideUi.brand : _GuideUi.soft,
                            shape: BoxShape.circle,
                            border: active
                                ? null
                                : Border.all(color: _GuideUi.lineSoft),
                          ),
                          child: Center(
                            child: Text(
                              tr('${i + 1}'),
                              style: TextStyle(
                                color: active ? Colors.white : _GuideUi.brand,
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
                              color: _GuideUi.ink,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (active)
                          const Icon(Icons.arrow_forward_ios_rounded,
                              color: _GuideUi.brand, size: 12),
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
          color: _GuideUi.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _GuideUi.line),
          boxShadow: _GuideUi.cardShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: _GuideUi.chip,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.menu_book_rounded,
                  size: 32, color: _GuideUi.brand),
            ),
            const SizedBox(height: 16),
            Text(
              tr('Tìm theo từ khóa phía trên, hoặc chọn một bước bên ${mobile ? 'dưới' : 'trái'} để xem hướng dẫn chi tiết từng bước'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _GuideUi.muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: mobile ? EdgeInsets.zero : const EdgeInsets.all(24),
      decoration: mobile
          ? null
          : BoxDecoration(
              color: _GuideUi.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _GuideUi.line),
              boxShadow: _GuideUi.cardShadow,
            ),
      child: _GuideStepDetail(
      key: ValueKey('$_section-$_active'),
      step: _steps[_active],
      stepNumber: _active + 1,
      stepTotal: _steps.length,
      sectionKey: _sectionKey,
      mobile: mobile,
      onPrev: _active > 0 ? () => _goAdjacent(-1) : null,
      onNext: _active < _steps.length - 1 ? () => _goAdjacent(1) : null,
    ),
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
              color: open ? _GuideUi.chip : _GuideUi.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: open ? _GuideUi.brand : _GuideUi.line,
              ),
              boxShadow: _GuideUi.cardShadow,
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
                          color: open ? _GuideUi.brand : _GuideUi.soft,
                          shape: BoxShape.circle,
                          border: open
                              ? null
                              : Border.all(color: _GuideUi.lineSoft)),
                      child: Center(
                          child: Text(tr('${i + 1}'),
                              style: TextStyle(
                                  color: open ? Colors.white : _GuideUi.brand,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(tr(s.title),
                            style: TextStyle(
                                color: _GuideUi.ink,
                                fontWeight:
                                    open ? FontWeight.w700 : FontWeight.w600,
                                fontSize: 14))),
                    Icon(
                        open
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: _GuideUi.muted),
                  ]),
                ),
                if (open) ...[
                  const Divider(color: _GuideUi.lineSoft, height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    child: _GuideStepDetail(
                      key: ValueKey('m-$_section-$i'),
                      step: s,
                      stepNumber: i + 1,
                      stepTotal: _steps.length,
                      sectionKey: _sectionKey,
                      mobile: true,
                      onPrev: i > 0 ? () => _goAdjacent(-1) : null,
                      onNext:
                          i < _steps.length - 1 ? () => _goAdjacent(1) : null,
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
    required this.stepNumber,
    required this.stepTotal,
    required this.sectionKey,
    required this.mobile,
    this.onPrev,
    this.onNext,
  });

  final LandingUsageGuideStep step;
  final int stepNumber;
  final int stepTotal;
  final String sectionKey;
  final bool mobile;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

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
            color: _GuideUi.soft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _GuideUi.lineSoft),
          ),
          child: Row(
            children: [
              const Icon(Icons.link_rounded,
                  size: 16, color: _GuideUi.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(shareLink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _GuideUi.body,
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
                  foregroundColor: _GuideUi.brand,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _GuideUi.chip,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tr('Mục $stepNumber / $stepTotal'),
                style: const TextStyle(
                  color: _GuideUi.brand,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(step.title),
                style: const TextStyle(
                  color: _GuideUi.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(tr(step.desc),
            style: const TextStyle(
                color: _GuideUi.body, fontSize: 14, height: 1.65)),
        if (step.keywords.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: step.keywords
                .take(8)
                .map(
                  (k) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _GuideUi.soft,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _GuideUi.lineSoft),
                    ),
                    child: Text(
                      tr(k),
                      style: const TextStyle(
                        color: _GuideUi.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
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
                              color: _GuideUi.chip,
                              child: const Icon(Icons.videocam_rounded,
                                  color: _GuideUi.brand, size: 48),
                            ),
                          )
                        : Container(
                            color: _GuideUi.chip,
                            child: const Icon(Icons.videocam_rounded,
                                color: _GuideUi.brand, size: 48),
                          ),
                  ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: _GuideUi.brand,
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
        Text(
          tr('Làm lần lượt các bước sau'),
          style: const TextStyle(
            color: _GuideUi.ink,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        ...step.bullets.asMap().entries.map((e) {
          final i = e.key;
          final b = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _GuideUi.chip,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFBBDEFB)),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: _GuideUi.brandDeep,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(b),
                    style: const TextStyle(
                      color: _GuideUi.body,
                      fontSize: 13.5,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        if (step.tip.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _GuideUi.chip,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBDEFB)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tips_and_updates_rounded,
                    color: _GuideUi.brand, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(tr(step.tip),
                        style: const TextStyle(
                            color: _GuideUi.brandDeep,
                            fontSize: 12.5,
                            height: 1.5))),
              ],
            ),
          ),
        ],
        if (onPrev != null || onNext != null) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              if (onPrev != null)
                OutlinedButton.icon(
                  onPressed: onPrev,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text(tr('Bước trước')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _GuideUi.brand,
                    side: const BorderSide(color: _GuideUi.brand, width: 1.5),
                  ),
                ),
              const Spacer(),
              if (onNext != null)
                FilledButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(tr('Bước tiếp')),
                  style: FilledButton.styleFrom(
                    backgroundColor: _GuideUi.brand,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
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
      backgroundColor: Colors.white,
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
                            color: _GuideUi.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: _GuideUi.muted),
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
                style: FilledButton.styleFrom(
                  backgroundColor: _GuideUi.brand,
                  foregroundColor: Colors.white,
                ),
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
        color: _GuideUi.chip,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Text(tr(label),
          style: const TextStyle(
              color: _GuideUi.brand,
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
            color: _GuideUi.ink,
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
            color: _GuideUi.muted, fontSize: 15, height: 1.5));
  }
}
