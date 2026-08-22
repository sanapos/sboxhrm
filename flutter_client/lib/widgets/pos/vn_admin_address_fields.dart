import 'package:flutter/material.dart';

import '../../data/vietnam_admin_units.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Chọn Tỉnh/TP + Phường/Xã từ danh mục hành chính VN (34 tỉnh / 3321 xã-phường).
class VnAdminAddressFields extends StatefulWidget {
  const VnAdminAddressFields({
    super.key,
    required this.provinceCtrl,
    required this.wardCtrl,
    this.enabled = true,
    this.onChanged,
    this.dense = false,
  });

  final TextEditingController provinceCtrl;
  final TextEditingController wardCtrl;
  final bool enabled;
  final VoidCallback? onChanged;
  final bool dense;

  @override
  State<VnAdminAddressFields> createState() => _VnAdminAddressFieldsState();
}

class _VnAdminAddressFieldsState extends State<VnAdminAddressFields> {
  String? _province;
  String? _ward;

  @override
  void initState() {
    super.initState();
    _syncFromControllers();
    widget.provinceCtrl.addListener(_onExternalProvince);
    widget.wardCtrl.addListener(_onExternalWard);
  }

  @override
  void dispose() {
    widget.provinceCtrl.removeListener(_onExternalProvince);
    widget.wardCtrl.removeListener(_onExternalWard);
    super.dispose();
  }

  void _syncFromControllers() {
    _province = vnMatchProvinceName(widget.provinceCtrl.text);
    if (_province != null && widget.provinceCtrl.text.trim() != _province) {
      widget.provinceCtrl.text = _province!;
    }
    _ward = vnMatchWardName(_province, widget.wardCtrl.text);
    if (_ward != null && widget.wardCtrl.text.trim() != _ward) {
      widget.wardCtrl.text = _ward!;
    }
  }

  void _onExternalProvince() {
    final matched = vnMatchProvinceName(widget.provinceCtrl.text);
    if (matched != _province) {
      setState(() {
        _province = matched;
        _ward = vnMatchWardName(_province, widget.wardCtrl.text);
      });
    }
  }

  void _onExternalWard() {
    final matched = vnMatchWardName(_province, widget.wardCtrl.text);
    if (matched != _ward) {
      setState(() => _ward = matched);
    }
  }

  Future<void> _pickProvince() async {
    if (!widget.enabled) return;
    final picked = await showVnSearchPicker(
      context,
      title: tr('Chọn Tỉnh/Thành phố'),
      items: kVietnamProvinces,
      selected: _province,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _province = picked;
      _ward = null;
      widget.provinceCtrl.text = picked;
      widget.wardCtrl.clear();
    });
    widget.onChanged?.call();
  }

  Future<void> _pickWard() async {
    if (!widget.enabled) return;
    if (_province == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(tr('Chọn Tỉnh/TP trước'))),
      );
      return;
    }
    final wards = vnWardsForProvince(_province);
    final picked = await showVnSearchPicker(
      context,
      title: tr('Chọn Phường/Xã'),
      items: wards,
      selected: _ward,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _ward = picked;
      widget.wardCtrl.text = picked;
    });
    widget.onChanged?.call();
  }

  InputDecoration _dec(String label) {
    if (widget.dense) {
      return InputDecoration(
        labelText: tr(label),
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        suffixIcon: const Icon(Icons.arrow_drop_down),
      );
    }
    return PosTheme.inputDecoration(label: label).copyWith(
      suffixIcon: const Icon(Icons.arrow_drop_down),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: widget.enabled ? _pickProvince : null,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: _dec('Tỉnh/TP'),
            child: Text(
              tr(_province?.isNotEmpty == true ? _province! : 'Chọn tỉnh/thành'),
              style: TextStyle(
                color: _province == null
                    ? PosTheme.textSecondary
                    : PosTheme.textPrimary,
                fontSize: widget.dense ? 13 : null,
              ),
            ),
          ),
        ),
        SizedBox(height: widget.dense ? 6 : 12),
        InkWell(
          onTap: widget.enabled ? _pickWard : null,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: _dec('Phường/Xã'),
            child: Text(
              tr(_ward?.isNotEmpty == true ? _ward! : 'Chọn phường/xã'),
              style: TextStyle(
                color: _ward == null
                    ? PosTheme.textSecondary
                    : PosTheme.textPrimary,
                fontSize: widget.dense ? 13 : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<String?> showVnSearchPicker(
  BuildContext context, {
  required String title,
  required List<String> items,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      return _VnSearchSheet(
        title: title,
        items: items,
        selected: selected,
      );
    },
  );
}

class _VnSearchSheet extends StatefulWidget {
  const _VnSearchSheet({
    required this.title,
    required this.items,
    this.selected,
  });

  final String title;
  final List<String> items;
  final String? selected;

  @override
  State<_VnSearchSheet> createState() => _VnSearchSheetState();
}

class _VnSearchSheetState extends State<_VnSearchSheet> {
  final _q = TextEditingController();
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _filter(String raw) {
    final q = raw.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.items;
      } else {
        _filtered =
            widget.items.where((e) => e.toLowerCase().contains(q)).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.85;
    return SizedBox(
      height: h,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _q,
              autofocus: true,
              decoration: InputDecoration(
                hintText: tr('Tìm kiếm...'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: _filter,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (ctx, i) {
                final item = _filtered[i];
                final sel = item == widget.selected;
                return ListTile(
                  dense: true,
                  title: Text(item),
                  trailing: sel
                      ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                      : null,
                  onTap: () => Navigator.pop(context, item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
