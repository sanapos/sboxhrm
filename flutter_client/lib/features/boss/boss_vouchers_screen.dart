import 'package:flutter/material.dart';

import 'boss_load_error.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../models/cash_transaction.dart';
import '../../screens/staff/staff_nav.dart';
import '../../screens/warehouse/editors/wh_mobile_purchase_receipt_editor.dart';
import '../../screens/warehouse/editors/wh_mobile_stock_issue_editor.dart';
import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/pos/pos_cash_voucher_dialog.dart';
import '../../widgets/sbox/sbox_basics.dart';
import '../../widgets/sbox/sbox_charts.dart';
import '../../widgets/warehouse/wh_doc_type.dart';

/// Mở bảng «Tạo phiếu» (nút ＋ của SBOX BOSS). Trả về true khi đã tạo phiếu (để danh sách tải lại).
Future<bool> showBossCreateSheet(BuildContext context) async {
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      // Loại phiếu gói dịch vụ / quyền không có thì ẩn — tránh mở biểu mẫu rồi mới báo lỗi.
      Widget? tile(String module, String key, IconData icon, Color color, String title, String sub) =>
          !staffCanOpen(ctx, module, listen: false)
              ? null
              : ListTile(
                  leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
                  title: Text(tr(title)),
                  subtitle: Text(tr(sub)),
                  onTap: () => Navigator.pop(ctx, key),
                );
      final tiles = [
        tile('CashTransaction', 'income', Icons.south_west_rounded, SboxColors.success, 'Phiếu thu', 'Thu tiền khách, thu khác'),
        tile('CashTransaction', 'expense', Icons.north_east_rounded, SboxColors.danger, 'Phiếu chi', 'Tiền điện, mua đồ, chi phí'),
        tile('CashTransaction', 'transfer', Icons.swap_horiz_rounded, SboxColors.brand600, 'Chuyển quỹ', 'Tiền mặt ⇄ tài khoản ngân hàng'),
        tile('PosPurchaseReceipts', 'purchase', Icons.inventory_2_rounded, SboxColors.violet, 'Phiếu nhập hàng', 'Nhập hàng từ nhà cung cấp'),
        tile('PosDamageIssues', 'damage', Icons.delete_forever_rounded, SboxColors.warning, 'Phiếu xuất hủy', 'Hàng hỏng, hết hạn'),
        tile('PenaltyTickets', 'penalty', Icons.gavel_rounded, SboxColors.danger, 'Phạt nhân viên', 'Vi phạm nội quy, đi trễ…'),
        tile('AdvanceRequests', 'advance', Icons.payments_rounded, SboxColors.success, 'Ứng lương cho nhân viên', 'Ghi khoản ứng trước lương'),
      ].whereType<Widget>().toList();
      return SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SboxSpace.lg, 0, SboxSpace.lg, SboxSpace.sm),
            child: Text(tr('Tạo phiếu'), style: SboxType.titleSmStyle()),
          ),
          if (tiles.isEmpty)
            const SboxEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Chưa có trong gói dịch vụ',
              message: 'Gói dịch vụ của cửa hàng chưa có chức năng này. Liên hệ đại lý để nâng cấp gói.',
            )
          else
            ...tiles,
          const SizedBox(height: SboxSpace.sm),
        ]),
      );
    },
  );
  if (picked == null || !context.mounted) return false;
  final nav = Navigator.of(context);
  switch (picked) {
    case 'income':
      return showPosCashVoucherDialog(context, type: CashTransactionType.income);
    case 'expense':
      return showPosCashVoucherDialog(context, type: CashTransactionType.expense);
    case 'transfer':
      return await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => const _FundTransferSheet(),
          ) ==
          true;
    case 'purchase':
      await nav.push(MaterialPageRoute(builder: (_) => const WhMobilePurchaseReceiptEditor()));
      return true;
    case 'damage':
      await nav.push(MaterialPageRoute(
          builder: (_) => const WhMobileStockIssueEditor(docType: WhDocType.damageIssue)));
      return true;
    case 'penalty':
    case 'advance':
      return await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _EmployeeMoneySheet(penalty: picked == 'penalty'),
          ) ==
          true;
  }
  return false;
}

