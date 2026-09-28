import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/hr_finance.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Nhân viên rút gọn cho chọn người / sổ theo nhân viên.
class HrFinPerson {
  const HrFinPerson({required this.id, this.userId, required this.name, this.code, this.department, this.photo});
  final String id;
  final String? userId;
  final String name;
  final String? code;
  final String? department;
  final String? photo;

  static List<HrFinPerson> fromEmployees(List<dynamic> list) {
    final out = <HrFinPerson>[];
    for (final e in list.whereType<Map>()) {
      final m = Map<String, dynamic>.from(e);
      final id = '${m['id'] ?? m['Id'] ?? ''}';
      if (id.isEmpty) continue;
      final full = (m['fullName'] ?? m['name'] ?? '${m['lastName'] ?? ''} ${m['firstName'] ?? ''}').toString().trim();
      out.add(HrFinPerson(
        id: id,
        userId: (m['applicationUserId'] ?? m['userId'])?.toString(),
        name: full.isEmpty ? '${m['employeeCode'] ?? id}' : full,
        code: m['employeeCode']?.toString(),
        department: (m['departmentName'] ?? m['department'])?.toString(),
        photo: (m['photoUrl'] ?? m['avatarUrl'])?.toString(),
      ));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }
}

/// Người đang xem hub: quản lý thấy toàn bộ, nhân viên chỉ thấy «Tiền của tôi».
class HrFinViewer {
  const HrFinViewer({required this.isManager, this.employeeId});
  final bool isManager;
  final String? employeeId;
}

String hrFinMoney(num? v) => SboxFmt.money(v);

String hrFinUrl(String url) {
  if (url.startsWith('http')) return url;
  final base = ApiService.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}

void hrFinToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(tr(message)),
    backgroundColor: error ? SboxColors.danger : null,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Hiện thông báo theo kết quả API; trả về true nếu thành công.
bool hrFinResult(BuildContext context, Map<String, dynamic> r, String okMessage) {
  final ok = r['isSuccess'] == true;
  if (context.mounted) hrFinToast(context, ok ? okMessage : '${r['message'] ?? 'Không thực hiện được'}', error: !ok);
  return ok;
}

String hrFinMonthLabel(DateTime m) => 'Tháng ${m.month.toString().padLeft(2, '0')}/${m.year}';

String hrFinDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ─── Nhãn / màu theo loại khoản ────────────────────────────────────

String hrFinKindLabel(String kind) => switch (kind) {
      'advance' => 'Ứng lương',
      'bonus' => 'Thưởng',
      'penalty' => 'Phạt',
      'ticket' => 'Phiếu phạt',
      'trip_advance' => 'Ứng công tác',
      'trip_settlement' => 'Quyết toán CT',
      'cash' => 'Phiếu quỹ',
      _ => kind,
    };

IconData hrFinKindIcon(String kind) => switch (kind) {
      'advance' => Icons.payments_outlined,
      'bonus' => Icons.card_giftcard_outlined,
      'penalty' => Icons.gavel_outlined,
      'ticket' => Icons.receipt_long_outlined,
      'trip_advance' => Icons.flight_takeoff_outlined,
      'trip_settlement' => Icons.fact_check_outlined,
      'cash' => Icons.account_balance_wallet_outlined,
      _ => Icons.attach_money,
    };

SboxTone hrFinKindTone(String kind) => switch (kind) {
      'advance' => SboxTone.brand,
      'bonus' => SboxTone.success,
      'penalty' || 'ticket' => SboxTone.danger,
      'trip_advance' || 'trip_settlement' => SboxTone.violet,
      _ => SboxTone.neutral,
    };

(String, SboxTone) hrFinStatus(HrFinItem it) {
  if (it.disputeStatus == 1) return ('Đang khiếu nại', SboxTone.warning);
  return switch (it.status) {
    'Pending' => (it.kind == 'cash' ? 'Chờ thanh toán' : 'Chờ duyệt', SboxTone.warning),
    'WaitingPayment' => ('Chờ thanh toán', SboxTone.warning),
    'Approved' when it.action == 'pay' => ('Đã duyệt · chờ chi', SboxTone.brand),
    'Approved' || 'Completed' => ('Đã duyệt', SboxTone.success),
    'AutoApproved' => ('Tự duyệt', SboxTone.success),
    'Paid' => ('Đã chi', SboxTone.success),
    'Rejected' => ('Từ chối', SboxTone.neutral),
    'Cancelled' => (it.disputeStatus == 2 ? 'Hủy (khiếu nại)' : 'Đã hủy', SboxTone.neutral),
    _ => (it.status, SboxTone.neutral),
  };
}

String hrFinActionLabel(String? action) => switch (action) {
      'approve' => 'Duyệt',
      'pay' => 'Chi / thu',
      'resolve' => 'Xử lý khiếu nại',
      _ => 'Xem',
    };

// ─── Thành phần ────────────────────────────────────────────────────

String hrFinInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return '${parts[parts.length - 2].characters.first}${parts.last.characters.first}'.toUpperCase();
}

