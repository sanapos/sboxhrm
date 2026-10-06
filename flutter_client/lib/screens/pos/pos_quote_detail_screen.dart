import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_quote.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/pos_quote_commercial.dart';
import '../../utils/pos_quote_export.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_contract_payment_panel.dart' show canUsePosContracts;
import '../../widgets/pos/pos_quote_care_sheet.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_contract_detail_screen.dart';
import 'pos_quote_composer_screen.dart';
import 'pos_quote_editor_screen.dart';

/// Các bước của một hồ sơ báo giá → hợp đồng (dùng chung danh sách + màn chi tiết).
class PosQuoteFlow {
  static const steps = ['Báo giá', 'Gửi khách', 'Khách chốt', 'Hợp đồng', 'Giao hàng', 'Nghiệm thu', 'Đóng'];

  static const _stageOrder = ['None', 'Accepted', 'Contracted', 'Issued', 'HandedOver', 'Inspected', 'Closed'];

  /// Số bước đã xong (0…7).
  static int doneCount(PosQuote q) {
    if (q.status == 'Draft') return 1;
    if (q.status != 'Accepted') return 2; // đã gửi / sửa / từ chối / hết hạn / hủy
    final s = _stageOrder.indexOf(q.commercialStage);
    if (s >= 6) return 7;
    if (s >= 5) return 6;
    if (s >= 3) return 5;
    if (s >= 2) return 4;
    return 3;
  }

  /// Báo giá đã dừng (không đi tiếp được).
  static bool isStopped(PosQuote q) => q.status == 'Rejected' || q.status == 'Expired' || q.status == 'Cancelled';

  /// Nhãn ngắn của bước tiếp theo (thẻ danh sách).
  static String? nextLabel(PosQuote q) {
    if (isStopped(q)) return null;
    return switch (doneCount(q)) {
      1 => 'Gửi khách',
      2 => 'Chờ khách chốt',
      3 => 'Lập hợp đồng',
      4 => 'Thu tiền / giao hàng',
      5 => 'Nghiệm thu',
      6 => 'Đóng hồ sơ',
      _ => null,
    };
  }

  /// Lập hợp đồng khi báo giá chưa chốt: hỏi xác nhận → phát hành (nếu nháp) → ghi nhận khách chốt.
  /// Máy chủ chỉ cho lập hợp đồng từ báo giá đã chấp nhận. Trả true khi báo giá đã ở trạng thái chấp nhận.
  static Future<bool> ensureAccepted(BuildContext context, PosQuote q) async {
    if (q.status == 'Accepted') return true;
    if (isStopped(q)) {
      NotificationOverlayManager().showError(
          title: 'Không lập được hợp đồng', message: tr('Báo giá đã ${PosQuote.statusLabel(q.status).toLowerCase()}.'));
      return false;
    }
    if (!context.read<PermissionProvider>().canApprove('PosQuotes')) {
      NotificationOverlayManager().showError(
          title: 'Cần quyền duyệt báo giá',
          message: tr('Lập hợp đồng cần ghi nhận khách đã chốt báo giá — nhờ quản lý thao tác.'));
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Khách đã chốt báo giá?')),
        content: Text(tr('Báo giá ${q.quoteNo} sẽ được ghi nhận ${q.status == 'Draft' ? 'đã gửi khách và ' : ''}'
            'khách chấp nhận (khóa sửa báo giá), sau đó lập hợp đồng.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Khách chốt & lập HĐ'))),
        ],
      ),
    );
    if (ok != true) return false;
    final api = ApiService();
    if (q.status == 'Draft') {
      final r = await api.sendPosQuote(q.id);
      if (r['isSuccess'] != true) {
        NotificationOverlayManager().showError(title: 'Chưa phát hành được', message: r['message']?.toString() ?? '');
        return false;
      }
    }
    final r = await api.acceptPosQuote(q.id);
    if (r['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Chưa ghi nhận khách chốt', message: r['message']?.toString() ?? '');
      return false;
    }
    return true;
  }

  /// «Còn N ngày» / «Hết hạn» — chỉ khi báo giá còn chờ khách.
  static (String, Color)? validity(PosQuote q) {
    final until = q.validUntil;
    if (until == null || q.status == 'Accepted' || isStopped(q)) return null;
    final today = DateUtils.dateOnly(DateTime.now());
    final days = DateUtils.dateOnly(until.toLocal()).difference(today).inDays;
    if (days < 0) return ('Quá hạn ${-days} ngày', SboxColors.danger);
    if (days == 0) return ('Hết hạn hôm nay', SboxColors.warning);
    return ('Còn $days ngày', days <= 3 ? SboxColors.warning : SboxColors.slate500);
  }
}

