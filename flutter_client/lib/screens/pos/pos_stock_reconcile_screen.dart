import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';

/// Đối soát kho: tồn tổng so với tổng các lô, số seri trong kho, tồn các chi nhánh và giữ chỗ đơn nháp.
/// Cho thấy dữ liệu đang lệch ở đâu; chỉ «Sửa giữ chỗ» tự xử lý, các loại còn lại xử lý bằng kiểm kê / phiếu.
class PosStockReconcileScreen extends StatefulWidget {
  const PosStockReconcileScreen({super.key});

  @override
  State<PosStockReconcileScreen> createState() => _PosStockReconcileScreenState();
}

class _PosStockReconcileScreenState extends State<PosStockReconcileScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _counts = {};
  String? _reservedNote;
  int _checked = 0;
  String _kind = '';

  static const _kinds = <String, (String, IconData, Color)>{
    'lot': ('Lô / HSD', Icons.event_available_outlined, SboxColors.warning),
    'lotbranch': ('Lô theo chi nhánh', Icons.account_tree_outlined, SboxColors.warning),
    'serial': ('Seri', Icons.qr_code_2_rounded, SboxColors.violet),
    'branch': ('Chi nhánh', Icons.store_mall_directory_outlined, SboxColors.brand600),
    'reserved': ('Giữ chỗ', Icons.lock_clock_outlined, SboxColors.danger),
  };

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
    final r = await _api.getPosStockReconcile();
    if (!mounted) return;
    if (r['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = r['message']?.toString() ?? 'Không tải được đối soát';
      });
      return;
    }
    final d = Map<String, dynamic>.from(r['data'] as Map);
    setState(() {
      _loading = false;
      _items = [
        for (final x in (d['items'] as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ];
      _counts = Map<String, dynamic>.from((d['counts'] as Map?) ?? const {});
      _reservedNote = d['reservedNote']?.toString();
      _checked = (d['checkedProducts'] as num?)?.toInt() ?? 0;
    });
  }

  Future<void> _fixReserved() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sửa giữ chỗ')),
        content: Text(tr('Đặt lại số giữ chỗ của mọi hàng về đúng nhu cầu của các đơn nháp đang mở. Không đổi tồn kho.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sửa'))),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.fixPosReservedStock();
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đối soát kho', message: tr('Đã sửa ${(r['data'] as Map?)?['fixedCount'] ?? 0} hàng'));
      _load();
    } else {
      NotificationOverlayManager()
          .showError(title: 'Đối soát kho', message: r['message']?.toString() ?? 'Thao tác thất bại');
    }
  }

  String _q(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _kind.isEmpty ? _items : _items.where((i) => i['kind'] == _kind).toList();
    final total = _items.length;
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: AppBar(
        title: Text(tr('Đối soát kho')),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (total == 0 ? SboxColors.success : SboxColors.warning).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(children: [
                        Icon(total == 0 ? Icons.verified_rounded : Icons.rule_rounded,
                            color: total == 0 ? SboxColors.success : SboxColors.warning),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tr(total == 0
                                ? 'Kho khớp: đã đối soát $_checked mặt hàng, không có chênh lệch.'
                                : 'Đã đối soát $_checked mặt hàng, có $total chênh lệch cần xem.'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                    ),
                    if (_reservedNote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(tr('Chưa đối soát được giữ chỗ: $_reservedNote'),
                            style: const TextStyle(color: SboxColors.slate500, fontSize: 12)),
                      ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(tr('Tất cả ($total)')),
                            selected: _kind.isEmpty,
                            onSelected: (_) => setState(() => _kind = ''),
                          ),
                        ),
                        for (final e in _kinds.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              avatar: Icon(e.value.$2, size: 16, color: e.value.$3),
                              label: Text(tr('${e.value.$1} (${(_counts[e.key] as num?)?.toInt() ?? 0})')),
                              selected: _kind == e.key,
                              onSelected: (_) => setState(() => _kind = e.key),
                            ),
                          ),
                      ]),
                    ),
                    if ((_counts['reserved'] as num? ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: _fixReserved,
                            icon: const Icon(Icons.build_circle_outlined, size: 18),
                            label: Text(tr('Sửa giữ chỗ')),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(child: Text(tr('Không có chênh lệch'), style: const TextStyle(color: SboxColors.slate500))),
                      )
                    else
                      for (final i in shown)
                        Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12), side: const BorderSide(color: SboxColors.slate200)),
                          child: ListTile(
                            leading: Icon(_kinds[i['kind']]?.$2 ?? Icons.help_outline, color: _kinds[i['kind']]?.$3),
                            title: Text(tr('${i['productName']}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(tr('${i['hint']}\nTồn ${_q(i['onHand'])} · so với ${_q(i['compared'])} · lệch ${_q(i['diff'])}')),
                            isThreeLine: true,
                          ),
                        ),
                  ],
                ),
    );
  }
}