double _parseMoney(String s) => double.tryParse(s.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

void _snack(BuildContext context, String msg) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr(msg))));

/// SBOX BOSS — phiếu thu chi gần đây (lọc Thu / Chi / Chờ duyệt), mở từ tab «Quản lý». Tạo phiếu bằng nút ＋.
class BossVouchersScreen extends StatefulWidget {
  const BossVouchersScreen({super.key, required this.refreshTick});

  /// Đổi giá trị = tải lại (sau khi tạo phiếu bằng nút ＋).
  final int refreshTick;

  @override
  State<BossVouchersScreen> createState() => _BossVouchersScreenState();
}

class _BossVouchersScreenState extends State<BossVouchersScreen> {
  List<CashTransaction> _items = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  String? _branch;

  @override
  void initState() {
    super.initState();
    _branch = BranchSession.instance.currentId;
    BranchSession.instance.addListener(_onBranchChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant BossVouchersScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _load();
  }

  @override
  void dispose() {
    BranchSession.instance.removeListener(_onBranchChanged);
    super.dispose();
  }

  void _onBranchChanged() {
    if (BranchSession.instance.currentId == _branch) return;
    _branch = BranchSession.instance.currentId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final r = await ApiService().getCashTransactions(
      pageNumber: 1,
      pageSize: 100,
      fromDate: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 14)),
      toDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      final d = r['data'];
      final list = d is List ? d : (d is Map ? (d['items'] ?? d['data'] ?? const []) as List : const []);
      if (r['isSuccess'] == true) {
        _items = [for (final e in list) if (e is Map) CashTransaction.fromJson(Map<String, dynamic>.from(e))];
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Không tải được phiếu';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _items.where((t) {
      return switch (_filter) {
        'income' => t.type == CashTransactionType.income,
        'expense' => t.type == CashTransactionType.expense,
        'pending' => t.status == CashTransactionStatus.pending,
        _ => true,
      };
    }).toList();
    final income = shown.where((t) => t.type == CashTransactionType.income && t.status == CashTransactionStatus.completed);
    final expense = shown.where((t) => t.type == CashTransactionType.expense && t.status == CashTransactionStatus.completed);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.md, SboxSpace.lg, 96),
        children: [
          Wrap(spacing: SboxSpace.sm, children: [
            for (final f in const [('all', 'Tất cả'), ('income', 'Thu'), ('expense', 'Chi'), ('pending', 'Chờ duyệt')])
              ChoiceChip(
                label: Text(tr(f.$2)),
                selected: _filter == f.$1,
                onSelected: (_) => setState(() => _filter = f.$1),
              ),
          ]),
          const SizedBox(height: SboxSpace.sm),
          Text(
            tr('14 ngày gần nhất · thu ${SboxFmt.money(income.fold<double>(0, (s, t) => s + t.amount))}'
                ' · chi ${SboxFmt.money(expense.fold<double>(0, (s, t) => s + t.amount))}'),
            style: SboxType.captionStyle(),
          ),
          const SizedBox(height: SboxSpace.sm),
          if (_loading && _items.isEmpty)
            const SboxLoading()
          else if (_error != null)
            BossLoadError(title: 'Không tải được phiếu', message: _error)
          else if (shown.isEmpty)
            const SboxEmptyState(icon: Icons.receipt_long_rounded, title: 'Chưa có phiếu thu chi')
          else
            SboxCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _VoucherTile(t: shown[i]),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

class _VoucherTile extends StatelessWidget {
  const _VoucherTile({required this.t});

  final CashTransaction t;

  @override
  Widget build(BuildContext context) {
    final income = t.type == CashTransactionType.income;
    final cancelled = t.status == CashTransactionStatus.cancelled;
    final pending = t.status == CashTransactionStatus.pending;
    final d = t.transactionDate.toLocal();
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (income ? SboxColors.success : SboxColors.danger).withValues(alpha: 0.12),
        child: Icon(income ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: income ? SboxColors.success : SboxColors.danger, size: 20),
      ),
      title: Text(t.description.isEmpty ? t.categoryName : t.description,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(decoration: cancelled ? TextDecoration.lineThrough : null)),
      subtitle: Text(
        '${t.transactionCode} · ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
        '${t.categoryName.isEmpty ? '' : ' · ${t.categoryName}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${income ? '+' : '−'}${SboxFmt.money(t.amount)}',
            style: SboxType.moneyStyle(c: cancelled ? SboxColors.textMuted : (income ? SboxColors.successText : SboxColors.dangerText))),
        if (pending || cancelled)
          SboxStatusChip(label: pending ? 'Chờ duyệt' : 'Đã hủy', tone: pending ? SboxTone.warning : SboxTone.neutral),
      ]),
    );
  }
}

