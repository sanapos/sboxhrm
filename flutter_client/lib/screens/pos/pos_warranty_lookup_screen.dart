import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/api_datetime.dart';
import '../../utils/pos_html_print.dart';
import '../../utils/pos_print_store_info.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

final _dateFmt = DateFormat('dd/MM/yyyy', 'vi_VN');
final _money = NumberFormat('#,##0', 'vi_VN');

DateTime? _date(dynamic v) {
  final s = '${v ?? ''}';
  if (s.isEmpty || s == 'null') return null;
  return parseApiUtcDateTime(s)?.toLocal();
}

String _d(dynamic v) {
  final x = _date(v);
  return x == null ? '' : _dateFmt.format(x);
}

String _s(Map<String, dynamic> m, String key) {
  final v = m[key] ?? m[key[0].toUpperCase() + key.substring(1)];
  return v == null ? '' : '$v';
}

num _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

/// Seri «AUTO-…» = hàng không bắt buộc seri, bảo hành theo đơn.
String _serialLabel(String serial) =>
    serial.startsWith('AUTO-') ? 'Không có seri — bảo hành theo đơn' : serial;

/// Bảo hành: phiếu tiếp nhận / sửa / trả máy, tra cứu máy đã bán, nhắc sắp hết hạn, báo cáo.
class PosWarrantyLookupScreen extends StatefulWidget {
  const PosWarrantyLookupScreen({super.key});

  @override
  State<PosWarrantyLookupScreen> createState() => _PosWarrantyLookupScreenState();
}

