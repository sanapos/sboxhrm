import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../services/branch_session.dart';
import '../theme/sbox_tokens.dart';

/// Chip chọn chi nhánh đang thao tác (bán hàng, kho, thu chi gắn theo chi nhánh này).
/// Tự ẩn khi cửa hàng chưa dùng chi nhánh hoặc người dùng chỉ có 1 chi nhánh.
class BranchSwitcher extends StatelessWidget {
  const BranchSwitcher({super.key, this.compact = false, this.onDark = false});

  /// Chỉ hiện icon + tên ngắn (thanh trên điện thoại).
  final bool compact;

  /// Nền tối (app bar màu) → chữ trắng.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BranchSession.instance,
      builder: (context, _) {
        final s = BranchSession.instance;
        if (!s.showSwitcher) return const SizedBox.shrink();
        final fg = onDark ? Colors.white : SboxColors.brand700;
        return PopupMenuButton<String>(
          tooltip: tr('Chi nhánh đang làm việc'),
          position: PopupMenuPosition.under,
          onSelected: (id) async {
            await s.select(id);
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
              duration: const Duration(seconds: 2),
              content: Text(tr('Đang xem: ${s.nameOf(id)}')),
            ));
          },
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              enabled: false,
              height: 32,
              child: Text(tr('Chọn chi nhánh làm việc'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate500)),
            ),
            PopupMenuItem<String>(
              value: BranchSession.allId,
              child: Row(children: [
                Icon(
                  s.isAll ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: 18,
                  color: s.isAll ? SboxColors.brand600 : SboxColors.slate400,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('Tất cả chi nhánh'),
                      style: TextStyle(
                          fontWeight: s.isAll ? FontWeight.w700 : FontWeight.w500, color: SboxColors.slate900)),
                ),
              ]),
            ),
            const PopupMenuDivider(height: 8),
            for (final b in s.branches)
              PopupMenuItem<String>(
                value: b.id,
                child: Row(children: [
                  Icon(
                    b.id == s.currentId ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    size: 18,
                    color: b.id == s.currentId ? SboxColors.brand600 : SboxColors.slate400,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tr(b.name),
                        style: TextStyle(
                            fontWeight: b.id == s.currentId ? FontWeight.w700 : FontWeight.w500,
                            color: b.isActive ? SboxColors.slate900 : SboxColors.slate400)),
                  ),
                  if (b.isHeadquarter)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: SboxColors.brand50,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(tr('Trụ sở'),
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: SboxColors.brand700)),
                    ),
                ]),
              ),
          ],
          child: Container(
            height: compact ? 32 : 36,
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
            decoration: BoxDecoration(
              color: onDark ? Colors.white.withValues(alpha: 0.14) : SboxColors.brand50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: onDark ? Colors.white.withValues(alpha: 0.3) : SboxColors.brand200),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(s.isAll ? Icons.account_tree_rounded : Icons.storefront_rounded, size: 17, color: fg),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 90 : 180),
                child: Text(
                  tr(s.currentLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 18, color: fg),
            ]),
          ),
        );
      },
    );
  }
}

/// Dòng mảnh "Đang xem: Chi nhánh X · Đổi" (điện thoại) — mọi màn hình lọc theo chi nhánh này.
/// Bấm "Đổi" mở danh sách chi nhánh (kèm "Tất cả chi nhánh").
class BranchViewStrip extends StatelessWidget {
  const BranchViewStrip({super.key});

  static Future<void> pick(BuildContext context) async {
    final s = BranchSession.instance;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget tile(String id, String name, {bool hq = false}) {
          final sel = id == s.currentId;
          return ListTile(
            leading: Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: sel ? SboxColors.brand600 : SboxColors.slate400),
            title: Text(tr(name), style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
            trailing: hq
                ? Text(tr('Trụ sở'),
                    style: const TextStyle(fontSize: 11, color: SboxColors.brand700, fontWeight: FontWeight.w700))
                : null,
            onTap: () => Navigator.pop(ctx, id),
          );
        }

        return SafeArea(
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('Chọn chi nhánh làm việc'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            tile(BranchSession.allId, 'Tất cả chi nhánh'),
            const Divider(height: 1),
            for (final b in s.branches) tile(b.id, b.name, hq: b.isHeadquarter),
          ]),
        );
      },
    );
    if (id != null) await s.select(id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BranchSession.instance,
      builder: (context, _) {
        final s = BranchSession.instance;
        if (!s.showSwitcher) return const SizedBox.shrink();
        return Material(
          color: SboxColors.brand50,
          child: InkWell(
            onTap: () => pick(context),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SboxColors.brand200))),
              child: Row(children: [
                Icon(s.isAll ? Icons.account_tree_rounded : Icons.storefront_rounded,
                    size: 15, color: SboxColors.brand700),
                const SizedBox(width: 6),
                Text(tr('Đang xem:'), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(tr(s.currentLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: SboxColors.brand700)),
                ),
                Text(tr('Đổi'),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: SboxColors.brand600)),
                const Icon(Icons.expand_more_rounded, size: 16, color: SboxColors.brand600),
              ]),
            ),
          ),
        );
      },
    );
  }
}
