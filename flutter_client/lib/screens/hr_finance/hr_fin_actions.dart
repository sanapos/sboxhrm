import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../models/hr_finance.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../business_trip_case_detail_screen.dart';
import 'hr_fin_common.dart';

// ─── Khung hộp thoại chung ─────────────────────────────────────────

Future<T?> hrFinDialog<T>(BuildContext context,
    {required String title, String? subtitle, required Widget Function(BuildContext ctx, StateSetter setS) body, double width = 520}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: SboxRadius.lgAll),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(title), style: SboxType.titleStyle()),
                    if (subtitle != null) Text(tr(subtitle), style: SboxType.smallStyle()),
                  ]),
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), child: body(ctx, setS))),
          ]),
        ),
      ),
    ),
  );
}

InputDecoration hrFinInput(String label, {String? hint, String? suffix, String? helper}) => InputDecoration(
      labelText: tr(label),
      hintText: hint == null ? null : tr(hint),
      suffixText: suffix,
      helperText: helper == null ? null : tr(helper),
      helperMaxLines: 3,
      isDense: true,
      border: OutlineInputBorder(borderRadius: SboxRadius.mdAll),
    );

double? hrFinParseMoney(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : double.tryParse(digits);
}

/// Định dạng 1.000.000 khi gõ.
class HrFinMoneyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    final t = buf.toString();
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

String hrFinMoneyText(double v) => HrFinMoneyFormatter()
    .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: v.round().toString()))
    .text;

/// Hai lựa chọn xử lý tiền: trừ/cộng lương hoặc tiền mặt.
class HrFinSettlementPicker extends StatelessWidget {
  const HrFinSettlementPicker({super.key, required this.value, required this.onChanged, required this.isPenalty});
  final String value;
  final ValueChanged<String> onChanged;
  final bool isPenalty;

  @override
  Widget build(BuildContext context) {
    Widget opt(String v, IconData icon, String title, String desc) {
      final sel = value == v;
      return Expanded(
        child: InkWell(
          borderRadius: SboxRadius.mdAll,
          onTap: () => onChanged(v),
          child: Container(
            padding: const EdgeInsets.all(SboxSpace.md),
            decoration: BoxDecoration(
              borderRadius: SboxRadius.mdAll,
              color: sel ? SboxColors.brand50 : SboxColors.white,
              border: Border.all(color: sel ? SboxColors.brand500 : SboxColors.border, width: sel ? 1.5 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 18, color: sel ? SboxColors.brand600 : SboxColors.slate500),
                const SizedBox(width: 6),
                Expanded(child: Text(tr(title), style: SboxType.bodyStrong(sel ? SboxColors.brand800 : SboxColors.text))),
              ]),
              const SizedBox(height: 4),
              Text(tr(desc), style: SboxType.captionStyle()),
            ]),
          ),
        ),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      opt('salary', Icons.receipt_long_outlined, isPenalty ? 'Trừ vào lương' : 'Cộng vào lương',
          'Tự động vào bảng lương kỳ này, không tạo phiếu quỹ'),
      const SizedBox(width: SboxSpace.sm),
      opt('cash', Icons.payments_outlined, isPenalty ? 'Thu tiền mặt' : 'Chi tiền mặt',
          isPenalty ? 'Tạo phiếu thu chờ thu, bảng lương bỏ qua' : 'Tạo phiếu chi chờ chi, bảng lương bỏ qua'),
    ]);
  }
}

// ─── Thực thi thao tác trên một khoản ─────────────────────────────

class HrFinActions {
  HrFinActions(this.api, this.settings);
  final ApiService api;
  HrFinSettings settings;

  /// Chạy thao tác chính của khoản (duyệt / chi / xử lý khiếu nại / mở hồ sơ công tác).
  Future<bool> run(BuildContext context, HrFinItem it) async {
    if (it.isTrip) return _openTrip(context, it);
    switch (it.action) {
      case 'resolve':
        return resolveDispute(context, it);
      case 'approve':
        return switch (it.kind) {
          'advance' => approveAdvance(context, it),
          'bonus' || 'penalty' => approveReward(context, it),
          'ticket' => approveTicket(context, it),
          _ => Future.value(false),
        };
      case 'pay':
        return switch (it.kind) {
          'advance' => payAdvance(context, it),
          'cash' => payCash(context, it),
          _ => Future.value(false),
        };
    }
    return false;
  }

