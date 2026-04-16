import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';

/// Màn hình Đào tạo — hiển thị bài viết loại Training (type=4)
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCategoryId;
  String _selectedTimeFilter = 'newest';
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _showMobileFilters = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([_loadArticles(), _loadCategories()]);
    } catch (e) {
      debugPrint('Load training data error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadArticles() async {
    try {
      final result = await _api.getCommunications(type: 4, pageSize: 200);
      final data = result['data'];
      if (data != null && data['items'] != null) {
        if (mounted) {
          setState(() => _articles = List<Map<String, dynamic>>.from(data['items']));
        }
      }
    } catch (e) {
      debugPrint('Load training articles error: $e');
    }
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _api.getContentCategories(contentType: 4);
      if (mounted) {
        setState(() => _categories = List<Map<String, dynamic>>.from(cats));
      }
    } catch (e) {
      debugPrint('Load categories error: $e');
    }
  }

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

  bool _isInTimeRange(Map<String, dynamic> a) {
    if (_selectedTimeFilter == 'all' || _selectedTimeFilter == 'newest') return true;
    final raw = a['createdAt'] ?? a['publishedAt'] ?? a['updatedAt'];
    if (raw == null) return true;
    final date = DateTime.tryParse(raw.toString());
    if (date == null) return true;
    final now = DateTime.now();
    switch (_selectedTimeFilter) {
      case 'this_week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return date.isAfter(DateTime(weekStart.year, weekStart.month, weekStart.day));
      case 'this_month':
        return date.year == now.year && date.month == now.month;
      case 'last_month':
        final lastMonth = DateTime(now.year, now.month - 1);
        return date.year == lastMonth.year && date.month == lastMonth.month;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _filteredArticles {
    var result = _articles.where((a) {
      if (_parseStatus(a['status']) != 2) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final title = (a['title'] ?? '').toString().toLowerCase();
        final summary = (a['summary'] ?? '').toString().toLowerCase();
        if (!title.contains(q) && !summary.contains(q)) return false;
      }
      if (_selectedCategoryId != null) {
        if (a['categoryId']?.toString() != _selectedCategoryId) return false;
      }
      if (!_isInTimeRange(a)) return false;
      return true;
    }).toList();
    if (_selectedTimeFilter == 'newest') {
      result.sort((a, b) {
        final da = DateTime.tryParse((a['createdAt'] ?? '').toString()) ?? DateTime(2000);
        final db = DateTime.tryParse((b['createdAt'] ?? '').toString()) ?? DateTime(2000);
        return db.compareTo(da);
      });
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredArticles;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: _isLoading
          ? const LoadingWidget()
          : Column(children: [
              // ── Header ──
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.school, color: Color(0xFF1E3A5F), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Đào tạo',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
                        SizedBox(height: 2),
                        Text('Chương trình đào tạo, khóa học nội bộ',
                            style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
                      ]),
                    ),
                    if (Responsive.isMobile(context))
                      IconButton(
                        icon: Stack(
                          children: [
                            Icon(
                              _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                              color: _showMobileFilters ? Colors.orange : const Color(0xFF71717A),
                            ),
                            if (_searchQuery.isNotEmpty || _selectedCategoryId != null || _selectedTimeFilter != 'newest')
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
                  ]),
                  if (!Responsive.isMobile(context) || _showMobileFilters) ...[
                  const SizedBox(height: 16),
                  // ── Search & Filter ──
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    SizedBox(
                      width: 320,
                      height: 40,
                      child: TextField(
                        onChanged: (v) => setState(() { _searchQuery = v; _currentPage = 1; }),
                        decoration: InputDecoration(
                          hintText: 'Tìm kiếm bài đào tạo...',
                          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA1A1AA)),
                          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFA1A1AA)),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                        ),
                      ),
                    ),
                    if (_categories.isNotEmpty)
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedCategoryId,
                            hint: const Text('Tất cả danh mục', style: TextStyle(fontSize: 13)),
                            style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Tất cả danh mục')),
                              ..._categories.map((c) => DropdownMenuItem(
                                    value: c['id'].toString(),
                                    child: Text(c['name'] ?? ''),
                                  )),
                            ],
                            onChanged: (v) => setState(() { _selectedCategoryId = v; _currentPage = 1; }),
                          ),
                        ),
                      ),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedTimeFilter,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                          items: const [
                            DropdownMenuItem(value: 'newest', child: Text('Mới nhất')),
                            DropdownMenuItem(value: 'this_week', child: Text('Tuần này')),
                            DropdownMenuItem(value: 'this_month', child: Text('Tháng này')),
                            DropdownMenuItem(value: 'last_month', child: Text('Tháng trước')),
                            DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                          ],
                          onChanged: (v) => setState(() { _selectedTimeFilter = v ?? 'newest'; _currentPage = 1; }),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A5F).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${filtered.length} bài viết',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  ], // end _showMobileFilters
                ]),
              ),

              // ── Content list ──
              Expanded(
                child: filtered.isEmpty
                    ? _emptyState()
                    : _buildPaginatedList(filtered),
              ),
            ]),
    );
  }

  Widget _buildPaginatedList(List<Map<String, dynamic>> filtered) {
    final isMobile = Responsive.isMobile(context);
    final totalCount = filtered.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = isMobile ? 0 : (page - 1) * _pageSize;
    final endIndex = isMobile ? totalCount : (page * _pageSize).clamp(0, totalCount);
    final paginatedItems = filtered.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: paginatedItems.length,
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
                  child: _articleCard(paginatedItems[i]),
                ),
              ),
            ),
          ),
        ),
        if (totalPages > 1 && !isMobile)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hiển thị ${startIndex + 1}-$endIndex / $totalCount',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: page > 1 ? () => setState(() => _currentPage--) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    Text('$page / $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: page < totalPages ? () => setState(() => _currentPage++) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _articleCard(Map<String, dynamic> a) {
    final title = (a['title'] ?? 'Chưa có tiêu đề').toString();
    final summary = (a['summary'] ?? '').toString();
    final thumb = a['thumbnailUrl']?.toString();
    final created = DateTime.tryParse((a['createdAt'] ?? '').toString());
    final views = a['viewCount'] ?? 0;

    return InkWell(
      onTap: () => _openDetail(a),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              image: thumb != null && thumb.isNotEmpty
                  ? DecorationImage(image: NetworkImage(thumb), fit: BoxFit.cover, onError: (_, __) {}) : null,
            ),
            child: thumb == null || thumb.isEmpty
                ? const Icon(Icons.school_outlined, color: Color(0xFF6EE7B7), size: 22) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF18181B)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                [
                  if (summary.isNotEmpty) summary,
                  '$views lượt xem',
                  if (created != null) '${created.day}/${created.month}/${created.year}',
                ].join(' · '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
        ]),
      ),
    );
  }

  void _openDetail(Map<String, dynamic> article) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _TrainingDetailPage(article: article),
    ));
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.school_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Chưa có bài đào tạo nào', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey[500])),
          const SizedBox(height: 6),
          Text('Các bài đào tạo đã xuất bản sẽ hiển thị ở đây', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════
// Training Article Detail View
// ═══════════════════════════════════════════════════════════════
class _TrainingDetailPage extends StatelessWidget {
  final Map<String, dynamic> article;
  const _TrainingDetailPage({required this.article});

  @override
  Widget build(BuildContext context) {
    final title = (article['title'] ?? '').toString();
    final content = (article['content'] ?? '').toString();
    final author = (article['authorName'] ?? '').toString();
    final created = DateTime.tryParse((article['createdAt'] ?? '').toString());
    final views = article['viewCount'] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)), onPressed: () => Navigator.pop(context)),
        title: Text(title, style: const TextStyle(color: Color(0xFF18181B), fontSize: 16, fontWeight: FontWeight.bold),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
                  const SizedBox(height: 12),
                  Wrap(spacing: 16, runSpacing: 6, children: [
                    if (author.isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.person_outline, size: 16, color: Color(0xFF71717A)),
                        const SizedBox(width: 4),
                        Text(author, style: const TextStyle(fontSize: 13, color: Color(0xFF71717A))),
                      ]),
                    if (created != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF71717A)),
                        const SizedBox(width: 4),
                        Text('${created.day}/${created.month}/${created.year}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF71717A))),
                      ]),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.visibility_outlined, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text('$views lượt xem', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                    ]),
                  ]),
                ]),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: content.isNotEmpty
                    ? Html(data: content)
                    : const Text('Không có nội dung', style: TextStyle(color: Color(0xFFA1A1AA), fontStyle: FontStyle.italic)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
