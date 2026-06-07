import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/employee.dart';
import '../widgets/loading_widget.dart';
import '../widgets/hrm_page_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// QUẢN LÝ QUÁ TRÌNH CÔNG TÁC CỦA NHÂN VIÊN
// Bao gồm: Chức vụ, Phòng ban, Khen thưởng, Kỷ luật
// ═══════════════════════════════════════════════════════════════

class EmployeeCareerScreen extends StatefulWidget {
  final Employee employee;

  const EmployeeCareerScreen({super.key, required this.employee});

  @override
  State<EmployeeCareerScreen> createState() => _EmployeeCareerScreenState();
}

class _EmployeeCareerScreenState extends State<EmployeeCareerScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;

  bool _loadingAssignments = true;
  bool _loadingAwards = true;
  bool _loadingDisciplines = true;

  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _awards = [];
  List<Map<String, dynamic>> _disciplines = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadAssignments(),
      _loadAwards(),
      _loadDisciplines(),
    ]);
  }

  Future<void> _loadAssignments() async {
    setState(() => _loadingAssignments = true);
    final res =
        await _apiService.getOrgAssignments(employeeId: widget.employee.id);
    if (mounted) {
      setState(() {
        _loadingAssignments = false;
        if (res['isSuccess'] == true) {
          _assignments = List<Map<String, dynamic>>.from(res['data'] ?? []);
        }
      });
    }
  }

  Future<void> _loadAwards() async {
    setState(() => _loadingAwards = true);
    // HrDocumentType.Award = 9
    final res = await _apiService.getHrDocuments(
        employeeId: widget.employee.id, type: '9', page: 1, pageSize: 500);
    if (mounted) {
      setState(() {
        _loadingAwards = false;
        if (res['isSuccess'] == true) {
          final data = res['data'];
          if (data is List) {
            _awards = List<Map<String, dynamic>>.from(data);
          } else if (data is Map && data['items'] != null) {
            _awards = List<Map<String, dynamic>>.from(data['items']);
          }
        }
      });
    }
  }

  Future<void> _loadDisciplines() async {
    setState(() => _loadingDisciplines = true);
    // HrDocumentType.Discipline = 8
    final res = await _apiService.getHrDocuments(
        employeeId: widget.employee.id, type: '8', page: 1, pageSize: 500);
    if (mounted) {
      setState(() {
        _loadingDisciplines = false;
        if (res['isSuccess'] == true) {
          final data = res['data'];
          if (data is List) {
            _disciplines = List<Map<String, dynamic>>.from(data);
          } else if (data is Map && data['items'] != null) {
            _disciplines = List<Map<String, dynamic>>.from(data['items']);
          }
        }
      });
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  Color _positionColor(int level) {
    switch (level) {
      case 1:
        return const Color(0xFF7C3AED);
      case 2:
        return const Color(0xFF1D4ED8);
      case 3:
        return const Color(0xFF0369A1);
      case 4:
        return const Color(0xFF0F766E);
      case 5:
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF52525B);
    }
  }

  // ─── Position/Department tab common: derive from _assignments ──────────────
  List<Map<String, dynamic>> get _positionHistory =>
      List<Map<String, dynamic>>.from(_assignments)
        ..sort((a, b) {
          final sa = a['startDate']?.toString() ?? '';
          final sb = b['startDate']?.toString() ?? '';
          return sb.compareTo(sa); // newest first
        });

  List<Map<String, dynamic>> get _departmentHistory {
    // Deduplicate: group by dept+period
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final a in _positionHistory) {
      final key = '${a['departmentId']}_${a['startDate']}_${a['endDate']}';
      if (!seen.contains(key)) {
        seen.add(key);
        result.add(a);
      }
    }
    return result;
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────
  Future<void> _showAddPositionDialog() async {
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Load org positions and departments first
    final posRes = await _apiService.getOrgPositions();
    final deptRes = await _apiService.getDepartments(pageSize: 100);

    if (!mounted) return;

    final positions = posRes['isSuccess'] == true
        ? List<Map<String, dynamic>>.from(posRes['data'] ?? [])
        : <Map<String, dynamic>>[];
    final departments = deptRes['isSuccess'] != false
        ? List<Map<String, dynamic>>.from((deptRes['data'] is List
            ? deptRes['data']
            : deptRes['data']?['items'] ?? deptRes['items'] ?? []))
        : <Map<String, dynamic>>[];

    String? selectedDeptId;
    String? selectedPosId;
    bool isPrimary = true;
    DateTime? startDate = DateTime.now();
    DateTime? endDate;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final content = SingleChildScrollView(
            padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Phòng ban *',
                    prefixIcon: Icon(Icons.business),
                  ),
                  items: departments
                      .map((d) => DropdownMenuItem(
                          value: d['id']?.toString(),
                          child: Text(d['name']?.toString() ?? '')))
                      .toList(),
                  onChanged: (v) => setState(() => selectedDeptId = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Chức vụ *',
                    prefixIcon: Icon(Icons.badge),
                  ),
                  items: positions
                      .map((p) => DropdownMenuItem(
                          value: p['id']?.toString(),
                          child: Text(p['name']?.toString() ?? '')))
                      .toList(),
                  onChanged: (v) => setState(() => selectedPosId = v),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: startDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setState(() => startDate = d);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'Ngày bắt đầu',
                              prefixIcon: Icon(Icons.calendar_today)),
                          child: Text(startDate != null
                              ? DateFormat('dd/MM/yyyy').format(startDate!)
                              : 'Chọn ngày'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: endDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setState(() => endDate = d);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Ngày kết thúc',
                            prefixIcon: const Icon(Icons.event_available),
                            suffixIcon: endDate != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () =>
                                        setState(() => endDate = null))
                                : null,
                          ),
                          child: Text(endDate != null
                              ? DateFormat('dd/MM/yyyy').format(endDate!)
                              : 'Đang giữ'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Chức vụ chính'),
                  value: isPrimary,
                  onChanged: (v) => setState(() => isPrimary = v),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          );
          return _buildFormDialog(
            ctx: ctx,
            title: 'Thêm chức vụ / phòng ban',
            icon: Icons.badge,
            content: content,
            isMobile: isMobile,
            onSave: () async {
              if (selectedDeptId == null || selectedPosId == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Vui lòng chọn phòng ban và chức vụ')));
                return;
              }
              final data = {
                'employeeId': widget.employee.id,
                'departmentId': selectedDeptId,
                'positionId': selectedPosId,
                'isPrimary': isPrimary,
                'startDate': startDate?.toIso8601String(),
                'endDate': endDate?.toIso8601String(),
              };
              Navigator.pop(ctx);
              final res = await _apiService.createOrgAssignment(data);
              if (mounted) {
                if (res['isSuccess'] == true) {
                  _showSuccess('Đã thêm ghi nhận chức vụ');
                  _loadAssignments();
                } else {
                  _showError(res['message'] ?? 'Không thể thêm chức vụ');
                }
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _showAddAwardDialog({bool isDiscipline = false}) async {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final docNumberCtrl = TextEditingController();
    DateTime? effectiveDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final content = SingleChildScrollView(
            padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: isDiscipline
                        ? 'Hình thức kỷ luật *'
                        : 'Nội dung khen thưởng *',
                    prefixIcon:
                        Icon(isDiscipline ? Icons.gavel : Icons.star_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: docNumberCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Số quyết định',
                    prefixIcon: Icon(Icons.numbers),
                    hintText: 'VD: QĐ-01/2025',
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: effectiveDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => effectiveDate = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Ngày hiệu lực',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(effectiveDate != null
                        ? DateFormat('dd/MM/yyyy').format(effectiveDate!)
                        : 'Chọn ngày'),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú',
                    prefixIcon: Icon(Icons.notes),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          );
          return _buildFormDialog(
            ctx: ctx,
            title: isDiscipline ? 'Thêm kỷ luật' : 'Thêm khen thưởng',
            icon: isDiscipline ? Icons.gavel : Icons.emoji_events,
            iconColor: isDiscipline
                ? const Color(0xFFDC2626)
                : const Color(0xFFD97706),
            content: content,
            isMobile: isMobile,
            onSave: () async {
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Vui lòng nhập nội dung')));
                return;
              }
              final data = {
                'employeeUserId': widget.employee.id,
                'name': nameCtrl.text.trim(),
                'documentType': isDiscipline ? 8 : 9,
                'effectiveDate': effectiveDate?.toIso8601String(),
                'documentNumber': docNumberCtrl.text.trim().isNotEmpty
                    ? docNumberCtrl.text.trim()
                    : null,
                'notes': notesCtrl.text.trim().isNotEmpty
                    ? notesCtrl.text.trim()
                    : null,
                'filePath': 'manual_entry',
                'fileName': 'entry.txt',
                'fileSize': 0,
              };
              Navigator.pop(ctx);
              final res = await _apiService.createHrDocument(data);
              if (mounted) {
                if (res['isSuccess'] == true) {
                  _showSuccess(
                      isDiscipline ? 'Đã thêm kỷ luật' : 'Đã thêm khen thưởng');
                  if (isDiscipline) {
                    _loadDisciplines();
                  } else {
                    _loadAwards();
                  }
                } else {
                  _showError(res['message'] ?? 'Không thể lưu');
                }
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _deleteAssignment(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Xóa ghi nhận?'),
        content: const Text('Bạn có chắc muốn xóa ghi nhận này không?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await _apiService.deleteOrgAssignment(id);
    if (mounted) {
      if (res['isSuccess'] == true) {
        _showSuccess('Đã xóa ghi nhận');
        _loadAssignments();
      } else {
        _showError(res['message'] ?? 'Không thể xóa');
      }
    }
  }

  Future<void> _deleteDocument(String id, bool isDiscipline) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(isDiscipline ? 'Xóa kỷ luật?' : 'Xóa khen thưởng?'),
        content: const Text('Bạn có chắc muốn xóa bản ghi này không?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await _apiService.deleteHrDocument(id);
    if (mounted) {
      if (res['isSuccess'] == true) {
        _showSuccess('Đã xóa');
        if (isDiscipline) {
          _loadDisciplines();
        } else {
          _loadAwards();
        }
      } else {
        _showError(res['message'] ?? 'Không thể xóa');
      }
    }
  }

  // ─── Build helper ──────────────────────────────────────────────────────────
  Widget _buildFormDialog({
    required BuildContext ctx,
    required String title,
    required IconData icon,
    Color? iconColor,
    required Widget content,
    required bool isMobile,
    required Future<void> Function() onSave,
  }) {
    iconColor ??= HrmPageChrome.primaryNavy;
    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: onSave,
          child: const Text('Lưu'),
        ),
      ],
    );
    if (isMobile) {
      return Dialog(
        insetPadding: EdgeInsets.zero,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx)),
            ),
            body: content,
            bottomNavigationBar:
                Padding(padding: const EdgeInsets.all(16), child: actions),
          ),
        ),
      );
    }
    return ScrollableAlertDialog(
      title: Row(children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 16)),
      ]),
      content: SizedBox(width: 480, child: content),
      actions: [actions],
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quá trình công tác',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.employee.fullName,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.badge, size: 18), text: 'Chức vụ'),
            Tab(icon: Icon(Icons.business, size: 18), text: 'Phòng ban'),
            Tab(icon: Icon(Icons.emoji_events, size: 18), text: 'Khen thưởng'),
            Tab(icon: Icon(Icons.gavel, size: 18), text: 'Kỷ luật'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPositionTab(),
          _buildDepartmentTab(),
          _buildAwardsTab(),
          _buildDisciplineTab(),
        ],
      ),
    );
  }

  // ── Tab 1: Chức vụ ────────────────────────────────────────────────────────
  Widget _buildPositionTab() {
    final canEdit = Provider.of<PermissionProvider>(context, listen: false)
        .canEdit('Employee');
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: _showAddPositionDialog,
              icon: const Icon(Icons.add),
              label: const Text('Thêm chức vụ'),
              backgroundColor: HrmPageChrome.primaryNavy,
              foregroundColor: Colors.white,
            )
          : null,
      body: _loadingAssignments
          ? const LoadingWidget()
          : _positionHistory.isEmpty
              ? _buildEmpty('Chưa có lịch sử chức vụ')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: _positionHistory.length,
                  itemBuilder: (_, i) =>
                      _buildPositionCard(_positionHistory[i]),
                ),
    );
  }

  Widget _buildPositionCard(Map<String, dynamic> a) {
    final level = a['positionLevel'] as int? ?? 6;
    final color = _positionColor(level);
    final isPrimary = a['isPrimary'] as bool? ?? false;
    final isActive = a['isActive'] as bool? ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: isActive
                ? color.withValues(alpha: 0.5)
                : const Color(0xFFE4E4E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline dot
            Column(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.badge, color: color, size: 18),
              ),
              if (_positionHistory.indexOf(a) < _positionHistory.length - 1)
                Container(width: 2, height: 20, color: const Color(0xFFE4E4E7)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        a['positionName']?.toString() ?? '—',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: color),
                      ),
                    ),
                    if (isPrimary)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Chính',
                            style: TextStyle(
                                fontSize: 10,
                                color: HrmPageChrome.primaryNavy,
                                fontWeight: FontWeight.w600)),
                      ),
                    if (isActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Hiện tại',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    a['departmentName']?.toString() ?? '—',
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF52525B)),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.calendar_today,
                        size: 12, color: Color(0xFFA1A1AA)),
                    const SizedBox(width: 4),
                    Text(
                      '${_fmt(a['startDate']?.toString())} → ${_fmt(a['endDate']?.toString())}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFA1A1AA)),
                    ),
                  ]),
                ],
              ),
            ),
            if (Provider.of<PermissionProvider>(context, listen: false)
                .canEdit('Employee'))
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFFA1A1AA)),
                onPressed: () => _deleteAssignment(a['id']?.toString() ?? ''),
                tooltip: 'Xóa',
              ),
          ],
        ),
      ),
    );
  }

  // ── Tab 2: Phòng ban ──────────────────────────────────────────────────────
  Widget _buildDepartmentTab() {
    final canEdit = Provider.of<PermissionProvider>(context, listen: false)
        .canEdit('Employee');
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: _showAddPositionDialog,
              icon: const Icon(Icons.add),
              label: const Text('Ghi nhận thay đổi'),
              backgroundColor: const Color(0xFF0369A1),
              foregroundColor: Colors.white,
            )
          : null,
      body: _loadingAssignments
          ? const LoadingWidget()
          : _departmentHistory.isEmpty
              ? _buildEmpty('Chưa có lịch sử phòng ban')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: _departmentHistory.length,
                  itemBuilder: (_, i) =>
                      _buildDepartmentCard(_departmentHistory[i]),
                ),
    );
  }

  Widget _buildDepartmentCard(Map<String, dynamic> a) {
    final isActive = a['isActive'] as bool? ?? false;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: isActive
                ? const Color(0xFF0369A1).withValues(alpha: 0.5)
                : const Color(0xFFE4E4E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0369A1).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.business,
                  color: Color(0xFF0369A1), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        a['departmentName']?.toString() ?? '—',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Color(0xFF0369A1)),
                      ),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Hiện tại',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.w600)),
                      ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'Chức vụ: ${a['positionName']?.toString() ?? '—'}',
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF52525B)),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.calendar_today,
                        size: 12, color: Color(0xFFA1A1AA)),
                    const SizedBox(width: 4),
                    Text(
                      '${_fmt(a['startDate']?.toString())} → ${_fmt(a['endDate']?.toString())}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFA1A1AA)),
                    ),
                  ]),
                ],
              ),
            ),
            if (Provider.of<PermissionProvider>(context, listen: false)
                .canEdit('Employee'))
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFFA1A1AA)),
                onPressed: () => _deleteAssignment(a['id']?.toString() ?? ''),
                tooltip: 'Xóa',
              ),
          ],
        ),
      ),
    );
  }

  // ── Tab 3: Khen thưởng ────────────────────────────────────────────────────
  Widget _buildAwardsTab() {
    final canEdit = Provider.of<PermissionProvider>(context, listen: false)
        .canEdit('Employee');
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _showAddAwardDialog(isDiscipline: false),
              icon: const Icon(Icons.add),
              label: const Text('Thêm khen thưởng'),
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
            )
          : null,
      body: _loadingAwards
          ? const LoadingWidget()
          : _awards.isEmpty
              ? _buildEmpty('Chưa có ghi nhận khen thưởng')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: _awards.length,
                  itemBuilder: (_, i) =>
                      _buildDocumentCard(_awards[i], isDiscipline: false),
                ),
    );
  }

  // ── Tab 4: Kỷ luật ────────────────────────────────────────────────────────
  Widget _buildDisciplineTab() {
    final canEdit = Provider.of<PermissionProvider>(context, listen: false)
        .canEdit('Employee');
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _showAddAwardDialog(isDiscipline: true),
              icon: const Icon(Icons.add),
              label: const Text('Thêm kỷ luật'),
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            )
          : null,
      body: _loadingDisciplines
          ? const LoadingWidget()
          : _disciplines.isEmpty
              ? _buildEmpty('Chưa có ghi nhận kỷ luật')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: _disciplines.length,
                  itemBuilder: (_, i) =>
                      _buildDocumentCard(_disciplines[i], isDiscipline: true),
                ),
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> doc,
      {required bool isDiscipline}) {
    final color =
        isDiscipline ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final bgColor = color.withValues(alpha: 0.08);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(isDiscipline ? Icons.gavel : Icons.emoji_events,
                  color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc['name']?.toString() ?? '—',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: color),
                  ),
                  if (doc['documentNumber'] != null &&
                      doc['documentNumber'].toString().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Số QĐ: ${doc['documentNumber']}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF52525B)),
                    ),
                  ],
                  if (doc['effectiveDate'] != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.calendar_today,
                          size: 12, color: Color(0xFFA1A1AA)),
                      const SizedBox(width: 4),
                      Text(
                        'Ngày: ${_fmt(doc['effectiveDate']?.toString())}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFA1A1AA)),
                      ),
                    ]),
                  ],
                  if (doc['notes'] != null &&
                      doc['notes'].toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        doc['notes'].toString(),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF52525B)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Color(0xFFA1A1AA)),
              onPressed: () =>
                  _deleteDocument(doc['id']?.toString() ?? '', isDiscipline),
              tooltip: 'Xóa',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(fontSize: 14, color: Colors.grey[400])),
        ],
      ),
    );
  }
}
