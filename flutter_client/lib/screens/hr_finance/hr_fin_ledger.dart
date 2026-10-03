import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/hr_finance.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'hr_fin_actions.dart';
import 'hr_fin_common.dart';

/// Sổ tiền của một nhân viên: đã nhận, bị trừ, dư nợ ứng, dòng khoản theo thời gian.
class HrFinLedgerView extends StatelessWidget {
  const HrFinLedgerView({super.key, required this.ledger, required this.onTapItem, this.header, this.itemAction});
  final HrFinLedger ledger;
  final ValueChanged<HrFinItem> onTapItem;
  final Widget? header;
  final Widget? Function(HrFinItem it)? itemAction;

  @override
  Widget build(BuildContext context) {
    final l = ledger;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (header != null) ...[header!, const SizedBox(height: SboxSpace.md)],
      SboxKpiStrip(items: [
        SboxKpi(label: 'Thưởng', value: hrFinMoney(l.bonus), icon: Icons.card_giftcard_outlined, tone: SboxTone.success),
        SboxKpi(label: 'Phạt', value: hrFinMoney(l.penalty), icon: Icons.gavel_outlined, tone: SboxTone.danger),
        SboxKpi(label: 'Đã ứng', value: hrFinMoney(l.advance), icon: Icons.payments_outlined, tone: SboxTone.brand),
        SboxKpi(
            label: 'Còn nợ ứng',
            value: hrFinMoney(l.advanceOutstanding),
            icon: Icons.account_balance_outlined,
            tone: l.advanceOutstanding > 0 ? SboxTone.warning : SboxTone.neutral,
            note: 'Sẽ trừ ở các kỳ lương tới'),
      ], maxColumns: 4),
      const SizedBox(height: SboxSpace.md),
      HrFinItemList(
        emptyTitle: 'Chưa có khoản nào',
        emptyMessage: 'Ứng lương, thưởng, phạt, công tác trong kỳ sẽ hiện ở đây',
        children: [
          for (final it in l.items)
            HrFinItemTile(item: it, showEmployee: false, onTap: () => onTapItem(it), trailingAction: itemAction?.call(it)),
        ],
      ),
    ]);
  }
}

/// «Tiền của tôi» — nhân viên xem hạn mức ứng, thưởng/phạt, khiếu nại.
class HrFinMyMoney extends StatefulWidget {
  const HrFinMyMoney({super.key, required this.api, required this.actions});
  final ApiService api;
  final HrFinActions actions;

  @override
  State<HrFinMyMoney> createState() => _HrFinMyMoneyState();
}

class _HrFinMyMoneyState extends State<HrFinMyMoney> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  String? _error;
  HrFinLedger? _ledger;
  HrFinAdvanceLimit? _limit;
  int _disputeDays = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await widget.api.getHrFinMe(_month.year, _month.month);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && r['data'] is Map) {
        final d = Map<String, dynamic>.from(r['data'] as Map);
        _error = null;
        _ledger = d['ledger'] is Map ? HrFinLedger.fromJson(Map<String, dynamic>.from(d['ledger'] as Map)) : null;
        _limit = d['advanceLimit'] is Map ? HrFinAdvanceLimit.fromJson(Map<String, dynamic>.from(d['advanceLimit'] as Map)) : null;
        _disputeDays = (d['disputeWindowDays'] as num?)?.toInt() ?? 7;
      } else {
        _error = '${r['message'] ?? 'Không tải được dữ liệu'}';
      }
    });
  }

  bool _canDispute(HrFinItem it) =>
      it.isPenalty &&
      it.disputeStatus == 0 &&
      !it.isCancelled &&
      (_disputeDays <= 0 || DateTime.now().difference(it.date).inDays <= _disputeDays);

  Future<void> _open(HrFinItem it) async {
    final changed = await widget.actions.showDetail(context, it, canAct: false, canDispute: _canDispute(it), disputeWindowDays: _disputeDays);
    if (changed) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = _limit;
    final limitCard = SboxCard(
      title: 'Ứng lương ${hrFinMonthLabel(_month).toLowerCase()}',
      trailing: SboxButton(
        label: 'Xin ứng',
        icon: Icons.add_rounded,
        size: SboxButtonSize.sm,
        onPressed: () async {
          if (await widget.actions.requestAdvance(context)) _load();
        },
      ),
      child: l == null || l.limit == null
          ? Text(tr('Không giới hạn hạn mức ứng'), style: SboxType.smallStyle())
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(hrFinMoney(l.remaining), style: SboxType.moneyStyle(size: SboxType.display, c: SboxColors.brand700)),
                const SizedBox(width: 8),
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(tr('còn được ứng'), style: SboxType.smallStyle())),
              ]),
              const SizedBox(height: SboxSpace.sm),
              ClipRRect(
                borderRadius: SboxRadius.pillAll,
                child: LinearProgressIndicator(
                  value: l.limit! <= 0 ? 0 : (l.used / l.limit!).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: SboxColors.slate100,
                  color: SboxColors.brand500,
                ),
              ),
              const SizedBox(height: 6),
              Text('Đã ứng ${hrFinMoney(l.used)} / hạn mức ${hrFinMoney(l.limit)}', style: SboxType.captionStyle()),
            ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        HrFinMonthBar(month: _month, onChanged: (m) {
          setState(() => _month = m);
          _load();
        }),
        const Spacer(),
      ]),
      const SizedBox(height: SboxSpace.md),
      if (_loading && _ledger == null)
        const SboxLoading()
      else if (_error != null)
        SboxEmptyState(icon: Icons.person_off_outlined, title: _error!)
      else ...[
        limitCard,
        const SizedBox(height: SboxSpace.md),
        if (_ledger != null)
          HrFinLedgerView(
            ledger: _ledger!,
            onTapItem: _open,
            itemAction: (it) => _canDispute(it)
                ? SboxButton.ghost(
                    label: 'Khiếu nại',
                    size: SboxButtonSize.sm,
                    icon: Icons.feedback_outlined,
                    onPressed: () async {
                      if (await widget.actions.dispute(context, it)) _load();
                    })
                : null,
          ),
      ],
    ]);
  }
}
