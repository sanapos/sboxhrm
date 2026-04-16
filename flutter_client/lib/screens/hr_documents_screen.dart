import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_responsive_dialog.dart';
import '../widgets/notification_overlay.dart';

class HrDocumentsScreen extends StatefulWidget {
  const HrDocumentsScreen({super.key});

  @override
  State<HrDocumentsScreen> createState() => _HrDocumentsScreenState();
}

class _HrDocumentsScreenState extends State<HrDocumentsScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  bool _isLoading = false;
  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _expiringDocs = [];
  int _currentPage = 1;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() => _currentPage = 1);
    });
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
      final results = await Future.wait([
        _apiService.getHrDocuments(),
        _apiService.getExpiringDocuments(),
      ]);
      setState(() {
        if (results[0]['isSuccess'] == true) _documents = List<Map<String, dynamic>>.from(results[0]['data'] ?? []);
        if (results[1]['isSuccess'] == true) _expiringDocs = List<Map<String, dynamic>>.from(results[1]['data'] ?? []);
      });
    } catch (e) {
      debugPrint('Error loading HR documents: $e');
    }
    setState(() => _isLoading = false);
  }

  Color _getDocTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'contract': return const Color(0xFF1E3A5F);
      case 'certificate': return const Color(0xFF0F2340);
      case 'id_card': return const Color(0xFFEA580C);
      case 'insurance': return const Color(0xFF059669);
      case 'license': return const Color(0xFF0F2340);
      default: return const Color(0xFF6B7280);
    }
  }

  String _getDocTypeLabel(String? type) {
    switch (type?.toLowerCase()) {
      case 'contract': return 'Hợp đồng';
      case 'certificate': return 'Bằng cấp';
      case 'id_card': return 'CMND/CCCD';
      case 'insurance': return 'Bảo hiểm';
      case 'license': return 'Giấy phép';
      default: return type ?? 'Khác';
    }
  }

  IconData _getDocTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'contract': return Icons.description;
      case 'certificate': return Icons.workspace_premium;
      case 'id_card': return Icons.badge;
      case 'insurance': return Icons.health_and_safety;
      case 'license': return Icons.card_membership;
      default: return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(controller: _tabController, children: [
                    _buildDocumentsList(_documents),
                    _buildExpiringList(),
                  ]),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showDocumentDialog(),
        icon: const Icon(Icons.note_add),
        label: const Text('Thêm tài liệu'),
        backgroundColor: const Color(0xFF0F2340),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF153058), Color(0xFF0F2340)]),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.folder_special, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hồ sơ nhân sự', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    Text('Hợp đồng, bằng cấp, giấy phép', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
              if (_expiringDocs.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.warning_amber, color: Color(0xFFD97706), size: 16),
                    const SizedBox(width: 4),
                    Text('${_expiringDocs.length} sắp hết hạn', style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w600, fontSize: 12)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: 'Tất cả (${_documents.length})'),
              Tab(text: 'Sắp hết hạn (${_expiringDocs.length})'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsList(List<Map<String, dynamic>> docs) {
    if (docs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_open, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Chưa có tài liệu', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ]),
      );
    }
    final totalCount = docs.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedDocs = docs.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: paginatedDocs.length,
            itemBuilder: (ctx, i) => Padding(
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
                child: _buildDocDeckItem(paginatedDocs[i]),
              ),
            ),
          ),
        ),
        if (totalPages > 1)
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
                      onPressed: page > 1 ? () => setState(() => _currentPage = page - 1) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    Text('$page / $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: page < totalPages ? () => setState(() => _currentPage = page + 1) : null,
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

  Widget _buildExpiringList() {
    if (_expiringDocs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified, size: 80, color: Colors.green[200]),
          const SizedBox(height: 16),
          Text('Không có tài liệu sắp hết hạn', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ]),
      );
    }
    final totalCount = _expiringDocs.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedDocs = _expiringDocs.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: paginatedDocs.length,
            itemBuilder: (ctx, i) {
              final doc = paginatedDocs[i];
              return Padding(
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
                  child: _buildDocDeckItem(doc, showWarning: true),
                ),
              );
            },
          ),
        ),
        if (totalPages > 1)
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
                      onPressed: page > 1 ? () => setState(() => _currentPage = page - 1) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    Text('$page / $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: page < totalPages ? () => setState(() => _currentPage = page + 1) : null,
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

  Widget _buildDocDeckItem(Map<String, dynamic> doc, {bool showWarning = false}) {
    final type = doc['documentType'] ?? doc['type'];
    final color = _getDocTypeColor(type);
    final expDate = doc['expiryDate'] ?? doc['expirationDate'];
    return InkWell(
      onTap: () => _showDocumentDialog(doc: doc),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(_getDocTypeIcon(type), color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc['title'] ?? doc['name'] ?? doc['documentName'] ?? 'Tài liệu', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [
                      _getDocTypeLabel(type),
                      if (doc['employeeName'] != null) doc['employeeName'],
                      if (expDate != null) 'Hết hạn: ${_formatDate(expDate)}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: showWarning ? const Color(0xFFD97706) : Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (showWarning)
              const Icon(Icons.warning_amber, size: 16, color: Color(0xFFD97706)),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey[400], size: 18),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Sửa')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Xóa', style: TextStyle(color: Colors.red))])),
              ],
              onSelected: (v) {
                if (v == 'edit') _showDocumentDialog(doc: doc);
                if (v == 'delete') _deleteDocument(doc);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date.toString());
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return date.toString();
    }
  }

  Future<void> _deleteDocument(Map<String, dynamic> doc) async {
    final confirm = await AppResponsiveDialog.confirmDelete(
      context: context,
      itemName: doc['title'] ?? doc['name'] ?? 'tài liệu',
    );
    if (confirm != true) return;
    try {
      await _apiService.deleteHrDocument(doc['id']?.toString() ?? '');
      _loadData();
    } catch (e) {
      debugPrint('Error deleting document: $e');
    }
  }

  void _showDocumentDialog({Map<String, dynamic>? doc}) {
    final isEdit = doc != null;
    final nameCtrl = TextEditingController(text: doc?['title'] ?? doc?['name'] ?? doc?['documentName'] ?? '');
    final typeCtrl = TextEditingController(text: doc?['documentType'] ?? doc?['type'] ?? '');
    final numberCtrl = TextEditingController(text: doc?['documentNumber'] ?? doc?['number'] ?? '');
    final noteCtrl = TextEditingController(text: doc?['notes'] ?? doc?['description'] ?? '');

    AppResponsiveDialog.show(
      context: context,
      title: isEdit ? 'Sửa tài liệu' : 'Thêm tài liệu',
      icon: isEdit ? Icons.edit : Icons.note_add,
      maxWidth: 420,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: InputDecoration(labelText: 'Tên tài liệu *', prefixIcon: const Icon(Icons.description, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: typeCtrl.text.isNotEmpty ? typeCtrl.text : null,
          decoration: InputDecoration(labelText: 'Loại', prefixIcon: const Icon(Icons.category, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          items: const [
            DropdownMenuItem(value: 'contract', child: Text('Hợp đồng')),
            DropdownMenuItem(value: 'certificate', child: Text('Bằng cấp')),
            DropdownMenuItem(value: 'id_card', child: Text('CMND/CCCD')),
            DropdownMenuItem(value: 'insurance', child: Text('Bảo hiểm')),
            DropdownMenuItem(value: 'license', child: Text('Giấy phép')),
          ],
          onChanged: (v) => typeCtrl.text = v ?? '',
        ),
        const SizedBox(height: 12),
        TextField(controller: numberCtrl, decoration: InputDecoration(labelText: 'Số tài liệu', prefixIcon: const Icon(Icons.tag, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
        const SizedBox(height: 12),
        TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: InputDecoration(labelText: 'Ghi chú', prefixIcon: const Icon(Icons.notes, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
      ]),
      actions: AppDialogActions(
        onCancel: () => Navigator.pop(context),
        onConfirm: () async {
          if (nameCtrl.text.trim().isEmpty) {
            appNotification.showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập tên tài liệu');
            return;
          }
          final data = {
            'title': nameCtrl.text,
            'documentName': nameCtrl.text,
            'name': nameCtrl.text,
            'documentType': typeCtrl.text,
            'type': typeCtrl.text,
            'documentNumber': numberCtrl.text,
            'number': numberCtrl.text,
            'notes': noteCtrl.text,
            'description': noteCtrl.text,
          };
          final navigator = Navigator.of(context);
          try {
            if (isEdit) {
              await _apiService.updateHrDocument(doc['id']?.toString() ?? '', data);
            } else {
              await _apiService.createHrDocument(data);
            }
            navigator.pop();
            _loadData();
          } catch (e) {
            if (context.mounted) {
              appNotification.showError(title: 'Lỗi', message: 'Không thể lưu tài liệu: $e');
            }
          }
        },
        confirmLabel: isEdit ? 'Cập nhật' : 'Tạo',
        confirmIcon: isEdit ? Icons.save : Icons.add,
      ),
    ).then((_) {
      nameCtrl.dispose();
      typeCtrl.dispose();
      numberCtrl.dispose();
      noteCtrl.dispose();
    });
  }
}
