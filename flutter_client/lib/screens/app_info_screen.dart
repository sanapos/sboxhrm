import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../content/app_legal_pages.dart';
import '../services/api_service.dart';
import '../theme/sbox_tokens.dart';
import 'settings_hub_screen.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Điều khoản sử dụng / Chính sách bảo mật / Trợ giúp / Báo lỗi.
/// Nội dung: máy chủ (Superadmin sửa được) → nếu trống / còn bản mẫu cũ vài dòng thì dùng nội dung
/// mặc định đầy đủ trong app ([AppLegalPages]). Hiển thị Markdown đơn giản (tiêu đề, gạch đầu dòng, chữ đậm)
/// — trước đây in nguyên chữ «# ## » ra màn hình.
class AppInfoScreen extends StatefulWidget {
  /// type: 'terms' | 'privacy' | 'help' | 'bugreport'
  final String type;
  const AppInfoScreen({super.key, required this.type});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  bool _loading = true;
  String _content = '';
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    if (widget.type != 'bugreport') _loadPage();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    String? server;
    try {
      final res = await ApiService().getAppPage(widget.type);
      if (res['isSuccess'] == true && res['data'] is Map) {
        server = (res['data'] as Map)['content']?.toString();
      }
    } catch (_) {
      // Mất mạng vẫn đọc được nội dung mặc định.
    }
    if (!mounted) return;
    final fallback = AppLegalPages.defaultFor(widget.type) ?? '';
    setState(() {
      _content = AppLegalPages.isPlaceholder(server) ? fallback : server!;
      _loading = false;
    });
  }

  String get _pageTitle => switch (widget.type) {
        'terms' => 'Điều khoản sử dụng',
        'privacy' => 'Chính sách bảo mật',
        'help' => 'Trợ giúp',
        _ => 'Thông tin',
      };

  IconData get _pageIcon => switch (widget.type) {
        'terms' => Icons.gavel_rounded,
        'privacy' => Icons.privacy_tip_outlined,
        'help' => Icons.support_agent_rounded,
        _ => Icons.info_outline,
      };

  void _back() {
    // Mở đè bằng Navigator.push (từ Cài đặt) → đóng trang; nằm trong Thiết lập SBOX → về danh mục hub.
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      SettingsHubScreen.goBack(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.type == 'bugreport') {
      return _BugReportForm(onBack: _back);
    }
    final blocks = _MdBlock.parse(_content);
    // Tiêu đề trang (# …) đã ở thanh trên — bỏ khỏi thân bài; lấy dòng «Cập nhật…» làm phụ đề.
    final h1 = blocks.where((b) => b.kind == _MdKind.h1).firstOrNull;
    final body = blocks.where((b) => !identical(b, h1)).toList();
    final sections = body.where((b) => b.kind == _MdKind.h2).toList();
    for (final s in sections) {
      _sectionKeys.putIfAbsent(s.text, () => GlobalKey());
    }

    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: AppBar(
        title: Text(tr(_pageTitle)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: SboxColors.text,
        elevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                  children: [
                    _header(body),
                    if (widget.type == 'help' && sections.length > 2) ...[
                      const SizedBox(height: 10),
                      _toc(sections),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: SboxColors.slate200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final b in body)
                            if (!(b.kind == _MdKind.para && b.text.startsWith(RegExp(r'(Cập nhật|Có hiệu lực)'))))
                              _block(b),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _contactCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _header(List<_MdBlock> body) {
    final dateLine = body
        .where((b) => b.kind == _MdKind.para && b.text.startsWith(RegExp(r'(Cập nhật|Có hiệu lực)')))
        .map((b) => b.text)
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [SboxColors.brand600, SboxColors.brand500]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
          child: Icon(_pageIcon, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(_pageTitle),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              tr(dateLine ?? 'SBOX HRM · SBOX POS'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5),
            ),
          ]),
        ),
      ]),
    );
  }

  /// Mục lục trang Trợ giúp: chạm để cuộn tới phần đó.
  Widget _toc(List<_MdBlock> sections) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final s in sections)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.white,
                side: const BorderSide(color: SboxColors.slate200),
                label: Text(tr(s.text), style: const TextStyle(fontSize: 12.5)),
                onPressed: () {
                  final ctx = _sectionKeys[s.text]?.currentContext;
                  if (ctx != null) {
                    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.05);
                  }
                },
              ),
            ),
        ]),
      );

  Widget _block(_MdBlock b) {
    switch (b.kind) {
      case _MdKind.h1:
      case _MdKind.h2:
        return Padding(
          key: _sectionKeys[b.text],
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(tr(b.text),
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: SboxColors.brand800)),
        );
      case _MdKind.h3:
        return Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(tr(b.text),
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: SboxColors.slate800)),
        );
      case _MdKind.bullet:
      case _MdKind.numbered:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 20,
              child: b.kind == _MdKind.numbered
                  ? Text('${b.number}.', style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.brand700))
                  : const Padding(
                      padding: EdgeInsets.only(top: 7),
                      child: Icon(Icons.circle, size: 6, color: SboxColors.brand500),
                    ),
            ),
            Expanded(child: _rich(b.text)),
          ]),
        );
      case _MdKind.para:
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: _rich(b.text));
    }
  }

  /// **đậm** trong đoạn.
  Widget _rich(String text) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*');
    var i = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate900)));
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(fontSize: 14.5, height: 1.55, color: SboxColors.slate700),
    );
  }

  Widget _contactCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Cần hỗ trợ thêm?'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          Text(tr('Đội ngũ SBOX hỗ trợ qua hotline (có Zalo) và email.'),
              style: const TextStyle(color: SboxColors.slate600, fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse('tel:${AppLegalPages.hotline.replaceAll(' ', '')}')),
              icon: const Icon(Icons.call_outlined, size: 18),
              label: Text(tr('Gọi ${AppLegalPages.hotline}')),
            ),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse('mailto:${AppLegalPages.supportEmail}')),
              icon: const Icon(Icons.mail_outline, size: 18),
              label: Text(AppLegalPages.supportEmail),
            ),
            if (widget.type == 'help')
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AppInfoScreen(type: 'bugreport')),
                ),
                icon: const Icon(Icons.bug_report_outlined, size: 18),
                label: Text(tr('Báo lỗi & Góp ý')),
              ),
          ]),
        ]),
      );
}

