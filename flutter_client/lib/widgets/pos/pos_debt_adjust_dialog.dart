import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';
import '../notification_overlay.dart';

/// Nhập nợ đầu kỳ / điều chỉnh công nợ (khách hàng hoặc nhà cung cấp) về số đúng, bắt buộc lý do.
/// [submit] gọi API (newBalance, reason) → map phản hồi. Trả true khi đã lưu.
Future<bool> showPosDebtAdjustDialog(
  BuildContext context, {
  required String partyName,
  required double currentDebt,
  required Future<Map<String, dynamic>> Function(double newBalance, String reason) submit,
  bool supplier = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _DebtAdjustDialog(
      partyName: partyName,
      currentDebt: currentDebt,
      submit: submit,
      supplier: supplier,
    ),
  );
  return ok == true;
}

class _DebtAdjustDialog extends StatefulWidget {
  const _DebtAdjustDialog({required this.partyName, required this.currentDebt, required this.submit, required this.supplier});
  final String partyName;
  final double currentDebt;
  final Future<Map<String, dynamic>> Function(double newBalance, String reason) submit;
  final bool supplier;

  @override
  State<_DebtAdjustDialog> createState() => _DebtAdjustDialogState();
}

class _DebtAdjustDialogState extends State<_DebtAdjustDialog> {
  final _money = NumberFormat('#,##0', 'vi_VN');
  late final _balanceCtrl = TextEditingController(text: _money.format(widget.currentDebt));
  final _reasonCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  static const _reasons = [
    'Nợ đầu kỳ chuyển từ phần mềm / sổ cũ',
    'Đối chiếu công nợ với khách',
    'Xóa nợ khó đòi',
    'Giảm trừ / chiết khấu thanh toán',
  ];

  @override
  void dispose() {
    _balanceCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  double? get _newBalance => double.tryParse(_balanceCtrl.text.replaceAll('.', '').replaceAll(',', '').trim());

  Future<void> _save() async {
    final v = _newBalance;
    final reason = _reasonCtrl.text.trim();
    if (v == null || v < 0) {
      setState(() => _error = 'Nhập số công nợ đúng (≥ 0)');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'Nhập lý do điều chỉnh');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await widget.submit(v, reason);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã điều chỉnh công nợ', message: tr('${widget.partyName}: ${_money.format(v)}đ'));
      Navigator.pop(context, true);
    } else {
      setState(() => _error = res['message']?.toString() ?? 'Không lưu được');
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _newBalance;
    final delta = v == null ? null : v - widget.currentDebt;
    return AlertDialog(
      title: Text(tr('Điều chỉnh công nợ — ${widget.partyName}')),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Công nợ hiện tại: ${_money.format(widget.currentDebt)}đ'),
              style: const TextStyle(color: SboxColors.slate600)),
          const SizedBox(height: 10),
          TextField(
            controller: _balanceCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: tr(widget.supplier ? 'Số mình còn nợ NCC (đúng)' : 'Số khách còn nợ (đúng)'),
              suffixText: 'đ',
              border: const OutlineInputBorder(),
              helperText: delta == null || delta == 0
                  ? null
                  : tr(delta > 0 ? 'Tăng ${_money.format(delta)}đ' : 'Giảm ${_money.format(-delta)}đ'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: InputDecoration(labelText: tr('Lý do *'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final r in _reasons)
              ActionChip(
                label: Text(tr(r), style: const TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _reasonCtrl.text = r),
              ),
          ]),
          const SizedBox(height: 8),
          Text(
            tr('Ghi vào sổ công nợ (lần đầu = «Số dư đầu»). Không đổi tiền đã thu của các đơn / phiếu; '
                'phần nợ này không có tuổi nợ theo đơn.'),
            style: const TextStyle(fontSize: 11.5, color: SboxColors.slate600),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(tr(_error!), style: const TextStyle(color: SboxColors.dangerText, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Hủy'))),
        FilledButton(onPressed: _saving ? null : _save, child: Text(tr(_saving ? 'Đang lưu…' : 'Lưu'))),
      ],
    );
  }
}
