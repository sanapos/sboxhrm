import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';

double? _dn(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
DateTime _dt(dynamic v) => DateTime.tryParse('${v ?? ''}') ?? DateTime.now();

/// Một yêu cầu trong hộp duyệt: chấm công mobile hoặc yêu cầu sửa/bổ sung công.
class AaItem {
  AaItem({
    required this.kind,
    required this.id,
    required this.employeeName,
    this.employeeCode,
    this.photoUrl,
    this.department,
    required this.time,
    required this.createdAt,
    this.title = '',
    this.subtitle,
    this.reason,
    this.riskLevel,
    this.riskScore = 0,
    this.flags = const [],
    this.distance,
    this.sitePhotoUrl,
    this.faceScore,
    this.punchType,
    this.isOutside = false,
    this.isTravel = false,
    this.correctionAction,
    this.step,
    this.overdue = false,
  });

  /// mobile / correction
  final String kind;
  final String id;
  final String employeeName;
  final String? employeeCode;
  final String? photoUrl;
  final String? department;
  final DateTime time;
  final DateTime createdAt;
  final String title;
  final String? subtitle;
  final String? reason;

  /// trusted / review / high
  final String? riskLevel;
  final int riskScore;
  final List<String> flags;
  final double? distance;
  final String? sitePhotoUrl;
  final double? faceScore;
  final int? punchType;
  final bool isOutside;
  final bool isTravel;
  final int? correctionAction;
  final String? step;
  final bool overdue;

  bool get isMobile => kind == 'mobile';
  bool get isTrusted => riskLevel == 'trusted' && !isTravel;

  factory AaItem.fromJson(Map<String, dynamic> j) => AaItem(
        kind: '${j['kind'] ?? ''}',
        id: '${j['id'] ?? ''}',
        employeeName: '${j['employeeName'] ?? ''}',
        employeeCode: j['employeeCode']?.toString(),
        photoUrl: j['photoUrl']?.toString(),
        department: j['department']?.toString(),
        time: _dt(j['time']),
        createdAt: _dt(j['createdAt']),
        title: '${j['title'] ?? ''}',
        subtitle: j['subtitle']?.toString(),
        reason: j['reason']?.toString(),
        riskLevel: j['riskLevel']?.toString(),
        riskScore: _i(j['riskScore']),
        flags: (j['flags'] as List?)?.map((e) => '$e').toList() ?? const [],
        distance: _dn(j['distance']),
        sitePhotoUrl: j['sitePhotoUrl']?.toString(),
        faceScore: _dn(j['faceScore']),
        punchType: j['punchType'] == null ? null : _i(j['punchType']),
        isOutside: j['isOutside'] == true,
        isTravel: j['isTravel'] == true,
        correctionAction: j['correctionAction'] == null ? null : _i(j['correctionAction']),
        step: j['step']?.toString(),
        overdue: j['overdue'] == true,
      );
}

class AaCounts {
  AaCounts(this.raw);
  final Map<String, dynamic> raw;
  int c(String k) => _i(raw[k]);
}

String aaUrl(String url) {
  if (url.startsWith('http')) return url;
  final base = ApiService.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}

String aaTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String aaDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
String aaDateTime(DateTime d) => '${aaTime(d)} · ${aaDate(d)}';

String aaAgo(DateTime utcOrLocal) {
  final diff = DateTime.now().difference(utcOrLocal.isUtc ? utcOrLocal.toLocal() : utcOrLocal);
  if (diff.inMinutes < 1) return 'vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  return '${diff.inDays} ngày trước';
}

String aaDistance(double? m) {
  if (m == null) return '—';
  return m >= 1000 ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km' : '${m.round()} m';
}

(String, SboxTone, IconData) aaRisk(AaItem it) {
  if (!it.isMobile) return ('Sửa / bổ sung công', SboxTone.violet, Icons.edit_calendar_outlined);
  if (it.isTravel) return ('Đi đường', SboxTone.brand, Icons.directions_car_outlined);
  return switch (it.riskLevel) {
    'trusted' => ('Tin cậy', SboxTone.success, Icons.verified_outlined),
    'high' => ('Rủi ro cao', SboxTone.danger, Icons.gpp_maybe_outlined),
    _ => ('Cần xem', SboxTone.warning, Icons.visibility_outlined),
  };
}

void aaToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(tr(message)),
    backgroundColor: error ? SboxColors.danger : null,
    behavior: SnackBarBehavior.floating,
  ));
}

