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
    final codeCtrl = TextEditingController(text: tr(existing?.code ?? ''));
    final nameCtrl = TextEditingController(text: tr(existing?.name ?? ''));
    final valueCtrl = TextEditingController(
      text: tr(existing != null ? existing.discountValue.toStringAsFixed(0) : ''),
    );
    final minCtrl = TextEditingController(
      text: tr(existing != null ? existing.minOrderAmount.toStringAsFixed(0) : '0'),
    );
    var isPercent = existing?.isPercent ?? false;
    var isActive = existing?.isActive ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr(existing == null ? 'Thêm voucher' : 'Sửa voucher')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  decoration: InputDecoration(labelText: tr('Mã voucher *')),
                  textCapitalization: TextCapitalization.characters,
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: tr('Tên')),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(tr('Giảm tiền'))),
                    ButtonSegment(value: true, label: Text(tr('Giảm %'))),
                  ],
                  selected: {isPercent},
                  onSelectionChanged: (s) => setDlg(() => isPercent = s.first),
                ),
                TextField(
                  controller: valueCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr(isPercent ? 'Phần trăm' : 'Số tiền giảm'),
                  ),
                ),
                TextField(
                  controller: minCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr('Đơn tối thiểu')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Đang hoạt động')),
                  value: isActive,
                  onChanged: (v) => setDlg(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
          ],
        ),
      ),
    );

    if (ok != true) {
      codeCtrl.dispose();
      nameCtrl.dispose();
      valueCtrl.dispose();
      minCtrl.dispose();
      return;
    }

    final body = {
      'code': codeCtrl.text.trim(),
      'name': nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      'discountType': isPercent ? 1 : 0,
      'discountValue': double.tryParse(valueCtrl.text.replaceAll(',', '')) ?? 0,
      'minOrderAmount': double.tryParse(minCtrl.text.replaceAll(',', '')) ?? 0,
      'isActive': isActive,
    };
    codeCtrl.dispose();
    nameCtrl.dispose();
    valueCtrl.dispose();
    minCtrl.dispose();

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
                text: (v) => v.isPercent
                    ? '${v.discountValue.toStringAsFixed(0)}%${v.maxDiscountAmount != null && v.maxDiscountAmount! > 0 ? ' (≤ ${SboxFmt.money(v.maxDiscountAmount!)})' : ''}'
                    : SboxFmt.money(v.discountValue),
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
