import '../../utils/permission_navigation.dart';
import '../../providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_quote_contract.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/number_formatter.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';

/// Hợp đồng: mốc tiến độ, đợt thanh toán, thu tiền (mỗi lần thu → phiếu thu quỹ), còn phải thu.

/// Gói + vai trò có «Hợp đồng & thu tiền theo đợt» (PosContracts).
bool canUsePosContracts(BuildContext context) {
  final auth = context.read<AuthProvider>();
  return PermissionNavigation.canAccessModule(
    'PosContracts',
    allowedModules: auth.user?.allowedModules,
    perm: context.read<PermissionProvider>(),
    role: auth.user?.role,
  );
}

class PosContractPaymentPanel extends StatefulWidget {
  const PosContractPaymentPanel({
    super.key,
    required this.quoteId,
    this.onChanged,
  });

  final String quoteId;

  /// Gọi sau khi lưu / thu / hủy (màn cha tải lại giai đoạn hợp đồng).
  final VoidCallback? onChanged;

  @override
  State<PosContractPaymentPanel> createState() => _PosContractPaymentPanelState();
}

class _PosContractPaymentPanelState extends State<PosContractPaymentPanel> {
  final _api = ApiService();
  static final _money = NumberFormat('#,##0', 'vi_VN');
  static final _date = DateFormat('dd/MM/yyyy');
  PosQuoteContract? _c;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.getPosQuoteContract(widget.quoteId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _c = PosQuoteContract.fromJson(Map<String, dynamic>.from(res['data'] as Map));
        _error = null;
      } else {
        _error = res['message']?.toString() ?? 'Không tải được hợp đồng';
      }
    });
  }

  bool _apply(Map<String, dynamic> res, String okTitle) {
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() => _c = PosQuoteContract.fromJson(Map<String, dynamic>.from(res['data'] as Map)));
      NotificationOverlayManager().showSuccess(title: okTitle, message: _c?.quoteNo ?? '');
      widget.onChanged?.call();
      return true;
    }
    NotificationOverlayManager().showError(
      title: 'Không lưu được',
      message: res['message']?.toString() ?? '',
    );
    return false;
  }

  String _d(DateTime? d) => d == null ? '—' : _date.format(d);

  // ── Sửa hợp đồng: số HĐ, mốc tiến độ, đợt thanh toán
  Future<void> _editSchedule() async {
    final c = _c;
    if (c == null) return;
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ScheduleDialog(contract: c),
    );
    if (body == null || !mounted) return;
    setState(() => _busy = true);
    final res = await _api.savePosQuoteContract(widget.quoteId, body);
    if (!mounted) return;
    setState(() => _busy = false);
    _apply(res, 'Đã lưu hợp đồng');
  }

  // ── Thu tiền
  Future<void> _collect() async {
    final c = _c;
    if (c == null) return;
    if (c.remaining <= 0) {
      NotificationOverlayManager().showInfo(
        title: 'Đã thu đủ',
        message: tr('Hợp đồng đã thu đủ giá trị'),
      );
      return;
    }
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CollectDialog(contract: c),
    );
    if (body == null || !mounted) return;
    setState(() => _busy = true);
    final res = await _api.addPosQuotePayment(widget.quoteId, body);
    if (!mounted) return;
    setState(() => _busy = false);
    _apply(res, 'Đã thu tiền — tạo phiếu thu');
  }

  Future<void> _cancelPayment(PosContractPayment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy lần thu?')),
        content: Text(tr(
            'Hủy lần thu ${_money.format(p.amount)}đ ngày ${_d(p.paidAt)}. Phiếu thu ${p.cashCode ?? ''} trong sổ quỹ chuyển «Đã hủy».')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Hủy lần thu')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final res = await _api.cancelPosQuotePayment(widget.quoteId, p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _apply(res, 'Đã hủy lần thu');
  }

  Color _statusColor(String s) => switch (s) {
        'paid' => Colors.green.shade700,
        'partial' => Colors.orange.shade800,
        'overdue' => Colors.red.shade700,
        _ => SboxColors.slate600,
      };

  Widget _stat(String label, double value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(label), style: TextStyle(fontSize: 12, color: SboxColors.slate600)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money.format(value),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _milestone(String label, DateTime? d) {
    final late = d != null &&
        DateTime(d.year, d.month, d.day).isBefore(DateUtils.dateOnly(DateTime.now()));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(tr(label), style: const TextStyle(fontSize: 13))),
          Text(
            _d(d),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: late ? Colors.red.shade700 : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    final canEdit = perm.canEdit('PosQuotes');
    final canDelete = perm.canDelete('PosQuotes');
    final c = _c;
    Widget card(Widget child) => Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        );

    if (_loading) {
      return card(const Center(child: Padding(
        padding: EdgeInsets.all(8),
        child: CircularProgressIndicator(),
      )));
    }
    if (c == null) {
      return card(Text(tr(_error ?? 'Không tải được hợp đồng')));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 20, color: PosTheme.kiotBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(tr('Thu tiền hợp đồng'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                if (canEdit)
                  FilledButton.icon(
                    onPressed: _busy ? null : _collect,
                    icon: const Icon(Icons.add_card_outlined, size: 18),
                    label: Text(tr('Thu tiền')),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _stat('Giá trị HĐ', c.total),
                _stat('Đã thu', c.collected, color: Colors.green.shade700),
                _stat('Còn phải thu', c.remaining, color: c.remaining > 0 ? PosTheme.kiotBlue : null),
              ],
            ),
            if (c.overdueAmount > 0) ...[
              const SizedBox(height: 8),
              Text(
                tr('Quá hạn: ${_money.format(c.overdueAmount)}đ'),
                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700),
              ),
            ] else if (c.nextDueTitle != null) ...[
              const SizedBox(height: 8),
              Text(
                tr('Đợt tới: ${c.nextDueTitle}${c.nextDueDate != null ? ' — hạn ${_d(c.nextDueDate)}' : ''}'),
                style: TextStyle(color: SboxColors.slate700, fontSize: 13),
              ),
            ],
            if (c.total > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (c.collected / c.total).clamp(0, 1).toDouble(),
                  minHeight: 6,
                  backgroundColor: SboxColors.slate200,
                ),
              ),
            ],
          ],
        )),
        const SizedBox(height: 10),
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note_outlined, size: 20, color: PosTheme.kiotBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(tr('Tiến độ & đợt thanh toán'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                if (canEdit)
                  TextButton.icon(
                    onPressed: _busy ? null : _editSchedule,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(tr('Sửa')),
                  ),
              ],
            ),
            if (c.contractNo != null)
              Text(tr('Số HĐ: ${c.contractNo}'), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            _milestone('Ngày ký hợp đồng', c.contractSignedAt),
            _milestone('Hạn xong sản xuất', c.productionDueAt),
            _milestone('Hạn lắp đặt / giao hàng', c.installDueAt),
            _milestone('Hạn bàn giao, nghiệm thu', c.handoverDueAt),
            if (c.contractNote != null) ...[
              const SizedBox(height: 4),
              Text(c.contractNote!, style: TextStyle(fontSize: 12, color: SboxColors.slate600)),
            ],
            const Divider(height: 20),
            if (c.stages.isEmpty)
              Text(
                tr(canEdit
                    ? 'Chưa chia đợt thanh toán — bấm «Sửa» để chia (cọc, lắp đặt, nghiệm thu…).'
                    : 'Chưa chia đợt thanh toán.'),
                style: TextStyle(fontSize: 13, color: SboxColors.slate600),
              ),
            for (final s in c.stages)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s.title}${s.percent != null ? ' (${NumberFormat('#,##0.##', 'vi_VN').format(s.percent)}%)' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            tr('Hạn ${_d(s.dueDate)} · đã thu ${_money.format(s.paid)}'),
                            style: TextStyle(fontSize: 12, color: SboxColors.slate600),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_money.format(s.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          tr(PosContractStage.statusLabel(s.status)),
                          style: TextStyle(fontSize: 12, color: _statusColor(s.status), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        )),
        const SizedBox(height: 10),
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Các lần thu (${c.payments.length})'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            if (c.payments.isEmpty)
              Text(tr('Chưa thu lần nào.'), style: TextStyle(fontSize: 13, color: SboxColors.slate600)),
            for (final p in c.payments)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${_money.format(p.amount)}đ · ${p.paymentMethod ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text([
                  _d(p.paidAt),
                  if (p.stageTitle != null) p.stageTitle!,
                  if (p.cashCode != null) 'Phiếu ${p.cashCode}',
                  if (p.collectedBy != null) p.collectedBy!,
                  if (p.note != null) p.note!,
                ].join(' · ')),
                trailing: canDelete
                    ? IconButton(
                        tooltip: tr('Hủy lần thu'),
                        onPressed: _busy ? null : () => _cancelPayment(p),
                        icon: Icon(Icons.undo, color: Colors.red.shade700),
                      )
                    : null,
              ),
          ],
        )),
      ],
    );
  }
}

