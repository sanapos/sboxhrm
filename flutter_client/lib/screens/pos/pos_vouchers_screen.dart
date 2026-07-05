import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_voucher.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';

class PosVouchersScreen extends StatefulWidget {
  const PosVouchersScreen({super.key});

  @override
  State<PosVouchersScreen> createState() => _PosVouchersScreenState();
}

class _PosVouchersScreenState extends State<PosVouchersScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  List<PosVoucher> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final valueCtrl = TextEditingController(
      text: existing != null ? existing.discountValue.toStringAsFixed(0) : '',
    );
    final minCtrl = TextEditingController(
      text: existing != null ? existing.minOrderAmount.toStringAsFixed(0) : '0',
    );
    var isPercent = existing?.isPercent ?? false;
    var isActive = existing?.isActive ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? 'Thêm voucher' : 'Sửa voucher'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Mã voucher *'),
                  textCapitalization: TextCapitalization.characters,
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên'),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Giảm tiền')),
                    ButtonSegment(value: true, label: Text('Giảm %')),
                  ],
                  selected: {isPercent},
                  onSelectionChanged: (s) => setDlg(() => isPercent = s.first),
                ),
                TextField(
                  controller: valueCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isPercent ? 'Phần trăm' : 'Số tiền giảm',
                  ),
                ),
                TextField(
                  controller: minCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Đơn tối thiểu'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đang hoạt động'),
                  value: isActive,
                  onChanged: (v) => setDlg(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PosMobileKiotHeader(title: 'Voucher'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: PosTheme.inputDecoration(label: 'Tìm mã voucher'),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final v = _items[i];
                        final discountLabel = v.isPercent
                            ? '${v.discountValue.toStringAsFixed(0)}%'
                            : '${_moneyFmt.format(v.discountValue)} đ';
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          child: ListTile(
                            onTap: () => _openEditor(v),
                            title: Text(v.code,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              [
                                if (v.name != null && v.name!.isNotEmpty) v.name,
                                'Giảm $discountLabel',
                                if (v.minOrderAmount > 0)
                                  'ĐH tối thiểu ${_moneyFmt.format(v.minOrderAmount)}',
                                'Đã dùng ${v.usedCount}${v.maxUses != null ? '/${v.maxUses}' : ''}',
                              ].whereType<String>().join(' · '),
                            ),
                            trailing: Icon(
                              v.isActive ? Icons.check_circle : Icons.cancel,
                              color: v.isActive ? Colors.green : Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
