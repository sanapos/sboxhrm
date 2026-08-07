import 'package:flutter/material.dart';

import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Sheet trừ buổi gói gym / liệu trình.
Future<bool?> showPosSessionRedeemSheet(
  BuildContext context, {
  required String customerId,
  required String customerName,
  String? saleOrderId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _PosSessionRedeemSheet(
      customerId: customerId,
      customerName: customerName,
      saleOrderId: saleOrderId,
    ),
  );
}

class _PosSessionRedeemSheet extends StatefulWidget {
  const _PosSessionRedeemSheet({
    required this.customerId,
    required this.customerName,
    this.saleOrderId,
  });

  final String customerId;
  final String customerName;
  final String? saleOrderId;

  @override
  State<_PosSessionRedeemSheet> createState() => _PosSessionRedeemSheetState();
}

class _PosSessionRedeemSheetState extends State<_PosSessionRedeemSheet> {
  final _api = ApiService();
  bool _loading = true;
  bool _redeeming = false;
  String? _error;
  List<PosSessionBalanceDto> _balances = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosSessionBalances(customerId: widget.customerId);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _error = res['message']?.toString() ?? 'Không tải được gói buổi';
        _loading = false;
      });
      return;
    }
    setState(() {
      _balances = ((res['data'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => PosSessionBalanceDto.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.remainingSessions > 0)
          .toList();
      _loading = false;
    });
  }

  Future<void> _redeem(PosSessionBalanceDto b) async {
    if (_redeeming) return;
    setState(() => _redeeming = true);
    final res = await _api.redeemPosSessionBalance({
      'balanceId': b.id,
      'sessions': 1,
      if (widget.saleOrderId != null && widget.saleOrderId!.isNotEmpty)
        'saleOrderId': widget.saleOrderId,
      'note': 'Trừ buổi tại quầy',
    });
    if (!mounted) return;
    setState(() => _redeeming = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không trừ được buổi',
        message: res['message']?.toString() ?? 'Lỗi',
      );
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr('Trừ buổi — ${widget.customerName}'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(tr('Chọn gói còn buổi để trừ 1 lần'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Text(tr(_error!), textAlign: TextAlign.center),
                    TextButton(onPressed: _load, child: Text(tr('Thử lại'))),
                  ],
                ),
              )
            else if (_balances.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(tr('Khách chưa có gói buổi còn lại.\nBán gói (session pack) rồi thanh toán để cộng buổi.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _balances.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final b = _balances[i];
                    return Material(
                      color: PosTheme.kiotBlueLight,
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        title: Text(
                          tr(b.packageName),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(tr('${tr('Còn ')}${b.remainingSessions}/${b.totalSessions} buổi'
                          '${b.expiresAt != null ? ' · HSD ${b.expiresAt!.toLocal().toString().substring(0, 10)}' : ''}'),
                        ),
                        trailing: FilledButton(
                          onPressed: _redeeming ? null : () => _redeem(b),
                          child: Text(tr('Trừ 1')),
                        ),
                      ),
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
