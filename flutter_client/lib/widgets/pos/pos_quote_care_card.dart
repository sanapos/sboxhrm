import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import 'pos_quote_care_sheet.dart';
import 'pos_theme.dart';

/// Ghi chép tự động của hệ thống (tạo / sửa / trạng thái / thu tiền / hợp đồng) — không phải lần chăm sóc.
const posCareSystemKinds = {'Created', 'Edit', 'Status', 'Payment', 'Contract', 'Document'};

bool isPosCareActivity(PosQuoteActivity a) => !posCareSystemKinds.contains(a.kind);

IconData posCareKindIcon(String kind) => switch (kind) {
      'Call' => Icons.call,
      'Meeting' => Icons.groups_outlined,
      'FollowUp' => Icons.event_available_outlined,
      'Created' => Icons.request_quote_outlined,
      'Edit' => Icons.edit_outlined,
      'Status' => Icons.flag_outlined,
      'Payment' => Icons.payments_outlined,
      'Contract' => Icons.handshake_outlined,
      _ => Icons.sticky_note_2_outlined,
    };

Color posCareKindColor(String kind) => switch (kind) {
      'Call' => SboxColors.success,
      'Meeting' => SboxColors.brand600,
      'FollowUp' => SboxColors.warning,
      'Note' => PosTheme.kiotBlue,
      _ => SboxColors.slate400,
    };

/// «Hôm nay» / «Hôm qua» / «N ngày trước».
String posCareAgo(DateTime t) {
  final days = DateUtils.dateOnly(DateTime.now()).difference(DateUtils.dateOnly(t.toLocal())).inDays;
  if (days <= 0) return tr('Hôm nay');
  if (days == 1) return tr('Hôm qua');
  return tr('$days ngày trước');
}

/// Một dòng tóm tắt: số lần chăm sóc · lần cuối · hẹn sắp tới (danh sách mới nhất trước).
String posCareSummary(List<PosQuoteActivity> items) {
  final care = items.where(isPosCareActivity).toList();
  if (care.isEmpty) return tr('Chưa chăm sóc lần nào');
  final parts = <String>[tr('${care.length} lần chăm sóc')];
  final last = care.first.createdAt;
  if (last != null) parts.add(tr('lần cuối ${posCareAgo(last).toLowerCase()}'));
  final now = DateTime.now();
  final next = care
      .map((a) => a.nextFollowUpAt?.toLocal())
      .whereType<DateTime>()
      .where((d) => d.isAfter(now))
      .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
  if (next != null) parts.add(tr('hẹn ${DateFormat('dd/MM HH:mm').format(next)}'));
  final score = care.map((a) => a.score).whereType<int>().firstOrNull;
  if (score != null) parts.add(tr('tiềm năng $score/10'));
  return parts.join(' · ');
}

/// Một mốc trên dòng thời gian chăm sóc: loại, ngày giờ, người ghi, nội dung, điểm tiềm năng, lịch hẹn.
class PosCareTimelineTile extends StatelessWidget {
  const PosCareTimelineTile({
    super.key,
    required this.activity,
    this.quoteNo,
    this.isLast = false,
    this.trailing,
    this.maxLines,
  });

  final PosQuoteActivity activity;

  /// Lịch sử cả khách: ghi số báo giá của lần chăm sóc.
  final String? quoteNo;
  final bool isLast;
  final Widget? trailing;

