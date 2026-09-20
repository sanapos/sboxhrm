import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../utils/pos_html_print.dart';
import '../../widgets/notification_overlay.dart';
import 'pos_theme.dart';

Future<void> callPosQuoteCustomer(String? phone) async {
  final raw = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
  if (raw.isEmpty) {
    NotificationOverlayManager().showWarning(
      title: 'Chưa có SĐT',
      message: tr('Báo giá này chưa có số điện thoại khách'),
    );
    return;
  }
  final uri = Uri(scheme: 'tel', path: raw);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    NotificationOverlayManager().showError(
      title: 'Không gọi được',
      message: raw,
    );
  }
}

Future<void> printPosQuoteSlip(
  BuildContext context, {
  required String quoteId,
  PosQuote? quote,
  bool includeImages = false,
}) async {
  final api = ApiService();
  PosQuote? q = quote;
  if (q == null || q.documents.isEmpty) {
    final res = await api.getPosQuote(quoteId);
    if (res['isSuccess'] == true && res['data'] is Map) {
      q = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
    }
  }
  var html = q?.quoteSlip?.htmlContent ?? '';
  var title = q?.quoteSlip?.title ?? 'BÁO GIÁ';
  if (html.trim().isEmpty || includeImages) {
    final preview = await api.previewPosQuoteDocument(
      quoteId,
      'Quote',
      includeImages: includeImages,
    );
    if (preview['isSuccess'] == true && preview['data'] is Map) {
      final data = Map<String, dynamic>.from(preview['data'] as Map);
      html = (data['htmlContent'] ?? data['HtmlContent'] ?? '').toString();
      title = (data['title'] ?? data['Title'] ?? title).toString();
    }
  }
  if (!context.mounted) return;
  if (html.trim().isEmpty) {
    NotificationOverlayManager().showError(
      title: 'Chưa có phiếu',
      message: tr('Không tạo được bảng báo giá'),
    );
    return;
  }
  await showPosHtmlPrintDialog(context, title: title, htmlDocument: html);
}

Future<void> showPosQuoteCareSheet(
  BuildContext context, {
  required String quoteId,
  required String quoteNo,
  String? customerName,
  String? customerPhone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PosQuoteCareSheet(
      quoteId: quoteId,
      quoteNo: quoteNo,
      customerName: customerName,
      customerPhone: customerPhone,
    ),
  );
}

class _PosQuoteCareSheet extends StatefulWidget {
  const _PosQuoteCareSheet({
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
  State<_PosQuoteCareSheet> createState() => _PosQuoteCareSheetState();
}

class _PosQuoteCareSheetState extends State<_PosQuoteCareSheet> {
  final _api = ApiService();
  final _note = TextEditingController();
  String _kind = 'Note';
  DateTime? _followUp;
  bool _loading = true;
  bool _saving = false;
  List<PosQuoteActivity> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosQuoteActivities(widget.quoteId);
    if (!mounted) return;
    final data = res['data'];
    final raw = data is Map ? (data['items'] as List? ?? []) : <dynamic>[];
    setState(() {
      _loading = false;
      _items = raw
          .whereType<Map>()
          .map((e) => PosQuoteActivity.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  Future<void> _add() async {
    final text = _note.text.trim();
    if (text.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu nội dung',
        message: tr('Nhập nội dung làm việc với khách'),
      );
      return;
    }
    setState(() => _saving = true);
    final res = await _api.createPosQuoteActivity(
      widget.quoteId,
      kind: _kind,
      content: text,
      nextFollowUpAt: _kind == 'FollowUp' ? _followUp : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: res['message']?.toString() ?? tr('Ghi lịch thất bại'),
      );
      return;
    }
    _note.clear();
    _followUp = null;
    NotificationOverlayManager().showSuccess(
      title: 'Đã ghi',
      message: tr('Đã thêm vào lịch chăm sóc khách'),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${tr('Lịch CSKH')} · ${widget.quoteNo}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if ((widget.customerName ?? '').isNotEmpty)
              Text(
                widget.customerName!,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => callPosQuoteCustomer(widget.customerPhone),
                  icon: const Icon(Icons.call, size: 18),
                  label: Text(tr('Gọi khách')),
                ),
                if ((widget.customerPhone ?? '').isNotEmpty)
                  Text(widget.customerPhone!,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _kind,
                    isDense: true,
                    decoration: PosTheme.inputDecoration(label: 'Loại'),
                    items: const [
                      DropdownMenuItem(value: 'Note', child: Text('Ghi chú')),
                      DropdownMenuItem(value: 'Call', child: Text('Gọi điện')),
                      DropdownMenuItem(value: 'Meeting', child: Text('Gặp khách')),
                      DropdownMenuItem(
                          value: 'FollowUp', child: Text('Hẹn chăm sóc')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _kind = v);
                    },
                  ),
                ),
                if (_kind == 'FollowUp') ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _followUp ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d == null || !context.mounted) return;
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(
                            _followUp ?? DateTime.now()),
                      );
                      setState(() {
                        _followUp = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          t?.hour ?? 9,
                          t?.minute ?? 0,
                        );
                      });
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_followUp == null
                        ? tr('Chọn hạn')
                        : DateFormat('dd/MM HH:mm').format(_followUp!)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 3,
              decoration: PosTheme.inputDecoration(
                label: 'Nội dung làm việc với khách',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _add,
              icon: const Icon(Icons.add_comment_outlined),
              label: Text(_saving ? tr('Đang lưu…') : tr('Ghi lịch')),
            ),
            const Divider(height: 20),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(child: Text(tr('Chưa có lịch làm việc với khách')))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final a = _items[i];
                            final when = a.createdAt == null
                                ? ''
                                : DateFormat('dd/MM HH:mm')
                                    .format(a.createdAt!.toLocal());
                            final who = (a.employeeName ?? a.createdBy ?? '')
                                .trim();
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(_iconOf(a.kind), size: 20),
                              title: Text(
                                '${PosQuoteActivity.kindLabel(a.kind)} · $when',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              subtitle: Text([
                                a.content,
                                if (who.isNotEmpty) who,
                                if (a.nextFollowUpAt != null)
                                  'Hẹn ${DateFormat('dd/MM HH:mm').format(a.nextFollowUpAt!.toLocal())}',
                              ].join('\n')),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconOf(String kind) => switch (kind) {
        'Call' => Icons.call,
        'Meeting' => Icons.groups_outlined,
        'FollowUp' => Icons.event_available_outlined,
        'Created' => Icons.request_quote_outlined,
        'Edit' => Icons.edit_outlined,
        'Status' => Icons.flag_outlined,
        _ => Icons.sticky_note_2_outlined,
      };
}
