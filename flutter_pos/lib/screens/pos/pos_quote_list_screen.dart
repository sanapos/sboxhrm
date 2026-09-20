import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_quote_care_sheet.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_commercial_company_screen.dart';
import 'pos_quote_composer_screen.dart';
import 'pos_quote_editor_screen.dart';

class PosQuoteListScreen extends StatefulWidget {
  const PosQuoteListScreen({super.key});

  @override
  State<PosQuoteListScreen> createState() => _PosQuoteListScreenState();
}

class _EmpOpt {
  const _EmpOpt(this.id, this.label);
  final String id;
  final String label;
}

class _PosQuoteListScreenState extends State<PosQuoteListScreen> {
  final _search = TextEditingController();
  final _money = NumberFormat('#,##0', 'vi_VN');
  String? _status;
  String? _employeeId;
  bool _loading = true;
  String? _error;
  bool _canViewAll = false;
  List<PosQuote> _items = [];
  List<_EmpOpt> _employees = [];

  bool _isManagerRole(String role) {
    const managers = {
      'Admin',
      'Director',
      'SuperAdmin',
      'Manager',
      'DepartmentHead',
      'Agent',
    };
    return managers.contains(role);
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadEmployees(), _load()]);
  }

  Future<void> _loadEmployees() async {
    final perm = context.read<PermissionProvider>();
    final role = context.read<AuthProvider>().userRole;
    final canAll = perm.canApprove('PosQuotes') || _isManagerRole(role);
    if (!canAll) return;
    try {
      final raw = await ApiService().getEmployeesForSelect(pageSize: 200);
      final list = <_EmpOpt>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] ?? m['Id'] ?? '').toString();
        if (id.isEmpty) continue;
        final last = (m['lastName'] ?? m['LastName'] ?? '').toString();
        final first = (m['firstName'] ?? m['FirstName'] ?? '').toString();
        final code = (m['employeeCode'] ?? m['EmployeeCode'] ?? '').toString();
        final name = '$last $first'.trim();
        list.add(_EmpOpt(
          id,
          name.isEmpty ? code : (code.isEmpty ? name : '$name ($code)'),
        ));
      }
      list.sort((a, b) => a.label.compareTo(b.label));
      if (!mounted) return;
      setState(() {
        _canViewAll = true;
        _employees = list;
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ApiService();
    final res = await api.getPosQuotes(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      status: _status,
      employeeId: _employeeId,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được báo giá';
      });
      return;
    }
    final data = res['data'];
    final raw = data is Map ? (data['items'] as List? ?? []) : <dynamic>[];
    final canAll = data is Map && data['canViewAll'] == true;
    setState(() {
      _loading = false;
      if (canAll) _canViewAll = true;
      _items = raw
          .whereType<Map>()
          .map((e) => PosQuote.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  Future<void> _openComposer() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PosQuoteComposerScreen()),
    );
    if (mounted && ok == true) _load();
    else if (mounted) _load();
  }

  Future<void> _openEditor(PosQuote q) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PosQuoteComposerScreen(quoteId: q.id),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openDocs(PosQuote q) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PosQuoteEditorScreen(quoteId: q.id)),
    );
    if (mounted) _load();
  }

  Future<void> _delete(PosQuote q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa báo giá nháp?')),
        content: Text(q.quoteNo),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Xóa'))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await ApiService().deletePosQuote(q.id);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không xóa được',
        message: res['message']?.toString() ?? q.quoteNo,
      );
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: 'Đã xóa',
      message: q.quoteNo,
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    if (!perm.canView('PosQuotes')) {
      return Scaffold(
        backgroundColor: PosTheme.background,
        body: Center(child: Text(tr('Không có quyền xem báo giá'))),
      );
    }
    final canCreate = perm.canCreate('PosQuotes') || perm.canEdit('PosQuotes');
    final canEdit = perm.canEdit('PosQuotes');
    final canDelete = perm.canDelete('PosQuotes');
    return Scaffold(
      backgroundColor: PosTheme.background,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _openComposer,
              icon: const Icon(Icons.add),
              label: Text(tr('Thêm báo giá mới')),
            )
          : null,
      body: Column(
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Báo giá'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Tải lại'),
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: tr('Thông tin công ty shop'),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const PosCommercialCompanyScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.apartment_outlined),
                  ),
                  if (canCreate)
                    FilledButton.icon(
                      onPressed: _openComposer,
                      icon: const Icon(Icons.add, size: 20),
                      label: Text(tr('Thêm báo giá mới')),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _search,
                    decoration: PosTheme.inputDecoration(
                      label: 'Số BG / khách / SĐT',
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                DropdownButton<String?>(
                  value: _status,
                  hint: Text(tr('Trạng thái')),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tất cả')),
                    for (final s in const [
                      'Draft',
                      'Sent',
                      'Revised',
                      'Accepted',
                      'Rejected',
                      'Expired',
                      'Cancelled',
                    ])
                      DropdownMenuItem(
                        value: s,
                        child: Text(PosQuote.statusLabel(s)),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _status = v);
                    _load();
                  },
                ),
                if (_canViewAll)
                  DropdownButton<String?>(
                    value: _employeeId,
                    hint: Text(tr('Nhân viên')),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Tất cả NV')),
                      for (final e in _employees)
                        DropdownMenuItem(value: e.id, child: Text(e.label)),
                    ],
                    onChanged: (v) {
                      setState(() => _employeeId = v);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(tr(
                                    'Chưa có báo giá — chọn hàng hóa / dịch vụ rồi nhập khách.')),
                                if (canCreate) ...[
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: _openComposer,
                                    icon: const Icon(Icons.add),
                                    label: Text(tr('Thêm báo giá mới')),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final q = _items[i];
                                final until = q.validUntil;
                                final staff = q.staffLabel;
                                return Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  child: ListTile(
                                    title: Text(
                                      '${q.quoteNo} · ${q.customerName?.isNotEmpty == true ? q.customerName : 'Chưa chọn khách'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: Text([
                                      PosQuote.statusLabel(q.status),
                                      if (q.status == 'Accepted')
                                        PosQuote.stageLabel(q.commercialStage),
                                      if (until != null)
                                        'Hạn ${DateFormat('dd/MM/yyyy').format(until.toLocal())}',
                                      '${_money.format(q.total)} đ',
                                      if (staff.isNotEmpty) staff,
                                    ].join('  ·  ')),
                                    onTap: () => _openEditor(q),
                                    trailing: PopupMenuButton<String>(
                                      tooltip: tr('Thao tác'),
                                      onSelected: (v) async {
                                        switch (v) {
                                          case 'edit':
                                            await _openEditor(q);
                                          case 'docs':
                                            await _openDocs(q);
                                          case 'print':
                                            await printPosQuoteSlip(
                                              context,
                                              quoteId: q.id,
                                              quote: q,
                                            );
                                          case 'call':
                                            await callPosQuoteCustomer(
                                                q.customerPhone);
                                          case 'care':
                                            await showPosQuoteCareSheet(
                                              context,
                                              quoteId: q.id,
                                              quoteNo: q.quoteNo,
                                              customerName: q.customerName,
                                              customerPhone: q.customerPhone,
                                            );
                                          case 'delete':
                                            await _delete(q);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        if (canEdit && !q.isLocked)
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text(tr('Sửa báo giá')),
                                          ),
                                        PopupMenuItem(
                                          value: 'docs',
                                          child: Text(tr('Hồ sơ HĐ / nghiệm thu')),
                                        ),
                                        PopupMenuItem(
                                          value: 'print',
                                          child: Text(tr('In phiếu báo giá')),
                                        ),
                                        PopupMenuItem(
                                          value: 'call',
                                          child: Text(tr('Gọi khách')),
                                        ),
                                        PopupMenuItem(
                                          value: 'care',
                                          child: Text(tr('Lịch CSKH')),
                                        ),
                                        if (canDelete && q.canDelete)
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text(tr('Xóa nháp')),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