  /// Thẻ tóm tắt: cắt nội dung dài.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final system = !isPosCareActivity(a);
    final color = posCareKindColor(a.kind);
    final who = (a.employeeName ?? a.createdBy ?? '').trim();
    final when = a.createdAt?.toLocal();
    final next = a.nextFollowUpAt?.toLocal();
    final overdue = next != null && next.isBefore(DateTime.now());
    final content = a.displayContent.trim();
    Widget chip(String text, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
        );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 30,
          child: Column(children: [
            const SizedBox(height: 2),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: color.withValues(alpha: system ? 0.10 : 0.16), shape: BoxShape.circle),
              child: Icon(posCareKindIcon(a.kind), size: 15, color: color),
            ),
            if (!isLast)
              Expanded(child: Container(width: 2, margin: const EdgeInsets.only(top: 2), color: SboxColors.slate200)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 2 : 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(
                    [if ((quoteNo ?? '').isNotEmpty) quoteNo!, tr(PosQuoteActivity.kindLabel(a.kind))].join(' · '),
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: system ? SboxColors.slate500 : SboxColors.slate900),
                  ),
                ),
                if (when != null)
                  Text(DateFormat('dd/MM/yyyy HH:mm').format(when),
                      style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
                if (trailing != null) trailing!,
              ]),
              Text(
                [if (when != null) posCareAgo(when), if (who.isNotEmpty) who].join(' · '),
                style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500),
              ),
              if (content.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(content,
                    maxLines: maxLines,
                    overflow: maxLines == null ? null : TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, height: 1.35, color: system ? SboxColors.slate500 : SboxColors.slate800)),
              ],
              if (a.score != null || next != null) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (a.score != null)
                    chip(tr('Tiềm năng ${a.score}/10'), PosQuoteActivity.scoreColor(a.score!)),
                  if (next != null)
                    overdue
                        ? chip(tr('Đã hẹn ${DateFormat('dd/MM HH:mm').format(next)}'), SboxColors.slate500)
                        : chip(tr('Hẹn ${DateFormat('dd/MM HH:mm').format(next)}'), SboxColors.warning),
                ]),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Thẻ «Chăm sóc khách» trên màn báo giá / hợp đồng: tóm tắt + 3 lần chăm sóc gần nhất,
/// nút ghi lần mới và xem toàn bộ dòng thời gian.
class PosQuoteCareCard extends StatefulWidget {
  const PosQuoteCareCard({
    super.key,
    required this.quoteId,
    required this.quoteNo,
    this.customerName,
    this.customerPhone,
  });

  final String quoteId;
  final String quoteNo;
  final String? customerName;
  final String? customerPhone;

  @override
  State<PosQuoteCareCard> createState() => PosQuoteCareCardState();
}

class PosQuoteCareCardState extends State<PosQuoteCareCard> {
  bool _loading = true;
  List<PosQuoteActivity> _items = const [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final res = await ApiService().getPosQuoteActivities(widget.quoteId);
    if (!mounted) return;
    final data = res['data'];
    final raw = data is Map ? (data['items'] as List? ?? const []) : const [];
    setState(() {
      _loading = false;
      _items = raw.whereType<Map>().map((e) => PosQuoteActivity.fromJson(Map<String, dynamic>.from(e))).toList();
    });
  }

  Future<void> open({bool form = false}) async {
    await showPosQuoteCareSheet(
      context,
      quoteId: widget.quoteId,
      quoteNo: widget.quoteNo,
      customerName: widget.customerName,
      customerPhone: widget.customerPhone,
      openForm: form,
    );
    if (mounted) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final care = _items.where(isPosCareActivity).toList();
    final shown = care.take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(tr(care.isEmpty ? 'Chăm sóc khách' : 'Chăm sóc khách (${care.length})'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          if (care.isNotEmpty) TextButton(onPressed: () => open(), child: Text(tr('Xem tất cả'))),
        ]),
        if (_loading)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else ...[
          Text(
            care.isEmpty
                ? tr('Chưa chăm sóc lần nào. Sau mỗi lần gọi / gặp khách, bấm «Ghi lần chăm sóc» để lưu lại đã trao đổi gì.')
                : posCareSummary(_items),
            style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600, height: 1.35),
          ),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < shown.length; i++)
              InkWell(
                onTap: () => open(),
                child: PosCareTimelineTile(activity: shown[i], isLast: i == shown.length - 1, maxLines: 2),
              ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => open(form: true),
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              label: Text(tr('Ghi lần chăm sóc')),
            ),
          ),
        ],
      ]),
    );
  }
}
