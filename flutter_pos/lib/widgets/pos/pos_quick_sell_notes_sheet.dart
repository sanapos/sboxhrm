import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_quick_sell_note.dart';
import '../../services/api_service.dart';
import '../../utils/pos_qty_rules.dart';
import '../notification_overlay.dart';
import 'pos_combo_component_picker.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Một món đang có trên giỏ — dùng để lưu giỏ hiện tại thành mục sổ tay.
class PosQuickSellCartItem {
  const PosQuickSellCartItem({
    required this.productId,
    required this.productName,
    required this.qty,
    this.price = 0,
  });

  final String productId;
  final String productName;
  final double qty;
  final double price;
}

/// Sổ tay bán hàng nhanh: danh sách mục đã lưu, bấm một mục là cả danh sách món vào giỏ.
/// Trả về mục được chọn (null = đóng mà không chọn).
class PosQuickSellNotesSheet extends StatefulWidget {
  const PosQuickSellNotesSheet({
    super.key,
    required this.api,
    this.cartItems = const [],
    this.canEdit = true,
    this.loadNotes,
  });

  final ApiService api;

  /// Chỉ dùng cho test: thay lời gọi API đọc danh sách sổ tay.
  final Future<Map<String, dynamic>> Function()? loadNotes;

  /// Giỏ hiện tại — có món thì hiện nút «Lưu giỏ này thành sổ».
  final List<PosQuickSellCartItem> cartItems;

  /// Tài khoản được tạo / sửa / xóa sổ tay.
  final bool canEdit;

  static Future<PosQuickSellNote?> show(
    BuildContext context, {
    required ApiService api,
    List<PosQuickSellCartItem> cartItems = const [],
    bool canEdit = true,
    Future<Map<String, dynamic>> Function()? loadNotes,
  }) {
    return showModalBottomSheet<PosQuickSellNote>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PosQuickSellNotesSheet(
        api: api,
        cartItems: cartItems,
        canEdit: canEdit,
        loadNotes: loadNotes,
      ),
    );
  }

  @override
  State<PosQuickSellNotesSheet> createState() => _PosQuickSellNotesSheetState();
}