class HrFinAvatar extends StatelessWidget {
  const HrFinAvatar({super.key, required this.name, this.photo, this.size = 36, this.icon});
  final String name;
  final String? photo;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: SboxColors.brand50, shape: BoxShape.circle),
      child: icon != null
          ? Icon(icon, size: size * 0.5, color: SboxColors.brand600)
          : Text(hrFinInitials(name), style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: SboxColors.brand700)),
    );
    final p = photo;
    if (p == null || p.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(hrFinUrl(p), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
    );
  }
}

/// Chọn tháng: ‹ Tháng 10/2026 ›
class HrFinMonthBar extends StatelessWidget {
  const HrFinMonthBar({super.key, required this.month, required this.onChanged});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: SboxSize.control,
      decoration: BoxDecoration(color: SboxColors.white, borderRadius: SboxRadius.mdAll, border: Border.all(color: SboxColors.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: tr('Tháng trước'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded, size: 20),
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        Text(hrFinMonthLabel(month), style: SboxType.bodyStrong()),
        IconButton(
          tooltip: tr('Tháng sau'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded, size: 20),
          onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
        ),
      ]),
    );
  }
}

/// Ảnh / PDF bằng chứng — bấm để mở.
class HrFinEvidenceStrip extends StatelessWidget {
  const HrFinEvidenceStrip({super.key, required this.urls, this.size = 56, this.onRemove});
  final List<String> urls;
  final double size;
  final ValueChanged<String>? onRemove;

  static bool isImage(String u) => RegExp(r'\.(png|jpe?g|webp|gif|bmp|heic)(\?|$)', caseSensitive: false).hasMatch(u);

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: [
      for (final u in urls)
        Stack(clipBehavior: Clip.none, children: [
          InkWell(
            borderRadius: SboxRadius.smAll,
            onTap: () => launchUrl(Uri.parse(hrFinUrl(u)), mode: LaunchMode.externalApplication),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(borderRadius: SboxRadius.smAll, border: Border.all(color: SboxColors.border), color: SboxColors.slate50),
              clipBehavior: Clip.antiAlias,
              child: isImage(u)
                  ? Image.network(hrFinUrl(u), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: SboxColors.slate400))
                  : const Icon(Icons.picture_as_pdf_outlined, color: SboxColors.danger),
            ),
          ),
          if (onRemove != null)
            Positioned(
              right: -6,
              top: -6,
              child: InkWell(
                onTap: () => onRemove!(u),
                child: Container(
                  decoration: const BoxDecoration(color: SboxColors.slate700, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
        ]),
    ]);
  }
}

