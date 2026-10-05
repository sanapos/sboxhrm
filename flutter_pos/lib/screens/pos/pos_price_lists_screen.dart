import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pos_price_list.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_price_list_detail_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
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

  /// Sao chép: tên mới, điều chỉnh ±% so với bảng gốc, làm tròn, khoảng ngày áp dụng.
  Future<void> _copyList(PosPriceList pl) async {
    final nameCtrl = TextEditingController(text: '${pl.name} (bản sao)');
    final pctCtrl = TextEditingController(text: '0');
    var roundTo = 0;
    DateTime? from;
    DateTime? to;
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Future<void> pick(bool isFrom) async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: ctx,
              initialDate: (isFrom ? from : to) ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 5),
            );
            if (d != null) setD(() => isFrom ? from = d : to = d);
          }

          return AlertDialog(
            title: Text(tr('Sao chép bảng giá «${pl.name}»')),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: PosTheme.inputDecoration(label: 'Tên bảng giá mới'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pctCtrl,
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      decoration: PosTheme.inputDecoration(
                        label: 'Điều chỉnh giá (%)',
                        hint: '-10 = giảm 10%, 5 = tăng 5%, 0 = giữ nguyên',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: roundTo,
                      isExpanded: true,
                      decoration: PosTheme.inputDecoration(label: 'Làm tròn giá'),
                      items: [
                        DropdownMenuItem(value: 0, child: Text(tr('Không làm tròn'))),
                        DropdownMenuItem(value: 100, child: Text(tr('Tròn 100đ'))),
                        DropdownMenuItem(value: 500, child: Text(tr('Tròn 500đ'))),
                        DropdownMenuItem(value: 1000, child: Text(tr('Tròn 1.000đ'))),
                      ],
                      onChanged: (v) => setD(() => roundTo = v ?? 0),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pick(true),
                            icon: const Icon(Icons.event, size: 16),
                            label: Text(from == null ? tr('Từ ngày') : _dateFmt.format(from!)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pick(false),
                            icon: const Icon(Icons.event, size: 16),
                            label: Text(to == null ? tr('Đến ngày') : _dateFmt.format(to!)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('Để trống ngày = áp dụng mọi ngày. Bảng mới không đặt làm mặc định.'),
                      style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
              FilledButton(
                style: PosTheme.filledButtonStyle,
                onPressed: () {
                  final pct = double.tryParse(pctCtrl.text.trim().replaceAll(',', '.')) ?? 0;
                  Navigator.pop(ctx, {
                    'name': nameCtrl.text.trim(),
                    'adjustPercent': pct,
                    'roundTo': roundTo,
                    'validFrom': from == null ? null : DateFormat('yyyy-MM-dd').format(from!),
                    'validTo': to == null ? null : DateFormat('yyyy-MM-dd').format(to!),
                  });
                },
                child: Text(tr('Sao chép')),
              ),
            ],
          );
        },
      ),
    );
    nameCtrl.dispose();
    pctCtrl.dispose();
    if (body == null) return;
    final res = await _api.copyPosPriceList(pl.id, body);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _load();
      NotificationOverlayManager().showSuccess(
        title: 'Đã sao chép',
        message: tr('${res['data']?['itemCount'] ?? 0} mức giá → ${res['data']?['name'] ?? ''}'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không sao chép được',
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
                  style: TextStyle(fontSize: 12, color: SboxColors.slate600),
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
    final canEdit =
        Provider.of<PermissionProvider>(context).canEdit('PosProducts');
    return Scaffold(
      backgroundColor: PosTheme.background,
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: _createList,
              child: const Icon(Icons.add),
            )
          : null,
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
                            onLongPress: canEdit ? () => _editList(pl) : null,
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
                                  if (canEdit)
                                    IconButton(
                                      tooltip: tr('Sao chép bảng giá'),
                                      onPressed: () => _copyList(pl),
                                      icon: const Icon(
                                        Icons.copy_all_outlined,
                                        size: 20,
                                        color: PosTheme.textSecondary,
                                      ),
                                    ),
                                  if (canEdit)
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