class _PosQuickSellNotesSheetState extends State<PosQuickSellNotesSheet> {
  final _money = NumberFormat('#,###', 'vi_VN');
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<PosQuickSellNote> _notes = [];

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
    final res = await (widget.loadNotes ?? widget.api.getPosQuickSellNotes)();
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = (res['message'] ?? 'Không tải được sổ tay').toString();
      });
      return;
    }
    final data = res['data'];
    setState(() {
      _loading = false;
      _notes = data is List
          ? data
              .whereType<Map>()
              .map((e) => PosQuickSellNote.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <PosQuickSellNote>[];
    });
  }

  Future<void> _saveCartAsNote() async {
    final items = widget.cartItems;
    if (items.isEmpty) return;
    // Giỏ có 2 dòng cùng món (khác topping / ghi chú) → gộp số lượng, sổ tay chỉ giữ món + số phần.
    final merged = <String, PosQuickSellNoteItem>{};
    for (final c in items) {
      final old = merged[c.productId];
      merged[c.productId] = PosQuickSellNoteItem(
        productId: c.productId,
        productName: c.productName,
        qty: (old?.qty ?? 0) + (c.qty <= 0 ? 1 : c.qty),
        price: c.price,
      );
    }
    final draft = PosQuickSellNote(name: '', items: merged.values.toList());
    final edited = await _openEditor(draft, title: 'Lưu giỏ này thành sổ');
    if (edited == null) return;
    await _persist(edited);
  }

  Future<void> _createEmpty() async {
    final edited = await _openEditor(
      const PosQuickSellNote(name: '', items: []),
      title: 'Thêm mục sổ tay',
    );
    if (edited == null) return;
    await _persist(edited);
  }

  Future<void> _edit(PosQuickSellNote note) async {
    final edited = await _openEditor(note, title: 'Sửa mục sổ tay');
    if (edited == null) return;
    await _persist(edited);
  }

  Future<PosQuickSellNote?> _openEditor(PosQuickSellNote note,
      {required String title}) {
    return showDialog<PosQuickSellNote>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _QuickSellNoteEditor(
        api: widget.api,
        note: note,
        title: title,
      ),
    );
  }

  Future<void> _persist(PosQuickSellNote note) async {
    setState(() => _saving = true);
    final body = note.toUpsertJson();
    final res = note.id.isEmpty
        ? await widget.api.createPosQuickSellNote(body)
        : await widget.api.updatePosQuickSellNote(note.id, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: tr('Không lưu được'),
        message: (res['message'] ?? 'Vui lòng thử lại').toString(),
      );
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: tr('Đã lưu sổ tay'),
      message: note.name,
    );
    await _load();
  }

  Future<void> _delete(PosQuickSellNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa mục sổ tay?')),
        content: Text(tr('«${note.name}» sẽ bị xóa khỏi sổ tay. Món trong danh mục không bị ảnh hưởng.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.dangerText),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final res = await widget.api.deletePosQuickSellNote(note.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: tr('Không xóa được'),
        message: (res['message'] ?? 'Vui lòng thử lại').toString(),
      );
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            if (_saving) const LinearProgressIndicator(minHeight: 2),
            Flexible(child: _body()),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.menu_book_outlined, size: 20, color: PosTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('Sổ tay bán nhanh'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  tr('Bấm một mục để thêm cả danh sách món vào đơn'),
                  style: TextStyle(fontSize: 12, color: SboxColors.slate600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Đóng'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(color: SboxColors.dangerText)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(tr('Thử lại')),
            ),
          ],
        ),
      );
    }
    if (_notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 40, color: SboxColors.slate400),
            const SizedBox(height: 10),
            Text(
              tr('Chưa có mục nào'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Gom những món hay bán cùng nhau thành một mục rồi đặt tên chung. Lần sau bấm một cái là cả danh sách vào đơn.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: SboxColors.slate600),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: _notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _noteCard(_notes[i]),
    );
  }

  Widget _noteCard(PosQuickSellNote note) {
    final empty = note.items.isEmpty;
    final summary = note.items
        .map((i) => '${i.productName}${i.qty > 1 ? ' ×${PosQtyRules.format(i.qty)}' : ''}')
        .join(', ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: empty ? null : () => Navigator.pop(context, note),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PosTheme.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      note.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    if ((note.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        note.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: SboxColors.slate600),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      empty ? tr('Chưa có món — bấm ⋮ để thêm') : summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: empty ? SboxColors.dangerText : SboxColors.slate700,
                      ),
                    ),
                    if (!empty) ...[
                      const SizedBox(height: 4),
                      Text(
                        tr('${note.items.length} món · ${PosQtyRules.format(note.totalQty)} phần'
                            '${note.estimatedTotal > 0 ? ' · tạm tính ${_money.format(note.estimatedTotal)}đ' : ''}'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: SboxColors.slate500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.canEdit)
                PopupMenuButton<String>(
                  tooltip: tr('Tùy chọn'),
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (v) {
                    if (v == 'edit') _edit(note);
                    if (v == 'delete') _delete(note);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('Xóa'))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    if (!widget.canEdit) return const SizedBox.shrink();
    final hasCart = widget.cartItems.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _createEmpty,
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Mục mới')),
            ),
          ),
          if (hasCart) ...[
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveCartAsNote,
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text(tr('Lưu giỏ này')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Soạn một mục sổ tay: tên, ghi chú, danh sách món + số phần.
class _QuickSellNoteEditor extends StatefulWidget {
  const _QuickSellNoteEditor({
    required this.api,
    required this.note,
    required this.title,
  });

  final ApiService api;
  final PosQuickSellNote note;
  final String title;

  @override
  State<_QuickSellNoteEditor> createState() => _QuickSellNoteEditorState();
}

class _QuickSellNoteEditorState extends State<_QuickSellNoteEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late List<PosQuickSellNoteItem> _items;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.note.name);
    _descCtrl = TextEditingController(text: widget.note.description ?? '');
    _items = List.of(widget.note.items);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _addProduct() async {
    final picked = await PosComboComponentPicker.show(
      context,
      api: widget.api,
      excludeComponentIds: _items.map((e) => e.productId).toSet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _items = [
        ..._items,
        PosQuickSellNoteItem(
          productId: picked.id,
          productName: picked.name,
          qty: 1,
          price: picked.basePrice,
        ),
      ];
    });
  }

  void _changeQty(int index, double delta) {
    final cur = _items[index];
    final next = cur.qty + delta;
    if (next < 1) return;
    setState(() {
      _items = [..._items]..[index] = cur.copyWith(qty: next);
    });
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = tr('Nhập tên cho mục này'));
      return;
    }
    final desc = _descCtrl.text.trim();
    Navigator.pop(
      context,
      widget.note.copyWith(
        name: name,
        description: desc.isEmpty ? null : desc,
        clearDescription: desc.isEmpty,
        items: _items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(widget.title)),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Tên mục'),
                  hintText: tr('vd: Mâm 4 người'),
                  errorText: _nameError,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Ghi chú (không bắt buộc)'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Món trong mục (${_items.length})'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addProduct,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr('Thêm món')),
                  ),
                ],
              ),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    tr('Chưa có món nào — bấm «Thêm món».'),
                    style: TextStyle(fontSize: 12, color: SboxColors.slate600),
                  ),
                ),
              for (var i = 0; i < _items.length; i++) _itemRow(i),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Hủy')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('Lưu'))),
      ],
    );
  }

  Widget _itemRow(int i) {
    final item = _items[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.productName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: tr('Bớt'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: item.qty <= 1 ? null : () => _changeQty(i, -1),
          ),
          SizedBox(
            width: 34,
            child: Text(
              PosQtyRules.format(item.qty),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: tr('Thêm'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: () => _changeQty(i, 1),
          ),
          IconButton(
            tooltip: tr('Bỏ món'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, size: 20, color: SboxColors.dangerText),
            onPressed: () => setState(() => _items = [..._items]..removeAt(i)),
          ),
        ],
      ),
    );
  }
}