/// Màn tổng quan một báo giá: tiến độ hồ sơ, bước tiếp theo, hàng hóa, hồ sơ, liên hệ / chia sẻ.
class PosQuoteDetailScreen extends StatefulWidget {
  const PosQuoteDetailScreen({super.key, required this.quoteId});

  final String quoteId;

  @override
  State<PosQuoteDetailScreen> createState() => _PosQuoteDetailScreenState();
}

class _PosQuoteDetailScreenState extends State<PosQuoteDetailScreen> {
  final _api = ApiService();
  final _money = NumberFormat('#,##0', 'vi_VN');
  PosQuote? _q;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.getPosQuote(widget.quoteId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _q = PosQuote.fromJson(Map<String, dynamic>.from(res['data'] as Map));
      }
    });
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() fn, String done) async {
    setState(() => _busy = true);
    final res = await fn();
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: 'Chưa thực hiện được', message: res['message']?.toString() ?? tr('Thao tác thất bại'));
      return;
    }
    _changed = true;
    NotificationOverlayManager().showSuccess(title: done, message: _q?.quoteNo ?? '');
    await _load();
  }

  Future<bool> _confirm(String title, String message, {String ok = 'Đồng ý', bool danger = false}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: Text(tr(message)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: SboxColors.danger) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ok)),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _push(Widget page) async {
    final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    if (r == true) _changed = true;
    _changed = true;
    await _load();
  }

  Future<void> _editItems() => _push(PosQuoteComposerScreen(quoteId: widget.quoteId));
  Future<void> _openContract() => _push(PosContractDetailScreen(quoteId: widget.quoteId));

  Future<void> _createDoc(String kind) async {
    final q = _q;
    if (q == null) return;
    final doc = await createPosQuoteCommercialDoc(context, quote: q, kind: kind, includeImages: q.includeImages);
    if (!mounted) return;
    if (doc != null) {
      _changed = true;
      if (kind == 'Contract' && canUsePosContracts(context)) {
        await _openContract();
        return;
      }
    }
    await _load();
  }

  Future<void> _createPackage() async {
    final q = _q;
    if (q == null) return;
    final ok = await createPosQuoteCommercialPackage(context, quote: q, includeImages: q.includeImages);
    if (!mounted) return;
    if (ok) {
      _changed = true;
      await _openContract();
    }
  }

  void _share(String action, {String documentType = 'Quote'}) {
    final q = _q;
    if (q == null) return;
    PosQuoteExport.run(context, quote: q, action: action, documentType: documentType);
  }

  Future<void> _delete() async {
    final q = _q;
    if (q == null) return;
    final ok = await _confirm(
      'Xóa báo giá?',
      q.status == 'Draft'
          ? 'Báo giá nháp ${q.quoteNo} sẽ bị xóa.'
          : 'Báo giá ${q.quoteNo} sẽ bị xóa cùng hợp đồng, đề nghị thanh toán, biên bản và lịch chăm sóc khách. '
              'Báo giá đã xuất kho không xóa được.',
      ok: 'Xóa',
      danger: true,
    );
    if (!ok) return;
    final res = await _api.deletePosQuote(q.id);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager()
          .showError(title: 'Không xóa được', message: res['message']?.toString() ?? q.quoteNo);
      return;
    }
    NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: q.quoteNo);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final perm = context.watch<PermissionProvider>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: PosTheme.background,
        appBar: AppBar(
          title: Text(q?.quoteNo ?? tr('Báo giá')),
          actions: [
            if (q != null) ...[
              IconButton(
                tooltip: tr('In báo giá'),
                onPressed: () => printPosQuoteSlip(context, quoteId: q.id, quote: q, includeImages: q.includeImages),
                icon: const Icon(Icons.print_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Thêm'),
                onSelected: (v) => switch (v) {
                  'wording' => _push(PosQuoteEditorScreen(quoteId: q.id)),
                  'delete' => _delete(),
                  _ => _share(v),
                },
                itemBuilder: (_) => [
                  _menu('pdf', Icons.picture_as_pdf_outlined, 'Xuất PDF'),
                  _menu('word', Icons.description_outlined, 'Xuất Word'),
                  _menu('excel', Icons.table_chart_outlined, 'Xuất Excel'),
                  _menu('png', Icons.image_outlined, 'Xuất ảnh PNG'),
                  _menu('email', Icons.email_outlined, 'Gửi Email'),
                  _menu('facebook', Icons.facebook, 'Chia sẻ Facebook'),
                  const PopupMenuDivider(),
                  _menu('wording', Icons.edit_note_outlined, 'Hồ sơ & lời văn chứng từ'),
                  if (perm.canDelete('PosQuotes') && q.canDelete) ...[
                    const PopupMenuDivider(),
                    _menu('delete', Icons.delete_outline, 'Xóa báo giá', color: SboxColors.danger),
                  ],
                ],
              ),
            ],
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : q == null
                ? Center(child: Text(tr('Không tìm thấy báo giá')))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                          children: [
                            _headerCard(q),
                            const SizedBox(height: 12),
                            _progressCard(q, perm),
                            const SizedBox(height: 12),
                            _contactRow(q),
                            const SizedBox(height: 12),
                            _linesCard(q, perm),
                            if (q.documents.any((d) => d.kind != 'Quote')) ...[
                              const SizedBox(height: 12),
                              _docsCard(q),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  PopupMenuItem<String> _menu(String v, IconData icon, String label, {Color? color}) => PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(icon, size: 18, color: color ?? SboxColors.slate600),
          const SizedBox(width: 10),
          Text(tr(label), style: TextStyle(color: color)),
        ]),
      );

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: child,
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(tr(text), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _headerCard(PosQuote q) {
    final validity = PosQuoteFlow.validity(q);
    final name = (q.customerName ?? '').trim();
    final sub = [
      if ((q.customerPhone ?? '').trim().isNotEmpty) q.customerPhone!.trim(),
      if ((q.customerAddress ?? '').trim().isNotEmpty) q.customerAddress!.trim(),
    ].join(' · ');
    final by = q.staffLabel;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _pill(PosQuote.statusLabel(q.status), PosQuote.statusColor(q.status)),
          if (q.revision > 1) ...[const SizedBox(width: 6), _pill('Bản sửa ${q.revision - 1}', SboxColors.slate500)],
          const Spacer(),
          if (validity != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.schedule, size: 14, color: validity.$2),
              const SizedBox(width: 4),
              Text(tr(validity.$1), style: TextStyle(fontSize: 12, color: validity.$2, fontWeight: FontWeight.w600)),
            ]),
        ]),
        const SizedBox(height: 12),
        Text(tr(name.isEmpty ? 'Khách lẻ (chưa chọn khách)' : name),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(tr(sub), style: const TextStyle(fontSize: 13, color: SboxColors.slate600)),
        ],
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Tổng giá trị'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              Text(tr('${_money.format(q.total)} đ'),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: PosTheme.kiotBlue)),
            ]),
          ),
          if (q.depositAmount > 0)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(tr('Tiền cọc'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              Text(
                tr('${_money.format(q.depositAmount)} đ${q.depositPercent != null ? ' (${q.depositPercent!.round()}%)' : ''}'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ]),
        ]),
        if (by.isNotEmpty || q.issuedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            tr([
              if (by.isNotEmpty) 'Người báo giá: $by',
              if (q.issuedAt != null) 'Ngày ${DateFormat('dd/MM/yyyy').format(q.issuedAt!.toLocal())}',
            ].join(' · ')),
            style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
          ),
        ],
      ]),
    );
  }

  /// Tiến độ hồ sơ + nút «bước tiếp theo» theo trạng thái.
  Widget _progressCard(PosQuote q, PermissionProvider perm) {
    final done = PosQuoteFlow.doneCount(q);
    final stopped = PosQuoteFlow.isStopped(q);
    final canEdit = perm.canEdit('PosQuotes');
    final canApprove = perm.canApprove('PosQuotes');
    final contracts = canUsePosContracts(context);

    String hint;
    final actions = <Widget>[];
    Widget primary(String label, IconData icon, VoidCallback? onTap) => FilledButton.icon(
          onPressed: _busy ? null : onTap,
          icon: Icon(icon, size: 18),
          label: Text(tr(label)),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        );
    Widget secondary(String label, IconData icon, VoidCallback? onTap, {Color? color}) => OutlinedButton.icon(
          onPressed: _busy ? null : onTap,
          icon: Icon(icon, size: 18, color: color),
          label: Text(tr(label), style: TextStyle(color: color)),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        );

    if (stopped) {
      hint = switch (q.status) {
        'Rejected' => 'Khách đã từ chối báo giá này.',
        'Expired' => 'Báo giá đã hết hạn.',
        _ => 'Báo giá đã hủy.',
      };
      if (perm.canCreate('PosQuotes') || canEdit) {
        actions.add(secondary('Tạo báo giá mới', Icons.add, () => _push(const PosQuoteComposerScreen())));
      }
    } else if (q.status == 'Draft' || q.status == 'Revised') {
      hint = q.status == 'Draft'
          ? 'Báo giá đang là bản nháp. Gửi cho khách (in / PDF / Zalo) rồi bấm «Phát hành» để ghi nhận đã gửi.'
          : 'Báo giá đã sửa — phát hành lại để khách xem bản mới.';
      if (canEdit) {
        actions.add(primary('Phát hành (đã gửi khách)', Icons.send_outlined, () async {
          if (await _confirm('Phát hành báo giá?', 'Ghi nhận đã gửi ${q.quoteNo} cho khách. Sau đó chờ khách chốt.',
              ok: 'Phát hành')) {
            await _run(() => _api.sendPosQuote(q.id), 'Đã phát hành');
          }
        }));
        actions.add(secondary('Sửa hàng hóa / giá', Icons.edit_outlined, _editItems));
        if (canApprove) actions.add(secondary('Khách chốt & lập HĐ', Icons.handshake_outlined, _acceptAndContract));
      }
      if (q.status == 'Revised' && canApprove) {
        actions.add(secondary('Khách chốt', Icons.verified_outlined, () => _accept(q)));
      }
    } else if (q.status == 'Sent') {
      hint = 'Đã gửi khách — chờ khách phản hồi. Khi khách đồng ý, bấm «Khách chốt» để lập hợp đồng.';
      if (canApprove) {
        actions.add(primary('Khách chốt báo giá', Icons.verified_outlined, () => _accept(q)));
        actions.add(secondary('Khách từ chối', Icons.close, () async {
          if (await _confirm('Khách từ chối?', 'Đánh dấu ${q.quoteNo} bị từ chối.', ok: 'Từ chối', danger: true)) {
            await _run(() => _api.rejectPosQuote(q.id), 'Đã ghi nhận từ chối');
          }
        }, color: SboxColors.danger));
      } else {
        hint += ' (Cần quyền duyệt báo giá để chốt.)';
      }
      if (canEdit && canApprove) actions.add(secondary('Khách chốt & lập HĐ', Icons.handshake_outlined, _acceptAndContract));
      if (canEdit) actions.add(secondary('Sửa (tạo bản sửa)', Icons.edit_outlined, _editItems));
    } else {
      // Đã chốt — hồ sơ thương mại.
      switch (q.commercialStage) {
        case 'None':
        case 'Accepted':
          hint = 'Khách đã chốt. Lập hợp đồng (hoặc trọn bộ hồ sơ: hợp đồng + đề nghị TT + bàn giao + nghiệm thu).';
          if (canEdit) {
            actions.add(primary('Lập hợp đồng', Icons.handshake_outlined, () => _createDoc('Contract')));
            actions.add(secondary('Trọn bộ hồ sơ', Icons.folder_copy_outlined, _createPackage));
          }
        case 'Contracted':
          hint = contracts
              ? 'Đã có hợp đồng. Thu cọc / các đợt thanh toán trong hợp đồng, rồi xuất kho hoặc bàn giao.'
              : 'Đã có hợp đồng. Xuất kho hoặc bàn giao khi giao hàng.';
          actions.add(primary(contracts ? 'Hợp đồng & thu tiền' : 'Mở hồ sơ hợp đồng', Icons.handshake_outlined,
              _openContract));
          if (canEdit) {
            actions.add(secondary('Xuất kho', Icons.outbox_outlined, () => _createDoc('StockIssue')));
            actions.add(secondary('Bàn giao', Icons.local_shipping_outlined, () => _createDoc('Handover')));
          }
        case 'Issued':
        case 'HandedOver':
          hint = 'Đã giao hàng. Lập biên bản nghiệm thu khi khách kiểm tra xong.';
          if (canEdit) actions.add(primary('Nghiệm thu', Icons.fact_check_outlined, () => _createDoc('Acceptance')));
          actions.add(secondary('Hồ sơ hợp đồng', Icons.folder_open_outlined, _openContract));
        case 'Inspected':
          hint = 'Đã nghiệm thu. Đóng hồ sơ khi đã thu đủ tiền.';
          if (canApprove) {
            actions.add(primary('Đóng hồ sơ', Icons.task_alt, () async {
              if (await _confirm('Đóng hồ sơ?', 'Kết thúc hồ sơ ${q.quoteNo}.', ok: 'Đóng hồ sơ')) {
                await _run(() => _api.closePosQuote(q.id), 'Đã đóng hồ sơ');
              }
            }));
          }
          actions.add(secondary('Hồ sơ hợp đồng', Icons.folder_open_outlined, _openContract));
        default:
          hint = 'Hồ sơ đã hoàn tất.';
          actions.add(secondary('Hồ sơ hợp đồng', Icons.folder_open_outlined, _openContract));
      }
    }

    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(tr('Tiến độ hồ sơ'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(tr('$done/${PosQuoteFlow.steps.length}'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate500, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        PosQuoteProgress(done: done, stopped: stopped),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: stopped ? SboxColors.slate100 : SboxColors.brand50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(stopped ? Icons.info_outline : Icons.lightbulb_outline,
                size: 18, color: stopped ? SboxColors.slate600 : PosTheme.kiotBlue),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(hint), style: const TextStyle(fontSize: 13, height: 1.35))),
          ]),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 520) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  actions[i],
                ],
              ]);
            }
            return Wrap(spacing: 8, runSpacing: 8, children: actions);
          }),
        ],
      ]),
    );
  }

  Future<void> _acceptAndContract() async {
    final q = _q;
    if (q == null) return;
    if (!await PosQuoteFlow.ensureAccepted(context, q)) return;
    _changed = true;
    await _load();
    if (!mounted) return;
    await _createDoc('Contract');
  }

  Future<void> _accept(PosQuote q) async {
    if (await _confirm('Khách chốt báo giá?',
        'Báo giá ${q.quoteNo} sẽ khóa sửa và chuyển sang bước lập hợp đồng.', ok: 'Khách chốt')) {
      await _run(() => _api.acceptPosQuote(q.id), 'Khách đã chốt');
    }
  }

  Widget _contactRow(PosQuote q) {
    final phone = (q.customerPhone ?? '').trim();
    Widget tile(IconData icon, String label, VoidCallback? onTap) => Expanded(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SboxColors.slate200),
                ),
                child: Column(children: [
                  Icon(icon, size: 22, color: onTap == null ? SboxColors.slate300 : PosTheme.kiotBlue),
                  const SizedBox(height: 4),
                  Text(tr(label),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: onTap == null ? SboxColors.slate400 : SboxColors.slate700)),
                ]),
              ),
            ),
          ),
        );
    return Row(children: [
      tile(Icons.call_outlined, 'Gọi', phone.isEmpty ? null : () => callPosQuoteCustomer(phone)),
      const SizedBox(width: 8),
      tile(Icons.chat_outlined, 'Zalo', phone.isEmpty ? null : () => _share('zalo')),
      const SizedBox(width: 8),
      tile(Icons.picture_as_pdf_outlined, 'Gửi PDF', () => _share('pdf')),
      const SizedBox(width: 8),
      tile(Icons.event_note_outlined, 'Chăm sóc', () {
        showPosQuoteCareSheet(context,
            quoteId: q.id, quoteNo: q.quoteNo, customerName: q.customerName, customerPhone: q.customerPhone);
      }),
    ]);
  }

  Widget _linesCard(PosQuote q, PermissionProvider perm) {
    final canEdit = perm.canEdit('PosQuotes') && !q.isLocked;
    Widget sumRow(String label, double v, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(
              child: Text(tr(label),
                  style: TextStyle(fontSize: bold ? 14 : 13, color: bold ? null : SboxColors.slate600)),
            ),
            Text(tr('${_money.format(v)} đ'),
                style: TextStyle(
                    fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
          ]),
        );
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(tr('Hàng hóa / dịch vụ (${q.lines.length})'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (canEdit)
            TextButton.icon(
              onPressed: _editItems,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(tr('Sửa')),
            ),
        ]),
        for (var i = 0; i < q.lines.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: SboxColors.slate100),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(q.lines[i].productName),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    tr('${NumberFormat('#,##0.##', 'vi_VN').format(q.lines[i].qty)}'
                        '${(q.lines[i].unitName ?? '').isEmpty ? '' : ' ${q.lines[i].unitName}'}'
                        ' × ${_money.format(q.lines[i].unitPrice)}'
                        '${q.lines[i].discountAmount > 0 ? ' · CK ${_money.format(q.lines[i].discountAmount)}' : ''}'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
                  ),
                  if ((q.lines[i].lineNote ?? '').trim().isNotEmpty)
                    Text(tr('↳ ${q.lines[i].lineNote!.trim()}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: PosTheme.kiotBlue)),
                ]),
              ),
              const SizedBox(width: 8),
              Text(tr(_money.format(q.lines[i].lineTotal > 0 ? q.lines[i].lineTotal : q.lines[i].net)),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
        const Divider(height: 16),
        sumRow('Tiền hàng', q.subTotal),
        if (q.discount > 0) sumRow('Giảm giá', -q.discount, color: SboxColors.danger),
        if (q.vatAmount > 0 && q.vatMode != PosQuoteVat.included) sumRow('Thuế VAT', q.vatAmount),
        sumRow(q.vatMode == PosQuoteVat.included && q.vatAmount > 0 ? 'Tổng cộng (đã gồm VAT)' : 'Tổng cộng', q.total,
            bold: true, color: PosTheme.kiotBlue),
        // Giá đã gồm VAT: VAT chỉ tách ra để xem, không cộng thêm.
        if (q.vatAmount > 0 && q.vatMode == PosQuoteVat.included)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(tr('Trong đó VAT ${_money.format(q.vatAmount)} đ · trước VAT ${_money.format(q.total - q.vatAmount)} đ'),
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
          ),
      ]),
    );
  }

  Widget _docsCard(PosQuote q) {
    const labels = {
      'Contract': ('Hợp đồng', Icons.handshake_outlined),
      'PaymentRequest': ('Đề nghị thanh toán', Icons.payments_outlined),
      'StockIssue': ('Phiếu xuất kho', Icons.outbox_outlined),
      'Handover': ('Biên bản bàn giao', Icons.local_shipping_outlined),
      'Acceptance': ('Biên bản nghiệm thu', Icons.fact_check_outlined),
    };
    final docs = q.documents.where((d) => d.kind != 'Quote').toList();
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(tr('Hồ sơ đã lập (${docs.length})'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton(onPressed: _openContract, child: Text(tr('Mở hồ sơ'))),
        ]),
        for (final d in docs)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(labels[d.kind]?.$2 ?? Icons.description_outlined, color: PosTheme.kiotBlue),
            title: Text(tr(d.title.isNotEmpty ? d.title : (labels[d.kind]?.$1 ?? d.kind)),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr([
              d.docNo,
              if (d.issuedAt != null) DateFormat('dd/MM/yyyy').format(d.issuedAt!.toLocal()),
            ].join(' · '))),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openContract,
          ),
      ]),
    );
  }
}

