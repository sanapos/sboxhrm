import 'package:flutter/material.dart';

import 'hrm_page_chrome.dart';

/// Toolbar tìm kiếm + nút thao tác trên mobile (không để trống + không ẩn sau filter).
class HrmMobileSearchRow extends StatelessWidget {
  final Widget searchField;
  final List<Widget> trailing;
  final double gap;

  const HrmMobileSearchRow({
    super.key,
    required this.searchField,
    this.trailing = const [],
    this.gap = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: searchField),
        for (var i = 0; i < trailing.length; i++) ...[
          SizedBox(width: gap),
          trailing[i],
        ],
      ],
    );
  }
}

/// Khung bộ lọc luôn hiển thị — Wrap gọn trên mobile.
class HrmInlineFilterPanel extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const HrmInlineFilterPanel({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(0, 10, 0, 0),
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

/// Ô tìm kiếm chuẩn HRM.
class HrmSearchField extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final bool showClear;
  final TextEditingController? controller;

  const HrmSearchField({
    super.key,
    this.hintText = 'Tìm kiếm...',
    required this.onChanged,
    this.onClear,
    this.showClear = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, color: HrmPageChrome.textDark),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(fontSize: 13, color: HrmPageChrome.textMuted),
        prefixIcon: const Icon(Icons.search, size: 20, color: HrmPageChrome.textMuted),
        suffixIcon: showClear
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: onClear,
              )
            : null,
        isDense: true,
        filled: true,
        fillColor: HrmPageChrome.background,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
      ),
    );
  }
}