class _PosWarrantyLookupScreenState extends State<PosWarrantyLookupScreen> {
  /// Tăng sau mỗi thao tác — các tab tự tải lại.
  final _tick = ValueNotifier<int>(0);

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: ColoredBox(
        color: PosTheme.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PosMobileKiotHeader(title: 'Bảo hành'),
            Material(
              color: Colors.white,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: SboxColors.brand700,
                unselectedLabelColor: SboxColors.slate500,
                indicatorColor: SboxColors.brand600,
                tabs: [
                  Tab(text: tr('Phiếu bảo hành')),
                  Tab(text: tr('Máy đã bán')),
                  Tab(text: tr('Sắp hết hạn')),
                  Tab(text: tr('Báo cáo')),
                ],
              ),
            ),
            const Divider(height: 1, color: SboxColors.border),
            Expanded(
              child: TabBarView(children: [
                _ClaimsTab(tick: _tick),
                _MachinesTab(tick: _tick),
                _ExpiringTab(tick: _tick),
                _ReportTab(tick: _tick),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Thao tác dùng chung ─────────────────────────

class _WarrantyActions {
  _WarrantyActions(this.context, this.tick);

  final BuildContext context;
  final ValueNotifier<int> tick;
  final _api = ApiService();

  void _toast(Map<String, dynamic> res, String ok) {
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Bảo hành', message: ok);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Bảo hành', message: res['message']?.toString() ?? 'Thao tác thất bại');
    }
  }

  void _changed() => tick.value++;

  /// Tiếp nhận máy: mô tả lỗi, tình trạng, phụ kiện, liên hệ, hẹn trả, phụ trách → in phiếu cho khách.
  Future<void> receive(Map<String, dynamic> reg) async {
    final expiry = _date(reg['warrantyExpiry'] ?? reg['WarrantyExpiry']);
    final months = _n(reg['warrantyMonths'] ?? reg['WarrantyMonths']).toInt();
    final inWarranty = months > 0 && expiry != null && !expiry.isBefore(DateTime.now());
    final desc = TextEditingController();
    final cond = TextEditingController();
    final acc = TextEditingController();
    final name = TextEditingController(text: _s(reg, 'customerName'));
    final phone = TextEditingController(text: _s(reg, 'customerPhone'));
    final assignee = TextEditingController();
    var due = DateTime.now().add(const Duration(days: 7));
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Tiếp nhận bảo hành')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr('${_s(reg, 'productName')} · ${_serialLabel(_s(reg, 'serialNumber'))}'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  tr(inWarranty
                      ? 'Còn bảo hành đến ${_dateFmt.format(expiry)}'
                      : 'Hết bảo hành — sửa có tính phí (nhập phí khi hoàn tất)'),
                  style: TextStyle(
                      fontSize: 12, color: inWarranty ? SboxColors.success : SboxColors.danger),
                ),
                const SizedBox(height: 12),
                _field(desc, 'Mô tả lỗi / yêu cầu của khách *', lines: 3, autofocus: true),
                _field(cond, 'Tình trạng máy lúc nhận (trầy, móp, màn hình…)'),
                _field(acc, 'Phụ kiện gửi kèm (sạc, hộp, ốp…)'),
                Row(children: [
                  Expanded(child: _field(name, 'Người liên hệ')),
                  const SizedBox(width: 8),
                  Expanded(child: _field(phone, 'SĐT liên hệ', phone: true)),
                ]),
                Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text(tr('Hẹn trả: ${_dateFmt.format(due)}')),
                        onPressed: () async {
                          final p = await showDatePicker(
                            context: ctx,
                            initialDate: due,
                            firstDate: DateTime.now().subtract(const Duration(days: 1)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (p != null) setD(() => due = p);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _field(assignee, 'Người phụ trách')),
                ]),
                if (error != null)
                  Text(tr(error!), style: const TextStyle(color: SboxColors.danger, fontSize: 12)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(
              onPressed: () {
                if (desc.text.trim().isEmpty) {
                  setD(() => error = 'Nhập mô tả lỗi');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(tr('Tiếp nhận')),
            ),
          ],
        ),
      ),
    );
    final body = {
      'claimType': 'Repair',
      'description': desc.text.trim(),
      'deviceCondition': cond.text.trim(),
      'accessories': acc.text.trim(),
      'contactName': name.text.trim(),
      'contactPhone': phone.text.trim(),
      'assignedTo': assignee.text.trim(),
      'expectedReturnDate': DateTime(due.year, due.month, due.day, 23, 59).toUtc().toIso8601String(),
    };
    for (final c in [desc, cond, acc, name, phone, assignee]) {
      c.dispose();
    }
    if (ok != true) return;
    final res = await _api.createPosWarrantyClaimFull(_s(reg, 'id'), body);
    _toast(res, 'Đã tiếp nhận — phiếu ${(res['data'] as Map?)?['claimNo'] ?? ''}');
    if (res['isSuccess'] != true) return;
    _changed();
    final claim = Map<String, dynamic>.from(res['data'] as Map);
    if (!context.mounted) return;
    final print = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('In phiếu tiếp nhận?')),
        content: Text(tr('Phiếu ${claim['claimNo'] ?? ''} — đưa khách giữ để nhận lại máy.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Để sau'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(tr('In phiếu')),
          ),
        ],
      ),
    );
    if (print == true) await printClaim(claim);
  }

  Widget _field(TextEditingController c, String label,
          {int lines = 1, bool autofocus = false, bool phone = false, bool money = false, ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          autofocus: autofocus,
          onChanged: onChanged,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          keyboardType: phone
              ? TextInputType.phone
              : money
                  ? TextInputType.number
                  : TextInputType.text,
          inputFormatters: money ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(labelText: tr(label), border: const OutlineInputBorder(), isDense: true),
        ),
      );

  Future<void> setProcessing(Map<String, dynamic> claim) async {
    final res = await _api.updatePosWarrantyClaimFull(_s(claim, 'id'), {'status': 'Processing'});
    _toast(res, 'Đã chuyển sang đang xử lý');
    if (res['isSuccess'] == true) _changed();
  }

  /// Hoàn tất (sửa xong) / Từ chối: kết quả, phí sửa, thu phí ngay.
  Future<void> close(Map<String, dynamic> claim, {required bool done}) async {
    final inWarranty = claim['inWarranty'] != false;
    final result = TextEditingController();
    final fee = TextEditingController(text: _n(claim['fee']) > 0 ? '${_n(claim['fee']).toInt()}' : '');
    var collect = false;
    var method = 'Tiền mặt';
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final feeVal = int.tryParse(fee.text) ?? 0;
          return AlertDialog(
            title: Text(tr(done ? 'Hoàn tất sửa — ${claim['claimNo'] ?? ''}' : 'Từ chối bảo hành — ${claim['claimNo'] ?? ''}')),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _field(result, done ? 'Kết quả sửa (đã thay / sửa gì) *' : 'Lý do từ chối *',
                      lines: 2, autofocus: true),
                  if (!inWarranty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(tr('Máy hết bảo hành lúc nhận — nhập phí sửa.'),
                          style: const TextStyle(fontSize: 12, color: SboxColors.danger)),
                    ),
                  _field(fee, 'Phí sửa (đ) — 0 nếu miễn phí', money: true, onChanged: (_) => setD(() {})),
                  if (feeVal > 0) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: collect,
                      onChanged: (v) => setD(() => collect = v ?? false),
                      title: Text(tr('Thu phí ngay (ghi phiếu thu)')),
                      subtitle: Text(tr('Không chọn: thu khi khách đến lấy máy')),
                    ),
                    if (collect) _methodPicker(method, (m) => setD(() => method = m)),
                  ],
                  if (error != null)
                    Text(tr(error!), style: const TextStyle(color: SboxColors.danger, fontSize: 12)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
              FilledButton(
                onPressed: () {
                  if (result.text.trim().isEmpty) {
                    setD(() => error = done ? 'Nhập kết quả sửa' : 'Nhập lý do từ chối');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(tr(done ? 'Hoàn tất' : 'Từ chối')),
              ),
            ],
          );
        },
      ),
    );
    final body = <String, dynamic>{
      'status': done ? 'Done' : 'Rejected',
      'resolution': result.text.trim(),
      'fee': int.tryParse(fee.text) ?? 0,
      'collectFee': collect && (int.tryParse(fee.text) ?? 0) > 0,
      'paymentMethod': method,
    };
    result.dispose();
    fee.dispose();
    if (ok != true) return;
    final res = await _api.updatePosWarrantyClaimFull(_s(claim, 'id'), body);
    _toast(res, done ? 'Đã hoàn tất — chờ khách lấy máy' : 'Đã từ chối — chờ khách lấy máy');
    if (res['isSuccess'] == true) _changed();
  }

  Widget _methodPicker(String method, ValueChanged<String> onChanged) => Wrap(spacing: 8, children: [
        for (final m in const ['Tiền mặt', 'Chuyển khoản'])
          ChoiceChip(label: Text(tr(m)), selected: method == m, onSelected: (_) => onChanged(m)),
      ]);

  /// Trả máy cho khách (thu phí nếu còn nợ) → in phiếu trả máy.
  Future<void> deliver(Map<String, dynamic> claim) async {
    final fee = _n(claim['fee']);
    final paid = claim['feePaid'] == true;
    var collect = fee > 0 && !paid;
    var method = 'Tiền mặt';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Trả máy cho khách — ${claim['claimNo'] ?? ''}')),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('${claim['productName'] ?? ''} · ${_serialLabel('${claim['serialNumber'] ?? ''}')}'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(tr('Kết quả: ${claim['resolution'] ?? ''}')),
              const SizedBox(height: 8),
              if (fee <= 0)
                Text(tr('Không thu phí.'), style: const TextStyle(color: SboxColors.success))
              else if (paid)
                Text(tr('Phí sửa ${_money.format(fee)} đ — đã thu.'),
                    style: const TextStyle(color: SboxColors.success))
              else ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: collect,
                  onChanged: (v) => setD(() => collect = v ?? false),
                  title: Text(tr('Thu phí sửa ${_money.format(fee)} đ')),
                  subtitle: Text(tr('Ghi phiếu thu «Phí sửa chữa bảo hành»')),
                ),
                if (collect) _methodPicker(method, (m) => setD(() => method = m)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
              label: Text(tr('Đã trả máy')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final res = await _api.updatePosWarrantyClaimFull(_s(claim, 'id'), {
      'deliver': true,
      'collectFee': collect,
      'paymentMethod': method,
    });
    _toast(res, 'Đã trả máy cho khách');
    if (res['isSuccess'] != true) return;
    _changed();
    if (!context.mounted) return;
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('In phiếu trả máy?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Để sau'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('In phiếu'))),
        ],
      ),
    );
    if (again == true) await printClaim(Map<String, dynamic>.from(res['data'] as Map));
  }

  /// Đổi người phụ trách / ngày hẹn trả.
  Future<void> edit(Map<String, dynamic> claim) async {
    final assignee = TextEditingController(text: '${claim['assignedTo'] ?? ''}');
    var due = _date(claim['expectedReturnDate']) ?? DateTime.now().add(const Duration(days: 3));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Cập nhật phiếu ${claim['claimNo'] ?? ''}')),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _field(assignee, 'Người phụ trách'),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(tr('Hẹn trả: ${_dateFmt.format(due)}')),
                onPressed: () async {
                  final p = await showDatePicker(
                    context: ctx,
                    initialDate: due,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (p != null) setD(() => due = p);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
          ],
        ),
      ),
    );
    final body = {
      'assignedTo': assignee.text.trim(),
      'expectedReturnDate': DateTime(due.year, due.month, due.day, 23, 59).toUtc().toIso8601String(),
    };
    assignee.dispose();
    if (ok != true) return;
    final res = await _api.updatePosWarrantyClaimFull(_s(claim, 'id'), body);
    _toast(res, 'Đã cập nhật phiếu');
    if (res['isSuccess'] == true) _changed();
  }

  Future<void> note(Map<String, dynamic> reg) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Ghi chú cho máy ${_serialLabel(_s(reg, 'serialNumber'))}')),
        content: SizedBox(width: 400, child: _field(c, 'Nội dung ghi chú *', lines: 3, autofocus: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(
              onPressed: () {
                if (c.text.trim().isNotEmpty) Navigator.pop(ctx, true);
              },
              child: Text(tr('Lưu'))),
        ],
      ),
    );
    final text = c.text.trim();
    c.dispose();
    if (ok != true) return;
    final res = await _api.createPosWarrantyClaimFull(_s(reg, 'id'), {'claimType': 'Note', 'description': text});
    _toast(res, 'Đã ghi chú');
    if (res['isSuccess'] == true) _changed();
  }

  /// Đổi máy: lấy máy trong kho (trừ tồn) hoặc máy hãng gửi về.
  Future<void> replace(Map<String, dynamic> reg) async {
    final serial = TextEditingController();
    final imei = TextEditingController();
    final reason = TextEditingController();
    var fromStock = true;
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Đổi máy bảo hành')),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr('${_s(reg, 'productName')} · seri cũ ${_s(reg, 'serialNumber')}'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                _field(serial, 'Seri máy mới *', autofocus: true),
                _field(imei, 'IMEI máy mới'),
                _field(reason, 'Lý do đổi máy *', lines: 2),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  value: true,
                  groupValue: fromStock,
                  onChanged: (v) => setD(() => fromStock = true),
                  title: Text(tr('Lấy máy trong kho cửa hàng')),
                  subtitle: Text(tr('Tự lập phiếu xuất kho 1 máy — tồn kho khớp sổ seri')),
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  value: false,
                  groupValue: fromStock,
                  onChanged: (v) => setD(() => fromStock = false),
                  title: Text(tr('Máy hãng gửi về')),
                  subtitle: Text(tr('Không trừ kho cửa hàng')),
                ),
                Text(tr('Máy mới giữ nguyên hạn bảo hành còn lại. Máy cũ ghi «thu hồi — chờ trả NCC / gửi hãng».'),
                    style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
                if (error != null)
                  Text(tr(error!), style: const TextStyle(color: SboxColors.danger, fontSize: 12)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(
              onPressed: () {
                if (serial.text.trim().isEmpty || reason.text.trim().isEmpty) {
                  setD(() => error = 'Nhập seri máy mới và lý do');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(tr('Đổi máy')),
            ),
          ],
        ),
      ),
    );
    final s = serial.text.trim(), i = imei.text.trim(), r = reason.text.trim();
    for (final c in [serial, imei, reason]) {
      c.dispose();
    }
    if (ok != true) return;
    final res = await _api.replacePosWarrantySerial(_s(reg, 'id'), s, i.isEmpty ? null : i, r, fromStock: fromStock);
    final issueNo = (res['data'] as Map?)?['issueNo'];
    _toast(res, issueNo == null
        ? 'Đã đổi máy — seri mới giữ hạn bảo hành còn lại'
        : 'Đã đổi máy, xuất kho $issueNo — seri mới giữ hạn bảo hành còn lại');
    if (res['isSuccess'] == true) _changed();
  }

  /// Lịch sử bảo hành của máy (gồm cả máy trước khi đổi).
  Future<void> history(Map<String, dynamic> reg) async {
    final res = await _api.getPosWarrantyClaims(_s(reg, 'id'));
    if (!context.mounted) return;
    if (res['isSuccess'] != true) {
      _toast(res, '');
      return;
    }
    final raw = (res['data'] as Map?)?['items'];
    final claims = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            shrinkWrap: true,
            children: [
              Text(tr('Lịch sử bảo hành — ${_serialLabel(_s(reg, 'serialNumber'))}'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text(tr(_s(reg, 'productName')), style: const TextStyle(color: PosTheme.textSecondary)),
              const SizedBox(height: 8),
              if (claims.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(tr('Chưa có lần bảo hành nào'))),
                ),
              for (final c in claims)
                _ClaimCard(
                  claim: c,
                  actions: this,
                  compact: true,
                  onAction: () => Navigator.pop(ctx),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Phiếu tiếp nhận / trả máy khổ A5 — khách giữ để nhận máy.
  Future<void> printClaim(Map<String, dynamic> claim) async {
    final store = await PosPrintStoreInfo.load();
    if (!context.mounted) return;
    const esc = HtmlEscape();
    String e(Object? v) => esc.convert('${v ?? ''}');
    final delivered = claim['deliveredDate'] != null;
    final status = '${claim['status'] ?? ''}';
    final closed = status == 'Done' || status == 'Rejected';
    final fee = _n(claim['fee']);
    final serial = '${claim['serialNumber'] ?? ''}';
    final imei = '${claim['imei'] ?? ''}';
    final months = _n(claim['warrantyMonths']).toInt();
    String row(String k, String v) => v.trim().isEmpty
        ? ''
        : '<tr><td style="padding:3px 6px;width:34%;vertical-align:top;color:#333">${e(k)}</td>'
            '<td style="padding:3px 6px;vertical-align:top"><b>${e(v)}</b></td></tr>';
    final html = '''
<!--POS_A4_V1 paper="A5" mt="8" mr="9" mb="8" ml="9"-->
<div style="font-family:'Times New Roman',serif;font-size:12.5pt;line-height:1.35;color:#000">
  <div style="text-align:center">
    <div style="font-size:14pt;font-weight:bold;text-transform:uppercase">${e(store.storeName)}</div>
    <div style="font-size:11pt">${e([if (store.address != null) store.address, if (store.phone != null) 'ĐT: ${store.phone}'].join(' · '))}</div>
  </div>
  <div style="text-align:center;margin:10px 0 2px;font-size:16pt;font-weight:bold">
    ${delivered ? 'PHIẾU TRẢ MÁY BẢO HÀNH' : 'PHIẾU TIẾP NHẬN BẢO HÀNH'}
  </div>
  <div style="text-align:center;font-size:11.5pt">Số phiếu: <b>${e(claim['claimNo'])}</b> · Ngày nhận: ${e(_d(claim['receivedDate']))}</div>
  <table style="width:100%;border-collapse:collapse;margin-top:10px;font-size:12pt">
    ${row('Khách hàng', '${claim['contactName'] ?? claim['customerName'] ?? ''}')}
    ${row('Số điện thoại', '${claim['contactPhone'] ?? claim['customerPhone'] ?? ''}')}
    ${row('Sản phẩm', '${claim['productName'] ?? ''}')}
    ${row('Seri / IMEI', [_serialLabel(serial), if (imei.isNotEmpty) 'IMEI $imei'].join(' · '))}
    ${row('Mua ngày', [_d(claim['saleDate']), if ('${claim['orderNo'] ?? ''}'.isNotEmpty) 'đơn ${claim['orderNo']}'].join(' · '))}
    ${row('Bảo hành', months > 0 ? '$months tháng — đến ${_d(claim['warrantyExpiry'])}${claim['inWarranty'] == false ? ' (đã hết hạn — sửa tính phí)' : ''}' : 'Không bảo hành — sửa tính phí')}
    ${row('Lỗi khách báo', '${claim['description'] ?? ''}')}
    ${row('Tình trạng máy', '${claim['deviceCondition'] ?? ''}')}
    ${row('Phụ kiện kèm', '${claim['accessories'] ?? ''}')}
    ${row('Hẹn trả', _d(claim['expectedReturnDate']))}
    ${row('Phụ trách', '${claim['assignedTo'] ?? ''}')}
    ${closed ? row(status == 'Rejected' ? 'Từ chối' : 'Kết quả sửa', '${claim['resolution'] ?? ''}') : ''}
    ${fee > 0 ? row('Phí sửa', '${_money.format(fee)} đ${claim['feePaid'] == true ? ' (đã thu)' : ' (chưa thu)'}') : ''}
    ${delivered ? row('Ngày trả máy', _d(claim['deliveredDate'])) : ''}
  </table>
  <div style="margin-top:10px;font-size:10.5pt;font-style:italic">
    ${delivered ? 'Khách đã nhận lại máy và phụ kiện như trên, kiểm tra máy hoạt động bình thường.' : 'Quý khách vui lòng mang theo phiếu này khi nhận lại máy. Cửa hàng không chịu trách nhiệm dữ liệu trong máy — vui lòng sao lưu trước khi gửi.'}
  </div>
  <table style="width:100%;margin-top:16px;text-align:center;font-size:12pt">
    <tr><td style="width:50%"><b>Khách hàng</b><br><i style="font-size:10pt">(ký, ghi rõ họ tên)</i></td>
        <td><b>${delivered ? 'Nhân viên trả máy' : 'Nhân viên tiếp nhận'}</b><br><i style="font-size:10pt">(ký, ghi rõ họ tên)</i></td></tr>
    <tr><td style="height:60px"></td><td></td></tr>
  </table>
</div>''';
    await showPosHtmlPrintDialog(
      context,
      title: '${delivered ? 'Phiếu trả máy' : 'Phiếu tiếp nhận'} ${claim['claimNo'] ?? ''}',
      htmlDocument: html,
      a4Paper: false,
    );
  }

  Future<void> call(String phone) async {
    final p = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.isEmpty) return;
    await launchUrl(Uri.parse('tel:$p'));
  }

  /// Mở Zalo của khách; lời nhắn chép sẵn vào bộ nhớ tạm để dán.
  Future<void> zalo(String phone, String message) async {
    var p = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('84') && p.length > 9) p = '0${p.substring(2)}';
    if (p.isEmpty) return;
    if (message.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: message));
      NotificationOverlayManager().showInfo(title: 'Zalo', message: tr('Đã chép lời nhắn — dán vào khung chat Zalo'));
    }
    await launchUrl(Uri.parse('https://zalo.me/$p'), mode: LaunchMode.externalApplication);
  }
}