/// Sửa số HĐ, mốc tiến độ và các đợt thanh toán.
class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.contract});

  final PosQuoteContract contract;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _StageRow {
  _StageRow(PosContractStage s)
      : id = s.id,
        title = TextEditingController(text: s.title),
        value = TextEditingController(
          text: s.percent != null
              ? NumberFormat('#,##0.##', 'vi_VN').format(s.percent)
              : (s.amount > 0 ? NumberFormat('#,###', 'vi_VN').format(s.amount) : ''),
        ),
        isPercent = s.percent != null,
        dueDate = s.dueDate;

  final String? id;
  final TextEditingController title;
  final TextEditingController value;
  bool isPercent;
  DateTime? dueDate;

  void dispose() {
    title.dispose();
    value.dispose();
  }
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  static final _money = NumberFormat('#,##0', 'vi_VN');
  static final _date = DateFormat('dd/MM/yyyy');
  late final TextEditingController _no;
  late final TextEditingController _note;
  DateTime? _signed;
  DateTime? _production;
  DateTime? _install;
  DateTime? _handover;
  final _rows = <_StageRow>[];

  @override
  void initState() {
    super.initState();
    final c = widget.contract;
    _no = TextEditingController(text: c.contractNo ?? '');
    _note = TextEditingController(text: c.contractNote ?? '');
    _signed = c.contractSignedAt ?? DateUtils.dateOnly(DateTime.now());
    _production = c.productionDueAt;
    _install = c.installDueAt;
    _handover = c.handoverDueAt;
    _rows.addAll(c.stages.map(_StageRow.new));
  }

  @override
  void dispose() {
    _no.dispose();
    _note.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  static double _raw(_StageRow r) =>
      parseFormattedNumber(r.value.text)?.toDouble() ??
      double.tryParse(r.value.text.replaceAll(',', '.')) ??
      0;

  /// Số tiền các đợt — cùng công thức máy chủ (cọc trước VAT, đợt cuối nhận phần còn lại).
  List<double> get _amounts => posContractStageAmounts(
        [
          for (final r in _rows)
            (
              title: r.title.text,
              percent: r.isPercent ? _raw(r) : null,
              amount: r.isPercent ? 0 : _raw(r),
            ),
        ],
        total: widget.contract.total,
        preVat: widget.contract.preVat > 0 ? widget.contract.preVat : widget.contract.total,
      );

  double _amountOf(_StageRow r) {
    final i = _rows.indexOf(r);
    return i < 0 ? 0 : _amounts[i];
  }

  bool _isDepositRow(_StageRow r) {
    if (!r.isPercent) return false;
    final first = _rows.where((x) => x.isPercent && x.title.text.toLowerCase().contains('cọc'));
    return first.isNotEmpty && identical(first.first, r);
  }

  double get _sum => _amounts.fold(0.0, (a, v) => a + v);

  /// Mẫu nhôm kính: cọc (theo báo giá, tính trên trước VAT; mặc định 50%) · lắp đặt xong 40% ·
  /// nghiệm thu phần còn lại.
  void _fillTemplate() {
    final c = widget.contract;
    final preVat = c.preVat > 0 ? c.preVat : c.total;
    final depositPct = (c.depositPercent ?? 0) > 0
        ? c.depositPercent!
        : preVat > 0 && c.depositAmount > 0
            ? (c.depositAmount / preVat * 100).roundToDouble()
            : 50.0;
    final install = (100 - depositPct) >= 50 ? 40.0 : ((100 - depositPct) * 0.8).roundToDouble();
    final last = 100 - depositPct - install;
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..add(_StageRow(PosContractStage(title: 'Đặt cọc khi ký hợp đồng', percent: depositPct, dueDate: _signed)))
        ..add(_StageRow(PosContractStage(title: 'Thanh toán khi lắp đặt xong', percent: install, dueDate: _install)))
        ..add(_StageRow(PosContractStage(title: 'Nghiệm thu, bàn giao', percent: last, dueDate: _handover)));
    });
  }

  Future<DateTime?> _pick(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );

  Widget _dateTile(String label, DateTime? value, ValueChanged<DateTime?> onSet) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(tr(label)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () async {
              final d = await _pick(value);
              if (d != null) setState(() => onSet(d));
            },
            child: Text(value == null ? tr('Chọn ngày') : _date.format(value)),
          ),
          if (value != null)
            IconButton(
              tooltip: tr('Bỏ'),
              onPressed: () => setState(() => onSet(null)),
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    );
  }

  void _save() {
    final stages = <Map<String, dynamic>>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final raw = parseFormattedNumber(r.value.text)?.toDouble() ??
          double.tryParse(r.value.text.replaceAll(',', '.')) ??
          0;
      final title = r.title.text.trim().isEmpty ? 'Đợt ${i + 1}' : r.title.text.trim();
      stages.add(PosContractStage(
        id: r.id,
        title: title,
        percent: r.isPercent ? raw : null,
        amount: r.isPercent ? 0 : raw,
        dueDate: r.dueDate,
      ).toInputJson());
    }
    Navigator.pop(context, {
      'contractNo': _no.text.trim(),
      'contractSignedAt': _signed == null ? null : dateOnly(_signed!),
      'productionDueAt': _production == null ? null : dateOnly(_production!),
      'installDueAt': _install == null ? null : dateOnly(_install!),
      'handoverDueAt': _handover == null ? null : dateOnly(_handover!),
      'contractNote': _note.text.trim(),
      'stages': stages,
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.contract.total;
    final diff = total - _sum;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      title: Text(tr('Hợp đồng & đợt thanh toán')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _no,
                decoration: PosTheme.inputDecoration(label: 'Số hợp đồng', hint: 'VD: 15/2026/HĐ-NK'),
              ),
              _dateTile('Ngày ký hợp đồng', _signed, (d) => _signed = d),
              _dateTile('Hạn xong sản xuất', _production, (d) => _production = d),
              _dateTile('Hạn lắp đặt / giao hàng', _install, (d) => _install = d),
              _dateTile('Hạn bàn giao, nghiệm thu', _handover, (d) => _handover = d),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: PosTheme.inputDecoration(label: 'Ghi chú hợp đồng'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(tr('Đợt thanh toán'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  TextButton(onPressed: _fillTemplate, child: Text(tr('Mẫu 3 đợt'))),
                  IconButton(
                    tooltip: tr('Thêm đợt'),
                    onPressed: _rows.length >= 20
                        ? null
                        : () => setState(() => _rows.add(_StageRow(
                            PosContractStage(title: 'Đợt ${_rows.length + 1}')))),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              for (var i = 0; i < _rows.length; i++) _stageEditor(i),
              const SizedBox(height: 6),
              Text(
                tr(diff.abs() < 1
                    ? 'Tổng các đợt = giá trị hợp đồng ${_money.format(total)}đ'
                    : 'Tổng các đợt ${_money.format(_sum)}đ — ${diff > 0 ? 'còn thiếu' : 'vượt'} ${_money.format(diff.abs())}đ so với giá trị HĐ ${_money.format(total)}đ'),
                style: TextStyle(
                  fontSize: 12,
                  color: diff.abs() < 1 ? Colors.green.shade700 : Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(onPressed: _save, child: Text(tr('Lưu'))),
      ],
    );
  }

  Widget _stageEditor(int i) {
    final r = _rows[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: SboxColors.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: r.title,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr('Tên đợt'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('Xóa đợt'),
                onPressed: () => setState(() => _rows.removeAt(i).dispose()),
                icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: r.value,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: r.isPercent ? null : [ThousandSeparatorFormatter()],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr(!r.isPercent
                        ? 'Số tiền'
                        : _isDepositRow(r)
                            ? '% giá trị trước VAT'
                            : '% giá trị HĐ'),
                    helperText: r.isPercent ? '= ${_money.format(_amountOf(r))}đ' : null,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('%')),
                  ButtonSegment(value: false, label: Text('đ')),
                ],
                selected: {r.isPercent},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  final amount = _amountOf(r);
                  r.isPercent = s.first;
                  final total = _isDepositRow(r) && widget.contract.preVat > 0
                      ? widget.contract.preVat
                      : widget.contract.total;
                  r.value.text = r.isPercent
                      ? (total > 0
                          ? NumberFormat('#,##0.##', 'vi_VN').format(amount / total * 100)
                          : '')
                      : NumberFormat('#,###', 'vi_VN').format(amount);
                }),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final d = await _pick(r.dueDate);
                if (d != null) setState(() => r.dueDate = d);
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text(r.dueDate == null
                  ? tr('Hạn thanh toán')
                  : tr('Hạn ${_date.format(r.dueDate!)}')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thu tiền: số tiền (mặc định = còn lại của đợt tới), đợt, phương thức, ngày.
class _CollectDialog extends StatefulWidget {
  const _CollectDialog({required this.contract});

  final PosQuoteContract contract;

  @override
  State<_CollectDialog> createState() => _CollectDialogState();
}

class _CollectDialogState extends State<_CollectDialog> {
  static final _money = NumberFormat('#,##0', 'vi_VN');
  static final _date = DateFormat('dd/MM/yyyy');
  static const _methods = ['Tiền mặt', 'Chuyển khoản', 'Thẻ'];
  late final TextEditingController _amount;
  final _note = TextEditingController();
  String? _stageId;
  String _method = 'Chuyển khoản';
  DateTime _paidAt = DateUtils.dateOnly(DateTime.now());
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.contract;
    PosContractStage? next;
    for (final s in c.stages) {
      if (s.remaining > 0) {
        next = s;
        break;
      }
    }
    _stageId = next?.id;
    final suggest = next != null && next.remaining > 0 ? next.remaining : c.remaining;
    _amount = TextEditingController(text: NumberFormat('#,###', 'vi_VN').format(suggest));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseFormattedNumber(_amount.text)?.toDouble() ?? 0;
    if (v <= 0) {
      setState(() => _error = 'Nhập số tiền thu');
      return;
    }
    if (v > widget.contract.remaining + 0.5) {
      setState(() => _error =
          'Vượt số còn phải thu ${_money.format(widget.contract.remaining)}đ');
      return;
    }
    Navigator.pop(context, {
      'amount': v,
      // Giữa trưa giờ máy → UTC, tránh lệch sang ngày khác.
      'paidAt': DateTime(_paidAt.year, _paidAt.month, _paidAt.day, 12).toUtc().toIso8601String(),
      'paymentMethod': _method,
      'stageId': _stageId,
      'note': _note.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.contract;
    return AlertDialog(
      title: Text(tr('Thu tiền hợp đồng')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Còn phải thu: ${_money.format(c.remaining)}đ'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              if (c.stages.isNotEmpty) ...[
                DropdownButtonFormField<String?>(
                  value: _stageId,
                  isExpanded: true,
                  decoration: PosTheme.inputDecoration(label: 'Đợt thanh toán'),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(tr('Không theo đợt'))),
                    for (final s in c.stages)
                      DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(
                          '${s.title} — còn ${_money.format(s.remaining)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _stageId = v;
                    for (final s in c.stages) {
                      if (s.id == v && s.remaining > 0) {
                        _amount.text = NumberFormat('#,###', 'vi_VN').format(s.remaining);
                      }
                    }
                  }),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandSeparatorFormatter()],
                onChanged: (_) => setState(() => _error = null),
                decoration: PosTheme.inputDecoration(label: 'Số tiền thu'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in _methods)
                    ChoiceChip(
                      label: Text(tr(m)),
                      selected: _method == m,
                      onSelected: (_) => setState(() => _method = m),
                    ),
                ],
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Ngày thu')),
                trailing: TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _paidAt,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (d != null) setState(() => _paidAt = d);
                  },
                  child: Text(_date.format(_paidAt)),
                ),
              ),
              TextField(
                controller: _note,
                decoration: PosTheme.inputDecoration(label: 'Ghi chú'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(tr(_error!), style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 6),
              Text(
                tr('Tạo phiếu thu «Thu tiền hợp đồng» trong sổ quỹ.'),
                style: TextStyle(fontSize: 12, color: SboxColors.slate600),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(onPressed: _save, child: Text(tr('Thu tiền'))),
      ],
    );
  }
}
