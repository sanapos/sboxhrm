import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/employee.dart';
import '../models/pos_customer.dart';
import '../services/api_service.dart';
import 'pos/pos_customer_debt_collect_dialog.dart';
import 'pos/pos_customer_form_dialog.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

enum CashPartyKind { customer, employee, other }

/// Chọn đối tượng phiếu thu/chi: khách hàng (công nợ), nhân viên, hoặc liên hệ tự nhập.
class CashPartyPicker extends StatefulWidget {
  const CashPartyPicker({
    super.key,
    required this.nameController,
    required this.phoneController,
    this.initialKind,
    this.dense = false,
    this.showDebt = true,
    this.enableDebtCollect = true,
    this.onDebtCollected,
    this.onAmountSuggested,
    this.onDescriptionSuggested,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final CashPartyKind? initialKind;
  final bool dense;
  final bool showDebt;
  /// Hiện nút «Thu công nợ» khi KH có nợ.
  final bool enableDebtCollect;
  final ValueChanged<PosCustomer>? onDebtCollected;
  /// Gợi ý điền số tiền sau khi thu nợ (nếu form còn mở).
  final ValueChanged<double>? onAmountSuggested;
  final ValueChanged<String>? onDescriptionSuggested;

  @override
  State<CashPartyPicker> createState() => _CashPartyPickerState();
}

class _CashPartyPickerState extends State<CashPartyPicker> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,###', 'vi_VN');
  final _searchCtrl = TextEditingController();

  CashPartyKind _kind = CashPartyKind.customer;
  PosCustomer? _customer;
  Employee? _employee;
  List<PosCustomer> _customerHits = [];
  List<Employee> _employeeHits = [];
  List<Employee> _employeeCache = [];
  bool _searching = false;
  bool _collectingDebt = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind ??
        (widget.nameController.text.trim().isNotEmpty
            ? CashPartyKind.other
            : CashPartyKind.customer);
    _searchCtrl.text = widget.nameController.text;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setKind(CashPartyKind k) {
    setState(() {
      _kind = k;
      _customer = null;
      _employee = null;
      _customerHits = [];
      _employeeHits = [];
      if (k != CashPartyKind.other) {
        _searchCtrl.clear();
        widget.nameController.clear();
        widget.phoneController.clear();
      } else {
        _searchCtrl.text = widget.nameController.text;
      }
    });
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (_kind == CashPartyKind.customer) {
        _searchCustomers(q);
      } else if (_kind == CashPartyKind.employee) {
        _searchEmployees(q);
      }
    });
  }

  Future<void> _searchCustomers(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _customerHits = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final res = await _api.getPosCustomers(search: q.trim(), pageSize: 12);
    if (!mounted) return;
    final items = <PosCustomer>[];
    if (res['isSuccess'] == true) {
      final data = res['data'];
      final list = data is List
          ? data
          : (data is Map ? (data['items'] as List? ?? const []) : const []);
      for (final e in list) {
        if (e is Map) {
          items.add(PosCustomer.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    setState(() {
      _customerHits = items;
      _searching = false;
    });
  }

  Future<List<Employee>> _loadEmployees() async {
    if (_employeeCache.isNotEmpty) return _employeeCache;
    final raw = await _api.getEmployeesForSelect(page: 1, pageSize: 500);
    _employeeCache = raw
        .map((e) => Employee.fromJson(e as Map<String, dynamic>))
        .toList();
    return _employeeCache;
  }

  Future<void> _searchEmployees(String q) async {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) {
      setState(() {
        _employeeHits = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final all = await _loadEmployees();
      if (!mounted) return;
      final hits = all
          .where((e) {
            final name = e.fullName.toLowerCase();
            final code = e.employeeCode.toLowerCase();
            final phone = (e.phone ?? '').toLowerCase();
            return name.contains(needle) ||
                code.contains(needle) ||
                phone.contains(needle);
          })
          .take(12)
          .toList();
      setState(() {
        _employeeHits = hits;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _employeeHits = [];
        _searching = false;
      });
    }
  }

  void _selectCustomer(PosCustomer c) {
    setState(() {
      _customer = c;
      _employee = null;
      _customerHits = [];
      _searchCtrl.text = c.name;
      widget.nameController.text = c.name;
      widget.phoneController.text = c.phone ?? '';
    });
  }

  void _selectEmployee(Employee e) {
    setState(() {
      _employee = e;
      _customer = null;
      _employeeHits = [];
      _searchCtrl.text = e.fullName;
      widget.nameController.text = e.fullName;
      widget.phoneController.text = e.phone ?? '';
    });
  }

  void _clearSelection() {
    setState(() {
      _customer = null;
      _employee = null;
      _customerHits = [];
      _employeeHits = [];
      _searchCtrl.clear();
      widget.nameController.clear();
      widget.phoneController.clear();
    });
  }

  Future<void> _addCustomer() async {
    final created = await showDialog<dynamic>(
      context: context,
      builder: (_) => const PosCustomerFormDialog(),
    );
    if (created == null || !mounted) return;
    if (created is Map) {
      _selectCustomer(
          PosCustomer.fromJson(Map<String, dynamic>.from(created)));
    }
  }

  Future<void> _browseCustomers() async {
    final picked = await showDialog<PosCustomer>(
      context: context,
      builder: (_) => _PartyBrowseDialog<PosCustomer>(
        title: 'Danh sách khách hàng',
        hint: 'Tìm tên / SĐT / mã KH',
        load: (q) async {
          final res = await _api.getPosCustomers(
            search: q.trim().isEmpty ? null : q.trim(),
            pageSize: 80,
          );
          final items = <PosCustomer>[];
          if (res['isSuccess'] == true) {
            final data = res['data'];
            final list = data is List
                ? data
                : (data is Map
                    ? (data['items'] as List? ?? const [])
                    : const []);
            for (final e in list) {
              if (e is Map) {
                items.add(PosCustomer.fromJson(Map<String, dynamic>.from(e)));
              }
            }
          }
          return items;
        },
        titleOf: (c) => c.name,
        subtitleOf: (c) {
          final parts = <String>[
            if (c.customerCode.isNotEmpty) c.customerCode,
            if ((c.phone ?? '').isNotEmpty) c.phone!,
            if (c.currentDebt > 0)
              'Nợ ${_moneyFmt.format(c.currentDebt)}đ',
          ];
          return parts.join(' · ');
        },
        leading: const Icon(Icons.storefront_outlined),
        onAdd: () async {
          final created = await showDialog<dynamic>(
            context: context,
            builder: (_) => const PosCustomerFormDialog(),
          );
          if (created is Map) {
            return PosCustomer.fromJson(Map<String, dynamic>.from(created));
          }
          return null;
        },
        addLabel: 'Thêm khách hàng',
      ),
    );
    if (picked != null && mounted) _selectCustomer(picked);
  }

  Future<void> _browseEmployees() async {
    final picked = await showDialog<Employee>(
      context: context,
      builder: (_) => _PartyBrowseDialog<Employee>(
        title: 'Danh sách nhân viên',
        hint: 'Tìm tên / mã / SĐT',
        load: (q) async {
          final all = await _loadEmployees();
          final needle = q.trim().toLowerCase();
          if (needle.isEmpty) return all;
          return all
              .where((e) {
                return e.fullName.toLowerCase().contains(needle) ||
                    e.employeeCode.toLowerCase().contains(needle) ||
                    (e.phone ?? '').toLowerCase().contains(needle);
              })
              .toList();
        },
        titleOf: (e) => e.fullName,
        subtitleOf: (e) => [
          e.employeeCode,
          if ((e.phone ?? '').isNotEmpty) e.phone!,
          if ((e.department ?? '').isNotEmpty) e.department!,
        ].join(' · '),
        leading: const Icon(Icons.badge_outlined),
      ),
    );
    if (picked != null && mounted) _selectEmployee(picked);
  }

  Future<void> _collectDebt() async {
    final c = _customer;
    if (c == null || c.currentDebt <= 0 || _collectingDebt) return;
    setState(() => _collectingDebt = true);
    final ok = await showPosCustomerDebtCollectDialog(context, customer: c);
    if (!mounted) return;
    setState(() => _collectingDebt = false);
    if (ok != true) return;

    // Reload customer debt after payment.
    PosCustomer updated = c;
    try {
      final res = await _api.getPosCustomers(search: c.phone ?? c.name, pageSize: 20);
      if (res['isSuccess'] == true) {
        final data = res['data'];
        final list = data is List
            ? data
            : (data is Map ? (data['items'] as List? ?? const []) : const []);
        for (final e in list) {
          if (e is Map) {
            final pc = PosCustomer.fromJson(Map<String, dynamic>.from(e));
            if (pc.id == c.id) {
              updated = pc;
              break;
            }
          }
        }
      }
    } catch (_) {}

    _selectCustomer(updated);
    widget.onDescriptionSuggested
        ?.call('Thu công nợ — ${updated.name}');
    widget.onDebtCollected?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.dense ? 10.0 : 12.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Đối tượng'),
          style: TextStyle(
            fontSize: widget.dense ? 12 : 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<CashPartyKind>(
          segments: [
            ButtonSegment(
              value: CashPartyKind.customer,
              label: Text(tr('Khách hàng'), style: const TextStyle(fontSize: 12)),
              icon: const Icon(Icons.storefront_outlined, size: 16),
            ),
            ButtonSegment(
              value: CashPartyKind.employee,
              label: Text(tr('Nhân viên'), style: const TextStyle(fontSize: 12)),
              icon: const Icon(Icons.badge_outlined, size: 16),
            ),
            ButtonSegment(
              value: CashPartyKind.other,
              label: Text(tr('Khác'), style: const TextStyle(fontSize: 12)),
              icon: const Icon(Icons.edit_outlined, size: 16),
            ),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => _setKind(s.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: pad, vertical: 8),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_kind == CashPartyKind.other) ...[
          TextFormField(
            controller: widget.nameController,
            decoration: InputDecoration(
              labelText: tr('Tên liên hệ'),
              prefixIcon: const Icon(Icons.person_outline),
              isDense: widget.dense,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: widget.phoneController,
            decoration: InputDecoration(
              labelText: tr('Số điện thoại'),
              prefixIcon: const Icon(Icons.phone_outlined),
              isDense: widget.dense,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: tr(_kind == CashPartyKind.customer
                        ? 'Tìm khách hàng (tên / SĐT)'
                        : 'Tìm nhân viên (tên / mã / SĐT)'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : (_searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: _clearSelection,
                              )
                            : null),
                    isDense: widget.dense,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    setState(() {});
                    _onSearchChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: tr(_kind == CashPartyKind.customer
                    ? 'Danh sách khách hàng'
                    : 'Danh sách nhân viên'),
                onPressed: _kind == CashPartyKind.customer
                    ? _browseCustomers
                    : _browseEmployees,
                icon: const Icon(Icons.list_alt),
              ),
              if (_kind == CashPartyKind.customer) ...[
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: tr('Thêm khách hàng'),
                  onPressed: _addCustomer,
                  icon: const Icon(Icons.person_add_alt_1),
                ),
              ],
            ],
          ),
          if (_kind == CashPartyKind.customer && _customerHits.isNotEmpty)
            _hitList(
              children: _customerHits
                  .map((c) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline, size: 20),
                        title: Text(tr(c.name),
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          tr([
                            if ((c.phone ?? '').isNotEmpty) c.phone!,
                            if (c.currentDebt > 0)
                              'Nợ ${_moneyFmt.format(c.currentDebt)}đ',
                          ].join(' · ')),
                          style: TextStyle(
                            fontSize: 11,
                            color: c.currentDebt > 0
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF64748B),
                          ),
                        ),
                        onTap: () => _selectCustomer(c),
                      ))
                  .toList(),
            ),
          if (_kind == CashPartyKind.employee && _employeeHits.isNotEmpty)
            _hitList(
              children: _employeeHits
                  .map((e) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.badge_outlined, size: 20),
                        title: Text(tr(e.fullName),
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          tr([
                            e.employeeCode,
                            if ((e.phone ?? '').isNotEmpty) e.phone!,
                          ].join(' · ')),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        onTap: () => _selectEmployee(e),
                      ))
                  .toList(),
            ),
          if (_customer != null) ...[
            const SizedBox(height: 8),
            _selectedCard(
              title: _customer!.name,
              subtitle: [
                if (_customer!.customerCode.isNotEmpty) _customer!.customerCode,
                if ((_customer!.phone ?? '').isNotEmpty) _customer!.phone!,
              ].join(' · '),
              onClear: _clearSelection,
              debt: widget.showDebt ? _customer!.currentDebt : null,
              debtAction: widget.enableDebtCollect &&
                      widget.showDebt &&
                      _customer!.currentDebt > 0
                  ? () => unawaited(_collectDebt())
                  : null,
              debtBusy: _collectingDebt,
            ),
          ],
          if (_employee != null) ...[
            const SizedBox(height: 8),
            _selectedCard(
              title: _employee!.fullName,
              subtitle: [
                _employee!.employeeCode,
                if ((_employee!.phone ?? '').isNotEmpty) _employee!.phone!,
              ].join(' · '),
              onClear: _clearSelection,
            ),
          ],
        ],
      ],
    );
  }

  Widget _hitList({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: ListView(shrinkWrap: true, children: children),
    );
  }

  Widget _selectedCard({
    required String title,
    required String subtitle,
    required VoidCallback onClear,
    double? debt,
    VoidCallback? debtAction,
    bool debtBusy = false,
  }) {
    final hasDebt = debt != null && debt > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasDebt
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasDebt
              ? const Color(0xFFFECACA)
              : const Color(0xFFBAE6FD),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                hasDebt
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                color: hasDebt
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF0284C7),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(title),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    if (subtitle.isNotEmpty)
                      Text(tr(subtitle),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF64748B))),
                    if (debt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          tr(hasDebt
                              ? 'Công nợ: ${_moneyFmt.format(debt)} đ'
                              : 'Công nợ: 0 đ'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: hasDebt
                                ? const Color(0xFFB91C1C)
                                : const Color(0xFF059669),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onClear,
                child: Text(tr('Đổi')),
              ),
            ],
          ),
          if (debtAction != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: debtBusy ? null : debtAction,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              icon: debtBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.payments_outlined, size: 18),
              label: Text(tr('Thu công nợ')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dialog duyệt danh sách KH / NV cho phiếu thu chi.
class _PartyBrowseDialog<T> extends StatefulWidget {
  const _PartyBrowseDialog({
    required this.title,
    required this.hint,
    required this.load,
    required this.titleOf,
    required this.subtitleOf,
    required this.leading,
    this.onAdd,
    this.addLabel,
  });

  final String title;
  final String hint;
  final Future<List<T>> Function(String query) load;
  final String Function(T) titleOf;
  final String Function(T) subtitleOf;
  final Widget leading;
  final Future<T?> Function()? onAdd;
  final String? addLabel;

  @override
  State<_PartyBrowseDialog<T>> createState() => _PartyBrowseDialogState<T>();
}

class _PartyBrowseDialogState<T> extends State<_PartyBrowseDialog<T>> {
  final _searchCtrl = TextEditingController();
  List<T> _items = [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reload('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload(String q) async {
    setState(() => _loading = true);
    try {
      final items = await widget.load(q);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr(widget.title),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  if (widget.onAdd != null)
                    TextButton.icon(
                      onPressed: () async {
                        final created = await widget.onAdd!();
                        if (created != null && mounted) {
                          Navigator.pop(context, created);
                        } else if (mounted) {
                          _reload(_searchCtrl.text);
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr(widget.addLabel ?? 'Thêm')),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: tr(widget.hint),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 280), () {
                    _reload(v);
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(child: Text(tr('Không có dữ liệu')))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            return ListTile(
                              leading: widget.leading,
                              title: Text(tr(widget.titleOf(item))),
                              subtitle: Text(tr(widget.subtitleOf(item)),
                                  style: const TextStyle(fontSize: 12)),
                              onTap: () => Navigator.pop(context, item),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