// ───────────────────────── Thẻ phiếu bảo hành ─────────────────────────

class _ClaimCard extends StatelessWidget {
  const _ClaimCard({required this.claim, required this.actions, this.compact = false, this.onAction});

  final Map<String, dynamic> claim;
  final _WarrantyActions actions;
  final bool compact;

  /// Gọi trước mỗi thao tác (vd đóng sheet lịch sử).
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final type = '${claim['claimType'] ?? 'Repair'}';
    final status = '${claim['status'] ?? ''}';
    final delivered = claim['deliveredDate'] != null;
    final received = _date(claim['receivedDate']);
    final due = _date(claim['expectedReturnDate']);
    final now = DateTime.now();
    final inShop = type == 'Repair' && !delivered;
    final overdue = inShop && due != null && due.isBefore(now);
    final days = received == null ? 0 : now.difference(received).inDays;
    final fee = _n(claim['fee']);
    final phone = '${claim['contactPhone'] ?? claim['customerPhone'] ?? ''}';
    final (label, color) = switch ((type, status, delivered)) {
      ('Note', _, _) => ('Ghi chú', SboxColors.slate500),
      ('Replace', _, _) => ('Đổi máy', SboxColors.brand600),
      (_, _, true) => ('Đã trả khách', SboxColors.slate500),
      (_, 'Received', _) => ('Đã tiếp nhận', SboxColors.warning),
      (_, 'Processing', _) => ('Đang xử lý', SboxColors.brand600),
      (_, 'Done', _) => ('Sửa xong — chờ trả', SboxColors.success),
      (_, 'Rejected', _) => ('Từ chối — chờ trả', SboxColors.danger),
      _ => (status, SboxColors.slate500),
    };
    Widget btn(String text, IconData icon, Future<void> Function() run, {bool primary = false}) {
      void tap() {
        onAction?.call();
        unawaited(run());
      }

      return primary
          ? FilledButton.icon(
              onPressed: tap,
              icon: Icon(icon, size: 16),
              label: Text(tr(text)),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            )
          : OutlinedButton.icon(
              onPressed: tap,
              icon: Icon(icon, size: 16),
              label: Text(tr(text)),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: PosTheme.mobileCardDecoration().copyWith(
        border: overdue ? Border.all(color: SboxColors.danger, width: 1.2) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              tr([
                if ('${claim['claimNo'] ?? ''}'.isNotEmpty) '${claim['claimNo']}',
                if (!compact) '${claim['productName'] ?? ''}',
              ].join(' · ')),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Text(tr(label), style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (!compact)
          Text(tr('Seri: ${_serialLabel('${claim['serialNumber'] ?? ''}')}'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
        if (!compact && '${claim['contactName'] ?? claim['customerName'] ?? ''}'.isNotEmpty)
          Text(tr('Khách: ${claim['contactName'] ?? claim['customerName']}${phone.isEmpty ? '' : ' · $phone'}'),
              style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          tr([
            'Nhận ${_d(claim['receivedDate'])}',
            if (inShop) 'giữ $days ngày',
            if (inShop && due != null) 'hẹn trả ${_dateFmt.format(due)}${overdue ? ' — QUÁ HẸN' : ''}',
            if (delivered) 'trả ${_d(claim['deliveredDate'])}',
            if (claim['inWarranty'] == false && type == 'Repair') 'hết BH — tính phí',
          ].join(' · ')),
          style: TextStyle(fontSize: 11, color: overdue ? SboxColors.danger : PosTheme.textSecondary),
        ),
        if ('${claim['description'] ?? ''}'.isNotEmpty)
          Text(tr('${type == 'Note' ? 'Ghi chú' : 'Lỗi'}: ${claim['description']}'), style: const TextStyle(fontSize: 13)),
        if ('${claim['deviceCondition'] ?? ''}'.isNotEmpty)
          Text(tr('Tình trạng: ${claim['deviceCondition']}'), style: const TextStyle(fontSize: 12)),
        if ('${claim['accessories'] ?? ''}'.isNotEmpty)
          Text(tr('Phụ kiện: ${claim['accessories']}'), style: const TextStyle(fontSize: 12)),
        if ('${claim['assignedTo'] ?? ''}'.isNotEmpty)
          Text(tr('Phụ trách: ${claim['assignedTo']}'), style: const TextStyle(fontSize: 12)),
        if ('${claim['resolution'] ?? ''}'.isNotEmpty)
          Text(tr('Xử lý: ${claim['resolution']}'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        if (fee > 0)
          Text(tr('Phí sửa: ${_money.format(fee)} đ${claim['feePaid'] == true ? ' — đã thu' : ' — chưa thu'}'),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: claim['feePaid'] == true ? SboxColors.success : SboxColors.warningText)),
        if (type == 'Repair') ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (!delivered && status == 'Received')
              btn('Đang xử lý', Icons.build_outlined, () => actions.setProcessing(claim)),
            if (!delivered && (status == 'Received' || status == 'Processing')) ...[
              btn('Hoàn tất', Icons.check_circle_outline, () => actions.close(claim, done: true), primary: true),
              btn('Từ chối', Icons.block_outlined, () => actions.close(claim, done: false)),
              btn('Hẹn / phụ trách', Icons.event_outlined, () => actions.edit(claim)),
            ],
            if (!delivered && (status == 'Done' || status == 'Rejected'))
              btn('Trả khách', Icons.assignment_turned_in_outlined, () => actions.deliver(claim), primary: true),
            btn(delivered ? 'In phiếu trả' : 'In phiếu', Icons.print_outlined, () => actions.printClaim(claim)),
            if (phone.isNotEmpty) ...[
              btn('Gọi', Icons.call_outlined, () => actions.call(phone)),
              btn('Zalo', Icons.chat_outlined, () => actions.zalo(phone, _readyMessage(claim))),
            ],
          ]),
        ],
      ]),
    );
  }