/// Ô nhập số tiền (tự thêm dấu chấm hàng nghìn).
class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller});

  final TextEditingController controller;
  static const label = 'Số tiền';

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          TextInputFormatter.withFunction((oldV, newV) {
            final digits = newV.text.replaceAll(RegExp(r'[^\d]'), '');
            if (digits.isEmpty) return newV.copyWith(text: '');
            final t = SboxFmt.number(int.parse(digits));
            return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
          }),
        ],
        decoration: InputDecoration(labelText: tr(label), suffixText: '₫', border: const OutlineInputBorder()),
      );
}

/// Chuyển quỹ tiền mặt ⇄ tài khoản ngân hàng (POST CashTransactions/fund-transfers).
class _FundTransferSheet extends StatefulWidget {
  const _FundTransferSheet();

  @override
  State<_FundTransferSheet> createState() => _FundTransferSheetState();
}

class _FundTransferSheetState extends State<_FundTransferSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  List<BankAccount> _banks = const [];
  String _from = 'cash';
  String? _to;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ApiService().getBankAccounts().then((r) {
      if (!mounted || r['data'] is! List) return;
      setState(() {
        _banks = [for (final b in r['data'] as List) if (b is Map) BankAccount.fromJson(Map<String, dynamic>.from(b))];
        _to = _banks.isNotEmpty ? _banks.first.id : null;
      });
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String>> get _options => [
        DropdownMenuItem(value: 'cash', child: Text(tr('Tiền mặt'))),
        for (final b in _banks)
          DropdownMenuItem(value: b.id, child: Text('${b.bankShortName ?? b.bankName} · ${b.accountNumber}')),
      ];

  Future<void> _save() async {
    final amount = _parseMoney(_amount.text);
    if (amount <= 0) return _snack(context, 'Nhập số tiền hợp lệ');
    if (_to == null || _to == _from) return _snack(context, 'Chọn hai quỹ khác nhau');
    setState(() => _saving = true);
    final r = await ApiService().createFundTransfer({
      'fromBankAccountId': _from == 'cash' ? null : _from,
      'toBankAccountId': _to == 'cash' ? null : _to,
      'amount': amount,
      'transferDate': DateTime.now().toUtc().toIso8601String(),
      'description': _note.text.trim().isEmpty ? 'Chuyển quỹ' : _note.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      _snack(context, 'Đã tạo phiếu chuyển quỹ');
      Navigator.pop(context, true);
    } else {
      _snack(context, r['message']?.toString() ?? 'Không tạo được phiếu chuyển quỹ');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(SboxSpace.lg, 0, SboxSpace.lg, MediaQuery.viewInsetsOf(context).bottom + SboxSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Chuyển quỹ'), style: SboxType.titleSmStyle()),
          const SizedBox(height: SboxSpace.md),
          DropdownButtonFormField<String>(
            initialValue: _from,
            items: _options,
            onChanged: (v) => setState(() => _from = v ?? 'cash'),
            decoration: InputDecoration(labelText: tr('Từ quỹ'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: SboxSpace.md),
          DropdownButtonFormField<String>(
            initialValue: _to,
            items: _options,
            onChanged: (v) => setState(() => _to = v),
            decoration: InputDecoration(labelText: tr('Sang quỹ'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: SboxSpace.md),
          _MoneyField(controller: _amount),
          const SizedBox(height: SboxSpace.md),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: tr('Nội dung'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: SboxSpace.lg),
          SboxButton(label: 'Tạo phiếu chuyển quỹ', expand: true, loading: _saving, onPressed: _saving ? null : _save),
        ]),
      );
}

/// Phạt nhân viên (POST PenaltyTickets, chờ duyệt như phiếu phạt tự động) hoặc ghi ứng lương hộ nhân viên.
class _EmployeeMoneySheet extends StatefulWidget {
  const _EmployeeMoneySheet({required this.penalty});

  final bool penalty;

  @override
  State<_EmployeeMoneySheet> createState() => _EmployeeMoneySheetState();
}

class _EmployeeMoneySheetState extends State<_EmployeeMoneySheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>> _employees = const [];
  String? _employeeId;
  String _type = 'Violation';
  bool _saving = false;

  static const _types = [
    ('Violation', 'Vi phạm nội quy'),
    ('Late', 'Đi trễ'),
    ('EarlyLeave', 'Về sớm'),
    ('ForgotCheck', 'Quên chấm công'),
    ('UnauthorizedLeave', 'Nghỉ không phép'),
  ];

  @override
  void initState() {
    super.initState();
    ApiService().getEmployeesForSelect(branchId: BranchSession.instance.viewBranchId).then((list) {
      if (!mounted) return;
      setState(() => _employees = [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)]);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _name(Map<String, dynamic> e) {
    final full = '${e['fullName'] ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    return '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim();
  }

  Future<void> _save() async {
    final amount = _parseMoney(_amount.text);
    if (_employeeId == null) return _snack(context, 'Chọn nhân viên');
    if (amount <= 0) return _snack(context, 'Nhập số tiền hợp lệ');
    if (widget.penalty && _note.text.trim().isEmpty) return _snack(context, 'Ghi nội dung vi phạm');
    setState(() => _saving = true);
    final api = ApiService();
    final r = widget.penalty
        ? await api.createPenaltyTicket({
            'employeeId': _employeeId,
            'type': _type,
            'amount': amount,
            'violationDate': DateTime.now().toIso8601String(),
            'description': _note.text.trim(),
          })
        : await api.createAdvanceRequest(
            amount: amount,
            employeeId: _employeeId,
            reason: _note.text.trim().isEmpty ? 'Ứng lương' : _note.text.trim(),
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      _snack(context, widget.penalty ? 'Đã tạo phiếu phạt (chờ duyệt)' : 'Đã ghi đơn ứng lương (chờ duyệt)');
      Navigator.pop(context, true);
    } else {
      _snack(context, r['message']?.toString() ?? 'Không lưu được');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(SboxSpace.lg, 0, SboxSpace.lg, MediaQuery.viewInsetsOf(context).bottom + SboxSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr(widget.penalty ? 'Phạt nhân viên' : 'Ứng lương cho nhân viên'), style: SboxType.titleSmStyle()),
          const SizedBox(height: SboxSpace.md),
          DropdownButtonFormField<String>(
            initialValue: _employeeId,
            isExpanded: true,
            items: [
              for (final e in _employees)
                DropdownMenuItem(value: '${e['id']}', child: Text(_name(e), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _employeeId = v),
            decoration: InputDecoration(
              labelText: tr('Nhân viên'),
              border: const OutlineInputBorder(),
              helperText: _employees.isEmpty ? tr('Đang tải danh sách nhân viên…') : null,
            ),
          ),
          if (widget.penalty) ...[
            const SizedBox(height: SboxSpace.md),
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: [for (final t in _types) DropdownMenuItem(value: t.$1, child: Text(tr(t.$2)))],
              onChanged: (v) => setState(() => _type = v ?? 'Violation'),
              decoration: InputDecoration(labelText: tr('Loại vi phạm'), border: const OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: SboxSpace.md),
          _MoneyField(controller: _amount),
          const SizedBox(height: SboxSpace.md),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: tr(widget.penalty ? 'Nội dung vi phạm' : 'Lý do'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: SboxSpace.lg),
          SboxButton(
            label: widget.penalty ? 'Tạo phiếu phạt' : 'Ghi đơn ứng lương',
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ]),
      );
}
