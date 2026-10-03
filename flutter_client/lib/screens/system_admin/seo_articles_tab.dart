import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';

/// Super Admin: bài viết SEO hiển thị tại /bai-viet trên sboxhrm.com (HRM) và sboxpos.com (POS).
/// Soạn bằng Markdown, xem trước, gợi ý SEO, xuất bản.
class SeoArticlesTab extends StatefulWidget {
  const SeoArticlesTab({super.key});

  @override
  State<SeoArticlesTab> createState() => SeoArticlesTabState();
}

class SeoArticlesTabState extends State<SeoArticlesTab> {
  final _api = ApiService();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _site;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    setState(() => _loading = true);
    final res = await _api.getSaArticles(site: _site, search: _search.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = res['isSuccess'] == true && res['data'] is List
          ? (res['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
    });
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Không tải được bài viết', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _open([Map<String, dynamic>? item]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _ArticleEditor(item: item, defaultSite: _site ?? 'hrm')),
    );
    if (saved == true) loadData();
  }

  @override
  Widget build(BuildContext context) {
    final dmy = DateFormat('dd/MM/yyyy');
    return Container(
      color: const Color(0xFFF6F7F9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.article_outlined, color: SboxColors.brand600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Bài viết SEO'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
              ),
              FilledButton.icon(onPressed: () => _open(), icon: const Icon(Icons.add), label: Text(tr('Viết bài'))),
            ]),
            const SizedBox(height: 4),
            Text(
              tr('Bài viết hiện tại sboxhrm.com/bai-viet và sboxpos.com/bai-viet, có trong sitemap cho Google.'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<String?>(
                segments: [
                  ButtonSegment(value: null, label: Text(tr('Tất cả'))),
                  const ButtonSegment(value: 'hrm', label: Text('SBOX HRM')),
                  const ButtonSegment(value: 'pos', label: Text('SBOX POS')),
                ],
                selected: {_site},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setState(() => _site = s.first);
                  loadData();
                },
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: tr('Tìm tiêu đề, đường dẫn, chuyên mục…'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), loadData);
                  },
                ),
              ),
            ]),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(child: Text(tr('Chưa có bài viết')))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final a = _items[i];
                        final published = a['isPublished'] == true;
                        final checks = (a['seoChecks'] as List?)?.length ?? 0;
                        final date = DateTime.tryParse('${a['publishedAt'] ?? a['createdAt'] ?? ''}');
                        return Card(
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10), side: const BorderSide(color: SboxColors.slate200)),
                          child: ListTile(
                            onTap: () => _open(a),
                            title: Text('${a['title']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                _badge(a['site'] == 'pos' ? 'SBOX POS' : 'SBOX HRM',
                                    a['site'] == 'pos' ? const Color(0xFF2E7D32) : const Color(0xFF0C56D0)),
                                _badge(published ? tr('Đã xuất bản') : tr('Bản nháp'),
                                    published ? SboxColors.success : SboxColors.slate500),
                                if ((a['category'] ?? '').toString().isNotEmpty)
                                  Text('${a['category']}', style: const TextStyle(fontSize: 12)),
                                Text('/bai-viet/${a['slug']}', style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                                if (date != null) Text(dmy.format(date.toLocal()), style: const TextStyle(fontSize: 12)),
                                Text(tr('${a['viewCount'] ?? 0} lượt xem · ${a['wordCount'] ?? 0} từ'),
                                    style: const TextStyle(fontSize: 12)),
                                if (checks > 0)
                                  Text(tr('$checks gợi ý SEO'),
                                      style: const TextStyle(fontSize: 12, color: SboxColors.warning, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                            trailing: published
                                ? IconButton(
                                    tooltip: tr('Mở trên web'),
                                    icon: const Icon(Icons.open_in_new),
                                    onPressed: () => launchUrl(Uri.parse('${a['url']}'), mode: LaunchMode.externalApplication),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }

  static Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
      );
}

class _ArticleEditor extends StatefulWidget {
  const _ArticleEditor({this.item, required this.defaultSite});

  final Map<String, dynamic>? item;
  final String defaultSite;

  @override
  State<_ArticleEditor> createState() => _ArticleEditorState();
}

class _ArticleEditorState extends State<_ArticleEditor> {
  final _api = ApiService();
  late String _site;
  late bool _published;
  late final Map<String, TextEditingController> _c;
  bool _saving = false;
  String? _previewHtml;
  List<String> _checks = [];

  String? get _id => widget.item?['id']?.toString();

  @override
  void initState() {
    super.initState();
    final a = widget.item ?? const {};
    _site = '${a['site'] ?? widget.defaultSite}';
    _published = a['isPublished'] == true;
    _checks = ((a['seoChecks'] as List?) ?? []).map((e) => '$e').toList();
    String v(String k) => (a[k] ?? '').toString();
    _c = {
      for (final k in ['title', 'slug', 'metaTitle', 'metaDescription', 'keywords', 'summary', 'category', 'coverImageUrl', 'authorName', 'contentMarkdown'])
        k: TextEditingController(text: v(k)),
    };
    _c['sortOrder'] = TextEditingController(text: '${a['sortOrder'] ?? 0}');
    for (final c in _c.values) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _preview() async {
    final res = await _api.previewSaArticle(_c['contentMarkdown']!.text);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() => _previewHtml = '${(res['data'] as Map)['html']}');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await _api.saveSaArticle(_id, {
      'site': _site,
      'title': _c['title']!.text,
      'slug': _c['slug']!.text,
      'metaTitle': _c['metaTitle']!.text,
      'metaDescription': _c['metaDescription']!.text,
      'keywords': _c['keywords']!.text,
      'summary': _c['summary']!.text,
      'contentMarkdown': _c['contentMarkdown']!.text,
      'coverImageUrl': _c['coverImageUrl']!.text,
      'category': _c['category']!.text,
      'authorName': _c['authorName']!.text,
      'isPublished': _published,
      'sortOrder': int.tryParse(_c['sortOrder']!.text) ?? 0,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Không lưu được', message: res['message']?.toString() ?? '');
      return;
    }
    final d = res['data'] is Map ? res['data'] as Map : const {};
    final checks = ((d['seoChecks'] as List?) ?? []).map((e) => '$e').toList();
    NotificationOverlayManager().showSuccess(
      title: 'Đã lưu bài viết',
      message: checks.isEmpty ? '${d['url'] ?? ''}' : 'Còn ${checks.length} gợi ý SEO nên xem lại',
    );
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa bài viết?')),
        content: Text(tr('Bài «${_c['title']!.text}» sẽ bị gỡ khỏi web và sitemap.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || _id == null) return;
    final res = await _api.deleteSaArticle(_id!);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(title: 'Không xóa được', message: res['message']?.toString() ?? '');
    }
  }

  Widget _field(String key, String label, {String? hint, int maxLines = 1, int? maxLength, String? helper}) {
    final c = _c[key]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        minLines: maxLines > 1 ? (maxLines > 10 ? 18 : 2) : 1,
        decoration: InputDecoration(
          labelText: tr(label),
          hintText: hint == null ? null : tr(hint),
          helperText: helper == null ? null : tr(helper),
          helperMaxLines: 3,
          counterText: maxLength == null ? null : '${c.text.length}/$maxLength',
          border: const OutlineInputBorder(),
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }

  /// Ô xem nhanh kết quả trên Google.
  Widget _googleSnippet() {
    final domain = _site == 'pos' ? 'sboxpos.com' : 'sboxhrm.com';
    final title = _c['metaTitle']!.text.trim().isNotEmpty ? _c['metaTitle']!.text : _c['title']!.text;
    final desc = _c['metaDescription']!.text.trim().isNotEmpty ? _c['metaDescription']!.text : _c['summary']!.text;
    final slug = _c['slug']!.text.trim().isEmpty ? '…' : _c['slug']!.text.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: SboxColors.slate200), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Xem trước trên Google'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('https://$domain › bai-viet › $slug', style: const TextStyle(fontSize: 12, color: Color(0xFF202124))),
        Text(title.isEmpty ? tr('(chưa có tiêu đề)') : title,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, color: Color(0xFF1A0DAB))),
        Text(desc.isEmpty ? tr('(chưa có mô tả)') : desc,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF4D5156))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final form = ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'hrm', label: Text('sboxhrm.com')),
            ButtonSegment(value: 'pos', label: Text('sboxpos.com')),
          ],
          selected: {_site},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _site = s.first),
        ),
        const Spacer(),
        Text(tr('Xuất bản')),
        Switch(value: _published, onChanged: (v) => setState(() => _published = v)),
      ]),
      const SizedBox(height: 12),
      _field('title', 'Tiêu đề bài viết (H1)', hint: 'Có từ khóa chính, 50–70 ký tự'),
      _field('slug', 'Đường dẫn (slug)', hint: 'vd: cach-tinh-luong-theo-ngay-cong', helper: 'Để trống sẽ tự tạo từ tiêu đề. Không nên đổi sau khi đã xuất bản.'),
      _field('metaTitle', 'Tiêu đề Google', maxLength: 60, helper: 'Để trống = tiêu đề bài + tên thương hiệu.'),
      _field('metaDescription', 'Mô tả Google', maxLines: 3, maxLength: 160, helper: 'Nên 120–160 ký tự, nói rõ lợi ích, có từ khóa.'),
      _googleSnippet(),
      const SizedBox(height: 12),
      _field('keywords', 'Từ khóa (cách nhau bởi dấu phẩy)'),
      _field('summary', 'Tóm tắt (hiện đầu bài & trong danh sách)', maxLines: 3),
      Row(children: [
        Expanded(child: _field('category', 'Chuyên mục', hint: 'vd: Chấm công, Tính lương')),
        const SizedBox(width: 10),
        SizedBox(width: 120, child: _field('sortOrder', 'Thứ tự ưu tiên')),
      ]),
      _field('coverImageUrl', 'Ảnh bìa (URL)', hint: '/images/landing/screenshot-01.jpg hoặc https://…', helper: 'Tỉ lệ 1200×630 cho Facebook / Zalo.'),
      _field('authorName', 'Tác giả', hint: 'Đội ngũ SBOX'),
      _field('contentMarkdown', 'Nội dung (Markdown)', maxLines: 40,
          helper: '## Tiêu đề mục · **đậm** · *nghiêng* · - danh sách · 1. danh sách số · [liên kết](/register) · '
              '![mô tả ảnh](/images/...) · > trích dẫn · bảng | A | B |'),
      if (_checks.isNotEmpty) ...[
        Text(tr('Gợi ý SEO (lần lưu trước)'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final c in _checks)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.tips_and_updates_outlined, size: 16, color: SboxColors.warning),
              const SizedBox(width: 6),
              Expanded(child: Text(tr(c), style: const TextStyle(fontSize: 13))),
            ]),
          ),
      ],
      const SizedBox(height: 60),
    ]);

    final preview = Container(
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Expanded(child: Text(tr('Xem trước nội dung'), style: const TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(onPressed: _preview, icon: const Icon(Icons.visibility_outlined), label: Text(tr('Cập nhật'))),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _previewHtml == null
              ? Center(child: Text(tr('Bấm «Cập nhật» để xem nội dung đã định dạng')))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_c['title']!.text, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Html(data: _previewHtml!),
                  ]),
                ),
        ),
      ]),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? tr('Viết bài mới') : tr('Sửa bài viết')),
        actions: [
          if (!wide)
            IconButton(
              tooltip: tr('Xem trước'),
              icon: const Icon(Icons.visibility_outlined),
              onPressed: () async {
                await _preview();
                if (!mounted) return;
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(appBar: AppBar(title: Text(tr('Xem trước'))), body: preview)));
              },
            ),
          if (_id != null)
            IconButton(tooltip: tr('Xóa'), onPressed: _delete, icon: const Icon(Icons.delete_outline, color: SboxColors.danger)),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(tr('Lưu')),
            ),
          ),
        ],
      ),
      body: wide
          ? Row(children: [
              Expanded(child: form),
              const VerticalDivider(width: 1),
              Expanded(child: preview),
            ])
          : form,
    );
  }
}