  /// Lời nhắn mặc định khi nhắn khách: sửa xong / từ chối → mời lấy máy.
  static String _readyMessage(Map<String, dynamic> c) {
    final name = '${c['contactName'] ?? c['customerName'] ?? 'Quý khách'}';
    final product = '${c['productName'] ?? ''}';
    final no = '${c['claimNo'] ?? ''}';
    final status = '${c['status'] ?? ''}';
    if (status == 'Done') {
      final fee = _n(c['fee']);
      return 'Chào $name, máy $product (phiếu $no) đã sửa xong. '
          '${fee > 0 && c['feePaid'] != true ? 'Phí sửa ${_money.format(fee)}đ. ' : ''}'
          'Mời anh/chị mang phiếu đến cửa hàng nhận máy. Cảm ơn!';
    }
    if (status == 'Rejected') {
      return 'Chào $name, máy $product (phiếu $no) không thuộc diện bảo hành: ${c['resolution'] ?? ''}. '
          'Mời anh/chị đến cửa hàng nhận lại máy hoặc liên hệ để báo giá sửa.';
    }
    return 'Chào $name, cửa hàng đang xử lý máy $product (phiếu $no). Sẽ báo anh/chị ngay khi xong.';
  }
}

// ───────────────────────── Tab 1: Phiếu bảo hành ─────────────────────────

