import '../../widgets/sbox/sbox_ui.dart';
import '../../widgets/pos/pos_contract_payment_panel.dart' show canUsePosContracts;
import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/pos/pos_list_filters.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_quote_commercial.dart';
import '../../utils/pos_quote_export.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/page_top_actions.dart';
import '../../widgets/pos/pos_form_keyboard.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_contract_detail_screen.dart';
import 'pos_contract_receivables_screen.dart';
import 'pos_quote_care_board_screen.dart';
import 'pos_quote_composer_screen.dart';
import 'pos_quote_detail_screen.dart';

import '../../theme/sbox_tokens.dart';
import '../../utils/pos_busy.dart';
import 'pos_quote_document_template_screen.dart';
class PosQuoteListScreen extends StatefulWidget {
  const PosQuoteListScreen({super.key, this.initialTab = 0});

  final int initialTab;

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
  String _period = 'all';
  DateTime? _from;
  DateTime? _to;
  bool _loading = true;
  String? _error;
  bool _canViewAll = false;
  late int _tab = widget.initialTab.clamp(0, 3);
  List<PosQuote> _items = [];
  /// Số báo giá theo trạng thái (lần tải không lọc trạng thái).
  Map<String, int> _statusCounts = {};
  int _allCount = 0;
  final Map<String, int> _careScores = {};
  List<PosQuote> _contracts = [];
  List<PosQuote> _payments = [];
  List<PosQuote> _accepts = [];
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
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadEmployees(), _reloadAll()]);
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
      from: _from?.toUtc(),
      to: _to?.toUtc(),
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
      final counts = data is Map ? data['statusCounts'] : null;
      if (counts is Map) {
        _statusCounts = {for (final e in counts.entries) e.key.toString(): (e.value as num).toInt()};
        _allCount = _statusCounts.values.fold(0, (a, b) => a + b);
      }
    });
    final missingApiScore = raw.whereType<Map>().every((e) =>
        !e.containsKey('potentialScore') && !e.containsKey('PotentialScore'));
    if (missingApiScore && _items.isNotEmpty) {
      unawaited(_hydratePotentialFromCare());
    }
  }

  Future<void> _loadContracts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ApiService().getPosQuotes(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      commercialStage: 'minContracted',
      employeeId: _employeeId,
      from: _from?.toUtc(),
      to: _to?.toUtc(),
      pageSize: 80,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được hợp đồng';
      });
      return;
    }
    final data = res['data'];
    final raw = data is Map ? (data['items'] as List? ?? []) : <dynamic>[];
    setState(() {
      _loading = false;
      _contracts = raw
          .whereType<Map>()
          .map((e) => PosQuote.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  Future<void> _loadByDocKind(String kind) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ApiService().getPosQuotes(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      documentKind: kind,
      employeeId: _employeeId,
      from: _from?.toUtc(),
      to: _to?.toUtc(),
      pageSize: 80,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được chứng từ';
      });
      return;
    }
    final data = res['data'];
    final raw = data is Map ? (data['items'] as List? ?? []) : <dynamic>[];
    final list = raw
        .whereType<Map>()
        .map((e) => PosQuote.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    setState(() {
      _loading = false;
      if (kind == 'PaymentRequest') {
        _payments = list;
      } else {
        _accepts = list;
      }
    });
  }

  Future<void> _reloadAll() async {
    hidePosSoftKeyboard(alsoAfterMs: 0);
    switch (_tab) {
      case 1:
        await _loadContracts();
      case 2:
        await _loadByDocKind('PaymentRequest');
      case 3:
        await _loadByDocKind('Acceptance');
      default:
        await _load();
    }
  }

  void _applyPeriod(String key) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endToday = today
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    DateTime? from;
    DateTime? to;
    switch (key) {
      case 'today':
        from = today;
        to = endToday;
      case '7d':
        from = today.subtract(const Duration(days: 6));
        to = endToday;
      case 'month':
        from = DateTime(now.year, now.month, 1);
        to = endToday;
      default:
        from = null;
        to = null;
    }
    setState(() {
      _period = key;
      _from = from;
      _to = to;
    });
    _reloadAll();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(
              start: DateTime(_from!.year, _from!.month, _from!.day),
              end: DateTime(_to!.year, _to!.month, _to!.day),
            )
          : null,
    );
    if (picked == null) return;
    setState(() {
      _period = 'custom';
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
        999,
      );
    });
    await _reloadAll();
  }

  Future<void> _openComposer() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PosQuoteComposerScreen()),
    );
    if (mounted) await _reloadAll();
  }

  Future<void> _openEditor(PosQuote q) async {
    hidePosSoftKeyboard(alsoAfterMs: 0);
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PosQuoteComposerScreen(quoteId: q.id),
      ),
    );
    if (mounted) await _reloadAll();
  }

  /// Bấm thẻ báo giá → màn tổng quan (tiến độ + bước tiếp theo).
  Future<void> _openDetail(PosQuote q) async {
    hidePosSoftKeyboard(alsoAfterMs: 0);
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PosQuoteDetailScreen(quoteId: q.id)),
    );
    if (mounted) await _reloadAll();
  }

  /// «Sửa riêng nội dung» của chứng từ mới nhất cùng loại (báo giá / hợp đồng / …) trên báo giá này.
  Future<void> _openDocContent(PosQuote q, String kind) async {
    final res = await ApiService().getPosQuote(q.id);
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      NotificationOverlayManager().showError(title: 'Không mở được', message: res['message']?.toString() ?? '');
      return;
    }
    final full = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
    final docs = full.documents.where((d) => d.kind == kind).toList()
      ..sort((a, b) => (b.issuedAt ?? DateTime(2000)).compareTo(a.issuedAt ?? DateTime(2000)));
    var doc = docs.firstOrNull;
    if (doc == null && kind == 'Quote') {
      final c = await ApiService().createPosQuoteDocument(q.id, 'Quote', includeImages: full.includeImages);
      if (!mounted) return;
      if (c['isSuccess'] == true && c['data'] is Map) {
        doc = PosQuoteDocument.fromJson(Map<String, dynamic>.from(c['data'] as Map));
      }
    }
    if (doc == null) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa có ${PosQuoteDocument.kindLabel(kind).toLowerCase()}',
        message: tr('Lập chứng từ trước rồi mới sửa riêng nội dung'),
      );
      return;
    }
    hidePosSoftKeyboard(alsoAfterMs: 0);
    PosBusy.hideLayer();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PosQuoteDocumentTemplateScreen(quoteId: q.id, document: doc!)),
    );
    if (mounted) await _reloadAll();
  }

  Future<void> _openContract(PosQuote q) async {
    hidePosSoftKeyboard(alsoAfterMs: 0);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PosContractDetailScreen(quoteId: q.id),
      ),
    );
    if (mounted) await _reloadAll();
  }

  /// Báo giá chưa chốt → ghi nhận khách chốt trước (máy chủ chỉ lập HĐ từ báo giá đã chấp nhận).
  Future<PosQuote?> _acceptedQuote(PosQuote q) async {
    if (!await PosQuoteFlow.ensureAccepted(context, q)) return null;
    if (q.status == 'Accepted') return q;
    final res = await ApiService().getPosQuote(q.id);
    return res['isSuccess'] == true && res['data'] is Map
        ? PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map))
        : q;
  }

  Future<void> _createContract(PosQuote q) async {
    hidePosSoftKeyboard(alsoAfterMs: 0);
    final accepted = await _acceptedQuote(q);
    if (accepted == null || !mounted) {
      if (mounted) await _reloadAll();
      return;
    }
    q = accepted;
    final doc = await createPosQuoteCommercialDoc(
      context,
      quote: q,
      kind: 'Contract',
    );
    if (!mounted) return;
    await _reloadAll();
    if (doc != null && mounted) await _openContract(q);
  }

  Future<void> _createPackage(PosQuote q) async {
    hidePosSoftKeyboard(alsoAfterMs: 0);
    final accepted = await _acceptedQuote(q);
    if (accepted == null || !mounted) {
      if (mounted) await _reloadAll();
      return;
    }
    q = accepted;
    final ok = await createPosQuoteCommercialPackage(context, quote: q);
    if (!mounted) return;
    await _reloadAll();
    if (ok && mounted) await _openContract(q);
  }

  Future<void> _createKind(PosQuote q, String kind) async {
    hidePosSoftKeyboard(alsoAfterMs: 0);
    final doc = await createPosQuoteCommercialDoc(
      context,
      quote: q,
      kind: kind,
    );
    if (!mounted) return;
    await _reloadAll();
    if (doc != null && mounted) await _openContract(q);
  }

  Future<void> _delete(PosQuote q) async {
    final draft = q.status == 'Draft';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa báo giá?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [q.quoteNo, if ((q.customerName ?? '').isNotEmpty) q.customerName!]
                  .join(' — '),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(draft
                ? tr('Báo giá nháp sẽ bị xóa.')
                : tr('Báo giá ${PosQuote.statusLabel(q.status).toLowerCase()} sẽ bị xóa cùng hợp đồng, '
                    'đề nghị thanh toán, biên bản và lịch chăm sóc khách. '
                    'Báo giá đã xuất kho không xóa được.')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Xóa báo giá'))),
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
    await _reloadAll();
  }

  Future<void> _openSide(String which) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => which == 'care' ? const PosQuoteCareBoardScreen() : const PosContractReceivablesScreen()));
    if (mounted) await _reloadAll();
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
      body: Column(
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 8, 10),
                    child: Row(
                      children: [
                        Expanded(child: _tabsBar()),
                        // Điện thoại: 2 nút biểu tượng không nhãn → gom vào «⋯» có chữ, nhường chỗ cho 4 tab.
                        if (MediaQuery.sizeOf(context).width < 600)
                          PopupMenuButton<String>(
                            tooltip: tr('Thêm'),
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) => unawaited(_openSide(v)),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'care',
                                child: ListTile(dense: true, leading: const Icon(Icons.insights_outlined),
                                    title: Text(tr('Theo dõi chăm sóc khách'))),
                              ),
                              if (canUsePosContracts(context))
                                PopupMenuItem(
                                  value: 'debt',
                                  child: ListTile(dense: true, leading: const Icon(Icons.account_balance_wallet_outlined),
                                      title: Text(tr('Công nợ hợp đồng'))),
                                ),
                            ],
                          )
                        else ...[
                          IconButton(
                            tooltip: tr('Theo dõi chăm sóc khách'),
                            onPressed: () => unawaited(_openSide('care')),
                            icon: const Icon(Icons.insights_outlined),
                          ),
                          if (canUsePosContracts(context))
                            IconButton(
                              tooltip: tr('Công nợ hợp đồng'),
                              onPressed: () => unawaited(_openSide('debt')),
                              icon: const Icon(Icons.account_balance_wallet_outlined),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            // Điện thoại: một hàng (ô tìm + nút Lọc) thay vì ô tìm / thời gian / nhân viên xếp chồng nhiều hàng.
            child: MediaQuery.sizeOf(context).width < 600 ? _phoneFilterRow(canCreate) : _filterBar(canCreate),
          ),
          if (_tab == 0) _statusStrip(),
          const SizedBox(height: 8),
          Expanded(
            child: switch (_tab) {
              1 => _stageList(
                  _contracts,
                  canEdit,
                  empty:
                      'Chưa có hợp đồng. Mở báo giá → menu → Tạo hợp đồng hoặc trọn bộ hồ sơ.',
                ),
              2 => _stageList(
                  _payments,
                  canEdit,
                  empty: 'Chưa có đề nghị thanh toán / tạm ứng.',
                ),
              3 => _stageList(
                  _accepts,
                  canEdit,
                  empty: 'Chưa có biên bản nghiệm thu.',
                ),
              _ => _quoteList(canCreate, canEdit, canDelete),
            },
          ),
        ],
      ),
    );
  }

  String get _docType => switch (_tab) {
        1 => 'Contract',
        2 => 'PaymentRequest',
        3 => 'Acceptance',
        _ => 'Quote',
      };

  Timer? _searchDebounce;

  /// Một hàng kiểu HRM: tìm · thời gian · trạng thái · nhân viên · Thêm báo giá.
  Widget _filterBar(bool canCreate) {
    final customLabel = _period == 'custom' && _from != null && _to != null
        ? '${DateFormat('dd/MM').format(_from!)}–${DateFormat('dd/MM').format(_to!)}'
        : 'Chọn ngày…';
    return SboxFilterBar(
      searchHint: switch (_tab) {
        1 => 'Số HĐ / khách',
        2 => 'Số ĐN / khách',
        3 => 'Số NT / khách',
        _ => 'Số BG / khách',
      },
      searchController: _search,
      onSearch: (_) {
        _searchDebounce?.cancel();
        _searchDebounce = Timer(const Duration(milliseconds: 400), _reloadAll);
      },
      filters: [
        SboxFilterChip<String>(
          label: 'Thời gian',
          value: _period,
          options: {'all': 'Tất cả', 'today': 'Hôm nay', '7d': '7 ngày', 'month': 'Tháng này', 'custom': customLabel},
          onChanged: (v) {
            if (v == 'custom') {
              _pickCustomRange();
              return;
            }
            _applyPeriod(v);
          },
        ),
        if (_canViewAll && _employees.isNotEmpty)
          PosPickChip(
            label: 'Nhân viên',
            value: _employeeId,
            options: {for (final e in _employees) e.id: e.label},
            onChanged: (v) {
              setState(() => _employeeId = v);
              _reloadAll();
            },
          ),
      ],
      actions: [
        if (canCreate && _tab == 0) SboxButton(label: 'Thêm báo giá', icon: Icons.add, onPressed: _openComposer),
      ],
    );
  }

  int? _shownScore(PosQuote q) => q.potentialScore ?? _careScores[q.id];

  Future<void> _hydratePotentialFromCare() async {
    final pending = _items.where((q) => q.potentialScore == null).toList();
    final api = ApiService();
    for (var i = 0; i < pending.length; i += 4) {
      if (!mounted) return;
      final slice = pending.skip(i).take(4);
      final found = <String, int>{};
      await Future.wait(slice.map((q) async {
        final res = await api.getPosQuoteActivities(q.id);
        final data = res['data'];
        final raw = data is Map ? (data['items'] as List? ?? []) : <dynamic>[];
        for (final e in raw.whereType<Map>()) {
          final score = PosQuoteActivity.fromJson(
            Map<String, dynamic>.from(e),
          ).score;
          if (score != null) {
            found[q.id] = score;
            break;
          }
        }
      }));
      if (!mounted || found.isEmpty) continue;
      setState(() => _careScores.addAll(found));
    }
  }

  Widget _quoteList(bool canCreate, bool canEdit, bool canDelete) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_items.isEmpty) {
      // Nút «+ Báo giá» đã ở nút nổi — màn trống chỉ hướng dẫn, căn giữa.
      return const SboxEmptyState(
        icon: Icons.request_quote_outlined,
        title: 'Chưa có báo giá',
        message: 'Bấm «Thêm báo giá» để chọn hàng hóa / dịch vụ rồi nhập thông tin khách.',
      );
    }
    return RefreshIndicator(
      onRefresh: _reloadAll,
      child: _cardList(_items.length, (i) => _quoteCard(_items[i], canEdit, canDelete)),
    );
  }

  Widget _stageList(List<PosQuote> rows, bool canEdit, {required String empty}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (rows.isEmpty) {
      return Center(child: Text(tr(empty)));
    }
    return RefreshIndicator(
      onRefresh: _reloadAll,
      child: _cardList(
        rows.length,
        (i) {
          final q = rows[i];
          return _modernCard(q, onTap: () => _openContract(q), menu: _moreButton(q, stage: true));
        },
      ),
    );
  }

  Widget _quoteCard(PosQuote q, bool canEdit, bool canDelete) {
    return _modernCard(q, onTap: () => _openDetail(q), menu: _moreButton(q, stage: false));
  }

  /// Điện thoại: danh sách dọc; màn rộng: lưới thẻ 2–3 cột.
  Widget _cardList(int count, Widget Function(int i) item) {
    return LayoutBuilder(builder: (context, c) {
      const pad = EdgeInsets.fromLTRB(12, 0, 12, 88);
      if (c.maxWidth < 760) {
        return ListView.separated(
          padding: pad,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => item(i),
        );
      }
      return GridView.builder(
        padding: pad,
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 480,
          mainAxisExtent: 156,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: count,
        itemBuilder: (_, i) => item(i),
      );
    });
  }

  static const _tabDefs = [
    (0, 'Báo giá', Icons.request_quote_outlined),
    (1, 'Hợp đồng', Icons.handshake_outlined),
    (2, 'Đề nghị TT', Icons.payments_outlined),
    (3, 'Nghiệm thu', Icons.fact_check_outlined),
  ];

  /// Tab gạch chân, cuộn ngang trên điện thoại (thay SegmentedButton bị bóp chữ).
  Widget _tabsBar() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final t in _tabDefs)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                if (_tab == t.$1) return;
                setState(() => _tab = t.$1);
                _reloadAll();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _tab == t.$1 ? PosTheme.kiotBlue : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(t.$3, size: 17, color: _tab == t.$1 ? PosTheme.kiotBlue : SboxColors.slate500),
                  const SizedBox(width: 6),
                  Text(
                    tr(t.$2),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _tab == t.$1 ? FontWeight.w700 : FontWeight.w500,
                      color: _tab == t.$1 ? PosTheme.kiotBlue : SboxColors.slate600,
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  /// Thanh trạng thái có đếm — bấm để lọc (thay ô «Trạng thái»).
  Widget _statusStrip() {
    const order = ['Draft', 'Sent', 'Revised', 'Accepted', 'Rejected', 'Expired', 'Cancelled'];
    Widget chip(String? value, String label, int n, Color color) {
      final sel = _status == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          visualDensity: VisualDensity.compact,
          showCheckmark: false,
          selected: sel,
          selectedColor: color.withValues(alpha: 0.14),
          side: BorderSide(color: sel ? color : SboxColors.slate200),
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(tr(label),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? color : SboxColors.slate700)),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: sel ? color : SboxColors.slate100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$n',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: sel ? Colors.white : SboxColors.slate600)),
            ),
          ]),
          onSelected: (_) {
            setState(() => _status = sel ? null : value);
            _reloadAll();
          },
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        children: [
          chip(null, 'Tất cả', _allCount, PosTheme.kiotBlue),
          for (final st in order)
            if ((_statusCounts[st] ?? 0) > 0 || _status == st)
              chip(st, PosQuote.statusLabel(st), _statusCounts[st] ?? 0, PosQuote.statusColor(st)),
        ],
      ),
    );
  }

  /// Thẻ báo giá / hợp đồng: số + trạng thái, khách, tổng tiền, hạn, thanh tiến độ, bước tiếp theo.
  Widget _modernCard(PosQuote q, {required VoidCallback onTap, required Widget menu}) {
    final done = PosQuoteFlow.doneCount(q);
    final stopped = PosQuoteFlow.isStopped(q);
    final validity = PosQuoteFlow.validity(q);
    final next = PosQuoteFlow.nextLabel(q);
    final score = _shownScore(q);
    final name = (q.customerName ?? '').trim();
    final statusColor = PosQuote.statusColor(q.status);
    final statusText =
        q.status == 'Accepted' ? PosQuote.stageLabel(q.commercialStage) : PosQuote.statusLabel(q.status);
    final date = q.issuedAt ?? q.createdAt;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SboxColors.slate200),
          ),
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(q.quoteNo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SboxColors.slate500)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(tr(statusText),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
              ),
              SizedBox(width: 40, height: 34, child: menu),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(children: [
                Expanded(
                  child: Text(tr(name.isEmpty ? 'Khách lẻ' : name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
                ),
                if (score != null)
                  Text(tr('TN $score/10'),
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: PosQuoteActivity.scoreColor(score))),
              ]),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(tr('${_money.format(q.total)} đ'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: PosTheme.kiotBlue)),
                const Spacer(),
                if (validity != null)
                  Text(tr(validity.$1),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: validity.$2))
                else if (date != null)
                  Text(DateFormat('dd/MM/yyyy').format(date.toLocal()),
                      style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              ]),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(children: [
                for (var i = 0; i < PosQuoteFlow.steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: i < done
                            ? (stopped ? SboxColors.slate400 : SboxColors.success)
                            : SboxColors.slate200,
                      ),
                    ),
                  ),
                ],
              ]),
            ),
            if (next != null || stopped) ...[
              const SizedBox(height: 6),
              Text(
                tr(stopped ? 'Đã dừng · ${PosQuote.statusLabel(q.status)}' : 'Tiếp theo: $next'),
                style: TextStyle(
                    fontSize: 12,
                    color: stopped ? SboxColors.slate500 : PosTheme.kiotBlue,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  int get _quoteFilterCount => (_period != 'all' ? 1 : 0) + (_employeeId != null ? 1 : 0);

  String get _periodLabel => switch (_period) {
        'today' => 'Hôm nay',
        '7d' => '7 ngày',
        'month' => 'Tháng này',
        'custom' when _from != null && _to != null =>
          '${DateFormat('dd/MM').format(_from!)}–${DateFormat('dd/MM').format(_to!)}',
        _ => 'Tất cả',
      };

  Widget _phoneFilterRow(bool canCreate) {
    final n = _quoteFilterCount;
    final row = Row(children: [
      Expanded(
        child: SizedBox(
          height: 40,
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14),
            onChanged: (_) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 400), _reloadAll);
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: tr(switch (_tab) {
                1 => 'Số HĐ / khách',
                2 => 'Số ĐN / khách',
                3 => 'Số NT / khách',
                _ => 'Số BG / khách',
              }),
              prefixIcon: const Icon(Icons.search, size: 20),
              contentPadding: EdgeInsets.zero,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: SboxColors.slate200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: SboxColors.slate200),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          onPressed: _openQuoteFilterSheet,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            backgroundColor: n > 0 ? SboxColors.brand50 : Colors.white,
            side: BorderSide(color: n > 0 ? PosTheme.kiotBlue : SboxColors.slate200),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.tune, size: 18),
          label: Text(tr(n > 0 ? _periodLabel : 'Lọc'), maxLines: 1),
        ),
      ),
    ]);
    if (!(canCreate && _tab == 0)) return row;
    // Nút «Thêm báo giá» vào nút nổi chung của app (như SboxFilterBar trên điện thoại).
    return RegisterPageTopActions(
      actions: [
        HrmTopBarAction(icon: Icons.add, label: 'Thêm báo giá', onPressed: _openComposer, primary: true, showLabel: true),
      ],
      child: row,
    );
  }

  Future<void> _openQuoteFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Widget title(String t) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(tr(t), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            );
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
                  child: Row(children: [
                    Expanded(
                      child: Text(tr('Lọc'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _employeeId = null);
                        _applyPeriod('all');
                        setSheet(() {});
                      },
                      child: Text(tr('Đặt lại')),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ]),
                ),
                title('Thời gian'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in const {'all': 'Tất cả', 'today': 'Hôm nay', '7d': '7 ngày', 'month': 'Tháng này'}.entries)
                      ChoiceChip(
                        label: Text(tr(e.value)),
                        selected: _period == e.key,
                        onSelected: (_) {
                          _applyPeriod(e.key);
                          setSheet(() {});
                        },
                      ),
                    ChoiceChip(
                      label: Text(tr(_period == 'custom' ? _periodLabel : 'Chọn ngày…')),
                      selected: _period == 'custom',
                      onSelected: (_) async {
                        await _pickCustomRange();
                        setSheet(() {});
                      },
                    ),
                  ]),
                ),
                if (_canViewAll && _employees.isNotEmpty) ...[
                  title('Nhân viên báo giá'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DropdownButtonFormField<String?>(
                      initialValue: _employeeId,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(tr('Tất cả nhân viên'))),
                        for (final e in _employees) DropdownMenuItem<String?>(value: e.id, child: Text(e.label)),
                      ],
                      onChanged: (v) {
                        setState(() => _employeeId = v);
                        setSheet(() {});
                        _reloadAll();
                      },
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    child: Text(tr('Xem kết quả')),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _moreButton(PosQuote q, {required bool stage}) => IconButton(
        tooltip: tr('Thao tác'),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_vert, size: 20),
        onPressed: () => _showQuoteActions(q, stage: stage),
      );

  /// Bảng thao tác chia nhóm (thay menu 16 dòng): hồ sơ · gửi khách · liên hệ · xóa.
  Future<void> _showQuoteActions(PosQuote q, {required bool stage}) async {
    final perm = context.read<PermissionProvider>();
    final canEdit = perm.canEdit('PosQuotes');
    final canDelete = perm.canDelete('PosQuotes');
    final stopped = PosQuoteFlow.isStopped(q);
    final hasContract = q.status == 'Accepted' && q.commercialStage != 'None' && q.commercialStage != 'Accepted';
    final docType = stage ? _docType : 'Quote';

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        Widget tile(String value, IconData icon, String label, {Color? color}) => InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(ctx, value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (color ?? PosTheme.kiotBlue).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 22, color: color ?? PosTheme.kiotBlue),
                  ),
                  const SizedBox(height: 6),
                  Text(tr(label),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 11.5, height: 1.2, color: SboxColors.slate700)),
                ]),
              ),
            );
        Widget section(String title, List<Widget> tiles) => tiles.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(tr(title),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate500)),
                  ),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 0.95,
                    children: tiles,
                  ),
                ]),
              );

        final docs = <Widget>[
          tile('detail', Icons.timeline, 'Tổng quan & tiến độ'),
          if (canEdit && !q.isLocked && !stage) tile('edit', Icons.edit_outlined, 'Sửa hàng hóa'),
          if (canEdit && !stopped)
            hasContract
                ? tile('contract', Icons.handshake_outlined, 'Mở hợp đồng')
                : tile('contract', Icons.handshake_outlined, q.status == 'Accepted' ? 'Lập hợp đồng' : 'Khách chốt & lập HĐ'),
          if (canEdit && !stopped && !hasContract) tile('package', Icons.folder_copy_outlined, 'Trọn bộ hồ sơ'),
          if (stage && canEdit) ...[
            tile('payment', Icons.payments_outlined, 'Đề nghị TT'),
            tile('handover', Icons.local_shipping_outlined, 'Bàn giao'),
            tile('acceptance', Icons.fact_check_outlined, 'Nghiệm thu'),
          ],
          if (canEdit) tile('docs', Icons.edit_note_outlined, stage ? 'Sửa riêng nội dung' : 'Sửa riêng nội dung báo giá'),
        ];
        final send = <Widget>[
          tile('print', Icons.print_outlined, 'In'),
          tile('pdf', Icons.picture_as_pdf_outlined, 'PDF'),
          tile('word', Icons.description_outlined, 'Word'),
          tile('excel', Icons.table_chart_outlined, 'Excel'),
          tile('png', Icons.image_outlined, 'Ảnh PNG'),
          tile('email', Icons.email_outlined, 'Email'),
          tile('zalo', Icons.chat_outlined, 'Gửi Zalo'),
          tile('facebook', Icons.facebook, 'Facebook'),
        ];
        final hasPhone = (q.customerPhone ?? '').replaceAll(RegExp(r'\D'), '').isNotEmpty;
        final contact = <Widget>[
          if (hasPhone) tile('call', Icons.call_outlined, 'Gọi khách'),
          if (hasPhone) tile('zaloCall', Icons.phone_in_talk_outlined, 'Gọi Zalo'),
          if (hasPhone || (q.customerName ?? '').trim().isNotEmpty)
            tile('facebookLink', Icons.link, 'Link Facebook'),
          tile('care', Icons.event_note_outlined, 'Lịch CSKH'),
        ];
        final name = (q.customerName ?? '').trim();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(q.quoteNo, style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                        Text(tr(name.isEmpty ? 'Khách lẻ' : name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(tr('${_money.format(q.total)} đ · ${q.status == 'Accepted' ? PosQuote.stageLabel(q.commercialStage) : PosQuote.statusLabel(q.status)}'),
                            style: const TextStyle(fontSize: 12, color: SboxColors.slate600)),
                      ]),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ]),
                ),
                const Divider(height: 8),
                section('Hồ sơ', docs),
                section('Gửi cho khách', send),
                section('Liên hệ', contact),
                if (canDelete && q.canDelete && !stage)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'delete'),
                      style: TextButton.styleFrom(foregroundColor: SboxColors.danger),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(tr('Xóa báo giá')),
                    ),
                  )
                else
                  const SizedBox(height: 12),
              ]),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case 'detail':
        await _openDetail(q);
      case 'edit':
        await _openEditor(q);
      case 'contract':
        hasContract ? await _openContract(q) : await _createContract(q);
      case 'package':
        await _createPackage(q);
      case 'payment':
        await _createKind(q, 'PaymentRequest');
      case 'handover':
        await _createKind(q, 'Handover');
      case 'acceptance':
        await _createKind(q, 'Acceptance');
      case 'docs':
        await PosBusy.run(context, () => _openDocContent(q, stage ? docType : 'Quote'), label: 'Đang mở nội dung…');
      case 'delete':
        await _delete(q);
      default:
        await PosBusy.run(
          context,
          () => PosQuoteExport.run(context, quote: q, action: picked, documentType: docType),
          label: switch (picked) {
            'print' => 'Đang dựng bản in…',
            'pdf' => 'Đang tạo PDF…',
            'word' => 'Đang tạo file Word…',
            'excel' => 'Đang tạo Excel…',
            'png' => 'Đang tạo ảnh…',
            'email' || 'zalo' || 'facebook' => 'Đang chuẩn bị gửi khách…',
            _ => 'Đang xử lý…',
          },
        );
    }
  }
}