class AaAvatar extends StatelessWidget {
  const AaAvatar({super.key, required this.name, this.photo, this.size = 40});
  final String name;
  final String? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final ini = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.characters.first.toUpperCase()
            : '${parts[parts.length - 2].characters.first}${parts.last.characters.first}'.toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: SboxColors.brand50, shape: BoxShape.circle),
      child: Text(ini, style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: SboxColors.brand700)),
    );
    if (photo == null || photo!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(aaUrl(photo!), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
    );
  }
}

/// Một dòng trong danh sách chờ duyệt.
class AaListTile extends StatelessWidget {
  const AaListTile({super.key, required this.item, required this.selected, required this.active, required this.onTap, this.onSelect});
  final AaItem item;
  final bool selected;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<bool>? onSelect;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = aaRisk(item);
    return Material(
      color: active ? SboxColors.brand50 : SboxColors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: active ? SboxColors.brand500 : Colors.transparent, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 36,
              child: onSelect == null
                  ? null
                  : Checkbox(value: selected, visualDensity: VisualDensity.compact, onChanged: (v) => onSelect!(v ?? false)),
            ),
            AaAvatar(name: item.employeeName, photo: item.photoUrl, size: 38),
            const SizedBox(width: SboxSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(item.employeeName, style: SboxType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(aaAgo(item.createdAt), style: SboxType.captionStyle()),
                ]),
                Text(item.title, style: SboxType.smallStyle(SboxColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (item.subtitle != null && item.subtitle!.isNotEmpty)
                  Text(item.subtitle!, style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (item.reason != null && item.reason!.isNotEmpty)
                  Text('“${item.reason}”', style: SboxType.captionStyle(SboxColors.textSecondary).copyWith(fontStyle: FontStyle.italic),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  SboxStatusChip(label: label, tone: tone, icon: icon),
                  if (item.step != null) SboxStatusChip(label: item.step!, tone: SboxTone.neutral),
                  if (item.overdue) const SboxStatusChip(label: 'Quá 24 giờ', tone: SboxTone.warning, icon: Icons.schedule),
                  if (item.sitePhotoUrl != null) const SboxStatusChip(label: 'Có ảnh', tone: SboxTone.neutral, icon: Icons.photo_outlined),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Dòng thông tin nhãn – giá trị trong khung chi tiết.
class AaFact extends StatelessWidget {
  const AaFact({super.key, required this.icon, required this.label, required this.value, this.tone});
  final IconData icon;
  final String label;
  final String value;
  final SboxTone? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: tone?.fg ?? SboxColors.slate500),
        const SizedBox(width: SboxSpace.sm),
        SizedBox(width: 118, child: Text(tr(label), style: SboxType.smallStyle())),
        Expanded(child: Text(value, style: SboxType.bodyStyle(tone?.fg ?? SboxColors.text))),
      ]),
    );
  }
}

/// Khung mục có tiêu đề nhỏ.
class AaSection extends StatelessWidget {
  const AaSection({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: SboxSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(tr(title), style: SboxType.smallStyle(SboxColors.textSecondary).copyWith(fontWeight: FontWeight.w600))),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: SboxSpace.xs),
        child,
      ]),
    );
  }
}

const kAaRejectPresets = [
  'Không đúng vị trí được phân công',
  'Không có lịch làm việc ngoài',
  'Ảnh hiện trường không rõ',
  'Chưa báo trước với quản lý',
];

/// Hỏi lý do từ chối (bắt buộc).
Future<String?> aaAskRejectReason(BuildContext context, {String title = 'Từ chối'}) {
  final ctrl = TextEditingController();
  String? err;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: SboxRadius.lgAll),
        title: Text(tr(title), style: SboxType.titleStyle()),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in kAaRejectPresets)
                ActionChip(label: Text(tr(p), style: SboxType.captionStyle()), onPressed: () => setS(() {
                      ctrl.text = p;
                      err = null;
                    })),
            ]),
            const SizedBox(height: SboxSpace.md),
            TextField(
              controller: ctrl,
              maxLines: 2,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Lý do (nhân viên sẽ nhận được)'),
                errorText: err,
                isDense: true,
                border: OutlineInputBorder(borderRadius: SboxRadius.mdAll),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () {
              if (ctrl.text.trim().length < 3) return setS(() => err = tr('Nhập lý do'));
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(tr('Từ chối')),
          ),
        ],
      ),
    ),
  );
}
