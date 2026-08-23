import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/cash_transaction.dart';
import '../../utils/pos_vietqr_helper.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Hiển thị mã VietQR động theo số tiền.
class PosVietQrPaymentPanel extends StatefulWidget {
  const PosVietQrPaymentPanel({
    super.key,
    required this.accounts,
    required this.amount,
    this.preferredAccountId,
    this.description,
    this.title = 'VietQR thanh toán',
    this.lockAccountSelection = false,
    this.compact = false,
    this.onAccountChanged,
  });

  final List<BankAccount> accounts;
  final double amount;
  final String? preferredAccountId;
  final String? description;
  final String title;
  final bool lockAccountSelection;
  final bool compact;
  final ValueChanged<BankAccount>? onAccountChanged;

  @override
  State<PosVietQrPaymentPanel> createState() => _PosVietQrPaymentPanelState();
}

class _PosVietQrPaymentPanelState extends State<PosVietQrPaymentPanel> {
  late BankAccount? _account;
  final _money = NumberFormat('#,##0', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _account = PosVietQrHelper.resolveAccount(
      widget.accounts,
      preferredId: widget.preferredAccountId,
    );
  }

  @override
  void didUpdateWidget(covariant PosVietQrPaymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accounts != widget.accounts ||
        oldWidget.preferredAccountId != widget.preferredAccountId) {
      _account = PosVietQrHelper.resolveAccount(
        widget.accounts,
        preferredId: widget.preferredAccountId,
      );
    }
  }

  String? get _qrUrl {
    final acc = _account;
    if (acc == null || widget.amount <= 0) return null;
    return PosVietQrHelper.qrImageUrl(
      account: acc,
      amount: widget.amount,
      description: widget.description,
    );
  }

  @override
  Widget build(BuildContext context) {
    final acc = _account;
    if (acc == null || widget.accounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Text(tr('Chưa có tài khoản ngân hàng. Vào Thiết lập cửa hàng để thêm.'),
          style: TextStyle(fontSize: 12),
        ),
      );
    }

    final qrSize = widget.compact ? 160.0 : 220.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PosTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2, color: _kiotBlue, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr(widget.title),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text(tr('${_money.format(widget.amount)} đ'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kiotBlue,
                ),
              ),
            ],
          ),
          if (widget.accounts.length > 1 && !widget.lockAccountSelection) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: acc.id,
              isDense: true,
              decoration: InputDecoration(
                labelText: tr('Tài khoản nhận'),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: widget.accounts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        tr('${a.bankShortName ?? a.bankName} · ${a.accountNumber}'
                        '${a.isDefault ? ' (Mặc định)' : ''}'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id == null) return;
                setState(() {
                  _account = widget.accounts.firstWhere((a) => a.id == id);
                });
                widget.onAccountChanged?.call(_account!);
              },
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              tr('${acc.bankShortName ?? acc.bankName} · ${acc.accountNumber}'),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            Text(
              tr(acc.accountName),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: _qrUrl == null
                ? SizedBox(
                    width: qrSize,
                    height: qrSize,
                    child: const Center(child: CircularProgressIndicator()),
                  )
                : Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: _qrUrl!,
                      width: qrSize,
                      height: qrSize,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => SizedBox(
                        width: qrSize,
                        height: qrSize,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, __, ___) => SizedBox(
                        width: qrSize,
                        height: qrSize,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red),
                            SizedBox(height: 6),
                            Text(tr('Không tải được mã QR'), style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          if (widget.description != null && widget.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('Nội dung: ${widget.description!.trim()}'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dialog / full-screen VietQR.
Future<void> showPosVietQrPaymentDialog(
  BuildContext context, {
  required List<BankAccount> accounts,
  required double amount,
  String? preferredAccountId,
  String? description,
  String title = 'VietQR thanh toán',
  String dialogTitle = 'Quét VietQR thanh toán',
  bool lockAccountSelection = false,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(dialogTitle)),
      content: SizedBox(
        width: 320,
        child: PosVietQrPaymentPanel(
          accounts: accounts,
          amount: amount,
          preferredAccountId: preferredAccountId,
          description: description,
          title: title,
          lockAccountSelection: lockAccountSelection,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
      ],
    ),
  );
}