class _ClaimsTab extends StatefulWidget {
  const _ClaimsTab({required this.tick});
  final ValueNotifier<int> tick;

  @override
  State<_ClaimsTab> createState() => _ClaimsTabState();
}

class _ClaimsTabState extends State<_ClaimsTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  final _search = TextEditingController();
  String _status = 'InShop';
  bool _loading = false;
  int _total = 0;
  int _page = 1;
  final _items = <Map<String, dynamic>>[];

  static const _filters = [
    ('InShop', 'Máy ở cửa hàng'),
    ('Ready', 'Chờ khách lấy'),
    ('Overdue', 'Quá hẹn'),
    ('Delivered', 'Đã trả khách'),
    ('All', 'Tất cả'),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.tick.removeListener(_reload);
    _search.dispose();
    super.dispose();
  }

  void _reload() => unawaited(_load(reset: true));

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final page = reset ? 1 : _page + 1;
    final res = await _api.listPosWarrantyClaims(status: _status, search: _search.text, page: page);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] != true || res['data'] is! Map) return;
      final data = res['data'] as Map;
      final raw = data['items'];
      if (reset) _items.clear();
      if (raw is List) _items.addAll(raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      _total = _n(data['total']).toInt();
      _page = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final actions = _WarrantyActions(context, widget.tick);
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reload(),
            decoration: PosTheme.inputDecoration(
              label: 'Tìm số phiếu, seri, tên / SĐT khách, sản phẩm',
            ).copyWith(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _reload),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in _filters)
              ChoiceChip(
                label: Text(tr(f.$2)),
                selected: _status == f.$1,
                onSelected: (_) {
                  setState(() => _status = f.$1);
                  _reload();
                },
              ),
          ]),
          const SizedBox(height: 6),
          Text(
            tr(_status == 'InShop'
                ? 'Tiếp nhận máy mới: tab «Máy đã bán» → tìm seri / SĐT → «Tiếp nhận BH».'
                : '$_total phiếu'),
            style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(tr(_status == 'InShop' ? 'Không có máy nào đang ở cửa hàng' : 'Không có phiếu'),
                    style: const TextStyle(color: PosTheme.textSecondary)),
              ),
            ),
          for (final c in _items) _ClaimCard(claim: c, actions: actions),
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (_items.length < _total)
            TextButton(onPressed: () => _load(), child: Text(tr('Tải thêm (${_items.length}/$_total)'))),
        ],
      ),
    );
  }
}

