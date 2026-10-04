import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pos_voucher.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
class PosVouchersScreen extends StatefulWidget {
  const PosVouchersScreen({super.key});

  @override
  State<PosVouchersScreen> createState() => _PosVouchersScreenState();
}

class _PosVouchersScreenState extends State<PosVouchersScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  List<PosVoucher> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosVouchers(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      activeOnly: false,
      pageSize: 100,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final raw = (res['data'] as Map)['items'] as List? ?? [];
      setState(() {
        _items = raw
            .map((e) => PosVoucher.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _openEditor([PosVoucher? existing]) async {
    String num0(double? v) => v == null ? '' : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final valueCtrl = TextEditingController(text: num0(existing?.discountValue));
    final minCtrl = TextEditingController(text: existing != null ? num0(existing.minOrderAmount) : '0');
    final maxDiscCtrl = TextEditingController(text: num0(existing?.maxDiscountAmount));
    final maxUsesCtrl = TextEditingController(text: existing?.maxUses?.toString() ?? '');
    var isPercent = existing?.isPercent ?? false;
    var isActive = existing?.isActive ?? true;
    DateTime? from = existing?.validFrom?.toLocal();
    DateTime? to = existing?.validTo?.toLocal();
    final dayFmt = DateFormat('dd/MM/yyyy');
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          Future<void> pickRange() async {
            final now = DateTime.now();
            final r = await showDateRangePicker(
              context: ctx,
              firstDate: DateTime(now.year - 2),
              lastDate: DateTime(now.year + 5),
              initialDateRange: from != null && to != null ? DateTimeRange(start: from!, end: to!) : null,
            );
            if (r != null) setDlg(() {
              from = r.start;
              to = r.end;
            });
          }

          return AlertDialog(
            title: Text(tr(existing == null ? 'Thêm voucher' : 'Sửa voucher')),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: codeCtrl,
                      decoration: InputDecoration(labelText: tr('Mã voucher *')),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    TextField(controller: nameCtrl, decoration: InputDecoration(labelText: tr('Tên chương trình'))),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: false, label: Text(tr('Giảm tiền'))),
                        ButtonSegment(value: true, label: Text(tr('Giảm %'))),
                      ],
                      selected: {isPercent},
                      onSelectionChanged: (v) => setDlg(() => isPercent = v.first),
                    ),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: valueCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tr(isPercent ? 'Phần trăm giảm *' : 'Số tiền giảm *'),
                            suffixText: isPercent ? '%' : 'đ',
                          ),
                        ),
                      ),
                      if (isPercent) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxDiscCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: tr('Giảm tối đa'), suffixText: 'đ', hintText: tr('Không giới hạn')),
                          ),
                        ),
                      ],
                    ]),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: minCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: tr('Đơn tối thiểu'), suffixText: 'đ'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maxUsesCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: tr('Số lượt tối đa'), hintText: tr('Không giới hạn')),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: pickRange,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: tr('Thời gian hiệu lực'),
                          suffixIcon: from == null
                              ? const Icon(Icons.date_range_outlined)
                              : IconButton(
                                  tooltip: tr('Không giới hạn'),
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setDlg(() {
                                    from = null;
                                    to = null;
                                  }),
                                ),
                        ),
                        child: Text(from == null || to == null
                            ? tr('Không giới hạn')
                            : '${dayFmt.format(from!)} – ${dayFmt.format(to!)}'),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('Đang hoạt động')),
                      value: isActive,
                      onChanged: (v) => setDlg(() => isActive = v),
                    ),
                    if (error != null)
                      Text(tr(error!), style: SboxType.smallStyle(SboxColors.dangerText)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
              FilledButton(
                onPressed: () {
                  final value = (isPercent
                          ? double.tryParse(valueCtrl.text.trim().replaceAll(',', '.'))
                          : double.tryParse(valueCtrl.text.replaceAll(',', '').replaceAll('.', ''))) ??
                      0;
                  if (codeCtrl.text.trim().isEmpty) return setDlg(() => error = 'Nhập mã voucher');
                  if (value <= 0) return setDlg(() => error = 'Mức giảm phải lớn hơn 0');
                  if (isPercent && value > 100) return setDlg(() => error = 'Giảm % không quá 100');
                  Navigator.pop(ctx, true);
                },
                child: Text(tr('Lưu')),
              ),
            ],
          );
        },
      ),
    );

    double? parseMoney(TextEditingController c) {
      final t = c.text.replaceAll(',', '').replaceAll('.', '').trim();
      return t.isEmpty ? null : double.tryParse(t);
    }

    final body = <String, dynamic>{
      'code': codeCtrl.text.trim(),
      'name': nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      // Máy chủ: Percent = 0, Fixed = 1 (trước đây gửi ngược → «giảm 10%» lưu thành giảm 10đ).
      'discountType': isPercent ? 0 : 1,
      'discountValue': (isPercent ? double.tryParse(valueCtrl.text.trim().replaceAll(',', '.')) : parseMoney(valueCtrl)) ?? 0,
      'minOrderAmount': parseMoney(minCtrl) ?? 0,
      // Gửi đủ các trường — trước đây sửa voucher làm mất hạn dùng / số lượt / giảm tối đa.
      'maxDiscountAmount': isPercent ? parseMoney(maxDiscCtrl) : null,
      'validFrom': from == null ? null : DateTime(from!.year, from!.month, from!.day).toUtc().toIso8601String(),
      'validTo': to == null ? null : DateTime(to!.year, to!.month, to!.day, 23, 59, 59).toUtc().toIso8601String(),
      'maxUses': int.tryParse(maxUsesCtrl.text.trim()),
      'customerId': existing?.customerId,
      'isActive': isActive,
    };
    for (final c in [codeCtrl, nameCtrl, valueCtrl, minCtrl, maxDiscCtrl, maxUsesCtrl]) {
      c.dispose();
    }
    if (ok != true) return;

    final res = existing == null
        ? await _api.createPosVoucher(body)
        : await _api.updatePosVoucher(existing.id, body);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã lưu', message: body['code'].toString());
      _load();
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  Timer? _debounce;

  /// Trạng thái thực tế: tắt tay / hết hạn / hết lượt / chưa tới ngày / đang chạy.
  (String, SboxTone) _status(PosVoucher v) {
    final now = DateTime.now();
    if (!v.isActive) return ('Đã tắt', SboxTone.neutral);
    if (v.validTo != null && v.validTo!.toLocal().isBefore(now)) return ('Hết hạn', SboxTone.danger);
    if (v.maxUses != null && v.usedCount >= v.maxUses!) return ('Hết lượt', SboxTone.warning);
    if (v.validFrom != null && v.validFrom!.toLocal().isAfter(now)) return ('Chưa tới ngày', SboxTone.violet);
    return ('Đang chạy', SboxTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canEdit = perm.canEdit('PosProducts');
    final running = _items.where((v) => _status(v).$1 == 'Đang chạy').length;
    final used = _items.fold<int>(0, (a, v) => a + v.usedCount);
    String day(DateTime? d) => d == null ? '—' : DateFormat('dd/MM/yyyy').format(d.toLocal());
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: Navigator.of(context).canPop()
          ? AppBar(
              title: Text(tr('Voucher')),
              backgroundColor: Colors.white,
              foregroundColor: SboxColors.text,
              surfaceTintColor: Colors.white,
              elevation: 0.5,
            )
          : null,
      body: SboxReportLayout(
        onRefresh: _load,
        filters: SboxFilterBar(
          searchHint: 'Tìm mã voucher',
          searchController: _searchCtrl,
          onSearch: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _load);
          },
          actions: [
            if (canEdit) SboxButton(label: 'Thêm voucher', icon: Icons.add, onPressed: () => _openEditor()),
          ],
        ),
        kpis: [
          SboxKpi(label: 'Voucher', value: SboxFmt.number(_items.length), icon: Icons.confirmation_number_outlined),
          SboxKpi(label: 'Đang chạy', value: SboxFmt.number(running), icon: Icons.play_circle_outline, tone: SboxTone.success),
          SboxKpi(label: 'Lượt đã dùng', value: SboxFmt.number(used), icon: Icons.receipt_long_outlined, tone: SboxTone.violet),
        ],
        maxKpiColumns: 3,
        table: SboxCard(
          padding: EdgeInsets.zero,
          child: SboxDataTable<PosVoucher>(
            loading: _loading,
            rows: _items,
            pageSize: 50,
            onRowTap: canEdit ? (v) => _openEditor(v) : null,
            emptyTitle: 'Chưa có voucher',
            emptyMessage: canEdit ? 'Tạo mã giảm giá để khách nhập khi thanh toán.' : null,
            columns: [
              SboxColumn(
                label: 'Mã',
                primary: true,
                flex: 2,
                minWidth: 180,
                cell: (v) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(v.code, style: SboxType.bodyStyle().copyWith(fontWeight: SboxType.semibold)),
                  if ((v.name ?? '').isNotEmpty)
                    Text(v.name!, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.textMuted)),
                ]),
                sortValue: (v) => v.code,
              ),
              SboxColumn(
                label: 'Giảm',
                numeric: true,
                minWidth: 110,
                // Voucher cũ lưu nhầm kiểu giảm (vd «giảm 50.000%») → báo đỏ để sửa lại.
                cell: (v) {
                  final wrong = v.isPercent && v.discountValue > 100;
                  return Tooltip(
                    message: wrong ? tr('Sai kiểu giảm: % không thể quá 100 — bấm để sửa thành «Giảm tiền»') : '',
                    child: Text(
                      wrong
                          ? tr('${v.discountValue.toStringAsFixed(0)}% ⚠ sai kiểu')
                          : v.isPercent
                              ? '${v.discountValue.toStringAsFixed(0)}%${v.maxDiscountAmount != null && v.maxDiscountAmount! > 0 ? ' (≤ ${SboxFmt.money(v.maxDiscountAmount!)})' : ''}'
                              : SboxFmt.money(v.discountValue),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: wrong
                          ? const TextStyle(color: SboxColors.dangerText, fontWeight: FontWeight.w700)
                          : const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );
                },
              ),
              SboxColumn(label: 'Đơn tối thiểu', numeric: true, minWidth: 120, hideOnMobile: true,
                  text: (v) => v.minOrderAmount > 0 ? SboxFmt.money(v.minOrderAmount) : '—'),
              SboxColumn(label: 'Hiệu lực', minWidth: 190, hideOnMobile: true,
                  text: (v) => v.validFrom == null && v.validTo == null ? 'Không giới hạn' : '${day(v.validFrom)} – ${day(v.validTo)}'),
              SboxColumn(label: 'Đã dùng', numeric: true, minWidth: 90,
                  text: (v) => '${v.usedCount}${v.maxUses != null ? '/${v.maxUses}' : ''}', sortValue: (v) => v.usedCount),
              SboxColumn(
                label: 'Trạng thái',
                minWidth: 120,
                cell: (v) {
                  final st = _status(v);
                  return Align(alignment: Alignment.centerLeft, child: SboxStatusChip(label: st.$1, tone: st.$2));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
