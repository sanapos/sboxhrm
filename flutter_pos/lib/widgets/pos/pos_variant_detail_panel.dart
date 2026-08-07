import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Chi tiết một hàng cùng loại (biến thể) — kiểu KiotViet khi bấm vào dòng con.
class PosVariantDetailPanel extends StatelessWidget {
  const PosVariantDetailPanel({
    super.key,
    required this.parent,
    required this.variant,
    required this.moneyFmt,
    required this.onEdit,
    this.onDelete,
    this.canDelete = false,
    this.compact = false,
  });

  final PosProduct parent;
  final PosProductVariant variant;
  final NumberFormat moneyFmt;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final bool canDelete;
  final bool compact;

  Map<String, String> _parseAttrs() {
    final raw = variant.attributeJson;
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, String>{};
      for (final e in map.entries) {
        if (e.key.startsWith('_')) continue;
        final v = '${e.value}'.trim();
        if (v.isNotEmpty) out[e.key] = v;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final attrs = _parseAttrs();
    final unit = _parseUnit(variant.attributeJson);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        border: Border(
          left: BorderSide(color: PosTheme.kiotBlue, width: 3),
          bottom: BorderSide(color: PosTheme.border.withOpacity(0.6)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(compact ? 16 : 88, 12, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(variant.name),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: PosTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 20,
                  runSpacing: 6,
                  children: [
                    _chip('Mã hàng', variant.skuCode),
                    _chip('Mã vạch', variant.barcode ?? '—'),
                    _chip('Giá bán', moneyFmt.format(variant.basePrice)),
                    _chip('Giá vốn', moneyFmt.format(variant.costPrice)),
                    _chip('Tồn kho', moneyFmt.format(variant.onHandQty)),
                    if (unit != null) _chip('Đơn vị', unit),
                  ],
                ),
                if (attrs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: attrs.entries
                        .map((e) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: PosTheme.kiotBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tr('${e.key}: ${e.value}'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: PosTheme.kiotBlue,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: onEdit,
                style: FilledButton.styleFrom(
                  backgroundColor: PosTheme.kiotBlue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.edit, size: 16),
                label: Text(tr('Chỉnh sửa')),
              ),
              if (canDelete && onDelete != null) ...[
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(tr('Xóa loại')),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String? _parseUnit(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map['_unit']?.toString();
    } catch (_) {
      return null;
    }
  }

  Widget _chip(String label, String value) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 12, color: PosTheme.textPrimary),
        children: [
          TextSpan(
            text: tr('$label: '),
            style: const TextStyle(color: PosTheme.textSecondary),
          ),
          TextSpan(text: tr(value)),
        ],
      ),
    );
  }
}
