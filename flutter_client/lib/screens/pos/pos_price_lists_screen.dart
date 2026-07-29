import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_price_list.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_price_list_detail_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Danh sách bảng giá POS.
class PosPriceListsScreen extends StatefulWidget {
  const PosPriceListsScreen({super.key});

  @override
  State<PosPriceListsScreen> createState() => _PosPriceListsScreenState();
}

class _PosPriceListsScreenState extends State<PosPriceListsScreen> {
  final _api = ApiService();
  final _dateFmt = DateFormat('dd/MM/yyyy');
  List<PosPriceList> _lists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosPriceLists();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      setState(() {
        _lists = (res['data'] as List)
            .map((e) => PosPriceList.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tải được bảng giá',
      );
    }
  }

  String _rangeLabel(PosPriceList pl) {
    if (pl.validFrom == null && pl.validTo == null) {
      return pl.isDefault ? 'Mặc định · mọi ngày' : '';
    }
    final from = pl.validFrom != null ? _dateFmt.format(pl.validFrom!) : '…';
    final to = pl.validTo != null ? _dateFmt.format(pl.validTo!) : '…';
    final def = pl.isDefault ? 'Mặc định · ' : '';
    return '$def$from → $to';
  }

  Future<void> _createList() async {
    final result = await _showPriceListEditor();
    if (result == null) return;
    final res = await _api.createPosPriceList(result);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _load();
      NotificationOverlayManager().showSuccess(
        title: 'Đã tạo',
        message: tr('Bảng giá mới'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tạo được',
      );
    }
  }

  Future<void> _editList(PosPriceList pl) async {
    final result = await _showPriceListEditor(existing: pl);
    if (result == null) return;
    final res = await _api.updatePosPriceList(pl.id, result);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _load();
      NotificationOverlayManager().showSuccess(
        title: 'Đã cập nhật',
        message: pl.name,
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không cập nhật được',
      );
    }
  }

  Future<Map<String, dynamic>?> _showPriceListEditor({PosPriceList? existing}) async {
    final nameCtrl = TextEditingController(text: tr(existing?.name ?? ''));
    var isDefault = existing?.isDefault ?? false;
    DateTime? validFrom = existing?.validFrom;
    DateTime? validTo = existing?.validTo;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr(existing == null ? 'Thêm bảng giá' : 'Cài bảng giá')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Tên bảng giá'),
                    border: OutlineInputBorder(),
                  ),
                  autofocus: existing == null,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Mặc định khi bán')),
                  subtitle: Text(tr('Hóa đơn trong khoảng ngày dưới sẽ dùng bảng này'),
                  ),
                  value: isDefault,
                  onChanged: (v) => setLocal(() => isDefault = v),
                ),
                const SizedBox(height: 4),
                Text(tr('Áp dụng từ ngày → đến ngày (để trống = mọi ngày)'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: validFrom ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setLocal(() => validFrom = picked);
                          }
                        },
                        child: Text(
                          tr(validFrom == null
                              ? 'Từ ngày'
                              : _dateFmt.format(validFrom!)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text(tr('→')),
                    ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: validTo ?? validFrom ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setLocal(() => validTo = picked);
                          }
                        },
                        child: Text(
                          tr(validTo == null
                              ? 'Đến ngày'
                              : _dateFmt.format(validTo!)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (validFrom != null || validTo != null)
                  TextButton(
                    onPressed: () => setLocal(() {
                      validFrom = null;
                      validTo = null;
                    }),
                    child: Text(tr('Xóa khoảng ngày')),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Huỷ')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(existing == null ? 'Tạo' : 'Lưu')),
            ),
          ],
        ),
      ),
    );

    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || name.isEmpty) return null;

    String? isoDate(DateTime? d) {
      if (d == null) return null;
      final local = DateTime(d.year, d.month, d.day);
      return local.toIso8601String();
    }

    return {
      'name': name,
      'isDefault': isDefault,
      'isActive': existing?.isActive ?? true,
      'sortOrder': existing?.sortOrder ?? _lists.length,
      'validFrom': isoDate(validFrom),
      'validTo': isoDate(validTo),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      floatingActionButton: FloatingActionButton(
        onPressed: _createList,
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PosMobileKiotHeader(title: 'Bảng giá'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                      itemCount: _lists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final pl = _lists[i];
                        final range = _rangeLabel(pl);
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PosPriceListDetailScreen(priceList: pl),
                                ),
                              );
                              _load();
                            },
                            onLongPress: () => _editList(pl),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: PosTheme.kiotBlueLight,
                                    child: Icon(
                                      pl.isDefault
                                          ? Icons.star
                                          : Icons.sell_outlined,
                                      color: PosTheme.kiotBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tr(pl.name),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          tr('${pl.itemCount} mức giá'
                                          '${range.isNotEmpty ? ' · $range' : ''}'),
                                          style: const TextStyle(
                                            color: PosTheme.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: tr('Cài mặc định / ngày'),
                                    onPressed: () => _editList(pl),
                                    icon: const Icon(
                                      Icons.settings_outlined,
                                      size: 20,
                                      color: PosTheme.textSecondary,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: PosTheme.textSecondary,
                                  ),
                                ],
                              ),
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