// ───────────────────────── Tab 2: Máy đã bán ─────────────────────────

class _MachinesTab extends StatefulWidget {
  const _MachinesTab({required this.tick});
  final ValueNotifier<int> tick;

  @override
  State<_MachinesTab> createState() => _MachinesTabState();
}

class _MachinesTabState extends State<_MachinesTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  final _search = TextEditingController();
  String _status = '';
  bool _loading = false;
  int _total = 0;
  int _page = 1;
  final _items = <Map<String, dynamic>>[];

  static const _filters = [
    ('', 'Tất cả'),
    ('InWarranty', 'Còn bảo hành'),
    ('Expired', 'Hết bảo hành'),
    ('Replaced', 'Đã đổi máy'),
    ('Returned', 'Khách đã trả hàng'),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.tick.removeListener(_reload);
    _search.dispose();
    super.dispose();
  }

  void _reload() => unawaited(_load(reset: true));

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final page = reset ? 1 : _page + 1;
    final res = await _api.listPosWarranties(status: _status, search: _search.text, page: page);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] != true || res['data'] is! Map) return;
      final data = res['data'] as Map;
      final raw = data['items'];
      if (reset) _items.clear();
      if (raw is List) _items.addAll(raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      _total = _n(data['total']).toInt();
      _page = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final actions = _WarrantyActions(context, widget.tick);
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reload(),
            decoration: PosTheme.inputDecoration(
              label: 'Tìm seri / IMEI, tên hoặc SĐT khách, mã đơn, sản phẩm',
            ).copyWith(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _reload),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in _filters)
              ChoiceChip(
                label: Text(tr(f.$2)),
                selected: _status == f.$1,
                onSelected: (_) {
                  setState(() => _status = f.$1);
                  _reload();
                },
              ),
          ]),
          const SizedBox(height: 6),
          Text(tr('$_total máy'), style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          const SizedBox(height: 8),
          if (_items.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(tr('Chưa có máy nào'), style: const TextStyle(color: PosTheme.textSecondary)),
              ),
            ),
          for (final r in _items) _MachineCard(reg: r, actions: actions),
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (_items.length < _total)
            TextButton(onPressed: () => _load(), child: Text(tr('Tải thêm (${_items.length}/$_total)'))),
        ],
      ),
    );
  }
}

class _MachineCard extends StatelessWidget {
  const _MachineCard({required this.reg, required this.actions, this.expiringMode = false});

  final Map<String, dynamic> reg;
  final _WarrantyActions actions;

  /// Tab «Sắp hết hạn»: nút nhắn khách thay cho tiếp nhận / đổi máy.
  final bool expiringMode;