/// Chọn ảnh / PDF và tải lên; trả về danh sách URL.
Future<List<String>> hrFinPickAndUpload(BuildContext context, ApiService api) async {
  final r = await FilePicker.platform.pickFiles(
      allowMultiple: true, withData: true, type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf']);
  if (r == null || r.files.isEmpty) return const [];
  final files = [
    for (final f in r.files)
      if (f.bytes != null && f.size <= 15 * 1024 * 1024) (bytes: f.bytes!.toList(), name: f.name),
  ];
  if (files.isEmpty) {
    if (context.mounted) hrFinToast(context, 'Tệp vượt quá 15 MB', error: true);
    return const [];
  }
  final res = await api.hrFinUpload(files);
  if (res['isSuccess'] == true && res['data'] is List) return (res['data'] as List).map((e) => '$e').toList();
  if (context.mounted) hrFinToast(context, '${res['message'] ?? 'Tải tệp thất bại'}', error: true);
  return const [];
}

/// Một dòng khoản tiền: avatar · nội dung · số tiền ± · trạng thái · nút xử lý.
class HrFinItemTile extends StatelessWidget {
  const HrFinItemTile({
    super.key,
    required this.item,
    this.onTap,
    this.onAction,
    this.showEmployee = true,
    this.selected,
    this.onSelect,
    this.trailingAction,
  });

  final HrFinItem item;
  final VoidCallback? onTap;
  final VoidCallback? onAction;
  final bool showEmployee;
  final bool? selected;
  final ValueChanged<bool>? onSelect;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final mobile = SboxBreakpoints.isMobile(context);
    final (statusLabel, statusTone) = hrFinStatus(item);
    final tone = hrFinKindTone(item.kind);
    final amountColor = item.isCancelled
        ? SboxColors.textMuted
        : item.isIn
            ? SboxColors.successText
            : SboxColors.dangerText;
    final sign = item.isCancelled ? '' : (item.isIn ? '+' : '−');
    final meta = <String>[
      hrFinKindLabel(item.kind),
      hrFinDate(item.date),
      if (item.code != null && item.code!.isNotEmpty) item.code!,
      if (item.settlement == 'salary') 'Trừ/cộng lương',
      if (item.settlement == 'cash') 'Tiền mặt',
      if (item.evidence.isNotEmpty) '${item.evidence.length} tệp đính kèm',
    ].join(' · ');

    final lead = showEmployee
        ? HrFinAvatar(name: item.employeeName, photo: item.photoUrl, size: 38)
        : Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: tone.bg, borderRadius: SboxRadius.mdAll),
            child: Icon(hrFinKindIcon(item.kind), size: 20, color: tone.fg),
          );

    final body = Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showEmployee)
          Text(item.employeeName.isEmpty ? '—' : item.employeeName,
              style: SboxType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(item.title, style: showEmployee ? SboxType.smallStyle(SboxColors.text) : SboxType.bodyStrong(),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        if (item.subtitle != null && item.subtitle!.isNotEmpty)
          Text(item.subtitle!, style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(meta, style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (item.isDisputeOpen && item.disputeReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Khiếu nại: ${item.disputeReason}',
                style: SboxType.captionStyle(SboxColors.warningText), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
      ]),
    );

    final right = Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      Text('$sign${hrFinMoney(item.amount)}',
          style: SboxType.moneyStyle(c: amountColor).copyWith(
              decoration: item.isCancelled ? TextDecoration.lineThrough : null, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      SboxStatusChip(label: statusLabel, tone: statusTone, dot: true),
      if (onAction != null && item.action != null && !mobile) ...[
        const SizedBox(height: 6),
        SboxButton(
          label: hrFinActionLabel(item.action),
          size: SboxButtonSize.sm,
          kind: item.action == 'pay' ? SboxButtonKind.pay : SboxButtonKind.primary,
          onPressed: onAction,
        ),
      ],
      if (trailingAction != null) ...[const SizedBox(height: 6), trailingAction!],
    ]);

    return Material(
      color: selected == true ? SboxColors.brand50 : SboxColors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SboxSpace.md, vertical: SboxSpace.md),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (onSelect != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Checkbox(
                    value: selected ?? false,
                    visualDensity: VisualDensity.compact,
                    onChanged: item.action == 'approve' ? (v) => onSelect!(v ?? false) : null,
                  ),
                ),
              lead,
              const SizedBox(width: SboxSpace.md),
              body,
              const SizedBox(width: SboxSpace.sm),
              right,
            ]),
            if (onAction != null && item.action != null && mobile)
              Padding(
                padding: const EdgeInsets.only(top: SboxSpace.sm),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SboxButton(
                    label: hrFinActionLabel(item.action),
                    size: SboxButtonSize.sm,
                    kind: item.action == 'pay' ? SboxButtonKind.pay : SboxButtonKind.primary,
                    onPressed: onAction,
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Danh sách khoản trong thẻ bo góc, có đường kẻ giữa các dòng.
class HrFinItemList extends StatelessWidget {
  const HrFinItemList({super.key, required this.children, this.emptyTitle = 'Chưa có dữ liệu', this.emptyMessage, this.emptyIcon = Icons.inbox_outlined});
  final List<Widget> children;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: SboxColors.white, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
      clipBehavior: Clip.antiAlias,
      child: children.isEmpty
          ? SboxEmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
          : Column(children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: SboxColors.divider),
                children[i],
              ],
            ]),
    );
  }
}

/// Nút chọn phân đoạn kiểu «viên thuốc».
class HrFinSegment<T> extends StatelessWidget {
  const HrFinSegment({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final e in options.entries)
          Padding(
            padding: const EdgeInsets.only(right: SboxSpace.sm),
            child: ChoiceChip(
              label: Text(tr(e.value)),
              selected: e.key == value,
              showCheckmark: false,
              onSelected: (_) => onChanged(e.key),
              labelStyle: SboxType.smallStyle(e.key == value ? SboxColors.brand700 : SboxColors.textSecondary)
                  .copyWith(fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w500),
              selectedColor: SboxColors.brand50,
              backgroundColor: SboxColors.white,
              side: BorderSide(color: e.key == value ? SboxColors.brand300 : SboxColors.border),
              shape: const StadiumBorder(),
            ),
          ),
      ]),
    );
  }
}