  Future<bool> _openTrip(BuildContext context, HrFinItem it) async {
    final caseId = it.caseId;
    if (caseId == null) return false;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessTripCaseDetailScreen(caseId: caseId)));
    return true;
  }

  Future<bool> approveAdvance(BuildContext context, HrFinItem it) async {
    final amount = TextEditingController(text: hrFinMoneyText(it.amount));
    final reason = TextEditingController();
    final res = await hrFinDialog<String>(context,
        title: 'Duyệt ứng lương',
        subtitle: '${it.employeeName} · ${it.subtitle ?? ''}',
        body: (ctx, setS) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(it.title, style: SboxType.bodyStyle()),
              const SizedBox(height: SboxSpace.md),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                inputFormatters: [HrFinMoneyFormatter()],
                decoration: hrFinInput('Số tiền duyệt', suffix: '₫', helper: 'Có thể duyệt thấp hơn số xin'),
              ),
              const SizedBox(height: SboxSpace.md),
              TextField(controller: reason, decoration: hrFinInput('Lý do từ chối (nếu từ chối)')),
              const SizedBox(height: SboxSpace.lg),
              Row(children: [
                Expanded(child: SboxButton.danger(label: 'Từ chối', onPressed: () => Navigator.pop(ctx, 'reject'))),
                const SizedBox(width: SboxSpace.sm),
                Expanded(child: SboxButton(label: 'Duyệt', icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx, 'approve'))),
              ]),
            ]));
    if (res == null || !context.mounted) return false;
    if (res == 'reject' && reason.text.trim().isEmpty) {
      hrFinToast(context, 'Vui lòng nhập lý do từ chối', error: true);
      return false;
    }
    final v = hrFinParseMoney(amount.text);
    final r = await api.approveAdvanceRequest(
      requestId: it.id,
      isApproved: res == 'approve',
      rejectionReason: res == 'reject' ? reason.text.trim() : null,
      approvedAmount: res == 'approve' && v != null && v < it.amount ? v : null,
    );
    return context.mounted && hrFinResult(context, r, res == 'approve' ? 'Đã duyệt ứng lương' : 'Đã từ chối');
  }

  Future<bool> payAdvance(BuildContext context, HrFinItem it) async {
    final method = await _pickPayMethod(context, 'Chi ứng lương', '${it.employeeName} · ${hrFinMoney(it.amount)}');
    if (method == null || !context.mounted) return false;
    final r = await api.payAdvanceRequest(it.id, paymentMethod: method);
    return context.mounted && hrFinResult(context, r, 'Đã chi ứng lương');
  }

  Future<bool> payCash(BuildContext context, HrFinItem it) async {
    final method = await _pickPayMethod(context, it.isIn ? 'Chi tiền' : 'Thu tiền', '${it.title} · ${hrFinMoney(it.amount)}');
    if (method == null || !context.mounted) return false;
    final r = await api.updateCashTransactionStatus(it.id, {'status': 'Completed', 'isPaid': true, 'paymentMethod': method});
    return context.mounted && hrFinResult(context, r, 'Đã ghi nhận thanh toán');
  }

  Future<String?> _pickPayMethod(BuildContext context, String title, String subtitle) {
    var method = 'Cash';
    return hrFinDialog<String>(context,
        title: title,
        subtitle: subtitle,
        width: 420,
        body: (ctx, setS) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HrFinSegment<String>(
                value: method,
                options: const {'Cash': 'Tiền mặt', 'BankTransfer': 'Chuyển khoản'},
                onChanged: (v) => setS(() => method = v),
              ),
              const SizedBox(height: SboxSpace.lg),
              SboxButton.pay(label: 'Xác nhận', icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx, method)),
            ]));
  }

  Future<bool> approveReward(BuildContext context, HrFinItem it) async {
    final isPenalty = it.kind == 'penalty';
    var settlement = it.settlement ?? (isPenalty ? settings.penaltyDefaultSettlement : settings.bonusDefaultSettlement);
    final res = await hrFinDialog<String>(context,
        title: isPenalty ? 'Duyệt phiếu phạt' : 'Duyệt phiếu thưởng',
        subtitle: '${it.employeeName} · ${hrFinMoney(it.amount)}',
        body: (ctx, setS) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(it.title, style: SboxType.bodyStrong()),
              if (it.subtitle != null) Text(it.subtitle!, style: SboxType.smallStyle()),
              if (it.evidence.isNotEmpty) ...[const SizedBox(height: SboxSpace.sm), HrFinEvidenceStrip(urls: it.evidence)],
              const SizedBox(height: SboxSpace.lg),
              Text(tr('Xử lý tiền'), style: SboxType.captionStyle()),
              const SizedBox(height: SboxSpace.xs),
              HrFinSettlementPicker(value: settlement, isPenalty: isPenalty, onChanged: (v) => setS(() => settlement = v)),
              const SizedBox(height: SboxSpace.lg),
              Row(children: [
                Expanded(child: SboxButton.secondary(label: 'Hủy phiếu', onPressed: () => Navigator.pop(ctx, 'cancel'))),
                const SizedBox(width: SboxSpace.sm),
                Expanded(child: SboxButton(label: 'Duyệt', icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx, 'approve'))),
              ]),
            ]));
    if (res == null || !context.mounted) return false;
    if (res == 'cancel') {
      final ok = await SboxDialogs.confirm(context, title: 'Hủy phiếu này?', danger: true, confirmLabel: 'Hủy phiếu');
      if (!ok || !context.mounted) return false;
      final r = await api.updateTransactionStatus(it.id, 'Cancelled');
      return context.mounted && hrFinResult(context, r, 'Đã hủy phiếu');
    }
    final r = await api.updateTransactionStatus(it.id, 'Completed', disbursementMode: settlement == 'cash' ? 'Cash' : 'Salary');
    return context.mounted && hrFinResult(context, r, 'Đã duyệt');
  }

  Future<bool> approveTicket(BuildContext context, HrFinItem it) async {
    final reason = TextEditingController();
    final res = await hrFinDialog<String>(context,
        title: 'Duyệt phiếu phạt',
        subtitle: '${it.employeeName} · ${it.code ?? ''}',
        body: (ctx, setS) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${it.title} · ${hrFinDate(it.date)}', style: SboxType.bodyStrong()),
              Text(hrFinMoney(it.amount), style: SboxType.moneyStyle(size: SboxType.title, c: SboxColors.dangerText)),
              if (it.subtitle != null) Text(it.subtitle!, style: SboxType.smallStyle()),
              const SizedBox(height: SboxSpace.md),
              TextField(controller: reason, decoration: hrFinInput('Lý do hủy (nếu hủy)')),
              const SizedBox(height: SboxSpace.lg),
              Row(children: [
                Expanded(child: SboxButton.secondary(label: 'Hủy phiếu', onPressed: () => Navigator.pop(ctx, 'cancel'))),
                const SizedBox(width: SboxSpace.sm),
                Expanded(child: SboxButton(label: 'Duyệt', icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx, 'approve'))),
              ]),
            ]));
    if (res == null || !context.mounted) return false;
    final r = res == 'approve'
        ? await api.approvePenaltyTicket(it.id)
        : await api.cancelPenaltyTicket(it.id, reason: reason.text.trim());
    return context.mounted && hrFinResult(context, r, res == 'approve' ? 'Đã duyệt phiếu phạt' : 'Đã hủy phiếu phạt');
  }

  Future<bool> resolveDispute(BuildContext context, HrFinItem it) async {
    final response = TextEditingController();
    final res = await hrFinDialog<bool>(context,
        title: 'Xử lý khiếu nại',
        subtitle: '${it.employeeName} · ${hrFinKindLabel(it.kind)} ${hrFinMoney(it.amount)}',
        body: (ctx, setS) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(it.title, style: SboxType.bodyStrong()),
              const SizedBox(height: SboxSpace.sm),
              Container(
                padding: const EdgeInsets.all(SboxSpace.md),
                decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: SboxRadius.mdAll),
                child: Text('“${it.disputeReason ?? ''}”', style: SboxType.bodyStyle(SboxColors.warningText)),
              ),
              if (it.evidence.isNotEmpty) ...[const SizedBox(height: SboxSpace.sm), HrFinEvidenceStrip(urls: it.evidence)],
              const SizedBox(height: SboxSpace.md),
              TextField(controller: response, maxLines: 2, decoration: hrFinInput('Phản hồi cho nhân viên')),
              const SizedBox(height: SboxSpace.lg),
              Row(children: [
                Expanded(child: SboxButton.secondary(label: 'Giữ nguyên phiếu', onPressed: () => Navigator.pop(ctx, false))),
                const SizedBox(width: SboxSpace.sm),
                Expanded(child: SboxButton(label: 'Chấp nhận · hủy phiếu', onPressed: () => Navigator.pop(ctx, true))),
              ]),
            ]));
    if (res == null || !context.mounted) return false;
    final r = await api.hrFinResolveDispute(it.kind, it.id, accept: res, response: response.text.trim());
    return context.mounted && hrFinResult(context, r, res ? 'Đã chấp nhận khiếu nại' : 'Đã giữ nguyên phiếu');
  }

  /// Nhân viên khiếu nại phiếu phạt.
  Future<bool> dispute(BuildContext context, HrFinItem it) async {
    final reason = TextEditingController();
    final ok = await hrFinDialog<bool>(context,
        title: 'Khiếu nại phiếu phạt',
        subtitle: '${it.title} · ${hrFinMoney(it.amount)}',
        width: 460,
        body: (ctx, setS) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: reason,
                maxLines: 4,
                autofocus: true,
                decoration: hrFinInput('Lý do khiếu nại', hint: 'VD: Hôm đó em đi công tác, đã báo quản lý…'),
              ),
              const SizedBox(height: SboxSpace.lg),
              SboxButton(label: 'Gửi khiếu nại', icon: Icons.send_rounded, onPressed: () => Navigator.pop(ctx, true)),
            ]));
    if (ok != true || !context.mounted) return false;
    final r = await api.hrFinDispute(it.kind, it.id, reason.text.trim());
    return context.mounted && hrFinResult(context, r, 'Đã gửi khiếu nại, quản lý sẽ phản hồi');
  }

  /// Tạo nhanh thưởng / phạt có bằng chứng.
  Future<bool> createReward(BuildContext context, List<HrFinPerson> people, {String type = 'Bonus', HrFinPerson? preset}) async {
    HrFinPerson? person = preset;
    var t = type;
    var settlement = t == 'Penalty' ? settings.penaltyDefaultSettlement : settings.bonusDefaultSettlement;
    var approveNow = true;
    var evidence = <String>[];
    var uploading = false;
    var saving = false;
    final amount = TextEditingController();
    final desc = TextEditingController();
    final note = TextEditingController();
    final quick = t == 'Bonus'
        ? const ['Hoàn thành xuất sắc', 'Doanh số vượt chỉ tiêu', 'Chuyên cần', 'Khách hàng khen']
        : const ['Vi phạm nội quy', 'Làm hỏng tài sản', 'Thiếu hụt quỹ', 'Không đồng phục'];
    final done = await hrFinDialog<bool>(context,
        title: 'Tạo thưởng / phạt',
        width: 560,
        body: (ctx, setS) {
          final isPenalty = t == 'Penalty';
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HrFinSegment<String>(
              value: t,
              options: const {'Bonus': '🎁 Thưởng', 'Penalty': '⚠️ Phạt'},
              onChanged: (v) => setS(() {
                t = v;
                settlement = v == 'Penalty' ? settings.penaltyDefaultSettlement : settings.bonusDefaultSettlement;
              }),
            ),
            const SizedBox(height: SboxSpace.md),
            Autocomplete<HrFinPerson>(
              initialValue: TextEditingValue(text: person?.name ?? ''),
              displayStringForOption: (p) => p.name,
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                return people.where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || (p.code ?? '').toLowerCase().contains(q)).take(30);
              },
              onSelected: (p) => setS(() => person = p),
              fieldViewBuilder: (c, ctrl, focus, submit) =>
                  TextField(controller: ctrl, focusNode: focus, decoration: hrFinInput('Nhân viên', hint: 'Gõ tên hoặc mã')),
            ),
            const SizedBox(height: SboxSpace.md),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [HrFinMoneyFormatter()],
              decoration: hrFinInput('Số tiền', suffix: '₫'),
            ),
            const SizedBox(height: SboxSpace.md),
            TextField(controller: desc, decoration: hrFinInput('Nội dung')),
            const SizedBox(height: SboxSpace.xs),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final q in (isPenalty
                  ? const ['Vi phạm nội quy', 'Làm hỏng tài sản', 'Thiếu hụt quỹ', 'Không đồng phục']
                  : quick))
                ActionChip(label: Text(q, style: SboxType.captionStyle()), onPressed: () => setS(() => desc.text = q)),
            ]),
            const SizedBox(height: SboxSpace.md),
            TextField(controller: note, decoration: hrFinInput('Ghi chú (không bắt buộc)')),
            const SizedBox(height: SboxSpace.md),
            Text(tr('Xử lý tiền'), style: SboxType.captionStyle()),
            const SizedBox(height: SboxSpace.xs),
            HrFinSettlementPicker(value: settlement, isPenalty: isPenalty, onChanged: (v) => setS(() => settlement = v)),
            const SizedBox(height: SboxSpace.md),
            Row(children: [
              Text(tr('Bằng chứng'), style: SboxType.captionStyle()),
              const Spacer(),
              SboxButton.ghost(
                label: uploading ? 'Đang tải…' : 'Thêm ảnh / PDF',
                icon: Icons.attach_file_rounded,
                size: SboxButtonSize.sm,
                onPressed: uploading
                    ? null
                    : () async {
                        setS(() => uploading = true);
                        final urls = await hrFinPickAndUpload(ctx, api);
                        setS(() {
                          uploading = false;
                          evidence = [...evidence, ...urls];
                        });
                      },
              ),
            ]),
            HrFinEvidenceStrip(urls: evidence, onRemove: (u) => setS(() => evidence = evidence.where((x) => x != u).toList())),
            const SizedBox(height: SboxSpace.sm),
            CheckboxListTile(
              value: approveNow,
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(tr('Duyệt luôn'), style: SboxType.bodyStyle()),
              subtitle: Text(tr('Bỏ chọn để gửi vào hàng chờ duyệt'), style: SboxType.captionStyle()),
              onChanged: (v) => setS(() => approveNow = v ?? true),
            ),
            const SizedBox(height: SboxSpace.sm),
            SboxButton(
              label: isPenalty ? 'Tạo phiếu phạt' : 'Tạo phiếu thưởng',
              icon: Icons.check_rounded,
              loading: saving,
              onPressed: () async {
                final v = hrFinParseMoney(amount.text);
                if (person == null) return hrFinToast(ctx, 'Chọn nhân viên', error: true);
                if (v == null || v <= 0) return hrFinToast(ctx, 'Nhập số tiền', error: true);
                setS(() => saving = true);
                final r = await api.createHrFinReward({
                  'employeeId': person!.id,
                  'type': t,
                  'amount': v,
                  'description': desc.text.trim(),
                  'note': note.text.trim(),
                  'settlement': settlement,
                  'evidenceUrls': evidence,
                  'approveNow': approveNow,
                });
                setS(() => saving = false);
                if (!ctx.mounted) return;
                if (hrFinResult(ctx, r, isPenalty ? 'Đã tạo phiếu phạt' : 'Đã tạo phiếu thưởng')) Navigator.pop(ctx, true);
              },
            ),
          ]);
        });
    return done == true;
  }

  /// Xin ứng lương (nhân viên tự xin, hoặc quản lý tạo hộ khi truyền [people]).
  Future<bool> requestAdvance(BuildContext context, {List<HrFinPerson>? people}) async {
    HrFinPerson? person;
    var month = DateTime(DateTime.now().year, DateTime.now().month);
    var installments = 1;
    HrFinAdvanceLimit? limit;
    var loadingLimit = false;
    var saving = false;
    final amount = TextEditingController();
    final reason = TextEditingController();

    Future<void> loadLimit(StateSetter setS) async {
      if (people != null && person == null) return;
      setS(() => loadingLimit = true);
      final r = await api.getAdvanceLimit(employeeId: person?.id, year: month.year, month: month.month);
      setS(() {
        loadingLimit = false;
        limit = r['isSuccess'] == true && r['data'] is Map ? HrFinAdvanceLimit.fromJson(Map<String, dynamic>.from(r['data'] as Map)) : null;
      });
    }

    var first = true;
    final done = await hrFinDialog<bool>(context,
        title: people == null ? 'Xin ứng lương' : 'Tạo ứng lương cho nhân viên',
        width: 500,
        body: (ctx, setS) {
          if (first) {
            first = false;
            WidgetsBinding.instance.addPostFrameCallback((_) => loadLimit(setS));
          }
          final l = limit;
          final v = hrFinParseMoney(amount.text) ?? 0;
          final perPeriod = installments > 1 ? (v / installments).floorToDouble() : v;
          final over = l?.remaining != null && perPeriod > l!.remaining!;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (people != null) ...[
              Autocomplete<HrFinPerson>(
                displayStringForOption: (p) => p.name,
                optionsBuilder: (t) {
                  final q = t.text.trim().toLowerCase();
                  return people.where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || (p.code ?? '').toLowerCase().contains(q)).take(30);
                },
                onSelected: (p) {
                  person = p;
                  loadLimit(setS);
                },
                fieldViewBuilder: (c, ctrl, focus, submit) =>
                    TextField(controller: ctrl, focusNode: focus, decoration: hrFinInput('Nhân viên', hint: 'Gõ tên hoặc mã')),
              ),
              const SizedBox(height: SboxSpace.md),
            ],
            _LimitCard(limit: l, loading: loadingLimit, month: month),
            const SizedBox(height: SboxSpace.md),
            TextField(
              controller: amount,
              autofocus: people == null,
              keyboardType: TextInputType.number,
              inputFormatters: [HrFinMoneyFormatter()],
              onChanged: (_) => setS(() {}),
              decoration: hrFinInput('Số tiền xin ứng', suffix: '₫'),
            ),
            if (l?.remaining != null) ...[
              const SizedBox(height: SboxSpace.xs),
              Wrap(spacing: 6, children: [
                for (final pct in const [25, 50, 100])
                  ActionChip(
                    label: Text(pct == 100 ? 'Tối đa' : '$pct%', style: SboxType.captionStyle()),
                    onPressed: () => setS(() => amount.text = hrFinMoneyText((l!.remaining! * pct / 100 / 10000).floorToDouble() * 10000)),
                  ),
              ]),
            ],
            const SizedBox(height: SboxSpace.md),
            Row(children: [
              Expanded(
                child: InputDecorator(
                  decoration: hrFinInput('Trừ vào lương kỳ'),
                  child: Row(children: [
                    InkWell(onTap: () => setS(() => month = DateTime(month.year, month.month - 1)), child: const Icon(Icons.chevron_left, size: 18)),
                    Expanded(child: Text(hrFinMonthLabel(month), textAlign: TextAlign.center, style: SboxType.bodyStrong())),
                    InkWell(onTap: () => setS(() => month = DateTime(month.year, month.month + 1)), child: const Icon(Icons.chevron_right, size: 18)),
                  ]),
                ),
              ),
              const SizedBox(width: SboxSpace.sm),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: installments,
                  decoration: hrFinInput('Trả góp'),
                  items: [
                    for (var i = 1; i <= (l?.maxInstallments ?? 3); i++)
                      DropdownMenuItem(value: i, child: Text(i == 1 ? 'Trừ 1 lần' : '$i kỳ')),
                  ],
                  onChanged: (x) => setS(() => installments = x ?? 1),
                ),
              ),
            ]),
            if (installments > 1 && v > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Mỗi kỳ trừ khoảng ${hrFinMoney(perPeriod)}', style: SboxType.captionStyle()),
              ),
            if (over)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Vượt hạn mức còn lại ${hrFinMoney(l.remaining)}', style: SboxType.captionStyle(SboxColors.dangerText)),
              ),
            const SizedBox(height: SboxSpace.md),
            TextField(controller: reason, maxLines: 2, decoration: hrFinInput('Lý do')),
            const SizedBox(height: SboxSpace.lg),
            SboxButton(
              label: 'Gửi yêu cầu',
              icon: Icons.send_rounded,
              loading: saving,
              onPressed: over
                  ? null
                  : () async {
                      if (people != null && person == null) return hrFinToast(ctx, 'Chọn nhân viên', error: true);
                      if (v <= 0) return hrFinToast(ctx, 'Nhập số tiền', error: true);
                      setS(() => saving = true);
                      final r = await api.createAdvanceRequestV2({
                        'amount': v,
                        'reason': reason.text.trim(),
                        'forMonth': month.month,
                        'forYear': month.year,
                        'installmentCount': installments,
                        if (person != null) 'employeeId': person!.id,
                      });
                      setS(() => saving = false);
                      if (!ctx.mounted) return;
                      if (hrFinResult(ctx, r, 'Đã gửi yêu cầu ứng lương')) Navigator.pop(ctx, true);
                    },
            ),
          ]);
        });
    return done == true;
  }

  /// Chi tiết một khoản.
  Future<bool> showDetail(BuildContext context, HrFinItem it, {required bool canAct, bool canDispute = false, int disputeWindowDays = 7}) async {
    final (statusLabel, statusTone) = hrFinStatus(it);
    final r = await hrFinDialog<String>(context,
        title: hrFinKindLabel(it.kind),
        subtitle: it.code,
        width: 480,
        body: (ctx, setS) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                HrFinAvatar(name: it.employeeName, photo: it.photoUrl, size: 44),
                const SizedBox(width: SboxSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.employeeName, style: SboxType.bodyStrong()),
                    if (it.department != null) Text(it.department!, style: SboxType.captionStyle()),
                  ]),
                ),
                SboxStatusChip(label: statusLabel, tone: statusTone, dot: true),
              ]),
              const SizedBox(height: SboxSpace.lg),
              Text('${it.isIn ? '+' : '−'}${hrFinMoney(it.amount)}',
                  style: SboxType.moneyStyle(size: SboxType.display, c: it.isIn ? SboxColors.successText : SboxColors.dangerText)),
              const SizedBox(height: SboxSpace.sm),
              Text(it.title, style: SboxType.bodyStrong()),
              if (it.subtitle != null) Text(it.subtitle!, style: SboxType.smallStyle()),
              const SizedBox(height: SboxSpace.sm),
              Text('Ngày: ${hrFinDate(it.date)}'
                  '${it.settlement == 'salary' ? ' · Trừ/cộng vào lương' : it.settlement == 'cash' ? ' · Tiền mặt' : ''}',
                  style: SboxType.captionStyle()),
              if (it.evidence.isNotEmpty) ...[
                const SizedBox(height: SboxSpace.md),
                Text(tr('Bằng chứng'), style: SboxType.captionStyle()),
                const SizedBox(height: SboxSpace.xs),
                HrFinEvidenceStrip(urls: it.evidence, size: 72),
              ],
              if (it.disputeStatus > 0) ...[
                const SizedBox(height: SboxSpace.md),
                Container(
                  padding: const EdgeInsets.all(SboxSpace.md),
                  decoration: BoxDecoration(
                      color: it.disputeStatus == 1 ? SboxColors.warningSoft : SboxColors.slate50, borderRadius: SboxRadius.mdAll),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                        switch (it.disputeStatus) {
                          1 => 'Đang khiếu nại',
                          2 => 'Khiếu nại được chấp nhận',
                          _ => 'Khiếu nại không được chấp nhận',
                        },
                        style: SboxType.bodyStrong()),
                    if (it.disputeReason != null) Text('Lý do: ${it.disputeReason}', style: SboxType.smallStyle()),
                    if (it.disputeResponse != null && it.disputeResponse!.isNotEmpty)
                      Text('Phản hồi: ${it.disputeResponse}', style: SboxType.smallStyle()),
                  ]),
                ),
              ],
              const SizedBox(height: SboxSpace.lg),
              if (canAct && (it.action != null || it.isTrip))
                SboxButton(
                  label: it.isTrip ? 'Mở hồ sơ công tác' : hrFinActionLabel(it.action),
                  kind: it.action == 'pay' ? SboxButtonKind.pay : SboxButtonKind.primary,
                  onPressed: () => Navigator.pop(ctx, 'act'),
                ),
              if (canAct && it.kind != 'cash' && !it.isTrip && it.kind != 'advance') ...[
                const SizedBox(height: SboxSpace.sm),
                SboxButton.secondary(label: 'Cập nhật bằng chứng', icon: Icons.attach_file_rounded, onPressed: () => Navigator.pop(ctx, 'evidence')),
              ],
              if (canDispute && it.isPenalty && it.disputeStatus == 0 && !it.isCancelled)
                SboxButton.secondary(label: 'Khiếu nại', icon: Icons.feedback_outlined, onPressed: () => Navigator.pop(ctx, 'dispute')),
            ]));
    if (!context.mounted) return false;
    switch (r) {
      case 'act':
        return run(context, it);
      case 'dispute':
        return dispute(context, it);
      case 'evidence':
        final urls = await hrFinPickAndUpload(context, api);
        if (urls.isEmpty || !context.mounted) return false;
        final res = await api.setHrFinEvidence(it.kind, it.id, [...it.evidence, ...urls]);
        return context.mounted && hrFinResult(context, res, 'Đã cập nhật bằng chứng');
    }
    return false;
  }
}

