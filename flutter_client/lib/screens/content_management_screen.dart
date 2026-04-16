import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import '../utils/image_source_picker.dart';

/// Màn hình quản lý nội dung (Nội quy / Đào tạo)
class ContentManagementScreen extends StatefulWidget {
  final int contentType;
  final String screenTitle;
  final Color themeColor;
  final IconData themeIcon;

  const ContentManagementScreen({
    super.key,
    required this.contentType,
    required this.screenTitle,
    required this.themeColor,
    required this.themeIcon,
  });

  @override
  State<ContentManagementScreen> createState() =>
      _ContentManagementScreenState();
}

class _ContentManagementScreenState extends State<ContentManagementScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  /// Parse status from API: handles both int (0,1,2) and String ("Draft","PendingApproval","Published")
  int _parseStatus(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    final s = raw.toString().toLowerCase();
    if (s == 'draft' || s == '0') return 0;
    if (s == 'pendingapproval' || s == '1') return 1;
    if (s == 'published' || s == '2') return 2;
    if (s == 'archived' || s == '3') return 3;
    return int.tryParse(s) ?? 0;
  }

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _articles = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCategoryId;
  int _selectedStatusFilter = -1;
  bool _showMobileFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([_loadCategories(), _loadArticles()]);
    } catch (e) {
      debugPrint('Load data error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadCategories() async {
    try {
      final cats =
          await _api.getContentCategories(contentType: widget.contentType);
      if (mounted) {
        setState(
            () => _categories = List<Map<String, dynamic>>.from(cats));
      }
    } catch (e) {
      debugPrint('Load categories error: $e');
    }
  }

  Future<void> _loadArticles() async {
    try {
      final result = await _api.getCommunications(
        type: widget.contentType,
        pageSize: 200,
      );
      final data = result['data'];
      if (data != null && data['items'] != null) {
        if (mounted) {
          setState(() =>
              _articles = List<Map<String, dynamic>>.from(data['items']));
        }
      }
    } catch (e) {
      debugPrint('Load articles error: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredArticles {
    return _articles.where((a) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final title = (a['title'] ?? '').toString().toLowerCase();
        final summary = (a['summary'] ?? '').toString().toLowerCase();
        if (!title.contains(q) && !summary.contains(q)) return false;
      }
      if (_selectedStatusFilter >= 0) {
        final status = _parseStatus(a['status']);
        if (status != _selectedStatusFilter) return false;
      }
      if (_selectedCategoryId != null) {
        if (a['categoryId']?.toString() != _selectedCategoryId) return false;
      }
      return true;
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: widget.themeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(widget.themeIcon, size: 18, color: widget.themeColor),
          ),
          const SizedBox(width: 10),
          Text(widget.screenTitle,
              style: const TextStyle(
                  color: Color(0xFF18181B),
                  fontWeight: FontWeight.bold,
                  fontSize: 17)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(isMobile ? '' : 'Tạo bài viết'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: widget.themeColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 10 : 16, vertical: 8),
            ),
          ),
          if (isMobile)
            IconButton(
              icon: Stack(
                children: [
                  Icon(
                    _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                    color: _showMobileFilters ? Colors.orange : const Color(0xFF71717A),
                  ),
                  if (_searchQuery.isNotEmpty || _selectedCategoryId != null || _selectedStatusFilter >= 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
              onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
            ),
          const SizedBox(width: 12),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: widget.themeColor,
          unselectedLabelColor: const Color(0xFFA1A1AA),
          indicatorColor: widget.themeColor,
          tabs: const [
            Tab(
                text: 'Bài viết',
                icon: Icon(Icons.article_outlined, size: 18)),
            Tab(
                text: 'Thư mục',
                icon: Icon(Icons.folder_outlined, size: 18)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildArticlesTab(), _buildCategoriesTab()],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 1: Bài viết
  // ═══════════════════════════════════════════════════════════
  Widget _buildArticlesTab() {
    final filtered = _filteredArticles;
    return Column(children: [
      if (!Responsive.isMobile(context) || _showMobileFilters)
      Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 280,
            height: 38,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm bài viết...',
                hintStyle:
                    const TextStyle(fontSize: 13, color: Color(0xFFA1A1AA)),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: Color(0xFFA1A1AA)),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              ),
            ),
          ),
          _chip('Tất cả', -1),
          _chip('Nháp', 0),
          _chip('Đã xuất bản', 2),
          if (_categories.isNotEmpty)
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE4E4E7)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedCategoryId,
                  hint: const Text('Tất cả thư mục',
                      style: TextStyle(fontSize: 12)),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF334155)),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Tất cả thư mục')),
                    ..._categories.map((c) => DropdownMenuItem(
                          value: c['id'].toString(),
                          child: Text(c['name'] ?? ''),
                        )),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedCategoryId = v),
                ),
              ),
            ),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.white,
        child: Row(children: [
          _stat('Tổng', _articles.length, const Color(0xFF1E3A5F)),
          const SizedBox(width: 12),
          _stat('Xuất bản', _articles.where((a) => _parseStatus(a['status']) == 2).length,
              const Color(0xFF1E3A5F)),
          const SizedBox(width: 12),
          _stat('Nháp', _articles.where((a) => _parseStatus(a['status']) == 0).length,
              const Color(0xFFF59E0B)),
          const Spacer(),
          Text('${filtered.length} kết quả',
              style:
                  const TextStyle(color: Color(0xFFA1A1AA), fontSize: 12)),
        ]),
      ),
      const Divider(height: 24),
      Expanded(
        child: filtered.isEmpty
            ? _emptyState()
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _articleDeckItem(filtered[i]),
                    ),
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _chip(String label, int status) {
    final on = _selectedStatusFilter == status;
    return FilterChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: on ? Colors.white : const Color(0xFF71717A))),
      selected: on,
      onSelected: (_) => setState(() => _selectedStatusFilter = status),
      backgroundColor: Colors.white,
      selectedColor: widget.themeColor,
      side: BorderSide(
          color: on ? widget.themeColor : const Color(0xFFE4E4E7)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _stat(String label, int n, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$n',
              style: TextStyle(
                  color: c, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: c.withValues(alpha: 0.8), fontSize: 11)),
        ]),
      );

  Widget _articleDeckItem(Map<String, dynamic> a) {
    final status = _parseStatus(a['status']);
    final pub = status == 2;
    final draft = status == 0;
    final title = (a['title'] ?? 'Chưa có tiêu đề').toString();
    final ai = a['isAiGenerated'] == true;
    final views = a['viewCount'] ?? 0;
    final created = DateTime.tryParse((a['createdAt'] ?? '').toString());

    return InkWell(
      onTap: () => _openEditor(article: a),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: widget.themeColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Icon(widget.themeIcon, color: widget.themeColor.withValues(alpha: 0.4), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (ai) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.auto_awesome, size: 12, color: Color(0xFF0F2340))),
              ]),
              const SizedBox(height: 2),
              Text(
                [
                  pub ? 'Đã XB' : draft ? 'Nháp' : 'Chờ duyệt',
                  '$views lượt xem',
                  if (created != null) '${created.day}/${created.month}/${created.year}',
                ].join(' · '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          _statusBadge(pub, draft),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFFA1A1AA)),
            onSelected: (v) {
              if (v == 'edit') _openEditor(article: a);
              if (v == 'publish') _publishArticle(a);
              if (v == 'delete') _deleteArticle(a);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Sửa')),
              if (draft) const PopupMenuItem(value: 'publish', child: Text('Xuất bản')),
              const PopupMenuItem(value: 'delete', child: Text('Xóa', style: TextStyle(color: Colors.red))),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _statusBadge(bool pub, bool draft) {
    final c = pub
        ? const Color(0xFF1E3A5F)
        : draft
            ? const Color(0xFFF59E0B)
            : const Color(0xFF71717A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(pub ? 'Đã xuất bản' : draft ? 'Nháp' : 'Chờ duyệt',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: c)),
    );
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.themeIcon,
              size: 56, color: widget.themeColor.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          const Text('Chưa có bài viết nào',
              style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 14)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Tạo bài viết đầu tiên'),
            style: TextButton.styleFrom(foregroundColor: widget.themeColor),
          ),
        ]),
      );

  // ═══════════════════════════════════════════════════════════
  // TAB 2: Thư mục
  // ═══════════════════════════════════════════════════════════
  Widget _buildCategoriesTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Row(children: [
          Icon(Icons.folder_open, color: widget.themeColor, size: 20),
          const SizedBox(width: 8),
          Text('Quản lý thư mục',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: widget.themeColor)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _showCategoryDialog(),
            icon: const Icon(Icons.create_new_folder, size: 16),
            label: const Text('Tạo thư mục'),
            style: TextButton.styleFrom(foregroundColor: widget.themeColor),
          ),
        ]),
      ),
      const Divider(height: 24),
      Expanded(
        child: _categories.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.folder_off, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                const Text('Chưa có thư mục',
                    style: TextStyle(color: Color(0xFFA1A1AA))),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _showCategoryDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Tạo thư mục đầu tiên'),
                ),
              ]))
            : RefreshIndicator(
                onRefresh: _loadCategories,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _categories.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _categoryDeckItem(_categories[i]),
                    ),
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _categoryDeckItem(Map<String, dynamic> c) {
    final name = c['name'] ?? '';
    final desc = c['description'] ?? '';
    final count = c['articleCount'] ?? 0;
    final hex = c['color'] as String?;
    final color = hex != null && hex.isNotEmpty
        ? Color(int.tryParse(hex.replaceFirst('#', '0xFF')) ?? 0xFF6366F1)
        : const Color(0xFF6366F1);

    return InkWell(
      onTap: () => _showCategoryDialog(category: c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.folder, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFF4F4F5), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF71717A))),
          ),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.edit, size: 16, color: Color(0xFFA1A1AA)), onPressed: () => _showCategoryDialog(category: c), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
          IconButton(icon: const Icon(Icons.delete, size: 16, color: Color(0xFFA1A1AA)), onPressed: () => _deleteCategory(c), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Category CRUD
  // ═══════════════════════════════════════════════════════════
  void _showCategoryDialog({Map<String, dynamic>? category}) {
    final isEdit = category != null;
    final nameC = TextEditingController(text: category?['name'] ?? '');
    final descC =
        TextEditingController(text: category?['description'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isEdit ? 'Sửa thư mục' : 'Tạo thư mục mới',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
          child:
              Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameC,
              decoration: InputDecoration(
                labelText: 'Tên thư mục *',
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descC,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Mô tả',
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy',
                style: TextStyle(color: Color(0xFF71717A))),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameC.text.trim().isEmpty) {
                appNotification.showWarning(
                    title: 'Thiếu thông tin',
                    message: 'Vui lòng nhập tên thư mục');
                return;
              }
              try {
                final data = {
                  'name': nameC.text.trim(),
                  'description': descC.text.trim(),
                  'contentType': widget.contentType,
                };
                final result = isEdit
                    ? await _api.updateContentCategory(
                        category['id'].toString(), data)
                    : await _api.createContentCategory(data);
                if (result['isSuccess'] == true) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  appNotification.showSuccess(
                      title: 'Thành công',
                      message:
                          isEdit ? 'Đã cập nhật thư mục' : 'Đã tạo thư mục');
                  _loadCategories();
                } else {
                  appNotification.showError(
                      title: 'Lỗi',
                      message:
                          result['message']?.toString() ?? 'Lỗi thao tác');
                }
              } catch (e) {
                appNotification.showError(
                    title: 'Lỗi', message: 'Lỗi: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.themeColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(isEdit ? 'Cập nhật' : 'Tạo'),
          ),
        ],
      ),
    ).then((_) {
      nameC.dispose();
      descC.dispose();
    });
  }

  Future<void> _deleteCategory(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa thư mục "${c['name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final r = await _api.deleteContentCategory(c['id'].toString());
      if (r['isSuccess'] == true) {
        appNotification.showSuccess(
            title: 'Đã xóa', message: 'Đã xóa thư mục');
        _loadCategories();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Article actions
  // ═══════════════════════════════════════════════════════════
  Future<void> _publishArticle(Map<String, dynamic> a) async {
    final r = await _api.publishCommunication(a['id'].toString());
    if (r['isSuccess'] != false) {
      appNotification.showSuccess(
          title: 'Thành công', message: 'Đã xuất bản');
      _loadArticles();
    } else {
      appNotification.showError(
          title: 'Lỗi', message: r['message']?.toString() ?? 'Lỗi');
    }
  }

  Future<void> _deleteArticle(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa bài viết "${a['title']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final r = await _api.deleteCommunication(a['id'].toString());
      if (r['isSuccess'] != false) {
        appNotification.showSuccess(
            title: 'Đã xóa', message: 'Đã xóa bài viết');
        _loadArticles();
      }
    }
  }

  void _openEditor({Map<String, dynamic>? article}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ArticleEditorPage(
          contentType: widget.contentType,
          themeColor: widget.themeColor,
          article: article,
          categories: _categories,
          onSaved: () => _loadData(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ARTICLE EDITOR — Word-like với flutter_quill
// ═══════════════════════════════════════════════════════════════════
class _ArticleEditorPage extends StatefulWidget {
  final int contentType;
  final Color themeColor;
  final Map<String, dynamic>? article;
  final List<Map<String, dynamic>> categories;
  final VoidCallback onSaved;

  const _ArticleEditorPage({
    required this.contentType,
    required this.themeColor,
    this.article,
    required this.categories,
    required this.onSaved,
  });

  @override
  State<_ArticleEditorPage> createState() => _ArticleEditorPageState();
}

class _ArticleEditorPageState extends State<_ArticleEditorPage> {
  final ApiService _api = ApiService();
  late quill.QuillController _quillController;
  final ScrollController _editorScrollCtrl = ScrollController();
  final FocusNode _editorFocusNode = FocusNode();

  late TextEditingController _titleCtrl;
  late TextEditingController _summaryCtrl;
  late TextEditingController _tagsCtrl;
  late TextEditingController _videoUrlCtrl;
  final TextEditingController _aiPromptCtrl = TextEditingController();

  String? _selectedCategoryId;
  String? _thumbnailUrl;
  List<String> _attachedImages = [];
  bool _isSaving = false;
  bool _isGeneratingAi = false;
  bool _isAiGenerated = false;
  String? _aiPrompt;
  bool _showAiPanel = false;
  String _aiStreamedText = '';
  StreamSubscription<String>? _aiStreamSub;
  // list of video URLs to embed
  final List<String> _embeddedVideos = [];

  bool get _isEditing => widget.article != null;

  @override
  void initState() {
    super.initState();
    final a = widget.article;
    _titleCtrl = TextEditingController(text: a?['title'] ?? '');
    _summaryCtrl = TextEditingController(text: a?['summary'] ?? '');
    _tagsCtrl = TextEditingController(text: a?['tags'] ?? '');
    _videoUrlCtrl = TextEditingController();
    _selectedCategoryId = a?['categoryId']?.toString();
    _thumbnailUrl = a?['thumbnailUrl'];
    _isAiGenerated = a?['isAiGenerated'] == true;
    _aiPrompt = a?['aiPrompt'];

    if (a?['attachedImages'] is List) {
      _attachedImages = List<String>.from(a!['attachedImages']);
    }

    // Init quill
    final existingHtml = (a?['content'] ?? '').toString();
    if (existingHtml.isNotEmpty) {
      _quillController = quill.QuillController.basic();
      final plainText = _stripHtml(existingHtml);
      if (plainText.isNotEmpty) {
        _quillController.document =
            quill.Document()..insert(0, plainText);
        _quillController.moveCursorToEnd();
      }
    } else {
      _quillController = quill.QuillController.basic();
    }
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<\/p>'), '\n')
        .replaceAll(RegExp(r'<\/div>'), '\n')
        .replaceAll(RegExp(r'<\/h[1-6]>'), '\n')
        .replaceAll(RegExp(r'<\/li>'), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }

  @override
  void dispose() {
    _quillController.dispose();
    _editorScrollCtrl.dispose();
    _editorFocusNode.dispose();
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _tagsCtrl.dispose();
    _videoUrlCtrl.dispose();
    _aiPromptCtrl.dispose();
    _aiStreamSub?.cancel();
    super.dispose();
  }

  /// Convert Quill Delta to HTML
  String _deltaToHtml() {
    final delta = _quillController.document.toDelta();
    final ops = <Map<String, dynamic>>[];
    for (final op in delta.toList()) {
      final map = <String, dynamic>{'insert': op.data};
      if (op.attributes != null && op.attributes!.isNotEmpty) {
        map['attributes'] = Map<String, dynamic>.from(op.attributes!);
      }
      ops.add(map);
    }
    final converter = QuillDeltaToHtmlConverter(
      ops,
      ConverterOptions(
        multiLineBlockquote: true,
        multiLineHeader: false,
        multiLineCodeblock: true,
      ),
    );
    return converter.convert();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF71717A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? 'Chỉnh sửa bài viết' : 'Soạn bài viết mới',
          style: const TextStyle(
              color: Color(0xFF18181B),
              fontSize: 16,
              fontWeight: FontWeight.bold),
        ),
        actions: [
          // AI toggle
          IconButton(
            icon: Icon(Icons.auto_awesome,
                color: _showAiPanel
                    ? const Color(0xFF0F2340)
                    : const Color(0xFFA1A1AA)),
            tooltip: 'AI Gemini',
            onPressed: () =>
                setState(() => _showAiPanel = !_showAiPanel),
          ),
          TextButton(
            onPressed: _isSaving ? null : () => _save(publish: false),
            child: const Text('Lưu nháp',
                style: TextStyle(color: Color(0xFF71717A))),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: _isSaving ? null : () => _save(publish: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Xuất bản'),
            ),
          ),
        ],
      ),
      body: Column(children: [
        // AI panel
        if (_showAiPanel) _buildAiPanel(),

        // === QUILL TOOLBAR — Word-style ===
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: quill.QuillSimpleToolbar(
            controller: _quillController,
            config: const quill.QuillSimpleToolbarConfig(
              multiRowsDisplay: true,
              showDividers: true,
              showFontFamily: false,
              showFontSize: false,
              showBoldButton: true,
              showItalicButton: true,
              showUnderLineButton: true,
              showStrikeThrough: true,
              showColorButton: true,
              showBackgroundColorButton: true,
              showClearFormat: true,
              showAlignmentButtons: true,
              showLeftAlignment: true,
              showCenterAlignment: true,
              showRightAlignment: true,
              showJustifyAlignment: true,
              showHeaderStyle: true,
              showListNumbers: true,
              showListBullets: true,
              showListCheck: true,
              showCodeBlock: true,
              showQuote: true,
              showIndent: true,
              showLink: true,
              showUndo: true,
              showRedo: true,
              showDirection: false,
              showSearchButton: true,
              showSubscript: false,
              showSuperscript: false,
              showSmallButton: false,
              showInlineCode: true,
            ),
          ),
        ),
        const Divider(height: 24, color: Color(0xFFE4E4E7)),

        // === Main editor body ===
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 10 : 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    _card(
                      child: TextField(
                        controller: _titleCtrl,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF18181B)),
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Nhập tiêu đề bài viết...',
                          hintStyle: TextStyle(
                              color: Color(0xFFCBD5E1), fontSize: 22),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Summary
                    _card(
                      child: TextField(
                        controller: _summaryCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Tóm tắt ngắn gọn...',
                          hintStyle: TextStyle(
                              color: Color(0xFFCBD5E1), fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          prefixIcon: Padding(
                            padding: EdgeInsets.only(left: 12, right: 8),
                            child: Icon(Icons.short_text,
                                size: 18, color: Color(0xFFA1A1AA)),
                          ),
                          prefixIconConstraints:
                              BoxConstraints(minHeight: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // === QUILL EDITOR — nội dung chính ===
                    _card(
                      child: Container(
                        constraints:
                            const BoxConstraints(minHeight: 400),
                        padding: const EdgeInsets.all(2),
                        child: quill.QuillEditor(
                          controller: _quillController,
                          scrollController: _editorScrollCtrl,
                          focusNode: _editorFocusNode,
                          config: const quill.QuillEditorConfig(
                            placeholder: 'Nhập nội dung bài viết ở đây...',
                            padding: EdgeInsets.all(16),
                            autoFocus: false,
                            expands: false,
                            scrollable: false,
                            customStyles: quill.DefaultStyles(
                              paragraph: quill.DefaultTextBlockStyle(
                                TextStyle(
                                    fontSize: 15,
                                    height: 1.6,
                                    color: Color(0xFF334155)),
                                quill.HorizontalSpacing(0, 0),
                                quill.VerticalSpacing(6, 6),
                                quill.VerticalSpacing(0, 0),
                                null,
                              ),
                              h1: quill.DefaultTextBlockStyle(
                                TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A)),
                                quill.HorizontalSpacing(0, 0),
                                quill.VerticalSpacing(12, 6),
                                quill.VerticalSpacing(0, 0),
                                null,
                              ),
                              h2: quill.DefaultTextBlockStyle(
                                TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF18181B)),
                                quill.HorizontalSpacing(0, 0),
                                quill.VerticalSpacing(10, 4),
                                quill.VerticalSpacing(0, 0),
                                null,
                              ),
                              h3: quill.DefaultTextBlockStyle(
                                TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF334155)),
                                quill.HorizontalSpacing(0, 0),
                                quill.VerticalSpacing(8, 4),
                                quill.VerticalSpacing(0, 0),
                                null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Media section
                    _buildMediaSection(),
                    const SizedBox(height: 12),

                    // Metadata section
                    _buildMetaSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: child,
      );

  // ═══════════════════════════════════════════════════════════
  // AI Panel
  // ═══════════════════════════════════════════════════════════
  Widget _buildAiPanel() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            const Color(0xFF0F2340).withValues(alpha: 0.05),
            const Color(0xFF1E3A5F).withValues(alpha: 0.05),
          ]),
          border: const Border(
              bottom: BorderSide(color: Color(0xFFE4E4E7))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2340).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 16, color: Color(0xFF0F2340)),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('AI Gemini — Trợ lý soạn thảo',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF18181B))),
              ),
              if (_isAiGenerated)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2340).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Đã dùng AI',
                      style: TextStyle(
                          color: Color(0xFF0F2340),
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () =>
                    setState(() => _showAiPanel = false),
              ),
            ]),
            const SizedBox(height: 10),
            Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _aiPromptCtrl,
                      maxLines: 2,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: _aiHint(),
                        hintStyle: const TextStyle(
                            color: Color(0xFFCBD5E1), fontSize: 13),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_isGeneratingAi)
                    ElevatedButton(
                      onPressed: _cancelAiGeneration,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.stop, size: 16),
                          SizedBox(width: 6),
                          Text('Dừng'),
                        ],
                      ),
                    )
                  else
                    ElevatedButton(
                      onPressed: _generateWithAi,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F2340),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 16),
                          SizedBox(width: 6),
                          Text('Soạn'),
                        ],
                      ),
                    ),
                ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              children: _quickPrompts()
                  .map((p) => ActionChip(
                        label: Text(p,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF71717A))),
                        backgroundColor: Colors.white,
                        side: const BorderSide(
                            color: Color(0xFFE4E4E7)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _aiPromptCtrl.text = p,
                      ))
                  .toList(),
            ),
            // Streaming preview
            if (_isGeneratingAi) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF0F2340).withValues(alpha: 0.3)),
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: const Color(0xFF0F2340).withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _aiStreamedText.isEmpty ? 'AI đang suy nghĩ...' : 'AI đang viết...',
                            style: TextStyle(
                              fontSize: 11,
                              color: const Color(0xFF0F2340).withValues(alpha: 0.7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (_aiStreamedText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _aiStreamedText,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF52525B), height: 1.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  String _aiHint() =>
      widget.contentType == 7 || widget.contentType == 3
          ? 'VD: Soạn nội quy giờ làm việc, trang phục...'
          : 'VD: Soạn bài đào tạo kỹ năng giao tiếp...';

  List<String> _quickPrompts() =>
      widget.contentType == 7 || widget.contentType == 3
          ? [
              'Nội quy giờ làm việc',
              'Quy định trang phục',
              'Nội quy sử dụng tài sản',
              'Quy tắc bảo mật',
              'An toàn lao động',
              'Xử lý vi phạm',
            ]
          : [
              'Kỹ năng giao tiếp',
              'Quy trình bán hàng',
              'An toàn lao động',
              'Hướng dẫn phần mềm',
              'Quản lý thời gian',
              'Nghiệp vụ chuyên môn',
            ];

  Future<void> _generateWithAi() async {
    final prompt = _aiPromptCtrl.text.trim();
    if (prompt.isEmpty) {
      appNotification.showWarning(
          title: 'Thiếu nội dung',
          message: 'Vui lòng mô tả nội dung bạn muốn AI soạn');
      return;
    }
    setState(() {
      _isGeneratingAi = true;
      _aiStreamedText = '';
    });

    final stream = _api.streamAiCommunicationContent({
      'prompt': prompt,
      'type': widget.contentType,
      'tone': 'formal',
      'maxLength': 3000,
      'language': 'vi',
      'context': widget.contentType == 7 || widget.contentType == 3
          ? 'Đây là nội quy/quy định công ty, cần rõ ràng, chi tiết'
          : 'Đây là tài liệu đào tạo nhân viên, cần sinh động, dễ tiếp thu',
    });

    _aiStreamSub = stream.listen(
      (chunk) {
        if (!mounted) return;
        if (chunk.startsWith('[ERROR]')) {
          final msg = chunk.substring(7);
          appNotification.showError(title: 'Lỗi AI', message: msg);
          setState(() => _isGeneratingAi = false);
          return;
        }
        setState(() {
          _aiStreamedText += chunk;
        });
      },
      onDone: () {
        if (!mounted) return;
        if (_aiStreamedText.isNotEmpty) {
          setState(() {
            if (_titleCtrl.text.isEmpty) {
              // Extract first line as title
              final lines = _aiStreamedText.split('\n');
              if (lines.isNotEmpty) {
                _titleCtrl.text = lines.first.replaceAll(RegExp(r'^[#=\s*]+'), '').trim();
              }
            }
            _quillController.document = quill.Document()..insert(0, _aiStreamedText);
            _quillController.moveCursorToEnd();
            _isAiGenerated = true;
            _aiPrompt = prompt;
            _isGeneratingAi = false;
          });
          appNotification.showSuccess(
              title: 'AI đã soạn xong',
              message: 'Bạn có thể chỉnh sửa nội dung');
        } else {
          setState(() => _isGeneratingAi = false);
        }
      },
      onError: (e) {
        if (!mounted) return;
        appNotification.showError(
            title: 'Lỗi', message: 'Lỗi kết nối AI: $e');
        setState(() => _isGeneratingAi = false);
      },
    );
  }

  void _cancelAiGeneration() {
    _aiStreamSub?.cancel();
    _aiStreamSub = null;
    if (_aiStreamedText.isNotEmpty) {
      // Keep what was generated so far
      setState(() {
        _quillController.document = quill.Document()..insert(0, _aiStreamedText);
        _quillController.moveCursorToEnd();
        _isGeneratingAi = false;
      });
      appNotification.showWarning(
          title: 'Đã dừng', message: 'Nội dung đã soạn được giữ lại');
    } else {
      setState(() => _isGeneratingAi = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Media Section
  // ═══════════════════════════════════════════════════════════
  Widget _buildMediaSection() {
    return _sectionCard(
      title: 'Phương tiện',
      icon: Icons.perm_media_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Thumbnail ──
        const Text('Ảnh đại diện',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF52525B))),
        const SizedBox(height: 8),
        Row(children: [
          InkWell(
            onTap: _pickThumbnail,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 140,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE4E4E7)),
                image: _thumbnailUrl != null &&
                        _thumbnailUrl!.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(_thumbnailUrl!),
                        fit: BoxFit.cover,
                        onError: (_, __) {})
                    : null,
              ),
              child: _thumbnailUrl == null || _thumbnailUrl!.isEmpty
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate,
                            size: 28, color: Color(0xFFA1A1AA)),
                        SizedBox(height: 4),
                        Text('Chọn ảnh',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFA1A1AA))),
                      ])
                  : null,
            ),
          ),
          if (_thumbnailUrl != null && _thumbnailUrl!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close,
                  size: 16, color: Color(0xFFEF4444)),
              onPressed: () => setState(() => _thumbnailUrl = null),
            ),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Metadata Section
  // ═══════════════════════════════════════════════════════════
  Widget _buildMetaSection() {
    return _sectionCard(
      title: 'Thông tin bổ sung',
      icon: Icons.tune,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.categories.isNotEmpty) ...[
              const Text('Thư mục',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF52525B))),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedCategoryId,
                    isExpanded: true,
                    hint: const Text('Chọn thư mục',
                        style: TextStyle(fontSize: 13)),
                    items: [
                      const DropdownMenuItem(
                          value: null,
                          child: Text('Không chọn')),
                      ...widget.categories.map((c) =>
                          DropdownMenuItem(
                            value: c['id'].toString(),
                            child: Text(c['name'] ?? '',
                                style: const TextStyle(
                                    fontSize: 13)),
                          )),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedCategoryId = v),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text('Tags / Từ khóa',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF52525B))),
            const SizedBox(height: 6),
            TextField(
              controller: _tagsCtrl,
              decoration: InputDecoration(
                hintText:
                    'nội quy, giờ làm, trang phục (phân cách dấu phẩy)',
                hintStyle: const TextStyle(
                    fontSize: 12, color: Color(0xFFCBD5E1)),
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 14),
              ),
            ),
          ]),
    );
  }

  Widget _sectionCard(
      {required String title,
      required IconData icon,
      required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: widget.themeColor),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: widget.themeColor)),
            ]),
            const SizedBox(height: 12),
            child,
          ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Image pickers
  // ═══════════════════════════════════════════════════════════
  Future<void> _pickThumbnail() async {
    final images = await pickImagesWithCamera(context);
    if (images != null && images.isNotEmpty) {
      final url = await _uploadImage(images.first.bytes, images.first.name);
      if (url != null) setState(() => _thumbnailUrl = url);
    }
  }

  Future<String?> _uploadImage(
      Uint8List bytes, String fileName) async {
    appNotification.showInfo(
        title: 'Đang tải ảnh...', message: fileName);
    final result =
        await _api.uploadCommunicationImage(bytes.toList(), fileName);
    if (result['isSuccess'] != false && result['data'] != null) {
      return result['data'].toString();
    } else {
      appNotification.showError(
          title: 'Lỗi upload',
          message: result['message']?.toString() ?? 'Không thể upload');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Save
  // ═══════════════════════════════════════════════════════════
  Future<void> _save({required bool publish}) async {
    if (_titleCtrl.text.trim().isEmpty) {
      appNotification.showWarning(
          title: 'Thiếu tiêu đề',
          message: 'Vui lòng nhập tiêu đề');
      return;
    }
    final plainText =
        _quillController.document.toPlainText().trim();
    if (plainText.isEmpty) {
      appNotification.showWarning(
          title: 'Thiếu nội dung',
          message: 'Vui lòng nhập nội dung bài viết');
      return;
    }
    setState(() => _isSaving = true);
    try {
      // Build HTML content
      String htmlContent = _deltaToHtml();

      // Append attached images
      if (_attachedImages.isNotEmpty) {
        htmlContent += '<div style="margin-top:20px">';
        for (final img in _attachedImages) {
          htmlContent +=
              '<img src="$img" style="max-width:100%;border-radius:8px;margin:8px 0"/>';
        }
        htmlContent += '</div>';
      }

      // Append video embeds
      for (final videoUrl in _embeddedVideos) {
        String embedUrl = videoUrl;
        final yt = RegExp(
                r'(?:youtube\.com/watch\?v=|youtu\.be/)([a-zA-Z0-9_-]+)')
            .firstMatch(videoUrl);
        if (yt != null) {
          embedUrl = 'https://www.youtube.com/embed/${yt.group(1)}';
        }
        htmlContent +=
            '<div style="position:relative;padding-bottom:56.25%;height:0;overflow:hidden;margin:16px 0">'
            '<iframe src="$embedUrl" style="position:absolute;top:0;left:0;width:100%;height:100%;border:0" '
            'allowfullscreen></iframe></div>';
      }

      final data = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'content': htmlContent,
        'summary': _summaryCtrl.text.trim(),
        'thumbnailUrl': _thumbnailUrl,
        'attachedImages': _attachedImages,
        'type': widget.contentType,
        'tags': _tagsCtrl.text.trim(),
        'publishImmediately': publish,
        'isAiGenerated': _isAiGenerated,
        'aiPrompt': _aiPrompt,
        'categoryId': _selectedCategoryId,
      };

      Map<String, dynamic> result;
      if (_isEditing) {
        result = await _api.updateCommunication(
            widget.article!['id'].toString(), data);
        if (publish) {
          await _api.publishCommunication(
              widget.article!['id'].toString());
        }
      } else {
        result = await _api.createCommunication(data);
      }

      if (result['isSuccess'] != false) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: publish ? 'Đã xuất bản bài viết' : 'Đã lưu nháp',
        );
        widget.onSaved();
        if (mounted) Navigator.pop(context);
      } else {
        appNotification.showError(
            title: 'Lỗi',
            message: result['message']?.toString() ??
                'Không thể lưu bài viết');
      }
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
