import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/pos_print_template.dart';
import '../../models/pos_print_template_v2.dart';
import '../../utils/pos_barcode_print.dart';
import '../../utils/pos_print_template_compiler.dart';
import '../../utils/pos_print_template_v2_codec.dart';
import '../../utils/pos_print_template_v2_presets.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/pos/pos_print_template_preview.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Trình soạn mẫu in V2 — block-based, chỉnh cỡ chữ / đậm / căn + mã nguồn.
class PosPrintTemplateV2Editor extends StatefulWidget {
  const PosPrintTemplateV2Editor({
    super.key,
    required this.template,
    required this.onChanged,
    this.readOnly = false,
    this.compact,
    this.onLegacyHtml,
  });

  final PosPrintTemplateV2 template;
  final ValueChanged<PosPrintTemplateV2> onChanged;
  final bool readOnly;

  /// Mobile / màn hẹp: tab Khối · Chỉnh · Xem trước · Mã nguồn.
  final bool? compact;

  /// Khi người dùng áp dụng HTML thuần (legacy) thay vì JSON V2.
  final ValueChanged<String>? onLegacyHtml;

  @override
  State<PosPrintTemplateV2Editor> createState() => _PosPrintTemplateV2EditorState();
}

class _PosPrintTemplateV2EditorState extends State<PosPrintTemplateV2Editor>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  TabController? _mobileTabs;
  /// desktop: 0 = trực quan, 1 = mã nguồn
  int _desktopMode = 0;

  PosPrintTemplateV2 get _tpl => widget.template;

  bool _isCompact(BuildContext context) =>
      widget.compact ?? Responsive.isCompactViewport(context);

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant PosPrintTemplateV2Editor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= _tpl.blocks.length) {
      _selectedIndex = (_tpl.blocks.length - 1).clamp(0, 999);
    }
  }

  @override
  void dispose() {
    _mobileTabs?.dispose();
    super.dispose();
  }

  void _update(PosPrintTemplateV2 t) => widget.onChanged(t);

  void _selectBlock(int i, {bool openProperties = false}) {
    setState(() => _selectedIndex = i.clamp(0, _tpl.blocks.length - 1));
    if (openProperties && _mobileTabs != null) {
      _mobileTabs!.animateTo(1);
    }
  }

  void _updateBlock(int i, PosPrintBlock block) {
    var blocks = List<PosPrintBlock>.from(_tpl.blocks);
    blocks[i] = block;
    if (block.type == PosPrintBlockType.vietQr &&
        block.qrPlacement != PosPrintQrPlacement.custom) {
      blocks = _blocksWithQrPlacement(blocks, i, block.qrPlacement);
      i = blocks.indexWhere((b) => b.type == PosPrintBlockType.vietQr);
    }
    _update(_tpl.copyWith(blocks: blocks));
    setState(() => _selectedIndex = i.clamp(0, blocks.length - 1));
  }

  List<PosPrintBlock> _blocksWithQrPlacement(
    List<PosPrintBlock> blocks,
    int qrIndex,
    PosPrintQrPlacement placement,
  ) {
    if (placement == PosPrintQrPlacement.custom) return blocks;
    final qr = blocks.removeAt(qrIndex);
    final totalsIdx = blocks.indexWhere((b) => b.type == PosPrintBlockType.totals);
    if (totalsIdx < 0) {
      blocks.add(qr);
      return blocks;
    }
    if (placement == PosPrintQrPlacement.aboveTotals) {
      blocks.insert(totalsIdx, qr);
    } else {
      blocks.insert(totalsIdx + 1, qr);
    }
    return blocks;
  }

  void _addBlock(PosPrintBlockType type) {
    final block = switch (type) {
      PosPrintBlockType.text => PosPrintBlock(type: PosPrintBlockType.text, text: tr('Dòng mới')),
      PosPrintBlockType.field => const PosPrintBlock(type: PosPrintBlockType.field, field: 'Ghi_Chu'),
      PosPrintBlockType.pair => const PosPrintBlock(
          type: PosPrintBlockType.pair,
          leftField: 'Ma_Don_Hang',
          rightField: 'Ngay',
        ),
      PosPrintBlockType.divider => const PosPrintBlock(type: PosPrintBlockType.divider),
      PosPrintBlockType.lineItems => const PosPrintBlock(type: PosPrintBlockType.lineItems),
      PosPrintBlockType.lineItemsKitchen =>
        const PosPrintBlock(type: PosPrintBlockType.lineItemsKitchen),
      PosPrintBlockType.totals => PosPrintBlock(
          type: PosPrintBlockType.totals,
          fields: const ['Tong_Cong'],
        ),
      PosPrintBlockType.spacer => const PosPrintBlock(type: PosPrintBlockType.spacer),
      PosPrintBlockType.vietQr => const PosPrintBlock(type: PosPrintBlockType.vietQr),
      PosPrintBlockType.barcode => const PosPrintBlock(
          type: PosPrintBlockType.barcode,
          field: 'Ma_Vach',
          barcodeHeight: 60,
          barcodeShowText: true,
        ),
    };
    final nextIndex = _tpl.blocks.length;
    _update(_tpl.copyWith(blocks: [..._tpl.blocks, block]));
    setState(() => _selectedIndex = nextIndex);
    _mobileTabs?.animateTo(1);
  }

  void _removeBlock(int i) {
    if (_tpl.blocks.length <= 1) return;
    final blocks = List<PosPrintBlock>.from(_tpl.blocks)..removeAt(i);
    _update(_tpl.copyWith(blocks: blocks));
    setState(() => _selectedIndex = (i - 1).clamp(0, blocks.length - 1));
  }

  void _moveBlock(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _tpl.blocks.length) return;
    final blocks = List<PosPrintBlock>.from(_tpl.blocks);
    final tmp = blocks[i];
    blocks[i] = blocks[j];
    blocks[j] = tmp;
    _update(_tpl.copyWith(blocks: blocks));
    setState(() => _selectedIndex = j);
  }

  @override
  Widget build(BuildContext context) {
    if (_isCompact(context)) {
      return _buildMobileShell(context);
    }
    return _buildDesktopLayout(context);
  }

  Widget _buildMobileShell(BuildContext context) {
    final tabs = _mobileTabs ??= TabController(length: 4, vsync: this);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: tabs,
            isScrollable: true,
            labelColor: PosTheme.edgeBlue,
            unselectedLabelColor: PosTheme.textSecondary,
            indicatorColor: PosTheme.edgeBlue,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: [
              Tab(text: tr('Khối')),
              Tab(text: tr('Chỉnh sửa')),
              Tab(text: tr('Xem trước')),
              Tab(text: tr('Mã nguồn')),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: tabs,
            children: [
              _buildMobileBlocksTab(context),
              _buildMobilePropertiesTab(context),
              _buildPreviewPanel(compact: true),
              _SourceCodePanel(
                template: _tpl,
                readOnly: widget.readOnly,
                onApplyV2: (v) => _update(v),
                onApplyLegacyHtml: widget.onLegacyHtml,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBlocksTab(BuildContext context) {
    final blocks = _tpl.blocks;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildSettingsCard(fullWidth: true)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Text(tr('Danh sách khối (${blocks.length})'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                if (!widget.readOnly)
                  TextButton.icon(
                    onPressed: () => _showAddBlockSheet(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr('Thêm')),
                  ),
              ],
            ),
          ),
        ),
        if (blocks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(tr('Chưa có khối nội dung'))),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            sliver: SliverList.separated(
              itemCount: blocks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _mobileBlockTile(blocks, i),
            ),
          ),
      ],
    );
  }

  Widget _mobileBlockTile(List<PosPrintBlock> blocks, int i) {
    final b = blocks[i];
    final selected = i == _selectedIndex;
    return Material(
      color: selected ? PosTheme.edgeBlueLight : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _selectBlock(i, openProperties: true),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? PosTheme.edgeBlue : PosTheme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: selected ? PosTheme.edgeBlue : const Color(0xFFE5E7EB),
                foregroundColor: selected ? Colors.white : PosTheme.textSecondary,
                child: Text(tr('${i + 1}'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(_blockLabel(b)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: selected ? PosTheme.edgeBlue : PosTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(_blockMeta(b)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (!widget.readOnly)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (a) {
                    if (a == 'del') _removeBlock(i);
                    if (a == 'up') _moveBlock(i, -1);
                    if (a == 'down') _moveBlock(i, 1);
                    if (a == 'edit') _selectBlock(i, openProperties: true);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(tr('Chỉnh sửa'))),
                    PopupMenuItem(value: 'up', child: Text(tr('Lên'))),
                    PopupMenuItem(value: 'down', child: Text(tr('Xuống'))),
                    PopupMenuItem(value: 'del', child: Text(tr('Xóa'))),
                  ],
                )
              else
                Icon(Icons.chevron_right, color: PosTheme.textSecondary.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobilePropertiesTab(BuildContext context) {
    final blocks = _tpl.blocks;
    if (blocks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.view_list_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(tr('Chưa có khối để chỉnh'),
                style: TextStyle(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(tr('Vào tab «Khối» để thêm hoặc chọn một khối.'),
                style: TextStyle(color: PosTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final i = _selectedIndex.clamp(0, blocks.length - 1);
    final sel = blocks[i];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: i > 0 ? () => setState(() => _selectedIndex = i - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      tr(_blockLabel(sel)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    Text(tr('Khối ${i + 1}/${blocks.length}'),
                      style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: i < blocks.length - 1 ? () => setState(() => _selectedIndex = i + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _BlockPropertiesPanel(
            key: ValueKey('block_props_${i}_${sel.type.name}'),
            block: sel,
            paperSize: _tpl.paperSize,
            readOnly: widget.readOnly,
            onChanged: (b) => _updateBlock(i, b),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddBlockSheet(BuildContext context) async {
    final types = <(String, PosPrintBlockType)>[
      ('Văn bản', PosPrintBlockType.text),
      ('Trường dữ liệu', PosPrintBlockType.field),
      ('Cặp trái — phải', PosPrintBlockType.pair),
      ('Đường kẻ', PosPrintBlockType.divider),
      ('Danh sách hàng', PosPrintBlockType.lineItems),
      ('Hàng bếp', PosPrintBlockType.lineItemsKitchen),
      ('Tổng tiền', PosPrintBlockType.totals),
      ('Mã VietQR', PosPrintBlockType.vietQr),
      ('Mã vạch', PosPrintBlockType.barcode),
      ('Khoảng trống', PosPrintBlockType.spacer),
    ];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            Padding(
              padding: EdgeInsets.all(12),
              child: Text(tr('Thêm khối nội dung'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final t in types)
              ListTile(
                leading: Icon(_blockIcon(t.$2), color: PosTheme.edgeBlue),
                title: Text(tr(t.$1)),
                onTap: () {
                  Navigator.pop(ctx);
                  _addBlock(t.$2);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final blocks = _tpl.blocks;
    final sel = blocks.isEmpty ? null : blocks[_selectedIndex.clamp(0, blocks.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSettingsCard(fullWidth: false),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text(tr('Trực quan')), icon: Icon(Icons.view_quilt_outlined, size: 18)),
              ButtonSegment(value: 1, label: Text(tr('Mã nguồn')), icon: Icon(Icons.code, size: 18)),
            ],
            selected: {_desktopMode},
            onSelectionChanged: (s) => setState(() => _desktopMode = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _desktopMode == 1
              ? Card(
                  margin: EdgeInsets.zero,
                  child: _SourceCodePanel(
                    template: _tpl,
                    readOnly: widget.readOnly,
                    onApplyV2: (v) => _update(v),
                    onApplyLegacyHtml: widget.onLegacyHtml,
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 220,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.all(10),
                              child: Text(tr('Khối nội dung'), style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Expanded(
                              child: ReorderableListView.builder(
                                buildDefaultDragHandles: !widget.readOnly,
                                itemCount: blocks.length,
                                onReorder: widget.readOnly
                                    ? (_, __) {}
                                    : (oldIndex, newIndex) {
                                        if (newIndex > oldIndex) newIndex--;
                                        final list = List<PosPrintBlock>.from(blocks);
                                        final item = list.removeAt(oldIndex);
                                        list.insert(newIndex, item);
                                        _update(_tpl.copyWith(blocks: list));
                                        setState(() => _selectedIndex = newIndex);
                                      },
                                itemBuilder: (_, i) {
                                  final b = blocks[i];
                                  final selected = i == _selectedIndex;
                                  return ListTile(
                                    key: ValueKey('block_${i}_${b.type.name}'),
                                    selected: selected,
                                    dense: true,
                                    title: Text(tr(_blockLabel(b)), style: const TextStyle(fontSize: 13)),
                                    subtitle: Text(
                                      tr(_blockMeta(b)),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    onTap: () => _selectBlock(i),
                                    trailing: widget.readOnly
                                        ? null
                                        : PopupMenuButton<String>(
                                            onSelected: (a) {
                                              if (a == 'del') _removeBlock(i);
                                              if (a == 'up') _moveBlock(i, -1);
                                              if (a == 'down') _moveBlock(i, 1);
                                            },
                                            itemBuilder: (_) => [
                                              PopupMenuItem(value: 'up', child: Text(tr('Lên'))),
                                              PopupMenuItem(value: 'down', child: Text(tr('Xuống'))),
                                              PopupMenuItem(value: 'del', child: Text(tr('Xóa'))),
                                            ],
                                          ),
                                  );
                                },
                              ),
                            ),
                            if (!widget.readOnly)
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    _addChip('Chữ', PosPrintBlockType.text),
                                    _addChip('Trường', PosPrintBlockType.field),
                                    _addChip('Cặp', PosPrintBlockType.pair),
                                    _addChip('Kẻ', PosPrintBlockType.divider),
                                    _addChip('Hàng', PosPrintBlockType.lineItems),
                                    _addChip('Tổng', PosPrintBlockType.totals),
                                    _addChip('QR', PosPrintBlockType.vietQr),
                                    _addChip('Barcode', PosPrintBlockType.barcode),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: sel == null
                            ? Center(child: Text(tr('Chưa có khối')))
                            : _BlockPropertiesPanel(
                                key: ValueKey('desk_props_${_selectedIndex}_${sel.type.name}'),
                                block: sel,
                                paperSize: _tpl.paperSize,
                                readOnly: widget.readOnly,
                                onChanged: (b) => _updateBlock(_selectedIndex, b),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildPreviewPanel(compact: false)),
                  ],
                ),
        ),
      ],
    );
  }

  List<DropdownMenuItem<String>> _paperSizeItems() {
    final doc = _tpl.documentType;
    if (doc == PosPrintDocumentTypes.kitchenLabel) {
      return PosPrintPaperSizes.kitchenLabelSizes
          .map((k) => DropdownMenuItem(
                value: k,
                child: Text(tr(PosPrintPaperSizes.labels[k] ?? k)),
              ))
          .toList();
    }
    if (doc == PosPrintDocumentTypes.barcodeLabel) {
      return posBarcodeLabelTemplates
          .map((t) => DropdownMenuItem(
                value: t.id,
                child: Text(
                  tr('${t.name} (${t.sizeLabel})'),
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList();
    }
    return [
      PosPrintPaperSizes.k58,
      PosPrintPaperSizes.k80,
    ]
        .map((k) => DropdownMenuItem(
              value: k,
              child: Text(tr(PosPrintPaperSizes.labels[k] ?? k)),
            ))
        .toList();
  }

  String _resolvedPaperValue(List<DropdownMenuItem<String>> items) {
    final keys = items.map((e) => e.value).whereType<String>().toSet();
    if (keys.contains(_tpl.paperSize)) return _tpl.paperSize;
    // Map Label50x30 ↔ roll_1_50x30 khi mở mẫu cũ.
    if (_tpl.documentType == PosPrintDocumentTypes.barcodeLabel) {
      if (_tpl.paperSize == PosPrintPaperSizes.label50x30 &&
          keys.contains('roll_1_50x30')) {
        return 'roll_1_50x30';
      }
      if (_tpl.paperSize == PosPrintPaperSizes.label40x30 &&
          keys.contains('roll_1_40x30')) {
        return 'roll_1_40x30';
      }
      return keys.contains('roll_1_50x30')
          ? 'roll_1_50x30'
          : (keys.firstOrNull ?? _tpl.paperSize);
    }
    if (_tpl.documentType == PosPrintDocumentTypes.kitchenLabel) {
      return keys.contains(PosPrintPaperSizes.label50x30)
          ? PosPrintPaperSizes.label50x30
          : (keys.firstOrNull ?? PosPrintPaperSizes.label50x30);
    }
    return keys.contains(PosPrintPaperSizes.k80)
        ? PosPrintPaperSizes.k80
        : (keys.firstOrNull ?? _tpl.paperSize);
  }

  Widget _buildSettingsCard({required bool fullWidth}) {
    final paperItems = _paperSizeItems();
    final paperValue = _resolvedPaperValue(paperItems);
    final isLabel = PosPrintPaperSizes.isLabelDoc(_tpl.documentType);
    final paperField = DropdownButtonFormField<String>(
      value: paperValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr(isLabel ? 'Khổ tem' : 'Khổ giấy'),
        isDense: true,
        border: OutlineInputBorder(),
        helperText: _tpl.documentType == PosPrintDocumentTypes.barcodeLabel
            ? tr('Cùng danh sách tem khi In tem hàng hóa')
            : (_tpl.documentType == PosPrintDocumentTypes.kitchenLabel
                ? tr('Tem báo bếp: 50×30 hoặc 40×30')
                : null),
      ),
      items: paperItems,
      onChanged: widget.readOnly
          ? null
          : (v) {
              if (v == null) return;
              _update(_tpl.copyWith(paperSize: v));
            },
    );

    final printerField = DropdownButtonFormField<String>(
      value: _tpl.printerProfile,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr('Máy in'),
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: PosPrintPrinterProfiles.labels.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(tr(e.value))))
          .toList(),
      onChanged: widget.readOnly
          ? null
          : (v) {
              if (v == null) return;
              _update(_tpl.copyWith(printerProfile: v));
            },
    );

    return Card(
      margin: fullWidth ? const EdgeInsets.fromLTRB(12, 8, 12, 4) : EdgeInsets.zero,
      elevation: fullWidth ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: fullWidth ? const BorderSide(color: PosTheme.border) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: fullWidth
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  paperField,
                  const SizedBox(height: 10),
                  printerField,
                  if (!widget.readOnly) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        final preset = PosPrintTemplateV2Presets.build(
                          documentType: _tpl.documentType,
                          paperSize: _tpl.paperSize,
                          printerProfile: _tpl.printerProfile,
                        );
                        _update(preset);
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(tr('Khôi phục mẫu gốc')),
                    ),
                  ],
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(width: 180, child: paperField),
                  SizedBox(width: 200, child: printerField),
                  if (!widget.readOnly)
                    OutlinedButton.icon(
                      onPressed: () {
                        final preset = PosPrintTemplateV2Presets.build(
                          documentType: _tpl.documentType,
                          paperSize: _tpl.paperSize,
                          printerProfile: _tpl.printerProfile,
                        );
                        _update(preset);
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(tr('Khôi phục mẫu gốc')),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildPreviewPanel({required bool compact}) {
    return Card(
      margin: compact ? EdgeInsets.zero : EdgeInsets.zero,
      shape: compact
          ? const RoundedRectangleBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Text(tr('Xem trước'), style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    tr(PosPrintPaperSizes.labels[_tpl.paperSize] ?? _tpl.paperSize),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(compact ? 8 : 0, 0, compact ? 8 : 0, compact ? 8 : 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(compact ? 8 : 0),
                  border: compact ? Border.all(color: PosTheme.border) : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(compact ? 8 : 0),
                  child: buildPosPrintTemplatePreview(_tpl),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addChip(String label, PosPrintBlockType type) => ActionChip(
        label: Text(tr(label), style: const TextStyle(fontSize: 11)),
        onPressed: () => _addBlock(type),
      );

  static String _blockLabel(PosPrintBlock b) => switch (b.type) {
        PosPrintBlockType.text => b.text ?? 'Văn bản',
        PosPrintBlockType.field => '{${b.field ?? '?'}}',
        PosPrintBlockType.pair => '${b.leftField} | ${b.rightField}',
        PosPrintBlockType.divider => b.divider == PosPrintDividerStyle.equals ? '═══' : '───',
        PosPrintBlockType.lineItems => 'Danh sách hàng',
        PosPrintBlockType.lineItemsKitchen => 'Hàng bếp',
        PosPrintBlockType.totals => 'Tổng cộng',
        PosPrintBlockType.spacer => 'Khoảng trống',
        PosPrintBlockType.vietQr => 'VietQR',
        PosPrintBlockType.barcode => 'Barcode {${b.field ?? 'Ma_Vach'}}',
      };

  static String _blockMeta(PosPrintBlock b) {
    if (b.type == PosPrintBlockType.barcode) {
      return 'Cao ${b.barcodeHeight} · ${b.barcodeShowText ? 'Hiện chữ' : 'Ẩn chữ'}';
    }
    final align = switch (b.style.align) {
      PosPrintTextAlign.center => 'Giữa',
      PosPrintTextAlign.right => 'Phải',
      _ => 'Trái',
    };
    return 'Cỡ ${b.style.fontSize.toInt()} · $align${b.style.bold ? ' · Đậm' : ''}';
  }

  static IconData _blockIcon(PosPrintBlockType t) => switch (t) {
        PosPrintBlockType.text => Icons.text_fields,
        PosPrintBlockType.field => Icons.data_object_outlined,
        PosPrintBlockType.pair => Icons.view_column_outlined,
        PosPrintBlockType.divider => Icons.horizontal_rule,
        PosPrintBlockType.lineItems => Icons.list_alt_outlined,
        PosPrintBlockType.lineItemsKitchen => Icons.soup_kitchen_outlined,
        PosPrintBlockType.totals => Icons.payments_outlined,
        PosPrintBlockType.spacer => Icons.space_bar,
        PosPrintBlockType.vietQr => Icons.qr_code_2,
        PosPrintBlockType.barcode => Icons.view_week,
      };
}

class _BlockPropertiesPanel extends StatefulWidget {
  const _BlockPropertiesPanel({
    super.key,
    required this.block,
    required this.paperSize,
    required this.onChanged,
    required this.readOnly,
  });

  final PosPrintBlock block;
  final String paperSize;
  final ValueChanged<PosPrintBlock> onChanged;
  final bool readOnly;

  @override
  State<_BlockPropertiesPanel> createState() => _BlockPropertiesPanelState();
}

class _BlockPropertiesPanelState extends State<_BlockPropertiesPanel> {
  late TextEditingController _textCtrl;
  late TextEditingController _labelCtrl;
  late TextEditingController _qrTitleCtrl;
  late TextEditingController _qrCaptionCtrl;
  late TextEditingController _leftLabelCtrl;
  late TextEditingController _rightLabelCtrl;
  late Map<String, TextEditingController> _totalLabelCtrls;
  late Map<String, TextEditingController> _colLabelCtrls;

  static const _totalKeys = [
    'Tong_Tien_Hang',
    'Chiet_Khau_Hoa_Don',
    'Tong_Cong',
    'Khach_Can_Tra',
    'Khach_Thanh_Toan',
    'Tien_Thua',
    'Con_Lai',
    'Hinh_Thuc_Thanh_Toan',
  ];

  static const _colKeys = ['Ten_Hang_Hoa', 'Don_Gia', 'So_Luong', 'Thanh_Tien'];

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: tr(widget.block.text ?? ''));
    _labelCtrl = TextEditingController(text: widget.block.label ?? '');
    _qrTitleCtrl = TextEditingController(text: tr(widget.block.qrTitle ?? ''));
    _qrCaptionCtrl = TextEditingController(text: tr(widget.block.qrCaption));
    _leftLabelCtrl = TextEditingController(
      text: widget.block.fieldLabels?[widget.block.leftField ?? ''] ?? '',
    );
    _rightLabelCtrl = TextEditingController(
      text: widget.block.fieldLabels?[widget.block.rightField ?? ''] ?? '',
    );
    _totalLabelCtrls = {
      for (final k in _totalKeys)
        k: TextEditingController(
          text: widget.block.fieldLabels?[k] ??
              PosPrintTemplateCompiler.defaultTotalLabels[k] ??
              k,
        ),
    };
    _colLabelCtrls = {
      for (final k in _colKeys)
        k: TextEditingController(
          text: widget.block.fieldLabels?[k] ??
              PosPrintTemplateCompiler.defaultColumnLabels[k] ??
              k,
        ),
    };
  }

  @override
  void didUpdateWidget(covariant _BlockPropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.block.text != oldWidget.block.text && widget.block.text != _textCtrl.text) {
      _textCtrl.text = widget.block.text ?? '';
    }
    if (widget.block.label != oldWidget.block.label &&
        (widget.block.label ?? '') != _labelCtrl.text) {
      _labelCtrl.text = widget.block.label ?? '';
    }
    if (widget.block.qrTitle != oldWidget.block.qrTitle &&
        widget.block.qrTitle != _qrTitleCtrl.text) {
      _qrTitleCtrl.text = widget.block.qrTitle ?? '';
    }
    if (widget.block.qrCaption != oldWidget.block.qrCaption &&
        widget.block.qrCaption != _qrCaptionCtrl.text) {
      _qrCaptionCtrl.text = widget.block.qrCaption;
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _labelCtrl.dispose();
    _qrTitleCtrl.dispose();
    _qrCaptionCtrl.dispose();
    _leftLabelCtrl.dispose();
    _rightLabelCtrl.dispose();
    for (final c in _totalLabelCtrls.values) {
      c.dispose();
    }
    for (final c in _colLabelCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _effectiveDividerChars =>
      widget.block.dividerChars ??
      PosPrintTemplateCompiler.defaultDividerChars(widget.paperSize);

  Map<String, String> _mergeFieldLabels(Map<String, String> patch) {
    final next = Map<String, String>.from(widget.block.fieldLabels ?? {});
    for (final e in patch.entries) {
      final v = e.value.trim();
      if (v.isEmpty) {
        next.remove(e.key);
      } else {
        next[e.key] = v;
      }
    }
    return next;
  }

  void _emitTotalsFields(List<String> fields) {
    final labels = <String, String>{};
    for (final k in fields) {
      final v = _totalLabelCtrls[k]?.text.trim() ?? '';
      final def = PosPrintTemplateCompiler.defaultTotalLabels[k] ?? k;
      if (v.isNotEmpty && v != def) labels[k] = v;
    }
    // Giữ nhãn cột nếu có
    for (final k in _colKeys) {
      final existing = widget.block.fieldLabels?[k];
      if (existing != null && existing.trim().isNotEmpty) {
        labels[k] = existing.trim();
      }
    }
    widget.onChanged(widget.block.copyWith(
      fields: fields,
      fieldLabels: labels,
      clearFieldLabels: labels.isEmpty,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final readOnly = widget.readOnly;
    final onChanged = widget.onChanged;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr(_typeLabel(block.type)), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 16),
        if (block.type == PosPrintBlockType.text)
          TextField(
            readOnly: readOnly,
            controller: _textCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: tr('Nội dung'),
              hintText: tr('Hỗ trợ {Token} — vd. HÓA ĐƠN BÁN HÀNG'),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => onChanged(block.copyWith(text: tr(v))),
          ),
        if (block.type == PosPrintBlockType.field) ...[
          _tokenField('Trường dữ liệu', block.field, (v) => onChanged(block.copyWith(field: v))),
          const SizedBox(height: 12),
          TextField(
            readOnly: readOnly,
            controller: _labelCtrl,
            decoration: InputDecoration(
              labelText: tr('Nhãn hiển thị (tuỳ chọn)'),
              hintText: tr('vd. KH:, Số HĐ:, Đơn hàng:'),
              border: OutlineInputBorder(),
              helperText: tr('Để trống = chỉ in giá trị'),
            ),
            onChanged: (v) => onChanged(block.copyWith(
              label: v.trim().isEmpty ? null : v,
              clearLabel: v.trim().isEmpty,
            )),
          ),
        ],
        if (block.type == PosPrintBlockType.pair) ...[
          _tokenField('Trái', block.leftField, (v) => onChanged(block.copyWith(leftField: v))),
          const SizedBox(height: 8),
          TextField(
            readOnly: readOnly,
            controller: _leftLabelCtrl,
            decoration: InputDecoration(
              labelText: tr('Nhãn bên trái'),
              hintText: tr('vd. Số HĐ:'),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              final key = block.leftField ?? '';
              if (key.isEmpty) return;
              onChanged(block.copyWith(
                fieldLabels: _mergeFieldLabels({key: v}),
              ));
            },
          ),
          const SizedBox(height: 12),
          _tokenField('Phải', block.rightField, (v) => onChanged(block.copyWith(rightField: v))),
          const SizedBox(height: 8),
          TextField(
            readOnly: readOnly,
            controller: _rightLabelCtrl,
            decoration: InputDecoration(
              labelText: tr('Nhãn bên phải'),
              hintText: tr('vd. Ngày:'),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              final key = block.rightField ?? '';
              if (key.isEmpty) return;
              onChanged(block.copyWith(
                fieldLabels: _mergeFieldLabels({key: v}),
              ));
            },
          ),
        ],
        if (block.type == PosPrintBlockType.totals) ...[
          Text(tr('Dòng tổng & nhãn hiển thị'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            tr('Bật/tắt dòng và sửa chữ in (vd. Tổng cộng → Tổng tiền)'),
            style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          ..._totalKeys.map((key) {
            final selected = (block.fields ?? const <String>[]).contains(key);
            final def = PosPrintTemplateCompiler.defaultTotalLabels[key] ?? key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: readOnly
                        ? null
                        : (v) {
                            final cur = List<String>.from(block.fields ?? const []);
                            if (v == true) {
                              if (!cur.contains(key)) cur.add(key);
                            } else {
                              cur.remove(key);
                            }
                            // Giữ thứ tự theo _totalKeys
                            cur.sort((a, b) =>
                                _totalKeys.indexOf(a).compareTo(_totalKeys.indexOf(b)));
                            _emitTotalsFields(cur);
                          },
                  ),
                  Expanded(
                    child: TextField(
                      readOnly: readOnly || !selected,
                      controller: _totalLabelCtrls[key],
                      decoration: InputDecoration(
                        labelText: tr(def),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: selected
                          ? (_) {
                              _emitTotalsFields(
                                List<String>.from(block.fields ?? const []),
                              );
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        if (block.type == PosPrintBlockType.lineItems) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Hiện tiêu đề cột')),
            subtitle: Text(tr('Tên hàng / Đ.giá / SL / TT')),
            value: block.showColumnHeader,
            onChanged: readOnly
                ? null
                : (v) => onChanged(block.copyWith(showColumnHeader: v)),
          ),
          if (block.showColumnHeader) ...[
            const SizedBox(height: 8),
            ..._colKeys.map((key) {
              final def = PosPrintTemplateCompiler.defaultColumnLabels[key] ?? key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  readOnly: readOnly,
                  controller: _colLabelCtrls[key],
                  decoration: InputDecoration(
                    labelText: tr(def),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final labels = _mergeFieldLabels({key: v});
                    // Đồng bộ nhãn totals đã tùy chỉnh
                    for (final tk in _totalKeys) {
                      final t = _totalLabelCtrls[tk]?.text.trim() ?? '';
                      final d = PosPrintTemplateCompiler.defaultTotalLabels[tk] ?? tk;
                      if (t.isNotEmpty && t != d) labels[tk] = t;
                    }
                    onChanged(block.copyWith(
                      fieldLabels: labels,
                      clearFieldLabels: labels.isEmpty,
                    ));
                  },
                ),
              );
            }),
          ],
        ],
        if (block.type == PosPrintBlockType.barcode) ...[
          _tokenField(
            'Nguồn mã vạch',
            block.field ?? 'Ma_Vach',
            (v) => onChanged(block.copyWith(field: v)),
          ),
          const SizedBox(height: 12),
          Text(tr('Chiều cao vạch: ${block.barcodeHeight}')),
          Slider(
            value: block.barcodeHeight.clamp(40, 120).toDouble(),
            min: 40,
            max: 120,
            divisions: 8,
            label: '${block.barcodeHeight}',
            onChanged: readOnly
                ? null
                : (v) => onChanged(block.copyWith(barcodeHeight: v.round())),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Hiện chữ mã dưới barcode')),
            value: block.barcodeShowText,
            onChanged: readOnly
                ? null
                : (v) => onChanged(block.copyWith(barcodeShowText: v)),
          ),
        ],
        if (block.type == PosPrintBlockType.vietQr) ...[
          DropdownButtonFormField<PosPrintQrPlacement>(
            value: block.qrPlacement,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr('Vị trí so với tổng cộng'),
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: PosPrintQrPlacement.aboveTotals,
                child: Text(tr('Trên tổng cộng')),
              ),
              DropdownMenuItem(
                value: PosPrintQrPlacement.belowTotals,
                child: Text(tr('Dưới tổng cộng')),
              ),
              DropdownMenuItem(
                value: PosPrintQrPlacement.custom,
                child: Text(tr('Tùy chỉnh (kéo thả khối)')),
              ),
            ],
            onChanged: readOnly
                ? null
                : (v) {
                    if (v != null) onChanged(block.copyWith(qrPlacement: v));
                  },
          ),
          const SizedBox(height: 12),
          Text(tr('Kích thước QR: ${block.qrSize}px')),
          Slider(
            value: block.qrSize.clamp(100, 220).toDouble(),
            min: 100,
            max: 220,
            divisions: 6,
            label: '${block.qrSize}px',
            onChanged: readOnly
                ? null
                : (v) => onChanged(block.copyWith(qrSize: v.round())),
          ),
          TextField(
            readOnly: readOnly,
            controller: _qrTitleCtrl,
            decoration: InputDecoration(
              labelText: tr('Dòng trên mã QR (tuỳ chọn)'),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => onChanged(
              block.copyWith(
                qrTitle: v.trim().isEmpty ? null : v,
                clearQrTitle: v.trim().isEmpty,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            readOnly: readOnly,
            controller: _qrCaptionCtrl,
            decoration: InputDecoration(
              labelText: tr('Dòng dưới mã QR'),
              hintText: tr('Quét VietQR thanh toán'),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => onChanged(block.copyWith(qrCaption: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Hiện số tiền dưới QR')),
            value: block.qrShowAmount,
            onChanged: readOnly
                ? null
                : (v) => onChanged(block.copyWith(qrShowAmount: v)),
          ),
        ],
        if (block.type != PosPrintBlockType.divider &&
            block.type != PosPrintBlockType.vietQr &&
            block.type != PosPrintBlockType.barcode &&
            block.type != PosPrintBlockType.spacer) ...[
          const SizedBox(height: 16),
          if (block.type == PosPrintBlockType.lineItems ||
              block.type == PosPrintBlockType.lineItemsKitchen ||
              block.type == PosPrintBlockType.totals)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                tr('Áp dụng cho toàn bộ dòng trong bảng in'),
                style: TextStyle(fontSize: 12, color: PosTheme.textSecondary),
              ),
            ),
          Text(tr('Cỡ chữ: ${block.style.fontSize.toInt()}')),
          Slider(
            value: block.style.fontSize.clamp(14, 48),
            min: 14,
            max: 48,
            divisions: 17,
            label: block.style.fontSize.toInt().toString(),
            onChanged: readOnly
                ? null
                : (v) => onChanged(block.copyWith(style: block.style.copyWith(fontSize: v))),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('In đậm')),
            value: block.style.bold,
            onChanged: readOnly
                ? null
                : (v) => onChanged(block.copyWith(style: block.style.copyWith(bold: v))),
          ),
          if (block.type == PosPrintBlockType.totals) ...[
            const SizedBox(height: 8),
            Text(tr(
                'Cỡ chữ Tổng cộng: ${(block.rightStyle ?? block.style).fontSize.toInt()}')),
            Slider(
              value: (block.rightStyle ?? block.style).fontSize.clamp(14, 48),
              min: 14,
              max: 48,
              divisions: 17,
              label: (block.rightStyle ?? block.style).fontSize.toInt().toString(),
              onChanged: readOnly
                  ? null
                  : (v) => onChanged(block.copyWith(
                        rightStyle: (block.rightStyle ?? block.style)
                            .copyWith(fontSize: v, bold: true),
                      )),
            ),
          ],
          if (block.type != PosPrintBlockType.lineItems &&
              block.type != PosPrintBlockType.lineItemsKitchen &&
              block.type != PosPrintBlockType.totals) ...[
            const SizedBox(height: 4),
            Text(tr('Căn lề'), style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            SegmentedButton<PosPrintTextAlign>(
              segments: const [
                ButtonSegment(value: PosPrintTextAlign.left, icon: Icon(Icons.format_align_left, size: 18)),
                ButtonSegment(value: PosPrintTextAlign.center, icon: Icon(Icons.format_align_center, size: 18)),
                ButtonSegment(value: PosPrintTextAlign.right, icon: Icon(Icons.format_align_right, size: 18)),
              ],
              selected: {block.style.align},
              onSelectionChanged: readOnly
                  ? null
                  : (s) => onChanged(block.copyWith(style: block.style.copyWith(align: s.first))),
            ),
          ],
        ],
        if (block.type == PosPrintBlockType.divider) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<PosPrintDividerStyle>(
            value: block.divider,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr('Kiểu kẻ'),
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: PosPrintDividerStyle.dash, child: Text(tr('Gạch ngang'))),
              DropdownMenuItem(value: PosPrintDividerStyle.equals, child: Text(tr('Đường kép (=)'))),
            ],
            onChanged: readOnly
                ? null
                : (v) {
                    if (v != null) onChanged(block.copyWith(divider: v));
                  },
          ),
          const SizedBox(height: 12),
          Text(
            tr('Số ký tự: $_effectiveDividerChars'
            '${block.dividerChars == null ? ' (tự động)' : ''}'),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Row(
            children: [
              IconButton(
                tooltip: tr('Giảm'),
                onPressed: readOnly
                    ? null
                    : () {
                        final next = (_effectiveDividerChars - 2).clamp(16, 80);
                        onChanged(block.copyWith(dividerChars: next));
                      },
                icon: const Icon(Icons.remove),
              ),
              TextButton(
                onPressed: readOnly
                    ? null
                    : () => onChanged(block.copyWith(clearDividerChars: true)),
                child: Text(tr('Tự động')),
              ),
              IconButton(
                tooltip: tr('Tăng'),
                onPressed: readOnly
                    ? null
                    : () {
                        final next = (_effectiveDividerChars + 2).clamp(16, 80);
                        onChanged(block.copyWith(dividerChars: next));
                      },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _tokenField(String label, String? value, ValueChanged<String> onField) {
    final tokenEntries = <(String, String)>[
      ...PosPrintTokens.store,
      ...PosPrintTokens.order,
      ...PosPrintTokens.customer,
      ...PosPrintTokens.line,
      ...PosPrintTokens.label,
      ...PosPrintTokens.totals,
      ('SDT', 'SĐT'),
      ('Gio', 'Giờ'),
    ];
    final tokens = tokenEntries.map((e) => e.$1).toSet().toList();
    final labels = {for (final e in tokenEntries) e.$1: e.$2};
    final current = tokens.contains(value) ? value : tokens.first;
    return DropdownButtonFormField<String>(
      value: current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr(label),
        border: const OutlineInputBorder(),
      ),
      items: tokens
          .map((t) => DropdownMenuItem(
                value: t,
                child: Text(tr('${labels[t] ?? t} ($t)'), overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: widget.readOnly ? null : (v) => onField(v ?? tokens.first),
    );
  }

  static String _typeLabel(PosPrintBlockType t) => switch (t) {
        PosPrintBlockType.text => 'Văn bản',
        PosPrintBlockType.field => 'Trường dữ liệu',
        PosPrintBlockType.pair => 'Cặp nhãn — giá trị',
        PosPrintBlockType.divider => 'Đường kẻ',
        PosPrintBlockType.lineItems => 'Danh sách hàng hóa',
        PosPrintBlockType.lineItemsKitchen => 'Danh sách bếp',
        PosPrintBlockType.totals => 'Khối tổng tiền',
        PosPrintBlockType.spacer => 'Khoảng trống',
        PosPrintBlockType.vietQr => 'Mã VietQR thanh toán',
        PosPrintBlockType.barcode => 'Mã vạch (barcode)',
      };
}

/// Tab / panel sửa mã JSON V2 hoặc HTML thuần.
class _SourceCodePanel extends StatefulWidget {
  const _SourceCodePanel({
    required this.template,
    required this.readOnly,
    required this.onApplyV2,
    this.onApplyLegacyHtml,
  });

  final PosPrintTemplateV2 template;
  final bool readOnly;
  final ValueChanged<PosPrintTemplateV2> onApplyV2;
  final ValueChanged<String>? onApplyLegacyHtml;

  @override
  State<_SourceCodePanel> createState() => _SourceCodePanelState();
}

class _SourceCodePanelState extends State<_SourceCodePanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late TextEditingController _jsonCtrl;
  late TextEditingController _htmlCtrl;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _jsonCtrl = TextEditingController(text: _prettyJson(widget.template));
    _htmlCtrl = TextEditingController(
      text: PosPrintTemplateCompiler.renderSamplePreview(widget.template),
    );
  }

  @override
  void didUpdateWidget(covariant _SourceCodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template != widget.template) {
      // Chỉ sync khi người dùng không đang gõ lệch (so khớp encode).
      final cur = _tryParseJson(_jsonCtrl.text);
      if (cur == null || cur.encode() != widget.template.encode()) {
        _jsonCtrl.text = _prettyJson(widget.template);
      }
      if (_tabs.index == 1) {
        _htmlCtrl.text =
            PosPrintTemplateCompiler.renderSamplePreview(widget.template);
      }
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _jsonCtrl.dispose();
    _htmlCtrl.dispose();
    super.dispose();
  }

  static String _prettyJson(PosPrintTemplateV2 t) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(t.toJson());
  }

  PosPrintTemplateV2? _tryParseJson(String raw) {
    var s = raw.trim();
    if (s.startsWith(kPosPrintTemplateV2Marker)) {
      s = s.substring(kPosPrintTemplateV2Marker.length).trim();
    }
    try {
      final map = jsonDecode(s);
      if (map is Map<String, dynamic>) {
        return PosPrintTemplateV2.fromJson(map);
      }
      if (map is Map) {
        return PosPrintTemplateV2.fromJson(Map<String, dynamic>.from(map));
      }
    } catch (_) {}
    return PosPrintTemplateV2Codec.tryParse(raw);
  }

  void _applyJson() {
    final parsed = _tryParseJson(_jsonCtrl.text);
    if (parsed == null) {
      setState(() {
        _error = 'JSON không hợp lệ. Kiểm tra cú pháp hoặc dùng mẫu V2.';
        _info = null;
      });
      return;
    }
    widget.onApplyV2(parsed);
    setState(() {
      _error = null;
      _info = 'Đã áp dụng JSON V2 vào mẫu in.';
      _htmlCtrl.text = PosPrintTemplateCompiler.renderSamplePreview(parsed);
    });
  }

  void _applyLegacyHtml() {
    final html = _htmlCtrl.text.trim();
    if (html.isEmpty) {
      setState(() {
        _error = 'HTML trống.';
        _info = null;
      });
      return;
    }
    if (widget.onApplyLegacyHtml == null) {
      setState(() {
        _error = 'Màn hình hiện tại không hỗ trợ lưu HTML thuần.';
        _info = null;
      });
      return;
    }
    widget.onApplyLegacyHtml!(html);
    setState(() {
      _error = null;
      _info =
          'Đã chuyển sang HTML thuần. In nhiệt Sunmi/ESC nên dùng JSON V2; HTML phù hợp in trình duyệt / A4.';
    });
  }

  void _refreshCompiledHtml() {
    setState(() {
      _htmlCtrl.text =
          PosPrintTemplateCompiler.renderSamplePreview(widget.template);
      _info = 'Đã làm mới HTML biên dịch từ khối hiện tại.';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            labelColor: PosTheme.edgeBlue,
            unselectedLabelColor: PosTheme.textSecondary,
            tabs: [
              Tab(text: tr('JSON V2')),
              Tab(text: tr('HTML')),
            ],
          ),
        ),
        if (_error != null)
          Material(
            color: const Color(0xFFFEE2E2),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(tr(_error!), style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13)),
            ),
          ),
        if (_info != null)
          Material(
            color: const Color(0xFFDCFCE7),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(tr(_info!), style: const TextStyle(color: Color(0xFF166534), fontSize: 13)),
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildJsonTab(),
              _buildHtmlTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJsonTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Sửa cấu trúc mẫu (blocks, fieldLabels, style). Marker <!--POS_TEMPLATE_V2--> tự thêm khi lưu.'),
            style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              readOnly: widget.readOnly,
              controller: _jsonCtrl,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.35),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!widget.readOnly)
                FilledButton.icon(
                  onPressed: _applyJson,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(tr('Áp dụng JSON')),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _jsonCtrl.text));
                  setState(() {
                    _info = 'Đã copy JSON.';
                    _error = null;
                  });
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(tr('Copy')),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _jsonCtrl.text = _prettyJson(widget.template);
                    _error = null;
                    _info = 'Đã khôi phục từ mẫu hiện tại.';
                  });
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(tr('Tải lại')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHtmlTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('HTML biên dịch (xem/sửa). Token: {Ma_Don_Hang}, {Tong_Cong}… · vòng hàng: <!--BEGIN_ITEMS-->…<!--END_ITEMS-->'),
            style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              readOnly: widget.readOnly,
              controller: _htmlCtrl,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.35),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _refreshCompiledHtml,
                icon: const Icon(Icons.sync, size: 18),
                label: Text(tr('Từ khối V2')),
              ),
              if (!widget.readOnly && widget.onApplyLegacyHtml != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
                  onPressed: _applyLegacyHtml,
                  icon: const Icon(Icons.html, size: 18),
                  label: Text(tr('Lưu HTML thuần')),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _htmlCtrl.text));
                  setState(() {
                    _info = 'Đã copy HTML.';
                    _error = null;
                  });
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(tr('Copy')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