enum _MdKind { h1, h2, h3, bullet, numbered, para }

/// Markdown tối giản cho trang nội dung: # / ## / ### tiêu đề, - gạch đầu dòng, 1. đánh số, còn lại là đoạn.
class _MdBlock {
  _MdBlock(this.kind, this.text, [this.number = 0]);
  final _MdKind kind;
  final String text;
  final int number;

  static List<_MdBlock> parse(String src) {
    final out = <_MdBlock>[];
    final para = <String>[];
    void flush() {
      if (para.isNotEmpty) {
        out.add(_MdBlock(_MdKind.para, para.join(' ')));
        para.clear();
      }
    }

    for (final raw in src.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        flush();
        continue;
      }
      final num = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (line.startsWith('### ')) {
        flush();
        out.add(_MdBlock(_MdKind.h3, line.substring(4).trim()));
      } else if (line.startsWith('## ')) {
        flush();
        out.add(_MdBlock(_MdKind.h2, line.substring(3).trim()));
      } else if (line.startsWith('# ')) {
        flush();
        out.add(_MdBlock(_MdKind.h1, line.substring(2).trim()));
      } else if (line.startsWith('- ') || line.startsWith('* ') || line.startsWith('• ')) {
        flush();
        out.add(_MdBlock(_MdKind.bullet, line.substring(2).trim()));
      } else if (num != null) {
        flush();
        out.add(_MdBlock(_MdKind.numbered, num.group(2)!.trim(), int.parse(num.group(1)!)));
      } else {
        para.add(line);
      }
    }
    flush();
    return out;
  }
}

class _BugReportForm extends StatefulWidget {
  final VoidCallback onBack;
  const _BugReportForm({required this.onBack});

  @override
  State<_BugReportForm> createState() => _BugReportFormState();
}

class _BugReportFormState extends State<_BugReportForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _type = 'Bug';
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final api = ApiService();
    try {
      final res = await api.submitAppBugReport({
        'type': _type,
        'title': _titleCtrl.text.trim(),
        'content': _contentCtrl.text.trim(),
        'appVersion': '1.0.0',
        'deviceInfo': 'Flutter App',
      });
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        setState(() { _submitted = true; _submitting = false; });
      } else {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(res['message'] as String? ?? 'Gửi thất bại')), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Gửi thất bại: $e')), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Báo lỗi & Góp ý')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: _submitted
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 64),
                  const SizedBox(height: 16),
                  Text(tr('Cảm ơn bạn đã gửi phản hồi!'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(tr('Chúng tôi sẽ xem xét và phản hồi sớm nhất có thể.'),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: widget.onBack,
                    child: Text(tr('Quay lại')),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr('Loại phản hồi'),
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: 'Bug', child: Text(tr('🐛 Báo lỗi'))),
                        DropdownMenuItem(value: 'Suggestion', child: Text(tr('💡 Góp ý / Đề xuất'))),
                        DropdownMenuItem(value: 'Other', child: Text(tr('📝 Khác'))),
                      ],
                      onChanged: (v) => setState(() => _type = v!),
                    ),
                    const SizedBox(height: 16),
                    Text(tr('Tiêu đề'),
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: InputDecoration(
                        hintText: tr('Mô tả ngắn gọn vấn đề...'),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tiêu đề' : null,
                    ),
                    const SizedBox(height: 16),
                    Text(tr('Nội dung chi tiết'),
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _contentCtrl,
                      maxLines: 6,
                      decoration: InputDecoration(
                        hintText: tr('Mô tả chi tiết lỗi, cách tái hiện, hoặc ý kiến góp ý...'),
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Vui lòng nhập nội dung' : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send),
                        label: Text(tr(_submitting ? 'Đang gửi...' : 'Gửi phản hồi')),
                        style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