  @override
  Widget build(BuildContext context) {
    final expiry = _date(reg['warrantyExpiry'] ?? reg['WarrantyExpiry']);
    final saleDate = _date(reg['saleDate'] ?? reg['SaleDate']);
    final status = _s(reg, 'status').isEmpty ? 'Active' : _s(reg, 'status');
    final months = _n(reg['warrantyMonths'] ?? reg['WarrantyMonths']).toInt();
    final now = DateTime.now();
    final noWarranty = status == 'Active' && months <= 0;
    final expired = status == 'Active' && expiry != null && expiry.isBefore(now);
    final openClaim = _s(reg, 'openClaimStatus');
    final phone = _s(reg, 'customerPhone');
    final claimCount = _n(reg['claimCount'] ?? reg['ClaimCount']).toInt();
    final Color color;
    if (status != 'Active' || noWarranty) {
      color = SboxColors.slate500;
    } else if (expired) {
      color = SboxColors.danger;
    } else if (expiry != null && expiry.difference(now).inDays <= 30) {
      color = SboxColors.warning;
    } else {
      color = SboxColors.success;
    }
    final label = noWarranty
        ? 'Không bảo hành'
        : expired
            ? 'Hết BH'
            : switch (status) {
                'Active' => 'Còn BH',
                'Returned' => 'Khách đã trả',
                'Voided' => 'Đơn đã huỷ',
                'Replaced' => 'Đã đổi máy',
                _ => status,
              };

    Widget btn(String text, IconData icon, Future<void> Function() run, {bool primary = false}) => primary
        ? FilledButton.icon(
            onPressed: () => unawaited(run()),
            icon: Icon(icon, size: 16),
            label: Text(tr(text)),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          )
        : OutlinedButton.icon(
            onPressed: () => unawaited(run()),
            icon: Icon(icon, size: 16),
            label: Text(tr(text)),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(tr(_serialLabel(_s(reg, 'serialNumber'))),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Text(tr(label), style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (_s(reg, 'imei').isNotEmpty)
          Text(tr('IMEI: ${_s(reg, 'imei')}'), style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
        const SizedBox(height: 2),
        Text(tr(_s(reg, 'productName')), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        Text(
          tr([
            if (months > 0) 'BH $months tháng' else 'Không bảo hành',
            if (saleDate != null) 'Mua: ${_dateFmt.format(saleDate)}',
            if (expiry != null && months > 0) 'Hết BH: ${_dateFmt.format(expiry)}',
          ].join(' · ')),
          style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
        ),
        Text(
          tr([
            'Đơn: ${_s(reg, 'orderNo').isEmpty ? '—' : _s(reg, 'orderNo')}',
            if (_s(reg, 'customerName').isNotEmpty) 'KH: ${_s(reg, 'customerName')}',
            if (phone.isNotEmpty) 'SĐT: $phone',
          ].join(' · ')),
          style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
        ),
        if (_s(reg, 'note').isNotEmpty)
          Text(tr(_s(reg, 'note')), style: const TextStyle(fontSize: 11, color: SboxColors.brand700)),
        if (openClaim.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr(switch (openClaim) {
                'Done' => '● Đang ở cửa hàng — sửa xong, chờ khách lấy',
                'Rejected' => '● Đang ở cửa hàng — từ chối, chờ khách lấy',
                'Processing' => '● Đang ở cửa hàng — đang sửa',
                _ => '● Đang ở cửa hàng — đã tiếp nhận',
              }),
              style: const TextStyle(fontSize: 12, color: SboxColors.warningText, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (expiringMode) ...[
            if (phone.isNotEmpty) ...[
              btn('Nhắn Zalo', Icons.chat_outlined, () => actions.zalo(phone, _expiryMessage(reg)), primary: true),
              btn('Gọi', Icons.call_outlined, () => actions.call(phone)),
            ] else
              Text(tr('Khách chưa có SĐT'), style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
            btn('Chép lời nhắn', Icons.copy_outlined, () async {
              await Clipboard.setData(ClipboardData(text: _expiryMessage(reg)));
              NotificationOverlayManager().showSuccess(title: 'Bảo hành', message: tr('Đã chép lời nhắn'));
            }),
          ] else ...[
            if (status == 'Active' && openClaim.isEmpty)
              btn('Tiếp nhận BH', Icons.build_circle_outlined, () => actions.receive(reg), primary: true),
            btn('Lịch sử ($claimCount)', Icons.history_rounded, () => actions.history(reg)),
            if (status == 'Active' && months > 0 && !expired)
              btn('Đổi máy', Icons.swap_horiz_rounded, () => actions.replace(reg)),
            btn('Ghi chú', Icons.sticky_note_2_outlined, () => actions.note(reg)),
          ],
        ]),
      ]),
    );
  }

  static String _expiryMessage(Map<String, dynamic> r) {
    final name = _s(r, 'customerName').isEmpty ? 'Quý khách' : _s(r, 'customerName');
    final serial = _s(r, 'serialNumber');
    return 'Chào $name, máy ${_s(r, 'productName')}'
        '${serial.startsWith('AUTO-') ? '' : ' (seri $serial)'} anh/chị mua tại cửa hàng '
        'sẽ hết bảo hành ngày ${_d(r['warrantyExpiry'])}. Nếu máy có lỗi, mời anh/chị mang đến kiểm tra '
        'trước ngày này để được bảo hành miễn phí. Cảm ơn anh/chị!';
  }
}

// ───────────────────────── Tab 3: Sắp hết hạn ─────────────────────────

class _ExpiringTab extends StatefulWidget {
  const _ExpiringTab({required this.tick});
  final ValueNotifier<int> tick;

  @override
  State<_ExpiringTab> createState() => _ExpiringTabState();
}

class _ExpiringTabState extends State<_ExpiringTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  int _days = 30;
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.tick.removeListener(_reload);
    super.dispose();
  }

  void _reload() => unawaited(_load());

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosWarrantyExpiring(days: _days);
    if (!mounted) return;
    setState(() {
      _loading = false;
      final raw = res['data'] is Map ? (res['data'] as Map)['items'] : null;
      _items = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final actions = _WarrantyActions(context, widget.tick);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          Wrap(spacing: 6, children: [
            for (final d in const [30, 60, 90])
              ChoiceChip(
                label: Text(tr('$d ngày tới')),
                selected: _days == d,
                onSelected: (_) {
                  setState(() => _days = d);
                  _reload();
                },
              ),
          ]),
          const SizedBox(height: 6),
          Text(
            tr('${_items.length} máy hết bảo hành trong $_days ngày tới — nhắn khách mang máy đến kiểm tra trước khi hết hạn.'),
            style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(tr('Không có máy sắp hết bảo hành'), style: const TextStyle(color: PosTheme.textSecondary)),
              ),
            ),
          for (final r in _items) _MachineCard(reg: r, actions: actions, expiringMode: true),
        ],
      ),
    );
  }
}

