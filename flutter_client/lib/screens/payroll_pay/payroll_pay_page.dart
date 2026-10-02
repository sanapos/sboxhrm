import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../utils/excel_download_helper.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Cách trả lương.
enum PayMethod { cash, bank, mixed }

final _money = NumberFormat('#,##0', 'vi_VN');
String payMoney(num v) => '${_money.format(v.round())}đ';

/// Một phiếu lương cần trả (từ /api/payslips/payment-info).
class PayLine {
  PayLine.fromJson(Map<String, dynamic> j)
      : payslipId = '${j['payslipId']}',
        employeeCode = '${j['employeeCode'] ?? ''}',
        employeeName = '${j['employeeName'] ?? ''}',
        month = (j['month'] as num?)?.toInt() ?? 0,
        year = (j['year'] as num?)?.toInt() ?? 0,
        netSalary = (j['netSalary'] as num?)?.toDouble() ?? 0,
        paid = (j['paidAmount'] as num?)?.toDouble() ?? 0,
        remaining = (j['remaining'] as num?)?.toDouble() ?? 0,
        bankText = j['bankText'] as String?,
        bankRecognized = j['bankRecognized'] == true,
        bankBin = j['bankBin'] as String?,
        bankShortName = j['bankShortName'] as String?,
        bankLogo = j['bankLogo'] as String?,
        accountNumber = j['accountNumber'] as String?,
        accountName = '${j['accountName'] ?? ''}',
        content = '${j['transferContent'] ?? ''}',
        ready = j['ready'] == true {
    amount = remaining;
    selected = remaining > 0;
  }

  final String payslipId;
  final String employeeCode;
  final String employeeName;
  final int month;
  final int year;
  final double netSalary;
  final double paid;
  final double remaining;
  final String? bankText;
  final bool bankRecognized;
  final String? bankBin;
  final String? bankShortName;
  final String? bankLogo;
  final String? accountNumber;
  final String accountName;
  final String content;
  final bool ready;

  bool selected = false;
  /// Số trả lần này (mặc định = còn lại).
  double amount = 0;
  /// Phần tiền mặt khi «Kết hợp».
  double cash = 0;
  bool done = false;

  double cashPart(PayMethod m) => switch (m) {
        PayMethod.cash => amount,
        PayMethod.bank => 0,
        PayMethod.mixed => cash.clamp(0, amount).toDouble(),
      };
  double bankPart(PayMethod m) => amount - cashPart(m);

  String get bankLabel => bankShortName ?? (bankText?.split(' - ').first ?? '');

  /// QR VietQR tới tài khoản nhân viên với đúng số chuyển lần này.
  String qrUrl(double amt) => 'https://img.vietqr.io/image/$bankBin-$accountNumber-compact2.png'
      '?amount=${amt.round()}&addInfo=${Uri.encodeComponent(content)}&accountName=${Uri.encodeComponent(accountName)}';
}

/// Tài khoản chi của cửa hàng.
class PaySource {
  PaySource.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        bankName = '${j['bankName'] ?? ''}',
        accountNumber = '${j['accountNumber'] ?? ''}',
        bin = j['bin'] as String?,
        appId = j['appId'] as String?,
        isDefault = j['isDefault'] == true;
  final String id;
  final String bankName;
  final String accountNumber;
  final String? bin;
  final String? appId;
  final bool isDefault;
}

/// Mở trang trả lương cho các phiếu lương. Trả về true nếu có trả.
Future<bool?> openPayrollPay(BuildContext context, List<String> payslipIds, {ApiService? api}) =>
    Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PayrollPayPage(payslipIds: payslipIds, api: api)));

/// Trả lương: tiền mặt / chuyển khoản / kết hợp; xuất file chuyển lương theo ngân hàng; chuyển từng người bằng QR.
class PayrollPayPage extends StatefulWidget {
  const PayrollPayPage({super.key, required this.payslipIds, this.api});
  final List<String> payslipIds;
  final ApiService? api;

  @override
  State<PayrollPayPage> createState() => _PayrollPayPageState();
}

