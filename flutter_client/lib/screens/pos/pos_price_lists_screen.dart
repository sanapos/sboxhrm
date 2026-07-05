import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/pos_price_list.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_price_list_detail_screen.dart';

/// Danh sách bảng giá POS.
class PosPriceListsScreen extends StatefulWidget {
  const PosPriceListsScreen({super.key});

  @override
  State<PosPriceListsScreen> createState() => _PosPriceListsScreenState();
}

class _PosPriceListsScreenState extends State<PosPriceListsScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
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
            .map((e) => PosPriceList.fromJson(e as Map<String, dynamic>))
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

  Future<void> _createList() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm bảng giá'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Tên bảng giá'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tạo')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) {
      nameCtrl.dispose();
      return;
    }
    final res = await _api.createPosPriceList({
      'name': nameCtrl.text.trim(),
      'isDefault': false,
      'isActive': true,
      'sortOrder': _lists.length,
    });
    nameCtrl.dispose();
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _load();
      NotificationOverlayManager().showSuccess(title: 'Đã tạo', message: 'Bảng giá mới');
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tạo được',
      );
    }
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
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PosPriceListDetailScreen(priceList: pl),
                                ),
                              );
                              _load();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: PosTheme.kiotBlueLight,
                                    child: Icon(
                                      pl.isDefault ? Icons.star : Icons.sell_outlined,
                                      color: PosTheme.kiotBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pl.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          '${pl.itemCount} mức giá${pl.isDefault ? ' · Mặc định' : ''}',
                                          style: const TextStyle(
                                            color: PosTheme.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: PosTheme.textSecondary),
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
