import 'package:flutter/material.dart';

import '../../models/pos_product.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class PosStaffAssignment {
  PosStaffAssignment({
    this.componentProductId,
    required this.assignedEmployeeId,
    required this.assignedEmployeeName,
  });

  final String? componentProductId;
  final String assignedEmployeeId;
  final String assignedEmployeeName;

  Map<String, dynamic> toJson() => {
        if (componentProductId != null && componentProductId!.isNotEmpty)
          'componentProductId': componentProductId,
        'assignedEmployeeId': assignedEmployeeId,
        'assignedEmployeeName': assignedEmployeeName,
      };
}

class PosStaffSlot {
  const PosStaffSlot({
    required this.key,
    required this.label,
    this.subtitle,
    this.componentProductId,
    this.isService = false,
  });

  final String key;
  final String label;
  final String? subtitle;
  final String? componentProductId;
  final bool isService;
}

/// Chọn nhân viên cho dòng hàng hoặc từng thành phần combo.
class PosLineStaffAssignSheet {
  static Future<List<PosStaffAssignment>?> show({
    required BuildContext context,
    required List<PosStaffSlot> slots,
    required List<Map<String, dynamic>> sellers,
    List<PosStaffAssignment> current = const [],
    bool requireService = false,
  }) {
    return showModalBottomSheet<List<PosStaffAssignment>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => _Sheet(
        slots: slots,
        sellers: sellers,
        current: current,
        requireService: requireService,
      ),
    );
  }

  static List<PosStaffSlot> slotsForProduct(PosProduct p) {
    final combo = p.comboLines ?? const <PosComboLine>[];
    if (p.productType == PosProductType.combo && combo.isNotEmpty) {
      return [
        for (final c in combo)
          PosStaffSlot(
            key: c.componentProductId,
            label: c.componentProductName,
            subtitle: c.qty == c.qty.roundToDouble()
                ? 'SL ${c.qty.toStringAsFixed(0)}'
                : 'SL ${c.qty}',
            componentProductId: c.componentProductId,
            isService: c.componentProductType.toLowerCase() == 'service',
          ),
      ];
    }
    return [
      PosStaffSlot(
        key: p.id,
        label: p.name,
        subtitle: p.productType == PosProductType.service ? 'Dịch vụ' : 'Hàng hóa',
        isService: p.productType == PosProductType.service,
      ),
    ];
  }
}

class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.slots,
    required this.sellers,
    required this.current,
    required this.requireService,
  });

  final List<PosStaffSlot> slots;
  final List<Map<String, dynamic>> sellers;
  final List<PosStaffAssignment> current;
  final bool requireService;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late final Map<String, String?> _picked;

  @override
  void initState() {
    super.initState();
    _picked = {
      for (final s in widget.slots)
        s.key: widget.current
            .where((a) => (a.componentProductId ?? '') == (s.componentProductId ?? ''))
            .map((a) => a.assignedEmployeeId)
            .firstOrNull,
    };
  }

  String _nameOf(String? id) {
    if (id == null || id.isEmpty) return '';
    return widget.sellers
            .where((s) => s['employeeId']?.toString() == id)
            .map((s) => s['displayName']?.toString() ?? '')
            .firstOrNull ??
        '';
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.sellers
        .map((s) => (
              id: s['employeeId']?.toString() ?? '',
              name: s['displayName']?.toString() ?? '—',
            ))
        .where((e) => e.id.isNotEmpty)
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Chọn nhân viên làm'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: PosTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Combo / gói dịch vụ: chọn NV cho từng phần để tính hoa hồng'),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.slots.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final slot = widget.slots[i];
                  return InputDecorator(
                    decoration: InputDecoration(
                      labelText: tr(slot.label),
                      helperText: slot.subtitle == null ? null : tr(slot.subtitle!),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: items.any((e) => e.id == _picked[slot.key])
                            ? _picked[slot.key]
                            : null,
                        hint: Text(tr(slot.isService && widget.requireService
                            ? 'Bắt buộc chọn NV'
                            : '— Không gán —')),
                        items: [
                          if (!(slot.isService && widget.requireService))
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text(tr('— Không gán —')),
                            ),
                          ...items.map(
                            (e) => DropdownMenuItem<String>(
                              value: e.id,
                              child: Text(tr(e.name), overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _picked[slot.key] = v),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final out = <PosStaffAssignment>[];
                for (final slot in widget.slots) {
                  final id = _picked[slot.key];
                  if (id == null || id.isEmpty) {
                    if (widget.requireService && slot.isService) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('Chưa chọn NV cho «${slot.label}»'))),
                      );
                      return;
                    }
                    continue;
                  }
                  out.add(PosStaffAssignment(
                    componentProductId: slot.componentProductId,
                    assignedEmployeeId: id,
                    assignedEmployeeName: _nameOf(id),
                  ));
                }
                Navigator.pop(context, out);
              },
              child: Text(tr('Lưu nhân viên')),
            ),
          ],
        ),
      ),
    );
  }
}