/// Thanh tiến độ 7 bước (báo giá → đóng hồ sơ) — màn báo giá + hợp đồng.
class PosQuoteProgress extends StatelessWidget {
  const PosQuoteProgress({super.key, required this.done, this.stopped = false});

  final int done;
  final bool stopped;

  @override
  Widget build(BuildContext context) {
    final steps = PosQuoteFlow.steps;
    return LayoutBuilder(builder: (context, c) {
      final compact = c.maxWidth < 520;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Container(
                      height: 3,
                      color: i == 0 ? Colors.transparent : (i < done ? SboxColors.success : SboxColors.slate200),
                    ),
                  ),
                  _dot(i, done, stopped),
                  Expanded(
                    child: Container(
                      height: 3,
                      color: i == steps.length - 1
                          ? Colors.transparent
                          : (i + 1 < done ? SboxColors.success : SboxColors.slate200),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  tr(steps[i]),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: compact ? 10 : 12,
                    height: 1.15,
                    fontWeight: i == done ? FontWeight.w700 : FontWeight.w500,
                    color: i < done
                        ? SboxColors.slate800
                        : (i == done && !stopped ? PosTheme.kiotBlue : SboxColors.slate400),
                  ),
                ),
              ]),
            ),
        ],
      );
    });
  }

  Widget _dot(int i, int done, bool stopped) {
    final isDone = i < done;
    final isCurrent = i == done && !stopped;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone ? SboxColors.success : (isCurrent ? PosTheme.kiotBlue : Colors.white),
        border: Border.all(
          color: isDone ? SboxColors.success : (isCurrent ? PosTheme.kiotBlue : SboxColors.slate300),
          width: 2,
        ),
      ),
      child: isDone
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : (stopped && i == done
              ? const Icon(Icons.close, size: 12, color: SboxColors.slate500)
              : Center(
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isCurrent ? Colors.white : SboxColors.slate400)),
                )),
    );
  }
}
