import 'package:flutter/material.dart';
import '../../utils/api_datetime.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
class PosWarrantyLookupScreen extends StatefulWidget {
  const PosWarrantyLookupScreen({super.key});

  @override
  State<PosWarrantyLookupScreen> createState() => _PosWarrantyLookupScreenState();
}

class _PosWarrantyLookupScreenState extends State<PosWarrantyLookupScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  int _mode = 0;
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _expiring = [];
  List<Map<String, dynamic>> _openClaims = [];

  static final _dateFmt = DateFormat('dd/MM/yyyy', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _loadExpiring();
    _loadOpenClaims();
  }

  Future<void> _loadOpenClaims() async {
    final res = await _api.getPosWarrantyOpenClaims();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final raw = (res['data'] as Map)['items'];
      setState(() {
        _openClaims = raw is List
            ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExpiring() async {
    final res = await _api.getPosWarrantyExpiring(days: 30);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map<String, dynamic>;
      final raw = data['items'];
      setState(() {
        _expiring = raw is List
            ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
      });
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      NotificationOverlayManager().showInfo(
        title: 'Tra cứu bảo hành',
        message: tr('Nhập seri, SĐT hoặc mã đơn'),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await _api.lookupPosWarranty(
        serial: _mode == 0 ? q : null,
        phone: _mode == 1 ? q : null,
        orderNo: _mode == 2 ? q : null,
      );
      if (!mounted) return;
      if (res['isSuccess'] != true) {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Tra cứu thất bại',
        );
        return;
      }
      final data = res['data'] as Map<String, dynamic>?;
      final raw = data?['items'];
      setState(() {
        _items = raw is List
            ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PosTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PosMobileKiotHeader(title: 'Tra cứu bảo hành'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(tr('Seri'))),
                ButtonSegment(value: 1, label: Text(tr('SĐT'))),
                ButtonSegment(value: 2, label: Text(tr('Mã đơn'))),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: PosTheme.inputDecoration(
                      label: _mode == 0
                          ? 'Seri / IMEI'
                          : _mode == 1
                              ? 'Số điện thoại khách'
                              : 'Mã đơn hàng',
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(tr('Tra')),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                if (_items.isNotEmpty) ...[
                  _sectionTitle('Kết quả tra cứu (${_items.length})'),
                  ..._items.map(_warrantyCard),
                ],
                if (_items.isEmpty && !_loading)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(tr('Nhập thông tin và bấm Tra cứu'),
                        style: TextStyle(color: PosTheme.textSecondary),
                      ),
                    ),
                  ),
                if (_openClaims.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionTitle('Phiếu bảo hành đang xử lý — ${_openClaims.length}'),
                  for (final oc in _openClaims)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: PosTheme.mobileCardDecoration(),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('${oc['serial'] ?? ''} · ${oc['productName'] ?? ''}'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(tr('${(oc['claim'] as Map?)?['description'] ?? ''}'),
                            style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => _showHistory({
                              'id': (oc['claim'] as Map?)?['registrationId'],
                              'serialNumber': oc['serial'],
                            }),
                            child: Text(tr('Xử lý')),
                          ),
                        ),
                      ]),
                    ),
                ],
                if (_expiring.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionTitle('Sắp hết BH (30 ngày) — ${_expiring.length}'),
                  ..._expiring.map(_warrantyCard),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          tr(text),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      );

  Widget _warrantyCard(Map<String, dynamic> r) {
    final expiry = parseApiUtcDateTime('${r['warrantyExpiry'] ?? r['WarrantyExpiry'] ?? ''}');
    final saleDate = parseApiUtcDateTime('${r['saleDate'] ?? r['SaleDate'] ?? ''}');
    final status = (r['status'] ?? r['Status'] ?? 'Active').toString();
    final months = (r['warrantyMonths'] ?? r['WarrantyMonths'] as num?)?.toInt() ?? 0;
    final now = DateTime.now();
    final noWarranty = status == 'Active' && months <= 0;
    Color? statusColor;
    if (status != 'Active' || noWarranty) {
      statusColor = SboxColors.slate500;
    } else if (expiry != null && expiry.isBefore(now)) {
      statusColor = SboxColors.danger;
    } else if (expiry != null && expiry.difference(now).inDays <= 30) {
      statusColor = SboxColors.warning;
    } else {
      statusColor = SboxColors.success;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(((r['serialNumber'] ?? r['SerialNumber'] ?? '').toString()).startsWith('AUTO-')
                      ? 'Không có seri — bảo hành theo đơn'
                      : (r['serialNumber'] ?? r['SerialNumber'] ?? '').toString()),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  tr(noWarranty
                      ? 'Không bảo hành'
                      : (status == 'Active' && expiry != null && expiry.isBefore(now))
                          ? 'Hết BH'
                          : _statusLabel(status)),
                  style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (r['imei'] != null || r['Imei'] != null)
            Text(
              tr('IMEI: ${r['imei'] ?? r['Imei']}'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          const SizedBox(height: 4),
          Text(
            tr((r['productName'] ?? r['ProductName'] ?? '').toString()),
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            tr([
              if (months > 0) 'BH $months tháng' else 'Không bảo hành',
              if (saleDate != null) 'Mua: ${_dateFmt.format(saleDate.toLocal())}',
              if (expiry != null && months > 0) 'Hết BH: ${_dateFmt.format(expiry.toLocal())}',
            ].join(' · ')),
            style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
          ),
          Text(
            tr([
              'Đơn: ${r['orderNo'] ?? r['OrderNo'] ?? '—'}',
              if (r['customerName'] ?? r['CustomerName'] != null)
                'KH: ${r['customerName'] ?? r['CustomerName']}',
              if (r['customerPhone'] ?? r['CustomerPhone'] != null)
                'SĐT: ${r['customerPhone'] ?? r['CustomerPhone']}',
            ].join(' · ')),
            style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
          ),
          if (status == 'Active') ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              OutlinedButton.icon(
                onPressed: () => _showHistory(r),
                icon: const Icon(Icons.history_rounded, size: 16),
                label: Text(tr('Lịch sử (${(r['claimCount'] ?? r['ClaimCount'] ?? 0)})')),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              OutlinedButton.icon(
                onPressed: () => _receiveClaim(r),
                icon: const Icon(Icons.build_circle_outlined, size: 16),
                label: Text(tr('Tiếp nhận BH')),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              if (months > 0 && expiry != null && !expiry.isBefore(now))
                OutlinedButton.icon(
                  onPressed: () => _replaceSerial(r),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: Text(tr('Đổi máy')),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
            ]),
          ],
        ],
      ),
    );
  }

  String _regId(Map<String, dynamic> r) => (r['id'] ?? r['Id']).toString();

  /// Hộp nhập nhiều trường; trả về null nếu huỷ. Trường bắt buộc rỗng → không đóng.
  Future<List<String>?> _form(String title, List<(String label, bool required)> fields) async {
    final ctls = [for (final _ in fields) TextEditingController()];
    final r = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: ctls[i],
                    autofocus: i == 0,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: tr('${fields[i].$1}${fields[i].$2 ? ' *' : ''}'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
          FilledButton(
            onPressed: () {
              for (var i = 0; i < fields.length; i++) {
                if (fields[i].$2 && ctls[i].text.trim().isEmpty) return;
              }
              Navigator.pop(ctx, [for (final c in ctls) c.text.trim()]);
            },
            child: Text(tr('Xác nhận')),
          ),
        ],
      ),
    );
    for (final c in ctls) {
      c.dispose();
    }
    return r;
  }

  void _toast(Map<String, dynamic> res, String ok) {
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Bảo hành', message: ok);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Bảo hành', message: res['message']?.toString() ?? 'Thao tác thất bại');
    }
  }

  Future<void> _receiveClaim(Map<String, dynamic> r) async {
    final v = await _form('Tiếp nhận bảo hành', [('Mô tả lỗi / yêu cầu của khách', true)]);
    if (v == null) return;
    final res = await _api.createPosWarrantyClaim(_regId(r), 'Repair', v[0]);
    _toast(res, 'Đã tiếp nhận bảo hành');
    if (res['isSuccess'] == true) {
      if (_items.isNotEmpty) await _search();
      await _loadOpenClaims();
    }
  }

  Future<void> _replaceSerial(Map<String, dynamic> r) async {
    final v = await _form('Đổi máy bảo hành', [
      ('Seri máy mới', true),
      ('IMEI máy mới', false),
      ('Lý do đổi máy', true),
    ]);
    if (v == null) return;
    final res = await _api.replacePosWarrantySerial(_regId(r), v[0], v[1].isEmpty ? null : v[1], v[2]);
    _toast(res, 'Đã đổi máy — seri mới giữ nguyên hạn bảo hành còn lại');
    if (res['isSuccess'] == true && _items.isNotEmpty) await _search();
  }

  Future<void> _showHistory(Map<String, dynamic> r) async {
    final res = await _api.getPosWarrantyClaims(_regId(r));
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      _toast(res, '');
      return;
    }
    final raw = (res['data'] as Map?)?['items'];
    final claims = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    const typeLabel = {'Repair': 'Sửa chữa', 'Replace': 'Đổi máy', 'Note': 'Ghi chú'};
    const statusLabel = {'Received': 'Đã tiếp nhận', 'Processing': 'Đang xử lý', 'Done': 'Hoàn tất', 'Rejected': 'Từ chối'};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            shrinkWrap: true,
            children: [
              Text(tr('Lịch sử bảo hành — ${r['serialNumber'] ?? r['SerialNumber'] ?? ''}'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (claims.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(tr('Chưa có lần bảo hành nào'))),
                ),
              for (final c in claims)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: PosTheme.mobileCardDecoration(),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      tr('${typeLabel[c['claimType']] ?? c['claimType']} · ${statusLabel[c['status']] ?? c['status']}'
                          '${c['inWarranty'] == false ? ' · tính phí (hết BH)' : ''}'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      tr('Nhận: ${_dateFmt.format((parseApiUtcDateTime('${c['receivedDate']}') ?? DateTime.now()).toLocal())}'
                          '${c['resolvedDate'] != null ? ' · Xong: ${_dateFmt.format((parseApiUtcDateTime('${c['resolvedDate']}') ?? DateTime.now()).toLocal())}' : ''}'),
                      style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                    ),
                    if ((c['description']?.toString() ?? '').isNotEmpty) Text(tr('Lỗi: ${c['description']}')),
                    if ((c['resolution']?.toString() ?? '').isNotEmpty) Text(tr('Xử lý: ${c['resolution']}')),
                    if (c['status'] == 'Received' || c['status'] == 'Processing')
                      Wrap(spacing: 6, children: [
                        if (c['status'] == 'Received')
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final res = await _api.updatePosWarrantyClaim(c['id'].toString(), 'Processing', null);
                              _toast(res, 'Đã chuyển sang đang xử lý');
                              if (mounted) {
                                await _loadOpenClaims();
                                _showHistory(r);
                              }
                            },
                            child: Text(tr('Đang xử lý')),
                          ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _closeClaim(c, r, 'Done');
                          },
                          child: Text(tr('Hoàn tất')),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _closeClaim(c, r, 'Rejected');
                          },
                          child: Text(tr('Từ chối')),
                        ),
                      ]),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _closeClaim(Map<String, dynamic> c, Map<String, dynamic> r, String status) async {
    final v = await _form(status == 'Done' ? 'Hoàn tất bảo hành' : 'Từ chối bảo hành', [('Kết quả xử lý', true)]);
    if (v == null) {
      if (mounted) _showHistory(r);
      return;
    }
    final res = await _api.updatePosWarrantyClaim(c['id'].toString(), status, v[0]);
    _toast(res, 'Đã cập nhật phiếu bảo hành');
    if (!mounted) return;
    await _loadOpenClaims();
    _showHistory(r);
  }

  String _statusLabel(String status) => switch (status) {
        'Active' => 'Còn BH',
        'Returned' => 'Đã trả',
        'Voided' => 'Huỷ',
        'Replaced' => 'Thay thế',
        _ => status,
      };
}