// ───────────────────────── Tab 4: Báo cáo ─────────────────────────

class _ReportTab extends StatefulWidget {
  const _ReportTab({required this.tick});
  final ValueNotifier<int> tick;

  @override
  State<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<_ReportTab> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  int _preset = 1;
  bool _loading = false;
  Map<String, dynamic>? _data;

  static const _presets = ['Tháng này', '3 tháng', '6 tháng', 'Năm nay'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.tick.removeListener(_reload);
    super.dispose();
  }

  void _reload() => unawaited(_load());

  Future<void> _load() async {
    final now = DateTime.now();
    final from = switch (_preset) {
      0 => DateTime(now.year, now.month, 1),
      1 => DateTime(now.year, now.month - 2, 1),
      2 => DateTime(now.year, now.month - 5, 1),
      _ => DateTime(now.year, 1, 1),
    };
    setState(() => _loading = true);
    final res = await _api.getPosWarrantyReport(from: from, to: now);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : null;
    });
  }

  Widget _tile(String label, String value, {Color? color, String? hint}) => Container(
        width: 160,
        padding: const EdgeInsets.all(10),
        decoration: PosTheme.mobileCardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(label), style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color ?? SboxColors.text)),
          if (hint != null) Text(tr(hint), style: const TextStyle(fontSize: 10, color: PosTheme.textSecondary)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = _data;
    final months = (d?['byMonth'] as List?)?.whereType<Map>().toList() ?? const [];
    final products = (d?['byProduct'] as List?)?.whereType<Map>().toList() ?? const [];
    final maxClaims = months.fold<num>(1, (m, x) => _n(x['claims']) > m ? _n(x['claims']) : m);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          Wrap(spacing: 6, children: [
            for (var i = 0; i < _presets.length; i++)
              ChoiceChip(
                label: Text(tr(_presets[i])),
                selected: _preset == i,
                onSelected: (_) {
                  setState(() => _preset = i);
                  _reload();
                },
              ),
          ]),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (d == null)
            Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('Không tải được báo cáo'))))
          else ...[
            Text(tr('Hiện tại'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _tile('Máy ở cửa hàng', '${d['inShopNow'] ?? 0}', color: SboxColors.brand700),
              _tile('Chờ khách lấy', '${d['readyToReturn'] ?? 0}', color: SboxColors.success),
              _tile('Quá hẹn trả', '${d['overdueNow'] ?? 0}', color: _n(d['overdueNow']) > 0 ? SboxColors.danger : null),
              _tile('Máy còn bảo hành', '${d['activeWarranties'] ?? 0}', hint: '${d['expiring30'] ?? 0} hết hạn trong 30 ngày'),
            ]),
            const SizedBox(height: 14),
            Text(tr('Trong kỳ ${_d(d['from'])} – ${_d(d['to'])}'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _tile('Lượt bảo hành', '${d['totalClaims'] ?? 0}', hint: '${d['repairs'] ?? 0} sửa · ${d['replaces'] ?? 0} đổi máy'),
              _tile('Từ chối', '${d['rejected'] ?? 0}'),
              _tile('Hết BH (tính phí)', '${d['outOfWarranty'] ?? 0}'),
              _tile('Xử lý trung bình', '${d['avgDays'] ?? 0} ngày'),
              _tile('Phí sửa đã thu', '${_money.format(_n(d['feeCollected']))} đ', color: SboxColors.success,
                  hint: _n(d['feeUnpaid']) > 0 ? 'Chưa thu ${_money.format(_n(d['feeUnpaid']))} đ' : null),
            ]),
            if (months.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(tr('Theo tháng'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final m in months)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    SizedBox(width: 70, child: Text('${m['month']}', style: const TextStyle(fontSize: 12))),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, c) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 14,
                            width: c.maxWidth * (_n(m['claims']) / maxClaims).clamp(0.02, 1.0),
                            decoration: BoxDecoration(
                              color: SboxColors.brand600,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: Text(
                        tr('${m['claims']} lượt · ${m['replaces']} đổi${_n(m['fee']) > 0 ? ' · ${_money.format(_n(m['fee']))}đ' : ''}'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ]),
                ),
            ],
            if (products.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(tr('Mặt hàng hay bảo hành'), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(tr('Tỉ lệ = lượt bảo hành trong kỳ / số máy đã bán có bảo hành'),
                  style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary)),
              const SizedBox(height: 6),
              Container(
                decoration: PosTheme.mobileCardDecoration(),
                child: Column(children: [
                  for (final p in products)
                    ListTile(
                      dense: true,
                      title: Text(tr('${p['productName'] ?? ''}')),
                      subtitle: Text(tr('${p['claims']} lượt · ${p['replaces']} đổi máy · đã bán ${p['sold']}')),
                      trailing: Text(
                        '${p['ratePercent']}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _n(p['ratePercent']) >= 10 ? SboxColors.danger : SboxColors.text,
                        ),
                      ),
                    ),
                ]),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