class _LimitCard extends StatelessWidget {
  const _LimitCard({required this.limit, required this.loading, required this.month});
  final HrFinAdvanceLimit? limit;
  final bool loading;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final l = limit;
    return Container(
      padding: const EdgeInsets.all(SboxSpace.md),
      decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: SboxRadius.mdAll, border: Border.all(color: SboxColors.brand100)),
      child: loading
          ? const SizedBox(height: 40, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          : l == null || l.limit == null
              ? Text(tr('Không giới hạn hạn mức ứng cho kỳ này'), style: SboxType.smallStyle(SboxColors.brand800))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Hạn mức ${hrFinMonthLabel(month).toLowerCase()}', style: SboxType.captionStyle(SboxColors.brand800))),
                    Text('Còn ${hrFinMoney(l.remaining)}', style: SboxType.bodyStrong(SboxColors.brand800)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: SboxRadius.pillAll,
                    child: LinearProgressIndicator(
                      value: l.limit! <= 0 ? 0 : (l.used / l.limit!).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      backgroundColor: SboxColors.white,
                      color: SboxColors.brand500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'Đã ứng ${hrFinMoney(l.used)} / ${hrFinMoney(l.limit)}'
                      '${l.limitPercent != null && l.monthlySalary != null ? ' (${l.limitPercent!.toStringAsFixed(0)}% lương ~${hrFinMoney(l.monthlySalary)})' : ''}',
                      style: SboxType.captionStyle()),
                ]),
    );
  }
}