class _PayrollPayPageState extends State<PayrollPayPage> {
  late final ApiService _api = widget.api ?? ApiService();
  List<PayLine> _lines = [];
  List<PaySource> _sources = [];
  String? _sourceId;
  PayMethod _method = PayMethod.bank;
  DateTime _paidAt = DateTime.now();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.getPayslipPaymentInfo(widget.payslipIds);
    if (!mounted) return;
    setState(() {
      _loading = false;
      final d = r['data'];
      if (r['isSuccess'] != true || d is! Map) {
        _error = '${r['message'] ?? 'Không tải được thông tin trả lương'}';
        return;
      }
      _lines = (d['items'] as List? ?? []).whereType<Map>().map((e) => PayLine.fromJson(Map<String, dynamic>.from(e))).toList();
      _sources = (d['sourceAccounts'] as List? ?? []).whereType<Map>().map((e) => PaySource.fromJson(Map<String, dynamic>.from(e))).toList();
      _sourceId ??= (_sources.where((s) => s.isDefault).firstOrNull ?? _sources.firstOrNull)?.id;
      if (_sources.isEmpty) _method = PayMethod.cash;
    });
  }

  List<PayLine> get _selected => _lines.where((l) => l.selected && !l.done && l.amount > 0).toList();
  PaySource? get _source => _sources.where((s) => s.id == _sourceId).firstOrNull;
  bool get _usesBank => _method != PayMethod.cash;

  double _sum(double Function(PayLine) f) => _selected.fold(0.0, (a, l) => a + f(l));

  String? _validate(List<PayLine> lines) {
    if (lines.isEmpty) return 'Chưa chọn nhân viên nào để trả';
    for (final l in lines) {
      if (l.amount > l.remaining + 0.5) return '${l.employeeName}: số trả lớn hơn số còn lại';
      if (_method == PayMethod.mixed && l.cash > l.amount) return '${l.employeeName}: tiền mặt lớn hơn số trả';
    }
    if (_usesBank && lines.any((l) => l.bankPart(_method) > 0)) {
      if (_source == null) return 'Chọn tài khoản ngân hàng chi lương';
      final missing = lines.where((l) => l.bankPart(_method) > 0 && !l.ready).toList();
      if (missing.isNotEmpty) {
        return 'Thiếu số tài khoản / ngân hàng: ${missing.take(3).map((l) => l.employeeName).join(', ')}'
            '${missing.length > 3 ? '…' : ''}. Bỏ chọn hoặc trả tiền mặt.';
      }
    }
    return null;
  }

  Future<bool> _submit(List<PayLine> lines) async {
    setState(() => _busy = true);
    final r = await _api.payPayslips([
      for (final l in lines) {'payslipId': l.payslipId, 'cashAmount': l.cashPart(_method), 'bankAmount': l.bankPart(_method)},
    ], bankAccountId: _usesBank ? _sourceId : null, paidAt: _paidAt);
    if (!mounted) return false;
    setState(() => _busy = false);
    if (r['isSuccess'] != true) {
      _toast('${r['message'] ?? 'Không ghi nhận được'}', error: true);
      return false;
    }
    final d = r['data'] is Map ? r['data'] as Map : const {};
    final errors = (d['errors'] as List? ?? []).map((e) => '$e').toList();
    _changed = true;
    final failed = errors.length;
    setState(() {
      for (final l in lines) {
        if (!errors.any((e) => e.startsWith(l.employeeName))) l.done = true;
      }
    });
    _toast(failed == 0 ? 'Đã ghi nhận trả lương ${d['paid']} người vào Thu chi' : '${d['paid']} người đã ghi nhận, $failed lỗi:\n${errors.take(3).join('\n')}',
        error: failed > 0);
    return failed == 0;
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(tr(m)), backgroundColor: error ? SboxColors.danger : null, behavior: SnackBarBehavior.floating));

  Future<void> _payAllNow() async {
    final lines = _selected;
    final err = _validate(lines);
    if (err != null) return _toast(err, error: true);
    final cash = _sum((l) => l.cashPart(_method));
    final bank = _sum((l) => l.bankPart(_method));
    final ok = await SboxDialogs.confirm(
      context,
      title: _method == PayMethod.cash ? 'Xác nhận đã trả tiền mặt?' : 'Xác nhận đã chuyển khoản theo file?',
      message: [
        '${lines.length} nhân viên',
        if (cash > 0) 'Tiền mặt: ${payMoney(cash)}',
        if (bank > 0) 'Chuyển khoản: ${payMoney(bank)} từ ${_source?.bankName} ${_source?.accountNumber}',
        'Phiếu chi được ghi vào Thu chi, nhân viên nhận thông báo.',
      ].join('\n'),
      confirmLabel: 'Ghi nhận đã trả',
    );
    if (!ok) return;
    if (await _submit(lines) && mounted && _lines.every((l) => l.done || !l.selected)) Navigator.of(context).pop(true);
  }

  Future<void> _export() async {
    final lines = _selected;
    if (lines.isEmpty) return _toast('Chưa chọn nhân viên nào', error: true);
    final t = await _api.getPayrollBankTemplates();
    if (!mounted) return;
    final templates = (t['data'] as List? ?? []).whereType<Map>().toList();
    final srcBin = _source?.bin;
    final suggested = templates.where((x) => x['bin'] != null && x['bin'] == srcBin).firstOrNull;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text(tr('Xuất file chuyển lương hàng loạt'), style: SboxType.titleStyle()),
          const SizedBox(height: 4),
          Text(tr('Chọn mẫu theo ngân hàng của tài khoản chi lương, rồi tải file lên Internet Banking doanh nghiệp.'),
              style: SboxType.smallStyle()),
          const SizedBox(height: 8),
          for (final x in [if (suggested != null) suggested, ...templates.where((x) => x != suggested)])
            ListTile(
              leading: Icon(x == suggested ? Icons.star_rounded : Icons.description_outlined,
                  color: x == suggested ? SboxColors.warning : SboxColors.brand600),
              title: Text(tr('${x['name']}')),
              subtitle: '${x['note'] ?? ''}'.isEmpty ? null : Text(tr('${x['note']}'), maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx, '${x['key']}'),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    final bytes = await _api.downloadPayrollBankFile(lines.map((l) => l.payslipId).toList(), picked);
    if (!mounted) return;
    setState(() => _busy = false);
    if (bytes == null) return _toast('Không xuất được file', error: true);
    final first = lines.first;
    await ExcelDownloadHelper.saveExcelBytes(bytes, 'chi-luong-T${first.month.toString().padLeft(2, '0')}-${first.year}-$picked.xlsx');
    if (mounted) _toast('Đã xuất file. Sau khi ngân hàng chuyển xong, bấm «Đã chuyển theo file».');
  }

  Future<void> _stepThrough() async {
    final lines = _selected;
    final err = _validate(lines);
    if (err != null) return _toast(err, error: true);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PayrollTransferStepper(lines: lines, method: _method, source: _source, onPaid: (l) => _submit([l])),
    ));
    if (!mounted) return;
    setState(() {});
    if (_lines.where((l) => l.selected).every((l) => l.done)) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(
          backgroundColor: SboxColors.surface,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop(_changed)),
          title: Text(tr('Trả lương')),
        ),
        body: _loading
            ? const SboxLoading()
            : _error != null
                ? SboxEmptyState(title: 'Không mở được', message: _error!)
                : Column(children: [
                    Expanded(
                      child: ListView(padding: EdgeInsets.all(wide ? 20 : 12), children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 960),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              _summary(),
                              const SizedBox(height: 12),
                              _options(),
                              const SizedBox(height: 12),
                              for (final l in _lines) _row(l),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                    _actions(),
                  ]),
      ),
    );
  }

  Widget _summary() {
    final total = _sum((l) => l.amount);
    final cash = _sum((l) => l.cashPart(_method));
    final bank = _sum((l) => l.bankPart(_method));
    final missing = _lines.where((l) => l.selected && !l.ready && l.bankPart(_method) > 0).length;
    Widget kpi(String label, String value, Color color) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(label), style: SboxType.captionStyle()),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: SboxType.titleStyle(color))),
          ]),
        );
    return SboxCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          kpi('Trả lần này (${_selected.length} người)', payMoney(total), SboxColors.brand700),
          kpi('Tiền mặt', payMoney(cash), SboxColors.successText),
          kpi('Chuyển khoản', payMoney(bank), SboxColors.brand600),
        ]),
        if (missing > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: SboxRadius.mdAll),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: SboxColors.warning, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('$missing người thiếu số tài khoản hoặc ngân hàng — cập nhật hồ sơ nhân viên, hoặc trả tiền mặt.'),
                    style: SboxType.smallStyle(SboxColors.warningText)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _options() {
    return SboxCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Phương thức'), style: SboxType.bodyStrong()),
        const SizedBox(height: 8),
        SegmentedButton<PayMethod>(
          segments: [
            ButtonSegment(value: PayMethod.cash, icon: const Icon(Icons.payments_outlined), label: Text(tr('Tiền mặt'))),
            ButtonSegment(value: PayMethod.bank, icon: const Icon(Icons.account_balance_outlined), label: Text(tr('Chuyển khoản')), enabled: _sources.isNotEmpty),
            ButtonSegment(value: PayMethod.mixed, icon: const Icon(Icons.call_split_rounded), label: Text(tr('Kết hợp')), enabled: _sources.isNotEmpty),
          ],
          selected: {_method},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _method = s.first),
        ),
        if (_sources.isEmpty) ...[
          const SizedBox(height: 8),
          Text(tr('Cửa hàng chưa có tài khoản ngân hàng — thêm ở Thu chi › Tài khoản ngân hàng để trả bằng chuyển khoản.'),
              style: SboxType.smallStyle()),
        ],
        if (_usesBank) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _sourceId,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Tài khoản chi lương'), isDense: true, border: const OutlineInputBorder()),
            items: [
              for (final s in _sources) DropdownMenuItem(value: s.id, child: Text('${s.bankName} · ${s.accountNumber}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _sourceId = v),
          ),
        ],
        if (_method == PayMethod.mixed) ...[
          const SizedBox(height: 8),
          Text(tr('Nhập phần tiền mặt của từng người; phần còn lại chuyển khoản.'), style: SboxType.smallStyle()),
        ],
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.event_outlined, size: 18, color: SboxColors.slate500),
          const SizedBox(width: 6),
          Text(tr('Ngày trả: ${DateFormat('dd/MM/yyyy').format(_paidAt)}'), style: SboxType.smallStyle(SboxColors.text)),
          TextButton(
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _paidAt, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setState(() => _paidAt = DateTime(d.year, d.month, d.day, 12));
            },
            child: Text(tr('Đổi')),
          ),
        ]),
      ]),
    );
  }

  Widget _row(PayLine l) {
    final paidAll = l.remaining <= 0 || l.done;
    final needBank = _usesBank && l.bankPart(_method) > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
        decoration: BoxDecoration(
          color: SboxColors.surface,
          borderRadius: SboxRadius.mdAll,
          border: Border.all(color: l.done ? SboxColors.success.withValues(alpha: 0.5) : SboxColors.border),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 620;
          final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${l.employeeName} · ${l.employeeCode}', style: SboxType.bodyStrong(), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            if (l.ready)
              Text('${l.bankLabel} · ${l.accountNumber}', style: SboxType.smallStyle(), overflow: TextOverflow.ellipsis)
            else
              Text(tr(l.accountNumber == null ? 'Chưa có số tài khoản' : 'Không nhận ra ngân hàng «${l.bankText ?? ''}»'),
                  style: SboxType.smallStyle(needBank ? SboxColors.dangerText : SboxColors.textMuted)),
            Text(
              tr(l.done
                  ? 'Đã ghi nhận trả'
                  : 'Thực lĩnh ${payMoney(l.netSalary)}${l.paid > 0 ? ' · đã trả ${payMoney(l.paid)}' : ''} · còn ${payMoney(l.remaining)}'),
              style: l.done ? SboxType.captionStyle(SboxColors.successText) : SboxType.captionStyle(),
            ),
          ]);
          final inputs = Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 130,
              child: _MoneyField(
                key: ValueKey('a-${l.payslipId}'),
                label: 'Số trả',
                value: l.amount,
                enabled: !paidAll && l.selected,
                onChanged: (v) => setState(() => l.amount = v),
              ),
            ),
            if (_method == PayMethod.mixed) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: _MoneyField(
                  key: ValueKey('c-${l.payslipId}'),
                  label: 'Tiền mặt',
                  value: l.cash,
                  enabled: !paidAll && l.selected,
                  onChanged: (v) => setState(() => l.cash = v),
                ),
              ),
            ],
          ]);
          final check = Checkbox(
            value: l.selected && !paidAll,
            onChanged: paidAll ? null : (v) => setState(() => l.selected = v == true),
          );
          if (narrow) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [check, Expanded(child: info)]),
              if (!paidAll) Padding(padding: const EdgeInsets.only(left: 46, top: 6), child: Align(alignment: Alignment.centerLeft, child: inputs)),
            ]);
          }
          return Row(children: [check, Expanded(child: info), if (!paidAll) inputs]);
        }),
      ),
    );
  }

  Widget _actions() {
    final any = _selected.isNotEmpty;
    return Material(
      color: SboxColors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: _method == PayMethod.cash
                  ? SboxButton(
                      label: 'Xác nhận đã trả tiền mặt (${_selected.length})',
                      icon: Icons.check_rounded,
                      expand: true,
                      loading: _busy,
                      onPressed: any && !_busy ? _payAllNow : null,
                    )
                  : Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
                      SboxButton.secondary(label: 'Xuất file ngân hàng', icon: Icons.file_download_outlined, onPressed: any && !_busy ? _export : null),
                      SboxButton.secondary(label: 'Đã chuyển theo file', icon: Icons.task_alt_rounded, onPressed: any && !_busy ? _payAllNow : null),
                      SboxButton(label: 'Chuyển từng người', icon: Icons.qr_code_2_rounded, loading: _busy, onPressed: any && !_busy ? _stepThrough : null),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoneyField extends StatefulWidget {
  const _MoneyField({super.key, required this.label, required this.value, required this.onChanged, this.enabled = true});
  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<_MoneyField> {
  late final _c = TextEditingController(text: _fmt(widget.value));

  static String _fmt(double v) => v <= 0 ? '' : _money.format(v.round());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      enabled: widget.enabled,
      textAlign: TextAlign.right,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: tr(widget.label), isDense: true, suffixText: 'đ', border: const OutlineInputBorder()),
      onChanged: (s) => widget.onChanged(double.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0),
      onEditingComplete: () {
        final v = double.tryParse(_c.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
        _c.text = _fmt(v);
        FocusScope.of(context).nextFocus();
      },
    );
  }
}

/// Chuyển từng người: QR tới tài khoản nhân viên, sao chép STK / số tiền / nội dung, mở app ngân hàng, «Đã chuyển».
class PayrollTransferStepper extends StatefulWidget {
  const PayrollTransferStepper({super.key, required this.lines, required this.method, required this.source, required this.onPaid});
  final List<PayLine> lines;
  final PayMethod method;
  final PaySource? source;
  final Future<bool> Function(PayLine) onPaid;

  @override
  State<PayrollTransferStepper> createState() => _PayrollTransferStepperState();
}

class _PayrollTransferStepperState extends State<PayrollTransferStepper> {
  int _i = 0;
  bool _busy = false;

  PayLine get _l => widget.lines[_i];
  bool get _mobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  void _next() {
    if (_i < widget.lines.length - 1) {
      setState(() => _i++);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Đã sao chép $label')), duration: const Duration(seconds: 1)));
    }
  }

  Future<void> _openApp() async {
    final app = widget.source?.appId;
    if (app == null) return;
    final l = _l;
    final amt = l.bankPart(widget.method).round();
    // VietQR deeplink: đa số app ngân hàng chỉ mở lên, chưa tự điền — dùng nút sao chép / quét QR.
    final uri = Uri.parse('https://dl.vietqr.io/pay?app=$app&ba=${l.accountNumber}@${l.bankBin}'
        '&am=$amt&tn=${Uri.encodeComponent(l.content)}&bn=${Uri.encodeComponent(l.accountName)}');
    await Clipboard.setData(ClipboardData(text: l.accountNumber ?? ''));
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    final ok = await widget.onPaid(_l);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _next();
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    final bank = l.bankPart(widget.method);
    final cash = l.cashPart(widget.method);
    Widget field(String label, String value, {bool big = false, String? copy}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 92, child: Text(tr(label), style: SboxType.smallStyle())),
            Expanded(child: SelectableText(value, style: big ? SboxType.titleStyle(SboxColors.brand700) : SboxType.bodyStrong())),
            IconButton(tooltip: tr('Sao chép'), icon: const Icon(Icons.copy_rounded, size: 18), onPressed: () => _copy(label, copy ?? value)),
          ]),
        );
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(tr('Chuyển lương ${_i + 1}/${widget.lines.length}')),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SboxCard(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l.employeeName, style: SboxType.titleStyle()),
                Text('${l.employeeCode} · lương T${l.month}/${l.year}', style: SboxType.smallStyle()),
                const SizedBox(height: 12),
                if (bank > 0 && l.ready) ...[
                  Center(
                    child: ClipRRect(
                      borderRadius: SboxRadius.mdAll,
                      child: Image.network(l.qrUrl(bank), width: 260, height: 300, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                                width: 260,
                                height: 120,
                                alignment: Alignment.center,
                                color: SboxColors.slate100,
                                child: Text(tr('Không tải được QR — dùng thông tin bên dưới'), textAlign: TextAlign.center, style: SboxType.smallStyle()),
                              )),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(tr('Quét bằng app ngân hàng của tài khoản ${widget.source?.bankName ?? ''} ${widget.source?.accountNumber ?? ''}'),
                      textAlign: TextAlign.center, style: SboxType.captionStyle()),
                  const SizedBox(height: 12),
                  field('Ngân hàng', l.bankLabel),
                  field('Số TK', l.accountNumber ?? ''),
                  field('Người nhận', l.accountName),
                  field('Số tiền', payMoney(bank), big: true, copy: '${bank.round()}'),
                  field('Nội dung', l.content),
                  if (_mobile && widget.source?.appId != null) ...[
                    const SizedBox(height: 6),
                    SboxButton.secondary(label: 'Mở app ${widget.source!.bankName}', icon: Icons.open_in_new_rounded, expand: true, onPressed: _openApp),
                    const SizedBox(height: 4),
                    Text(tr('Số tài khoản đã được sao chép sẵn. Nhiều app ngân hàng chỉ mở lên, chưa tự điền — dán / sao chép từng mục ở trên.'),
                        style: SboxType.captionStyle()),
                  ],
                ] else if (bank > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: SboxColors.dangerSoft, borderRadius: SboxRadius.mdAll),
                    child: Text(tr('Thiếu số tài khoản / ngân hàng — không chuyển được. Bỏ qua hoặc trả tiền mặt.'),
                        style: SboxType.smallStyle(SboxColors.dangerText)),
                  ),
                if (cash > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: SboxColors.successSoft, borderRadius: SboxRadius.mdAll),
                    child: Row(children: [
                      const Icon(Icons.payments_outlined, color: SboxColors.successText),
                      const SizedBox(width: 8),
                      Expanded(child: Text(tr('Trả tiền mặt: ${payMoney(cash)}'), style: SboxType.bodyStrong(SboxColors.successText))),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: Material(
        color: SboxColors.surface,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: SboxButton.ghost(label: 'Bỏ qua', onPressed: _busy ? null : _next)),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SboxButton(
                  label: bank > 0 ? 'Đã chuyển xong' : 'Đã trả',
                  icon: Icons.check_rounded,
                  loading: _busy,
                  onPressed: _busy || (bank > 0 && !l.ready) ? null : _done,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
